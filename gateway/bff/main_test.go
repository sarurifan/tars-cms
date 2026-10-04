package main

import (
	"net/http/httptest"
	"strings"
	"testing"
)

// ==================== parseInt（BFF 参数解析）====================

func TestParseInt(t *testing.T) {
	cases := []struct {
		in   string
		def  int
		want int
	}{
		{"", 5, 5},       // 空串 → 默认
		{"42", 5, 42},    // 正常
		{"0", 5, 0},      // 0 是合法值
		{"-3", 5, 5},     // 负数 → 默认
		{"abc", 5, 5},    // 非数字 → 默认
		{"12a", 5, 5},    // 混合 → 默认
		{"999", 0, 999},  // 大数
		{" 7 ", 0, 0},    // 带空格 → 默认
		{"007", 0, 7},    // 前导 0
	}
	for _, c := range cases {
		got := parseInt(c.in, c.def)
		if got != c.want {
			t.Errorf("parseInt(%q,%d) = %d, want %d", c.in, c.def, got, c.want)
		}
	}
}

// ==================== extractBearer（token 提取）====================

func TestExtractBearer_Header(t *testing.T) {
	req := httptest.NewRequest("GET", "/api/x", nil)
	req.Header.Set("Authorization", "Bearer abc123")
	if got := extractBearer(req); got != "abc123" {
		t.Errorf("从 Header 提取 = %q, want abc123", got)
	}
}

func TestExtractBearer_Query(t *testing.T) {
	req := httptest.NewRequest("GET", "/api/x?token=fromQuery", nil)
	if got := extractBearer(req); got != "fromQuery" {
		t.Errorf("从 Query 提取 = %q, want fromQuery", got)
	}
}

func TestExtractBearer_HeaderPrecedence(t *testing.T) {
	req := httptest.NewRequest("GET", "/api/x?token=queryToken", nil)
	req.Header.Set("Authorization", "Bearer headerToken")
	if got := extractBearer(req); got != "headerToken" {
		t.Errorf("Header 应优先, got %q", got)
	}
}

func TestExtractBearer_NonBearer(t *testing.T) {
	req := httptest.NewRequest("GET", "/api/x", nil)
	req.Header.Set("Authorization", "Basic dXNlcjpwYXNz") // 非 Bearer
	if got := extractBearer(req); got != "" {
		t.Errorf("非 Bearer 应返回空, got %q", got)
	}
}

func TestExtractBearer_Empty(t *testing.T) {
	req := httptest.NewRequest("GET", "/api/x", nil)
	if got := extractBearer(req); got != "" {
		t.Errorf("无 token 应返回空, got %q", got)
	}
}

// ==================== parseJSONBody（简单 JSON 解析）====================

func TestParseJSONBody_Basic(t *testing.T) {
	req := httptest.NewRequest("POST", "/api/x", strings.NewReader(`{"username":"admin","password":"secret"}`))
	m := parseJSONBody(req)
	if m["username"] != "admin" || m["password"] != "secret" {
		t.Errorf("解析错误: %v", m)
	}
}

func TestParseJSONBody_Empty(t *testing.T) {
	req := httptest.NewRequest("POST", "/api/x", strings.NewReader(""))
	m := parseJSONBody(req)
	if len(m) != 0 {
		t.Errorf("空 body 应返回空 map, got %v", m)
	}
}

func TestParseJSONBody_Malformed(t *testing.T) {
	req := httptest.NewRequest("POST", "/api/x", strings.NewReader("not json"))
	m := parseJSONBody(req)
	if len(m) != 0 {
		t.Errorf("非法 JSON 应返回空 map, got %v", m)
	}
}

func TestParseJSONBody_WithSpaces(t *testing.T) {
	req := httptest.NewRequest("POST", "/api/x", strings.NewReader(`{ "key" : "value" }`))
	m := parseJSONBody(req)
	if m["key"] != "value" {
		t.Errorf("带空格解析错误: %v", m)
	}
}

func TestParseJSONBody_Nested(t *testing.T) {
	// 简单解析器不处理嵌套，只取第一层
	req := httptest.NewRequest("POST", "/api/x", strings.NewReader(`{"a":{"b":"c"},"d":"e"}`))
	m := parseJSONBody(req)
	if m["a"] != `{"b":"c"}` {
		t.Errorf("嵌套对象解析: %v", m)
	}
	if m["d"] != "e" {
		t.Errorf("d = %v", m)
	}
}

// ==================== writeJSONError（错误响应格式）====================

func TestWriteJSONError_Format(t *testing.T) {
	w := httptest.NewRecorder()
	writeJSONError(w, "出错了")
	body := w.Body.String()
	if !strings.Contains(body, `"code":-1`) {
		t.Errorf("缺 code:-1: %s", body)
	}
	if !strings.Contains(body, `"msg":"出错了"`) {
		t.Errorf("缺 msg: %s", body)
	}
	if ct := w.Header().Get("Content-Type"); ct != "application/json; charset=utf-8" {
		t.Errorf("Content-Type = %q", ct)
	}
}
