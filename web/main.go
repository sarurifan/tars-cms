package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// ================================================================
// CmsWeb — tars-cms 静态资源服务（tarsnode 托管的 Web 服务）
// ================================================================
// 【职责】
//   /             → h5 内容站（SPA，history 路由回退 index.html）
//   /admin/       → admin 管理后台（SPA，回退 index.html）
//   /uploads/     → 用户上传文件（图片/附件）
//   /health       → 健康检查
//
// 【托管方式】
//   tarsnode 以 tars_cpp + not_tars 协议托管本二进制（见 n06-deploy-web.sh）
//   tarsnode 会注入 --config=<conf> 参数 → 由包装脚本拦截后忽略
//
// 【环境变量】
//   CMS_WEB_PORT  监听端口（默认 13103）
//   CMS_H5_DIR    h5 构建产物目录
//   CMS_ADMIN_DIR admin 构建产物目录
//   CMS_UPLOAD_DIR 上传文件目录
// ================================================================

func main() {
	port := envOr("CMS_WEB_PORT", "13103")
	h5Dir := envOr("CMS_H5_DIR", "/usr/local/app/tars/tarsnode/data/cms.CmsWeb/data/h5")
	adminDir := envOr("CMS_ADMIN_DIR", "/usr/local/app/tars/tarsnode/data/cms.CmsWeb/data/admin")
	uploadDir := envOr("CMS_UPLOAD_DIR", "/data/tars/cms/uploads")

	mux := http.NewServeMux()

	// 健康检查
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprintf(w, `{"code":0,"msg":"ok","service":"cms.CmsWeb","time":%q}`, time.Now().Format(time.RFC3339))
	})

	// 上传文件
	mux.Handle("/uploads/", http.StripPrefix("/uploads/", http.FileServer(http.Dir(uploadDir))))

	// admin 后台（/admin/ 前缀）
	mux.Handle("/admin/", http.StripPrefix("/admin/", spaHandler(adminDir, "/admin")))

	// h5 内容站（根路径，兜底）
	mux.Handle("/", spaHandler(h5Dir, ""))

	// 访问日志
	handler := logMiddleware(mux)

	addr := ":" + port
	log.Printf("cms.CmsWeb listening on %s", addr)
	log.Printf("  h5:     %s", h5Dir)
	log.Printf("  admin:  %s", adminDir)
	log.Printf("  upload: %s", uploadDir)

	if err := http.ListenAndServe(addr, handler); err != nil {
		log.Fatalf("listen failed: %v", err)
	}
}

// spaHandler SPA 静态服务：命中文件则返回，否则回退 index.html
// base 为 URL 前缀（如 /admin），用于处理回退时的路径
func spaHandler(dir string, base string) http.Handler {
	fs := http.FileServer(http.Dir(dir))
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// 安全：禁止路径穿越
		if strings.Contains(r.URL.Path, "..") {
			http.Error(w, "invalid path", http.StatusBadRequest)
			return
		}

		cleanPath := strings.TrimPrefix(r.URL.Path, "/")
		absPath := filepath.Join(dir, cleanPath)

		if st, err := os.Stat(absPath); err == nil && !st.IsDir() {
			// 静态资源缓存（带 hash 的可长缓存）
			if strings.Contains(r.URL.Path, "/assets/") {
				w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
			}
			fs.ServeHTTP(w, r)
			return
		}

		// 回退 index.html（SPA 路由）
		index := filepath.Join(dir, "index.html")
		if _, err := os.Stat(index); err == nil {
			w.Header().Set("Cache-Control", "no-cache")
			http.ServeFile(w, r, index)
			return
		}

		http.NotFound(w, r)
	})
}

// logMiddleware 访问日志
func logMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		lw := &loggingResponseWriter{ResponseWriter: w, status: 200}
		next.ServeHTTP(lw, r)
		// 忽略健康检查噪音
		if r.URL.Path != "/health" {
			log.Printf("%s %s %d %s", r.Method, r.URL.Path, lw.status, time.Since(start))
		}
	})
}

type loggingResponseWriter struct {
	http.ResponseWriter
	status int
}

func (l *loggingResponseWriter) WriteHeader(code int) {
	l.status = code
	l.ResponseWriter.WriteHeader(code)
}

func envOr(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}
