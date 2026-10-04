package main

import (
	"encoding/json"
	"strings"
	"testing"
	"time"
)

// ==================== SanitizeHTML（XSS 过滤）====================

func TestSanitizeHTML_XSSRemoval(t *testing.T) {
	cases := []struct {
		name     string
		in       string
		contains string  // 应保留的内容
		notContain string // 不应包含（危险片段）
	}{
		{"script标签剥离", `<p>安全</p><script>alert('xss')</script>`, "安全", "script"},
		{"onclick事件剥离", `<p onclick="evil()">点我</p>`, "点我", "onclick"},
		{"javascript协议", `<a href="javascript:alert(1)">链接</a>`, "链接", "javascript:"},
		{"onerror事件剥离", `<img src=x onerror="alert(1)">`, "img", "onerror"},
		{"iframe剥离", `<iframe src="http://evil.com"></iframe>`, "", "iframe"},
		{"保持合法标签", `<h1>标题</h1><p><strong>加粗</strong></p><code>代码</code>`, "标题", ""},
		{"表格保留", `<table><tr><td>单元格</td></tr></table>`, "单元格", ""},
		{"链接保留+target", `<a href="http://example.com" target="_blank">外部</a>`, "example.com", ""},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := SanitizeHTML(c.in)
			if c.contains != "" && !strings.Contains(got, c.contains) {
				t.Errorf("应保留 %q，得到: %s", c.contains, got)
			}
			if c.notContain != "" && strings.Contains(strings.ToLower(got), strings.ToLower(c.notContain)) {
				t.Errorf("应移除 %q，得到: %s", c.notContain, got)
			}
		})
	}
}

func TestSanitizeHTML_KeepsImageAttrs(t *testing.T) {
	got := SanitizeHTML(`<img src="/a.png" alt="图" width="100" height="50">`)
	if !strings.Contains(got, `src="/a.png"`) {
		t.Errorf("图片 src 应保留: %s", got)
	}
	if !strings.Contains(got, `alt="图"`) {
		t.Errorf("图片 alt 应保留: %s", got)
	}
}

// ==================== truncateSummary（摘要截取）====================

func TestTruncateSummary(t *testing.T) {
	cases := []struct {
		name string
		in   string
		n    int
		want string
	}{
		{"纯文本不截断", "短文本", 60, "短文本"},
		{"去HTML标签", "<p>这是正文</p>", 60, "这是正文"},
		{"超长截断", strings.Repeat("字", 100), 10, strings.Repeat("字", 10)},
		{"n<=0用默认60", strings.Repeat("a", 100), 0, strings.Repeat("a", 60)},
		{"多空白合并", "  多   个   空格  ", 60, "多 个 空格"},
		{"中文按rune截断", "中文测试内容足够长", 3, "中文测"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := truncateSummary(c.in, c.n)
			if got != c.want {
				t.Errorf("got %q, want %q", got, c.want)
			}
		})
	}
}

// ==================== buildCategoryTree（分类树构建）====================

func TestBuildCategoryTree_Flat(t *testing.T) {
	list := []Category{
		{ID: 1, PID: 0, Name: "A", Sort: 20},
		{ID: 2, PID: 0, Name: "B", Sort: 10},
		{ID: 3, PID: 0, Name: "C", Sort: 30},
	}
	roots := buildCategoryTree(list)
	if len(roots) != 3 {
		t.Fatalf("根节点数 = %d, want 3", len(roots))
	}
	// 按 sort asc: B(10) A(20) C(30)
	if roots[0].Name != "B" || roots[1].Name != "A" || roots[2].Name != "C" {
		t.Errorf("排序错误: %s %s %s", roots[0].Name, roots[1].Name, roots[2].Name)
	}
}

func TestBuildCategoryTree_Hierarchical(t *testing.T) {
	list := []Category{
		{ID: 1, PID: 0, Name: "父1", Sort: 10},
		{ID: 2, PID: 0, Name: "父2", Sort: 20},
		{ID: 3, PID: 1, Name: "子1-1", Sort: 10},
		{ID: 4, PID: 1, Name: "子1-2", Sort: 20},
		{ID: 5, PID: 3, Name: "孙1-1-1", Sort: 10},
	}
	roots := buildCategoryTree(list)
	if len(roots) != 2 {
		t.Fatalf("根节点数 = %d, want 2", len(roots))
	}
	if len(roots[0].Children) != 2 {
		t.Errorf("父1 子节点 = %d, want 2", len(roots[0].Children))
	}
	if len(roots[0].Children[0].Children) != 1 {
		t.Errorf("子1-1 孙节点 = %d, want 1", len(roots[0].Children[0].Children))
	}
}

