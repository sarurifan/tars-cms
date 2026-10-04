package main

import (
	"context"
	"encoding/base64"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/TarsCloud/TarsGo/tars"
	"github.com/tars-cms/cms/tars-protocol/cms"
)

// cms BFF — HTTP → TARS RPC 转换层
//
// 【架构】
//   前端 (h5/admin) → TarsGateway(8200) → BFF(3103) → cms.CmsServer(13101 tars adapter)
//
//   BFF 是轻量 HTTP 转发层：
//     - 收到 /api/cms/home → 调用 cms.ArticleObj.GetHome()
//     - 收到 /api/auth/login → 调用 cms.AuthObj.Login()
//     - 返回 tars 服务的 JSON 结果
//
// 【为什么独立】
//   按用户要求「组件宁可冗余也要单独处理，绝不复用」，不改旧 nerv BFF(3102)。

func main() {
	// TarsGo 客户端：连接 cms.CmsServer
	comm := tars.NewCommunicator()
	obj := "cms.CmsServer.ArticleObj@tcp -h 172.25.0.5 -t 60000 -p 13101 -e 0"
	articleProxy := cms.NewArticleObj()
	comm.StringToProxy(obj, articleProxy)

	obj2 := "cms.CmsServer.AuthObj@tcp -h 172.25.0.5 -t 60000 -p 13102 -e 0"
	authProxy := cms.NewAuthObj()
	comm.StringToProxy(obj2, authProxy)

	// RPC 超时（P2-4）：防止 TARS 调用挂起导致 HTTP 请求无限等待
	// 默认 8s，可用 CMS_RPC_TIMEOUT_MS 覆盖
	rpcTimeout := 8000
	if v := os.Getenv("CMS_RPC_TIMEOUT_MS"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 {
			rpcTimeout = n
		}
	}
	articleProxy.TarsSetTimeout(rpcTimeout)
	authProxy.TarsSetTimeout(rpcTimeout)

	mux := http.NewServeMux()

	// ---------- 健康检查（P2-1）----------
	// /health     : 服务存活（不调下游，快速返回）
	// /health/full: 连带探测 CmsServer RPC 是否可用
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json; charset=utf-8")
		io.WriteString(w, `{"status":"ok","service":"cms.CmsBff","rpc_timeout_ms":`+strconv.Itoa(rpcTimeout)+`}`)
	})
	mux.HandleFunc("/health/full", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json; charset=utf-8")
		if _, err := articleProxy.GetCategories(1); err != nil {
			w.WriteHeader(http.StatusServiceUnavailable)
			io.WriteString(w, `{"status":"degraded","error":"`+strings.ReplaceAll(err.Error(), `"`, "'")+`"}`)
			return
		}
		io.WriteString(w, `{"status":"ok","rpc":"up"}`)
	})

	// ---------- 公开接口（H5 内容站） ----------

	// 首页聚合
	mux.HandleFunc("/api/cms/home", func(w http.ResponseWriter, r *http.Request) {
		tenantId := int32(parseInt(r.URL.Query().Get("tenantId"), 1))
		result, err := articleProxy.GetHome(tenantId)
		if err != nil {
			writeJSONError(w, err.Error())
			return
		}
		writeJSON(w, result)
	})

	// 分类树
	mux.HandleFunc("/api/cms/categories/tree", func(w http.ResponseWriter, r *http.Request) {
		tenantId := int32(parseInt(r.URL.Query().Get("tenantId"), 1))
		result, err := articleProxy.GetCategoryTree(tenantId)
		if err != nil {
			writeJSONError(w, err.Error())
			return
		}
		writeJSON(w, result)
	})

	// 分类列表
	mux.HandleFunc("/api/cms/categories", func(w http.ResponseWriter, r *http.Request) {
		tenantId := int32(parseInt(r.URL.Query().Get("tenantId"), 1))
		result, err := articleProxy.GetCategories(tenantId)
		if err != nil {
			writeJSONError(w, err.Error())
			return
		}
		writeJSON(w, result)
	})

	// 文章列表
	mux.HandleFunc("/api/cms/articles", func(w http.ResponseWriter, r *http.Request) {
		tenantId := int32(parseInt(r.URL.Query().Get("tenantId"), 1))
		categoryId := int32(parseInt(r.URL.Query().Get("categoryId"), 0))
		keyword := r.URL.Query().Get("keyword")
		page := int32(parseInt(r.URL.Query().Get("page"), 1))
		size := int32(parseInt(r.URL.Query().Get("size"), 10))
		result, err := articleProxy.GetArticleList(tenantId, categoryId, keyword, page, size)
		if err != nil {
			writeJSONError(w, err.Error())
			return
		}
		writeJSON(w, result)
	})

	// 文章详情
	mux.HandleFunc("/api/cms/articles/", func(w http.ResponseWriter, r *http.Request) {
		// 提取 /api/cms/articles/:id
		path := strings.TrimPrefix(r.URL.Path, "/api/cms/articles/")
		if path == "" {
			writeJSONError(w, "article id required")
			return
		}
		id := int32(parseInt(path, 0))
		tenantId := int32(parseInt(r.URL.Query().Get("tenantId"), 1))
		result, err := articleProxy.GetArticleDetail(tenantId, id)
		if err != nil {
			writeJSONError(w, err.Error())
			return
		}
		writeJSON(w, result)
	})

	// 成员列表
	mux.HandleFunc("/api/cms/members", func(w http.ResponseWriter, r *http.Request) {
		tenantId := int32(parseInt(r.URL.Query().Get("tenantId"), 1))
		result, err := articleProxy.GetMemberList(tenantId)
		if err != nil {
			writeJSONError(w, err.Error())
			return
		}
		writeJSON(w, result)
	})

	// 站点配置
	mux.HandleFunc("/api/cms/config", func(w http.ResponseWriter, r *http.Request) {
		tenantId := int32(parseInt(r.URL.Query().Get("tenantId"), 1))
		result, err := articleProxy.GetSiteConfig(tenantId)
		if err != nil {
			writeJSONError(w, err.Error())
			return
		}
		writeJSON(w, result)
	})

	// ---------- 认证接口 ----------

	// 注册
	mux.HandleFunc("/api/auth/register", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			writeJSONError(w, "POST required")
			return
		}
		body := parseJSONBody(r)
		tenantId := int32(parseInt(body["tenantId"], 1))
		username := body["username"]
		password := body["password"]
		email := body["email"]
		result, err := authProxy.Register(tenantId, username, password, email)
		if err != nil {
			writeJSONError(w, err.Error())
			return
		}
		writeJSON(w, result)
	})

	// 登录
	mux.HandleFunc("/api/auth/login", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			writeJSONError(w, "POST required")
			return
		}
		body := parseJSONBody(r)
		tenantId := int32(parseInt(body["tenantId"], 1))
		username := body["username"]
		password := body["password"]
		result, err := authProxy.Login(tenantId, username, password)
		if err != nil {
			writeJSONError(w, err.Error())
			return
		}
		writeJSON(w, result)
	})

	// 用户信息
	mux.HandleFunc("/api/auth/userinfo", func(w http.ResponseWriter, r *http.Request) {
		tenantId := int32(parseInt(r.URL.Query().Get("tenantId"), 1))
		token := extractBearer(r)
		result, err := authProxy.GetUserInfo(tenantId, token)
		if err != nil {
			writeJSONError(w, err.Error())
			return
		}
		writeJSON(w, result)
	})

	// 登出
	mux.HandleFunc("/api/auth/logout", func(w http.ResponseWriter, r *http.Request) {
		tenantId := int32(parseInt(r.URL.Query().Get("tenantId"), 1))
		token := extractBearer(r)
		result, err := authProxy.Logout(tenantId, token)
		if err != nil {
			writeJSONError(w, err.Error())
			return
		}
		writeJSON(w, result)
	})

	// ---------- 后台管理接口 ----------

	// 文章列表（后台）
	mux.HandleFunc("/api/admin/articles", func(w http.ResponseWriter, r *http.Request) {
		tenantId := int32(parseInt(r.URL.Query().Get("tenantId"), 1))
		if r.Method == http.MethodGet {
			categoryId := int32(parseInt(r.URL.Query().Get("categoryId"), 0))
			status := int32(parseInt(r.URL.Query().Get("status"), -1))
			page := int32(parseInt(r.URL.Query().Get("page"), 1))
			size := int32(parseInt(r.URL.Query().Get("size"), 10))
			result, err := articleProxy.GetAdminArticleList(tenantId, categoryId, status, page, size)
			if err != nil {
				writeJSONError(w, err.Error())
				return
			}
			writeJSON(w, result)
			return
		}
		if r.Method == http.MethodPost {
			body := parseJSONBody(r)
			result, err := articleProxy.CreateArticle(
				tenantId,
				body["title"], body["summary"], body["content"],
				int32(parseInt(body["categoryId"], 0)),
				body["cover"], body["type"],
				body["isTop"] == "true", body["isFocus"] == "true", body["isBanner"] == "true",
				int32(parseInt(body["sort"], 0)),
				int32(parseInt(body["authorId"], 0)),
				body["source"],
			)
			if err != nil {
				writeJSONError(w, err.Error())
				return
			}
			writeJSON(w, result)
			return
		}
		writeJSONError(w, "GET or POST required")
	})

	// 文章详情（后台编辑用）
	mux.HandleFunc("/api/admin/articles/", func(w http.ResponseWriter, r *http.Request) {
		path := strings.TrimPrefix(r.URL.Path, "/api/admin/articles/")
		if path == "" {
			writeJSONError(w, "article id required")
			return
		}
		// PUT /api/admin/articles/:id
		id := int32(parseInt(path, 0))
		tenantId := int32(parseInt(r.URL.Query().Get("tenantId"), 1))
		if r.Method == http.MethodPut {
			body := parseJSONBody(r)
			result, err := articleProxy.UpdateArticle(
				tenantId, id,
				body["title"], body["summary"], body["content"],
				int32(parseInt(body["categoryId"], 0)),
				body["cover"], body["type"],
				body["isTop"] == "true", body["isFocus"] == "true", body["isBanner"] == "true",
				int32(parseInt(body["sort"], 0)),
				int32(parseInt(body["authorId"], 0)),
				body["source"],
			)
			if err != nil {
				writeJSONError(w, err.Error())
				return
			}
			writeJSON(w, result)
			return
		}
		// DELETE /api/admin/articles/:id
		if r.Method == http.MethodDelete {
			result, err := articleProxy.DeleteArticle(tenantId, id)
			if err != nil {
				writeJSONError(w, err.Error())
				return
			}
			writeJSON(w, result)
			return
		}
		writeJSONError(w, "PUT or DELETE required")
	})

	// 分类列表（后台）
	mux.HandleFunc("/api/admin/categories", func(w http.ResponseWriter, r *http.Request) {
		tenantId := int32(parseInt(r.URL.Query().Get("tenantId"), 1))
		if r.Method == http.MethodGet {
			result, err := articleProxy.GetAdminCategoryList(tenantId)
			if err != nil {
				writeJSONError(w, err.Error())
				return
			}
			writeJSON(w, result)
			return
		}
		if r.Method == http.MethodPost {
			body := parseJSONBody(r)
			result, err := articleProxy.CreateCategory(
				tenantId,
				int32(parseInt(body["pid"], 0)),
				body["name"], body["slug"],
				int32(parseInt(body["sort"], 0)),
			)
			if err != nil {
				writeJSONError(w, err.Error())
				return
			}
			writeJSON(w, result)
			return
		}
		writeJSONError(w, "GET or POST required")
	})

	// 分类详情（PUT/DELETE）
	mux.HandleFunc("/api/admin/categories/", func(w http.ResponseWriter, r *http.Request) {
		path := strings.TrimPrefix(r.URL.Path, "/api/admin/categories/")
		if path == "" {
			writeJSONError(w, "category id required")
			return
		}
		id := int32(parseInt(path, 0))
		tenantId := int32(parseInt(r.URL.Query().Get("tenantId"), 1))
		if r.Method == http.MethodPut {
			body := parseJSONBody(r)
			result, err := articleProxy.UpdateCategory(
				tenantId, id,
				int32(parseInt(body["pid"], 0)),
				body["name"], body["slug"],
				int32(parseInt(body["sort"], 0)),
			)
			if err != nil {
				writeJSONError(w, err.Error())
				return
			}
			writeJSON(w, result)
			return
		}
		if r.Method == http.MethodDelete {
			result, err := articleProxy.DeleteCategory(tenantId, id)
			if err != nil {
				writeJSONError(w, err.Error())
				return
			}
			writeJSON(w, result)
			return
		}
		writeJSONError(w, "PUT or DELETE required")
	})

	// 站点配置（GET/PUT）
	mux.HandleFunc("/api/admin/config", func(w http.ResponseWriter, r *http.Request) {
		tenantId := int32(parseInt(r.URL.Query().Get("tenantId"), 1))
		if r.Method == http.MethodGet {
			result, err := articleProxy.GetSiteConfig(tenantId)
			if err != nil {
				writeJSONError(w, err.Error())
				return
			}
			writeJSON(w, result)
			return
		}
		if r.Method == http.MethodPut {
			body := r.URL.Query().Get("config")
			// 直接把整个 body 转发（JSON 字符串）
			raw, _ := io.ReadAll(r.Body)
			result, err := articleProxy.UpdateSiteConfig(tenantId, string(raw))
			if err != nil {
				writeJSONError(w, err.Error())
				return
			}
			_ = body
			writeJSON(w, result)
			return
		}
		writeJSONError(w, "GET or PUT required")
	})

	// 成员列表（GET/POST）
	mux.HandleFunc("/api/admin/members", func(w http.ResponseWriter, r *http.Request) {
		tenantId := int32(parseInt(r.URL.Query().Get("tenantId"), 1))
		if r.Method == http.MethodGet {
			result, err := articleProxy.GetMemberList(tenantId)
			if err != nil {
				writeJSONError(w, err.Error())
				return
			}
			writeJSON(w, result)
			return
		}
		if r.Method == http.MethodPost {
			body := parseJSONBody(r)
			result, err := articleProxy.CreateMember(
				tenantId,
				body["name"], body["avatar"], body["title"], body["bio"], body["role"],
				int32(parseInt(body["sort"], 0)),
			)
			if err != nil {
				writeJSONError(w, err.Error())
				return
			}
			writeJSON(w, result)
			return
		}
		writeJSONError(w, "GET or POST required")
	})

	// 成员详情（PUT/DELETE）
	mux.HandleFunc("/api/admin/members/", func(w http.ResponseWriter, r *http.Request) {
		path := strings.TrimPrefix(r.URL.Path, "/api/admin/members/")
		if path == "" {
			writeJSONError(w, "member id required")
			return
		}
		id := int32(parseInt(path, 0))
		tenantId := int32(parseInt(r.URL.Query().Get("tenantId"), 1))
		if r.Method == http.MethodPut {
			body := parseJSONBody(r)
			result, err := articleProxy.UpdateMember(
				tenantId, id,
				body["name"], body["avatar"], body["title"], body["bio"], body["role"],
				int32(parseInt(body["sort"], 0)),
			)
			if err != nil {
				writeJSONError(w, err.Error())
				return
			}
			writeJSON(w, result)
			return
		}
		if r.Method == http.MethodDelete {
			result, err := articleProxy.DeleteMember(tenantId, id)
			if err != nil {
				writeJSONError(w, err.Error())
				return
			}
			writeJSON(w, result)
			return
		}
		writeJSONError(w, "PUT or DELETE required")
	})

	// 媒体列表
	mux.HandleFunc("/api/admin/media", func(w http.ResponseWriter, r *http.Request) {
		tenantId := int32(parseInt(r.URL.Query().Get("tenantId"), 1))
		page := int32(parseInt(r.URL.Query().Get("page"), 1))
		size := int32(parseInt(r.URL.Query().Get("size"), 10))
		result, err := articleProxy.GetMediaList(tenantId, page, size)
		if err != nil {
			writeJSONError(w, err.Error())
			return
		}
		writeJSON(w, result)
	})

	// 媒体删除: POST /api/admin/media/delete  body: {tenantId, id}
	// 删 DB 记录 + 物理文件（P1-3）
	mux.HandleFunc("/api/admin/media/delete", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			writeJSONError(w, "POST required")
			return
		}
		body := parseJSONBody(r)
		tenantId := int32(parseInt(body["tenantId"], 1))
		id := int32(parseInt(body["id"], 0))
		if id <= 0 {
			writeJSONError(w, "id required")
			return
		}
		result, err := articleProxy.DeleteMedia(tenantId, id)
		if err != nil {
			writeJSONError(w, err.Error())
			return
		}
		writeJSON(w, result)
	})

	// ---------- 上传接口（multipart → base64 → TARS） ----------

	// 图片上传: POST /api/admin/upload/image  (multipart: file)
	mux.HandleFunc("/api/admin/upload/image", func(w http.ResponseWriter, r *http.Request) {
		handleUpload(w, r, articleProxy, "image")
	})

	// 文件上传: POST /api/admin/upload/file   (multipart: file)
	mux.HandleFunc("/api/admin/upload/file", func(w http.ResponseWriter, r *http.Request) {
		handleUpload(w, r, articleProxy, "file")
	})

	// ---------- 上传文件静态托管（/uploads/ 经网关可访问） ----------
	uploadDir := os.Getenv("CMS_UPLOAD_DIR")
	if uploadDir == "" {
		uploadDir = "/data/tars/cms/uploads"
	}
	mux.Handle("/uploads/", http.StripPrefix("/uploads/", http.FileServer(http.Dir(uploadDir))))

	// ---------- 前端静态站点（h5/admin 构建产物，可选挂载） ----------
	// CMS_H5_DIR / CMS_ADMIN_DIR 设置后，/ 与 /admin/ 提供静态资源
	if h5Dir := os.Getenv("CMS_H5_DIR"); h5Dir != "" {
		mux.Handle("/", spaFileServer(h5Dir))
	}
	if adminDir := os.Getenv("CMS_ADMIN_DIR"); adminDir != "" {
		mux.Handle("/admin/", http.StripPrefix("/admin/", spaFileServer(adminDir)))
	}

	// CORS 中间件 + 后台鉴权
	// 注意：/api/admin/ 全部接口必须登录后才可访问（否则未授权可读写全部内容）
	handler := corsMiddleware(authMiddleware(authProxy, mux))

	// 启动
	port := os.Getenv("PORT")
	if port == "" {
		port = "3103"
	}
	fmt.Printf("cms BFF listening on :%s\n", port)
	if err := http.ListenAndServe(":"+port, handler); err != nil {
		fmt.Fprintf(os.Stderr, "listen failed: %v\n", err)
		os.Exit(1)
	}
}

