package main

import (
	"crypto/sha1"
	"encoding/hex"
	"encoding/json"
	"io"
	"net/http"
	"sort"
	"strings"
	"time"
)

// Response 统一 RPC/JSON 返回包装
type Response struct {
	Code int         `json:"code"`
	Msg  string      `json:"msg"`
	Data interface{} `json:"data"`
}

func toJSON(v interface{}) string {
	b, err := json.Marshal(v)
	if err != nil {
		return `{"code":-1,"msg":"json marshal error","data":null}`
	}
	return string(b)
}

func toJSONOK(data interface{}) string {
	return toJSON(Response{Code: 0, Msg: "success", Data: data})
}

func toJSONFail(msg string) string {
	return toJSON(Response{Code: -1, Msg: msg, Data: nil})
}

// verifyWxSignature 公众号服务器校验签名
func verifyWxSignature(token, timestamp, nonce, signature string) bool {
	strs := []string{token, timestamp, nonce}
	sort.Strings(strs)
	combined := strings.Join(strs, "")
	h := sha1.New()
	h.Write([]byte(combined))
	calc := hex.EncodeToString(h.Sum(nil))
	return strings.ToLower(calc) == strings.ToLower(signature)
}

// httpGetJSON 通用 GET 请求解析 JSON
func httpGetJSON(url string, target interface{}) error {
	client := &http.Client{Timeout: 8 * time.Second}
	resp, err := client.Get(url)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return err
	}
	return json.Unmarshal(body, target)
}

// httpPostJSON 通用 POST 请求
func httpPostJSON(url string, reqBody interface{}, target interface{}) error {
	client := &http.Client{Timeout: 8 * time.Second}
	b, err := json.Marshal(reqBody)
	if err != nil {
		return err
	}
	resp, err := client.Post(url, "application/json", strings.NewReader(string(b)))
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return err
	}
	return json.Unmarshal(body, target)
}

// fmtTime
func fmtTime(t time.Time) string {
	if t.IsZero() {
		return ""
	}
	return t.Format("2006-01-02 15:04:05")
}
