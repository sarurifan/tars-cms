package main

import (
	"testing"
)

// ==================== sanitizeFilename / detectMime（上传安全）====================

func TestSanitizeFilename(t *testing.T) {
	cases := []struct {
		in   string
		want string
	}{
		{"photo.png", "photo.png"},
		{"../../etc/passwd", "passwd"}, // 路径穿越 → 取 base
		{"a b.png", "a_b.png"},         // 空格 → _
		{"中文名.jpg", "中文名.jpg"},       // 中文保留
		{"semi;colon.txt", "semi_colon.txt"},
		{"", "file.bin"},       // 空 → 默认
		{"..", "file.bin"},     // 特殊 → 默认
		{"a*b*c.png", "a_b_c.png"}, // 非法字符 → _
	}
	for _, c := range cases {
		got := sanitizeFilename(c.in)
		if got != c.want {
			t.Errorf("sanitizeFilename(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}

func TestDetectMime(t *testing.T) {
	cases := []struct {
		name string
		want string
	}{
		{"a.png", "image/png"},
		{"a.jpg", "image/jpeg"},
		{"a.jpeg", "image/jpeg"},
		{"a.gif", "image/gif"},
		{"a.webp", "image/webp"},
		{"a.svg", "image/svg+xml"},
		{"a.pdf", "application/pdf"},
		{"a.md", "text/markdown"},
		{"a.txt", "text/plain"},
		{"a.zip", "application/zip"},
		{"a.json", "application/json"},
		{"a.js", "application/javascript"},
		{"a.css", "text/css"},
		{"a.xyz", "application/octet-stream"},
		{"noext", "application/octet-stream"},
		{"a.PNG", "image/png"}, // 大写
	}
	for _, c := range cases {
		got := detectMime(c.name)
		if got != c.want {
			t.Errorf("detectMime(%q) = %q, want %q", c.name, got, c.want)
		}
	}
}