// ---------- 工具函数 ----------

// authMiddleware 后台接口鉴权
// /api/admin/ 下的所有路由必须携带有效 token，否则返回 401。
// token 校验走 TARS AuthObj.GetUserInfo（code==0 视为有效）。
func authMiddleware(authProxy *cms.AuthObj, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// 仅保护后台接口；OPTIONS 预检放行
		if !strings.HasPrefix(r.URL.Path, "/api/admin/") || r.Method == http.MethodOptions {
			next.ServeHTTP(w, r)
			return
		}

		token := extractBearer(r)
		if token == "" {
			w.Header().Set("Content-Type", "application/json; charset=utf-8")
			w.WriteHeader(http.StatusUnauthorized)
			io.WriteString(w, `{"code":-1,"msg":"unauthorized: token required","data":null}`)
			return
		}

		tenantId := int32(parseInt(r.URL.Query().Get("tenantId"), 1))
		result, err := authProxy.GetUserInfo(tenantId, token)
		if err != nil {
			w.Header().Set("Content-Type", "application/json; charset=utf-8")
			w.WriteHeader(http.StatusUnauthorized)
			io.WriteString(w, `{"code":-1,"msg":"unauthorized","data":null}`)
			return
		}
		// GetUserInfo 返回 {"code":0,...} 表示有效
		if !strings.Contains(result, `"code":0`) {
			w.Header().Set("Content-Type", "application/json; charset=utf-8")
			w.WriteHeader(http.StatusUnauthorized)
			io.WriteString(w, `{"code":-1,"msg":"unauthorized: invalid or expired token","data":null}`)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func corsMiddleware(next http.Handler) http.Handler {
	// 允许的来源白名单（P1-2：禁止反射任意 Origin + 携带凭据）
	// 可用 CORS_ALLOWED_ORIGINS 覆盖，逗号分隔
	allowed := map[string]bool{}
	for _, o := range strings.Split(envOr(
		"CORS_ALLOWED_ORIGINS",
		"http://192.168.1.95:8200,http://127.0.0.1:8200,http://localhost:8200",
	), ",") {
		if o = strings.TrimSpace(o); o != "" {
			allowed[o] = true
		}
	}

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := r.Header.Get("Origin")
		if origin != "" && allowed[origin] {
			w.Header().Set("Access-Control-Allow-Origin", origin)
			w.Header().Set("Access-Control-Allow-Credentials", "true")
			w.Header().Set("Vary", "Origin")
		}
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusOK)
			return
		}
		next.ServeHTTP(w, r)
	})
}

