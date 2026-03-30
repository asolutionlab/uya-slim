// benchmarks/http_bench.go — 与 http_bench.uya 对齐的 Go 参考服务端（同端口、同路由、同响应体长度）
// Rust 对照：benchmarks/http_bench_tokio（Tokio + Hyper）
//
// 路由与体大小（与 Uya 版一致）：
//   GET /              → "hello"（5 字节）
//   GET /json          → {"ok":true}（11 字节）
//   GET /item/:id      → 体为路径参数 id（单段）
//   GET /payload1k     → 1024 字节 'a'
//   GET /payload10k    → 10240 字节 'a'
//   GET /payload100k   → 102400 字节 'a'
//
// 默认 127.0.0.1:8876；`--once`：accept 一次连接，处理首个请求后退出（与 Uya `--once` 用途类似）。
//
// 运行：
//   cd benchmarks && go run .
// 压测（与 Uya 相同 URL）：
//   wrk -t4 -c64 -d10s http://127.0.0.1:8876/

package main

import (
	"bufio"
	"bytes"
	"fmt"
	"net"
	"net/http"
	"os"
	"strings"
)

const benchPort = "8876"

var (
	payload1k   = bytes.Repeat([]byte{'a'}, 1024)
	payload10k  = bytes.Repeat([]byte{'a'}, 10240)
	payload100k = bytes.Repeat([]byte{'a'}, 102400)
)

func setPlain(w http.ResponseWriter) {
	w.Header().Set("Content-Type", "text/plain")
}

func writeOK(w http.ResponseWriter, body []byte) {
	setPlain(w)
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(body)
}

func writeEmpty(w http.ResponseWriter, code int) {
	setPlain(w)
	w.WriteHeader(code)
}

func handlerItem(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeEmpty(w, http.StatusMethodNotAllowed)
		return
	}
	rest, ok := strings.CutPrefix(r.URL.Path, "/item/")
	if !ok || rest == "" || strings.Contains(rest, "/") {
		if rest == "" {
			writeEmpty(w, http.StatusBadRequest)
			return
		}
		writeEmpty(w, http.StatusNotFound)
		return
	}
	writeOK(w, []byte(rest))
}

func registerCompat(mux *http.ServeMux) {
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			writeEmpty(w, http.StatusMethodNotAllowed)
			return
		}
		p := r.URL.Path
		switch {
		case p == "/":
			writeOK(w, []byte("hello"))
		case p == "/json":
			writeOK(w, []byte(`{"ok":true}`))
		case strings.HasPrefix(p, "/item/"):
			handlerItem(w, r)
		case p == "/payload1k":
			writeOK(w, payload1k)
		case p == "/payload10k":
			writeOK(w, payload10k)
		case p == "/payload100k":
			writeOK(w, payload100k)
		default:
			writeEmpty(w, http.StatusNotFound)
		}
	})
}

func runOnce() error {
	ln, err := net.Listen("tcp", "127.0.0.1:"+benchPort)
	if err != nil {
		return err
	}
	defer ln.Close()
	conn, err := ln.Accept()
	if err != nil {
		return err
	}
	defer conn.Close()
	br := bufio.NewReader(conn)
	req, err := http.ReadRequest(br)
	if err != nil {
		return err
	}
	mux := http.NewServeMux()
	registerCompat(mux)
	w := newOnceResponseWriter(conn)
	mux.ServeHTTP(w, req)
	return w.finish()
}

// 单次响应写回（无 Server，与 Uya run_once 接近）
type onceResponseWriter struct {
	conn          net.Conn
	status        int
	header        http.Header
	wroteHeader   bool
	headerFlushed bool
}

func newOnceResponseWriter(c net.Conn) *onceResponseWriter {
	return &onceResponseWriter{conn: c, header: make(http.Header)}
}

func (o *onceResponseWriter) Header() http.Header { return o.header }

func (o *onceResponseWriter) WriteHeader(code int) {
	if o.wroteHeader {
		return
	}
	o.wroteHeader = true
	o.status = code
}

func (o *onceResponseWriter) Write(b []byte) (int, error) {
	if !o.wroteHeader {
		o.WriteHeader(http.StatusOK)
	}
	if o.headerFlushed {
		return 0, fmt.Errorf("response already sent")
	}
	o.headerFlushed = true
	if o.status == 0 {
		o.status = http.StatusOK
	}
	ct := o.header.Get("Content-Type")
	if ct == "" {
		ct = "text/plain"
	}
	cl := fmt.Sprintf("%d", len(b))
	statusLine := fmt.Sprintf("HTTP/1.1 %d %s\r\n", o.status, http.StatusText(o.status))
	var buf bytes.Buffer
	buf.WriteString(statusLine)
	buf.WriteString("Content-Length: " + cl + "\r\n")
	buf.WriteString("Content-Type: " + ct + "\r\n")
	buf.WriteString("Connection: close\r\n\r\n")
	buf.Write(b)
	_, err := o.conn.Write(buf.Bytes())
	return len(b), err
}

// 处理仅 WriteHeader、无 Write 的空体响应（如 404）
func (o *onceResponseWriter) finish() error {
	if o.headerFlushed {
		return nil
	}
	if !o.wroteHeader {
		o.status = http.StatusOK
		o.wroteHeader = true
	}
	o.headerFlushed = true
	ct := o.header.Get("Content-Type")
	if ct == "" {
		ct = "text/plain"
	}
	statusLine := fmt.Sprintf("HTTP/1.1 %d %s\r\n", o.status, http.StatusText(o.status))
	var buf bytes.Buffer
	buf.WriteString(statusLine)
	buf.WriteString("Content-Length: 0\r\n")
	buf.WriteString("Content-Type: " + ct + "\r\n")
	buf.WriteString("Connection: close\r\n\r\n")
	_, err := o.conn.Write(buf.Bytes())
	return err
}

func main() {
	once := false
	for _, a := range os.Args[1:] {
		if a == "--once" {
			once = true
			break
		}
	}
	if once {
		if err := runOnce(); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		return
	}
	addr := "127.0.0.1:" + benchPort
	mux := http.NewServeMux()
	registerCompat(mux)
	srv := &http.Server{Addr: addr, Handler: mux}
	fmt.Fprintf(os.Stderr, "listening on http://%s/\n", addr)
	if err := srv.ListenAndServe(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
