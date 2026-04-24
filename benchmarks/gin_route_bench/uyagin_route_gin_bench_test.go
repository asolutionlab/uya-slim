package gin_route_bench

import (
	"net/http"
	"strconv"
	"testing"

	"github.com/gin-gonic/gin"
)

type discardWriter struct {
	header http.Header
}

func (w *discardWriter) Header() http.Header {
	if w.header == nil {
		w.header = make(http.Header)
	}
	return w.header
}

func (w *discardWriter) Write(p []byte) (int, error) {
	return len(p), nil
}

func (w *discardWriter) WriteHeader(statusCode int) {
	_ = statusCode
}

func buildGinRouteEngine(routeCount int, caseKind string) *gin.Engine {
	gin.SetMode(gin.ReleaseMode)
	engine := gin.New()
	noOp := func(c *gin.Context) {}

	idx := 0
	switch caseKind {
	case "param":
		engine.GET("/users/:id", noOp)
		idx++
	case "wildcard":
		engine.GET("/assets/*path", noOp)
		idx++
	}

	for idx < routeCount {
		engine.GET("/r"+strconv.Itoa(idx), noOp)
		idx++
	}
	return engine
}

func benchGinCase(b *testing.B, routeCount int, caseKind string, path string) {
	engine := buildGinRouteEngine(routeCount, caseKind)
	req, err := http.NewRequest(http.MethodGet, path, nil)
	if err != nil {
		b.Fatal(err)
	}
	w := &discardWriter{}
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		engine.ServeHTTP(w, req)
	}
}

func BenchmarkUyaginRouteGin(b *testing.B) {
	counts := []int{1, 16, 128, 1024}
	for _, count := range counts {
		count := count
		b.Run("static/"+strconv.Itoa(count), func(b *testing.B) {
			benchGinCase(b, count, "static", "/r"+strconv.Itoa(count-1))
		})
		b.Run("param/"+strconv.Itoa(count), func(b *testing.B) {
			benchGinCase(b, count, "param", "/users/42")
		})
		b.Run("wildcard/"+strconv.Itoa(count), func(b *testing.B) {
			benchGinCase(b, count, "wildcard", "/assets/a/b/c")
		})
	}
}
