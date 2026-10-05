package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strconv"
	"strings"

	"github.com/TarsCloud/TarsGo/tars"
	"github.com/tars-cms/wx/tars-protocol/wx"
)

// wx-bff — HTTP → TARS 协议转换层（微信节点，端口 3203）
//
// 链路：
//   前端/客户端 → TarsGateway(8200) → wx-bff(3203) → wx.WxServer(13201 tars adapter)
//
// 提供的 REST API：
//   GET  /health                  健康检查
//   GET  /api/wx/mp/token         获取公众号 access_token (中控)
//   POST /api/wx/mp/token/refresh 强制刷新公众号 access_token
//   GET  /api/wx/mp/userinfo      获取关注用户基本信息
//   POST /api/wx/mp/template/send 发送模板消息
//   GET  /api/wx/verify           微信服务器验签接口 (供配置时自测)
//   POST /api/wx/ma/code2session  小程序登录换取 openid
//   GET  /api/wx/ma/token         获取小程序 access_token (中控)
//   POST /api/wx/ma/subscribe/send 发送小程序订阅消息

func main() {
	nodeIP := envOr("CMS_NODE_IP", "172.25.0.5")

	comm := tars.NewCommunicator()
	mpObj := fmt.Sprintf("wx.WxServer.MpObj@tcp -h %s -t 60000 -p 13201 -e 0", nodeIP)
	mpProxy := wx.NewMpObj()
	comm.StringToProxy(mpObj, mpProxy)

	maObj := fmt.Sprintf("wx.WxServer.MaObj@tcp -h %s -t 60000 -p 13202 -e 0", nodeIP)
	maProxy := wx.NewMaObj()
	comm.StringToProxy(maObj, maProxy)

	rpcTimeout := 8000
	if v := os.Getenv("CMS_RPC_TIMEOUT_MS"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 {
			rpcTimeout = n
		}
	}
	mpProxy.TarsSetTimeout(rpcTimeout)
	maProxy.TarsSetTimeout(rpcTimeout)

	mux := http.NewServeMux()

	// ---------- 健康检查 ----------
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json; charset=utf-8")
		io.WriteString(w, `{"status":"ok","service":"wx.WxBff","rpc_timeout_ms":`+strconv.Itoa(rpcTimeout)+`}`)
	})
	mux.HandleFunc("/health/full", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json; charset=utf-8")
		// 调一次验签测连通性
		if _, err := mpProxy.VerifySignature("test", "123", "456", "abc"); err != nil {
			w.WriteHeader(http.StatusServiceUnavailable)
			io.WriteString(w, `{"status":"degraded","error":"`+strings.ReplaceAll(err.Error(), `"`, "'")+`"}`)
			return
		}
		io.WriteString(w, `{"status":"ok","rpc":"up"}`)
	})

	// ---------- 公众号接口 ----------

	// access_token (中控读取)
	mux.HandleFunc("/api/wx/mp/token", func(w http.ResponseWriter, r *http.Request) {
		tenantId := int32(parseInt(r.URL.Query().Get("tenantId"), 1))
		appid := r.URL.Query().Get("appid")
		if appid == "" {
			writeJSONError(w, "appid required")
			return
		}
		result, err := mpProxy.GetAccessToken(tenantId, appid)
		if err != nil {
			writeJSONError(w, err.Error())
			return
		}
		writeJSON(w, result)
	})

	// access_token 强制刷新
	mux.HandleFunc("/api/wx/mp/token/refresh", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			writeJSONError(w, "POST required")
			return
		}
		tenantId := int32(parseInt(r.URL.Query().Get("tenantId"), 1))
		body := parseJSONBody(r)
		appid := body["appid"]
		if appid == "" {
			appid = r.URL.Query().Get("appid")
		}
		if appid == "" {
			writeJSONError(w, "appid required")
			return
		}
		result, err := mpProxy.RefreshAccessToken(tenantId, appid)
		if err != nil {
			writeJSONError(w, err.Error())
			return
		}
		writeJSON(w, result)
	})

	// 获取用户基本信息
	mux.HandleFunc("/api/wx/mp/userinfo", func(w http.ResponseWriter, r *http.Request) {
		tenantId := int32(parseInt(r.URL.Query().Get("tenantId"), 1))
		appid := r.URL.Query().Get("appid")
		openid := r.URL.Query().Get("openid")
		if appid == "" || openid == "" {
			writeJSONError(w, "appid and openid required")
			return
		}
		result, err := mpProxy.GetUserInfo(tenantId, appid, openid)
		if err != nil {
			writeJSONError(w, err.Error())
			return
		}
		writeJSON(w, result)
	})

	// 发送模板消息
	mux.HandleFunc("/api/wx/mp/template/send", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			writeJSONError(w, "POST required")
			return
		}
		tenantId := int32(parseInt(r.URL.Query().Get("tenantId"), 1))
		body := parseJSONBody(r)
		appid := body["appid"]
		openid := body["openid"]
		templateId := body["template_id"]
		data := body["data"]
		url := body["url"]
		if appid == "" || openid == "" || templateId == "" {
			writeJSONError(w, "appid, openid, template_id required")
			return
		}
		result, err := mpProxy.SendTemplateMsg(tenantId, appid, openid, templateId, data, url)
		if err != nil {
			writeJSONError(w, err.Error())
			return
		}
		writeJSON(w, result)
	})

	// 辅助签名验证
	mux.HandleFunc("/api/wx/verify", func(w http.ResponseWriter, r *http.Request) {
		q := r.URL.Query()
		token := q.Get("token")
		timestamp := q.Get("timestamp")
		nonce := q.Get("nonce")
		signature := q.Get("signature")
		if token == "" || signature == "" {
			writeJSONError(w, "token and signature required")
			return
		}
		result, err := mpProxy.VerifySignature(token, timestamp, nonce, signature)
		if err != nil {
			writeJSONError(w, err.Error())
			return
		}
		writeJSON(w, result)
	})

	// ---------- 小程序接口 ----------

	// code2session 登录凭证校验
	mux.HandleFunc("/api/wx/ma/code2session", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			writeJSONError(w, "POST required")
			return
		}
		tenantId := int32(parseInt(r.URL.Query().Get("tenantId"), 1))
		body := parseJSONBody(r)
		appid := body["appid"]
		code := body["code"]
		if appid == "" || code == "" {
			writeJSONError(w, "appid and code required")
			return
		}
		result, err := maProxy.Code2Session(tenantId, appid, code)
		if err != nil {
			writeJSONError(w, err.Error())
			return
		}
		writeJSON(w, result)
	})

	// 小程序 access_token (中控读取)
	mux.HandleFunc("/api/wx/ma/token", func(w http.ResponseWriter, r *http.Request) {
		tenantId := int32(parseInt(r.URL.Query().Get("tenantId"), 1))
		appid := r.URL.Query().Get("appid")
		if appid == "" {
			writeJSONError(w, "appid required")
			return
		}
		result, err := maProxy.GetAccessToken(tenantId, appid)
		if err != nil {
			writeJSONError(w, err.Error())
			return
		}
		writeJSON(w, result)
	})

	// 小程序微信登录（code → openid → cms token）
	mux.HandleFunc("/api/wx/ma/login", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			writeJSONError(w, "POST required")
			return
		}
		tenantId := int32(parseInt(r.URL.Query().Get("tenantId"), 1))
		body := parseJSONBody(r)
		appid := body["appid"]
		code := body["code"]
		if appid == "" || code == "" {
			writeJSONError(w, "appid and code required")
			return
		}
		result, err := maProxy.Login(tenantId, appid, code)
		if err != nil {
			writeJSONError(w, err.Error())
			return
		}
		writeJSON(w, result)
	})

	// 小程序发送订阅消息
	mux.HandleFunc("/api/wx/ma/subscribe/send", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			writeJSONError(w, "POST required")
			return
		}
		tenantId := int32(parseInt(r.URL.Query().Get("tenantId"), 1))
		body := parseJSONBody(r)
		appid := body["appid"]
		openid := body["openid"]
		templateId := body["template_id"]
		data := body["data"]
		page := body["page"]
		if appid == "" || openid == "" || templateId == "" {
			writeJSONError(w, "appid, openid, template_id required")
			return
		}
		result, err := maProxy.SendSubscribeMsg(tenantId, appid, openid, templateId, data, page)
		if err != nil {
			writeJSONError(w, err.Error())
			return
		}
		writeJSON(w, result)
	})

	port := envOr("PORT", "3203")
	handler := corsMiddleware(mux)

	fmt.Printf("wx-bff listening on :%s (forwarding to wx.WxServer on %s:13201)\n", port, nodeIP)
	if err := http.ListenAndServe(":"+port, handler); err != nil {
		fmt.Fprintf(os.Stderr, "server error: %v\n", err)
		os.Exit(1)
	}
}

