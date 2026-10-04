package main

import "testing"

// isAllowedUploadExt 是安全白名单，必须能挡住所有可携带脚本的扩展名。
// 这些用例编码「为什么」：防任意文件上传与存储型 XSS（P0-1）。

func TestUploadWhitelist_BlocksScriptableExtensions(t *testing.T) {
	// 高危扩展名：无论 kind 是 image 还是 file，一律拒绝
	// 理由：这些类型能在同源下执行脚本，可窃取管理员 token
	dangerous := []string{
		".html", ".htm", ".svg", ".php", ".phtml", ".php3",
		".js", ".mjs", ".jsp", ".asp", ".aspx", ".cgi", ".sh",
		".exe", ".bat", ".cmd", ".swf", ".xhtml",
		".css", // 可注入 CSS 绕过 UI 诱导
		".xml", // XXE 风险
	}
	for _, ext := range dangerous {
		for _, kind := range []string{"image", "file", "other"} {
			if isAllowedUploadExt(ext, kind) {
				t.Errorf("必须拒绝 %q (kind=%q)，但被放行了", ext, kind)
			}
		}
	}
}

func TestUploadWhitelist_AllowsImages(t *testing.T) {
	imageOK := []string{".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp", ".ico"}
	for _, ext := range imageOK {
		if !isAllowedUploadExt(ext, "image") {
			t.Errorf("图片 kind 应放行 %q", ext)
		}
		if !isAllowedUploadExt(ext, "file") {
			t.Errorf("文件 kind 也应放行图片 %q（附件里可放图）", ext)
		}
	}
}

func TestUploadWhitelist_ImageKindRejectsNonImage(t *testing.T) {
	// 图片接口收到非图片 → 拒绝（即使扩展名在通用白名单里）
	for _, ext := range []string{".pdf", ".zip", ".txt", ".doc"} {
		if isAllowedUploadExt(ext, "image") {
			t.Errorf("image kind 应拒绝非图片 %q", ext)
		}
	}
}

func TestUploadWhitelist_FileKindAllowsDocs(t *testing.T) {
	fileOK := []string{".pdf", ".txt", ".md", ".zip", ".csv", ".docx", ".xlsx"}
	for _, ext := range fileOK {
		if !isAllowedUploadExt(ext, "file") {
			t.Errorf("文件 kind 应放行 %q", ext)
		}
	}
}

func TestUploadWhitelist_EmptyAndNoExt(t *testing.T) {
	for _, ext := range []string{"", "."} {
		if isAllowedUploadExt(ext, "image") || isAllowedUploadExt(ext, "file") {
			t.Errorf("空/无扩展名 %q 应拒绝", ext)
		}
	}
}

func TestUploadWhitelist_CaseInsensitive(t *testing.T) {
	// 大写扩展名必须与小写同等处理（否则 .HTML 绕过）
	if isAllowedUploadExt(".HTML", "file") {
		t.Error(".HTML 必须拒绝（大小写不敏感）")
	}
	if !isAllowedUploadExt(".PNG", "image") {
		t.Error(".PNG 必须放行（大小写不敏感）")
	}
}
