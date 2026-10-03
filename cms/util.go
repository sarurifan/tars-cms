package main

import (
	"encoding/json"
	"strings"
	"time"

	"github.com/microcosm-cc/bluemonday"
)

// ============ 工具函数 ============

var (
	// htmlPolicy XSS 过滤白名单（参考 bluemonday UGCPolicy）
	htmlPolicy = bluemonday.UGCPolicy()
)

func init() {
	// 放宽常用标签：代码块、表格、标题等（CMS 需要）
	htmlPolicy.AllowElements("pre", "code", "table", "thead", "tbody", "tr", "td", "th",
		"h1", "h2", "h3", "h4", "h5", "h6",
		"blockquote", "hr", "br",
		"em", "strong", "del", "u",
		"ol", "ul", "li",
		"a", "img")
	htmlPolicy.AllowAttrs("href", "title", "target", "rel").OnElements("a")
	htmlPolicy.AllowAttrs("src", "alt", "title", "width", "height").OnElements("img")
	htmlPolicy.AllowAttrs("class").OnElements("pre", "code", "table", "div")
	// 防止 target=_blank 的 tabnabbing
	htmlPolicy.RequireNoFollowOnLinks(false)
	htmlPolicy.AllowAttrs("target").OnElements("a")
	htmlPolicy.AddTargetBlankToFullyQualifiedLinks(true)
}

// SanitizeHTML 净化富文本，防 XSS（存储前必过）
func SanitizeHTML(s string) string {
	return htmlPolicy.Sanitize(s)
}

// toJSON 序列化为 JSON 字符串（接口返回值格式）
func toJSON(v interface{}) string {
	b, err := json.Marshal(v)
	if err != nil {
		return `{"code":-1,"msg":"json marshal error","data":null}`
	}
	return string(b)
}

// toJSONOK 包装统一响应 {code, msg, data}
func toJSONOK(data interface{}) string {
	return toJSON(Response{Code: 0, Msg: "success", Data: data})
}

func toJSONFail(msg string) string {
	return toJSON(Response{Code: -1, Msg: msg, Data: nil})
}

// fmtTime 格式化时间为 "2006-01-02 15:04:05"
func fmtTime(t time.Time) string {
	if t.IsZero() {
		return ""
	}
	return t.Format("2006-01-02 15:04:05")
}

// truncateSummary 从正文截取摘要（去掉 HTML 标签）
func truncateSummary(html string, n int) string {
	// 去标签：用 bluemonday 的 StripTagsPolicy
	txt := bluemonday.StripTagsPolicy().Sanitize(html)
	txt = strings.TrimSpace(txt)
	txt = strings.Join(strings.Fields(txt), " ")
	if n <= 0 {
		n = 60
	}
	r := []rune(txt)
	if len(r) > n {
		return string(r[:n])
	}
	return txt
}

// buildCategoryTree 把平铺分类转成树形
func buildCategoryTree(list []Category) []*CategoryNode {
	nodes := make(map[int64]*CategoryNode, len(list))
	var roots []*CategoryNode

	for _, c := range list {
		nodes[c.ID] = &CategoryNode{
			ID:    c.ID,
			Name:  c.Name,
			Slug:  c.Slug,
			PID:   c.PID,
			Sort:  c.Sort,
			Children: []*CategoryNode{},
		}
	}
	for _, c := range list {
		n := nodes[c.ID]
		if c.PID == 0 {
			roots = append(roots, n)
		} else if p, ok := nodes[c.PID]; ok {
			p.Children = append(p.Children, n)
		} else {
			roots = append(roots, n) // 父找不到时提升为根
		}
	}
	// 排序：同层按 sort asc, id asc
	sortNodes(roots)
	return roots
}

func sortNodes(ns []*CategoryNode) {
	if len(ns) <= 1 {
		return
	}
	// 简单插入排序（类目数少，够用）
	for i := 1; i < len(ns); i++ {
		for j := i; j > 0; j-- {
			a, b := ns[j-1], ns[j]
			if a.Sort > b.Sort || (a.Sort == b.Sort && a.ID > b.ID) {
				ns[j-1], ns[j] = b, a
			} else {
				break
			}
		}
	}
	for _, n := range ns {
		sortNodes(n.Children)
	}
}

// toListItem Article -> ArticleListItem
func toListItem(a Article, cat *Category) ArticleListItem {
	item := ArticleListItem{
		ID:        a.ID,
		Title:     a.Title,
		Summary:   a.Summary,
		Cover:     a.Cover,
		Type:      a.Type,
		ViewCount: a.ViewCount,
		PublishAt: fmtTime(a.PublishAt),
		Sort:      a.Sort,
	}
	if cat != nil {
		item.Category.ID = cat.ID
		item.Category.Name = cat.Name
	}
	return item
}

// toDetail Article + ArticleBody -> ArticleDetail
func toDetail(a Article, body string, cat *Category, m *Member) ArticleDetail {
	d := ArticleDetail{
		ID:        a.ID,
		Title:     a.Title,
		Summary:   a.Summary,
		Content:   body,
		Cover:     a.Cover,
		Type:      a.Type,
		Source:    a.Source,
		ViewCount: a.ViewCount,
		PublishAt: fmtTime(a.PublishAt),
	}
	if cat != nil {
		d.Category.ID = cat.ID
		d.Category.Name = cat.Name
	}
	if m != nil {
		d.Author.ID = m.ID
		d.Author.Name = m.Name
	}
	return d
}