func TestBuildCategoryTree_OrphanPromoted(t *testing.T) {
	list := []Category{
		{ID: 1, PID: 0, Name: "正常", Sort: 10},
		{ID: 9, PID: 99, Name: "孤儿", Sort: 20}, // PID 不存在
	}
	roots := buildCategoryTree(list)
	if len(roots) != 2 {
		t.Errorf("孤儿应提升为根, got %d 根", len(roots))
	}
}

func TestBuildCategoryTree_SortTieBreakByID(t *testing.T) {
	list := []Category{
		{ID: 5, PID: 0, Name: "五", Sort: 10},
		{ID: 3, PID: 0, Name: "三", Sort: 10},
	}
	roots := buildCategoryTree(list)
	// sort 相同按 id asc: 3, 5
	if roots[0].ID != 3 || roots[1].ID != 5 {
		t.Errorf("sort 相同应按 id asc, got %d, %d", roots[0].ID, roots[1].ID)
	}
}

// ==================== fmtTime（时间格式化）====================

func TestFmtTime(t *testing.T) {
	zero := time.Time{}
	if got := fmtTime(zero); got != "" {
		t.Errorf("零值时间应返回空, got %q", got)
	}
	tm := time.Date(2026, 10, 4, 15, 30, 45, 0, time.UTC)
	want := "2026-10-04 15:30:45"
	if got := fmtTime(tm); got != want {
		t.Errorf("got %q, want %q", got, want)
	}
}

// ==================== toListItem / toDetail（模型转换）====================

func TestToListItem_WithCategory(t *testing.T) {
	a := Article{
		ID: 1, Title: "标题", Summary: "摘要", Cover: "c.png",
		Type: "doc", ViewCount: 42, Sort: 10,
		PublishAt: time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC),
	}
	cat := &Category{ID: 7, Name: "分类"}
	item := toListItem(a, cat)

	if item.Category.ID != 7 || item.Category.Name != "分类" {
		t.Errorf("分类字段错误: %+v", item.Category)
	}
	if item.PublishAt != "2026-01-01 00:00:00" {
		t.Errorf("PublishAt = %q", item.PublishAt)
	}
	if item.ViewCount != 42 {
		t.Errorf("ViewCount = %d", item.ViewCount)
	}
}

func TestToListItem_NilCategory(t *testing.T) {
	a := Article{ID: 2, Title: "t"}
	item := toListItem(a, nil)
	// 分类应为空（零值）
	if item.Category.ID != 0 || item.Category.Name != "" {
		t.Errorf("nil 分类应为零值, got %+v", item.Category)
	}
}

func TestToDetail_NilMember(t *testing.T) {
	a := Article{ID: 3, Title: "t"}
	d := toDetail(a, "<p>正文</p>", nil, nil)
	if d.Content != "<p>正文</p>" {
		t.Errorf("Content = %q", d.Content)
	}
	if d.Author.ID != 0 || d.Author.Name != "" {
		t.Errorf("nil member 应为零值, got %+v", d.Author)
	}
}

// ==================== toJSON 系列（响应包装）====================

func TestToJSONOK(t *testing.T) {
	got := toJSONOK(map[string]string{"k": "v"})
	var resp struct {
		Code int               `json:"code"`
		Msg  string            `json:"msg"`
		Data map[string]string `json:"data"`
	}
	if err := json.Unmarshal([]byte(got), &resp); err != nil {
		t.Fatalf("JSON 解析失败: %v", err)
	}
	if resp.Code != 0 || resp.Msg != "success" {
		t.Errorf("code=%d msg=%q", resp.Code, resp.Msg)
	}
	if resp.Data["k"] != "v" {
		t.Errorf("data = %v", resp.Data)
	}
}

func TestToJSONFail(t *testing.T) {
	got := toJSONFail("boom")
	var resp struct {
		Code int    `json:"code"`
		Msg  string `json:"msg"`
	}
	if err := json.Unmarshal([]byte(got), &resp); err != nil {
		t.Fatalf("解析失败: %v", err)
	}
	if resp.Code != -1 || resp.Msg != "boom" {
		t.Errorf("code=%d msg=%q", resp.Code, resp.Msg)
	}
}