// envOr 读取环境变量，空则用默认值（BFF 侧副本，避免跨包依赖）
func envOr(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func writeJSON(w http.ResponseWriter, data string) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	io.WriteString(w, data)
}

// handleUpload multipart 上传 → base64 → 调 cms TARS
func handleUpload(w http.ResponseWriter, r *http.Request, articleProxy *cms.ArticleObj, kind string) {
	if r.Method != http.MethodPost {
		writeJSONError(w, "POST required")
		return
	}
	// 解析 multipart（限制 20MB）
	r.Body = http.MaxBytesReader(w, r.Body, 20<<20)
	if err := r.ParseMultipartForm(20 << 20); err != nil {
		writeJSONError(w, "parse multipart failed: "+err.Error())
		return
	}
	file, header, err := r.FormFile("file")
	if err != nil {
		writeJSONError(w, "file field required: "+err.Error())
		return
	}
	defer file.Close()

	raw, err := io.ReadAll(file)
	if err != nil {
		writeJSONError(w, "read file failed: "+err.Error())
		return
	}
	if len(raw) == 0 {
		writeJSONError(w, "empty file")
		return
	}

	tenantId := int32(parseInt(r.URL.Query().Get("tenantId"), 1))
	b64 := base64.StdEncoding.EncodeToString(raw)

	var result string
	if kind == "image" {
		result, err = articleProxy.UploadImage(tenantId, header.Filename, b64)
	} else {
		result, err = articleProxy.UploadFile(tenantId, header.Filename, b64)
	}
	if err != nil {
		writeJSONError(w, err.Error())
		return
	}
	writeJSON(w, result)
}

