package main

import (
	"encoding/binary"
	"fmt"
	"io"
	"net"
	"time"
)

const rounds = 100

func writeFrame(w io.Writer, opcode byte, payload []byte, masked bool) error {
	header := []byte{0x80 | opcode}
	if masked {
		header = append(header, 0x80|byte(len(payload)))
		mask := [4]byte{1, 2, 3, 4}
		header = append(header, mask[:]...)
		if _, err := w.Write(header); err != nil {
			return err
		}
		buf := make([]byte, len(payload))
		for i := range payload {
			buf[i] = payload[i] ^ mask[i%4]
		}
		_, err := w.Write(buf)
		return err
	}
	header = append(header, byte(len(payload)))
	if _, err := w.Write(header); err != nil {
		return err
	}
	_, err := w.Write(payload)
	return err
}

func readFrame(r io.Reader, expectMasked bool) (byte, []byte, error) {
	var hdr [2]byte
	if _, err := io.ReadFull(r, hdr[:]); err != nil {
		return 0, nil, err
	}
	opcode := hdr[0] & 0x0f
	masked := (hdr[1] & 0x80) != 0
	n := int(hdr[1] & 0x7f)
	if masked != expectMasked {
		return 0, nil, fmt.Errorf("masked mismatch")
	}
	var mask [4]byte
	if masked {
		if _, err := io.ReadFull(r, mask[:]); err != nil {
			return 0, nil, err
		}
	}
	payload := make([]byte, n)
	if _, err := io.ReadFull(r, payload); err != nil {
		return 0, nil, err
	}
	if masked {
		for i := range payload {
			payload[i] ^= mask[i%4]
		}
	}
	return opcode, payload, nil
}

func main() {
	server, client := net.Pipe()
	defer server.Close()
	defer client.Close()

	go func() {
		for i := 0; i < rounds; i++ {
			opcode, payload, err := readFrame(server, true)
			if err != nil {
				return
			}
			_ = writeFrame(server, opcode, payload, false)
		}
	}()

	payload := []byte{0x5a}
	start := time.Now()
	for i := 0; i < rounds; i++ {
		if err := writeFrame(client, 1, payload, true); err != nil {
			panic(err)
		}
		opcode, echoed, err := readFrame(client, false)
		if err != nil {
			panic(err)
		}
		if opcode != 1 || len(echoed) != 1 || echoed[0] != payload[0] {
			panic("unexpected echo")
		}
	}
	elapsed := time.Since(start)
	ms := elapsed.Milliseconds()
	if ms == 0 {
		ms = 1
	}
	rps := uint64(rounds) * 1000 / uint64(ms)
	fmt.Printf("{\"roundtrips\":%d,\"go_ws_rps\":%d,\"elapsed_ms\":%d}\n", rounds, rps, ms)
	_ = binary.MaxVarintLen64
}