// ============ 中间件与辅助函数 ============

func corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// 安全响应头（与 cms BFF 保持一致标准）
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("X-Frame-Options", "SAMEORIGIN")
		w.Header().Set("Referrer-Policy", "strict-origin-when-cross-origin")
		w.Header().Set("X-XSS-Protection", "0")

		origin := r.Header.Get("Origin")
		if origin != "" {
			w.Header().Set("Access-Control-Allow-Origin", origin)
			w.Header().Set("Access-Control-Allow-Credentials", "true")
			w.Header().Set("Vary", "Origin")
		}
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")

		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

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

func writeJSONError(w http.ResponseWriter, msg string) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	fmt.Fprintf(w, `{"code":-1,"msg":%q,"data":null}`, msg)
}

func parseInt(s string, def int) int {
	if s == "" {
		return def
	}
	n, err := strconv.Atoi(s)
	if err != nil {
		return def
	}
	return n
}

func parseJSONBody(r *http.Request) map[string]string {
	raw, _ := io.ReadAll(r.Body)
	result := make(map[string]string)
	var obj map[string]interface{}
	if err := json.Unmarshal(raw, &obj); err == nil {
		for k, v := range obj {
			switch val := v.(type) {
			case string:
				result[k] = val
			default:
				b, _ := json.Marshal(val)
				result[k] = string(b)
			}
		}
	}
	return result
}