// spaFileServer 提供 SPA 单页应用静态服务（history 路由回退 index.html）
func spaFileServer(dir string) http.Handler {
	fs := http.FileServer(http.Dir(dir))
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		path := filepath.Join(dir, r.URL.Path)
		// 文件存在则直接服务
		if st, err := os.Stat(path); err == nil && !st.IsDir() {
			fs.ServeHTTP(w, r)
			return
		}
		// 否则回退 index.html（SPA 路由）
		index := filepath.Join(dir, "index.html")
		if _, err := os.Stat(index); err == nil {
			http.ServeFile(w, r, index)
			return
		}
		http.NotFound(w, r)
	})
}

func writeJSONError(w http.ResponseWriter, msg string) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	fmt.Fprintf(w, `{"code":-1,"msg":%q,"data":null}`, msg)
}

func parseInt(s string, def int) int {
	if s == "" {
		return def
	}
	n := 0
	for _, c := range s {
		if c < '0' || c > '9' {
			return def
		}
		n = n*10 + int(c-'0')
	}
	return n
}

func extractBearer(r *http.Request) string {
	auth := r.Header.Get("Authorization")
	if strings.HasPrefix(auth, "Bearer ") {
		return strings.TrimPrefix(auth, "Bearer ")
	}
	return r.URL.Query().Get("token")
}

func parseJSONBody(r *http.Request) map[string]string {
	raw, _ := io.ReadAll(r.Body)
	// 简单 JSON 解析（避免引入额外依赖）
	result := make(map[string]string)
	// 粗略解析：{"key":"value", ...}
	s := strings.TrimSpace(string(raw))
	s = strings.TrimPrefix(s, "{")
	s = strings.TrimSuffix(s, "}")
	for _, kv := range strings.Split(s, ",") {
		parts := strings.SplitN(kv, ":", 2)
		if len(parts) != 2 {
			continue
		}
		k := strings.Trim(strings.TrimSpace(parts[0]), `"`)
		v := strings.Trim(strings.TrimSpace(parts[1]), `"`)
		result[k] = v
	}
	return result
}

var _ = context.Background
