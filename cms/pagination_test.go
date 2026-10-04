package main

import (
	"testing"
)

// TestNormPage_ZeroValues — 非法分页参数应优雅降级（0 → 1/10）
func TestNormPage_ZeroValues(t *testing.T) {
	page, size := normPage(0, 0)
	if page != 1 {
		t.Errorf("page=0 应归一化为 1，实际 %d", page)
	}
	if size != 10 {
		t.Errorf("size=0 应归一化为 10，实际 %d", size)
	}
}

// TestNormPage_NegativeValues — 负数视为非法
func TestNormPage_NegativeValues(t *testing.T) {
	page, size := normPage(-3, -5)
	if page != 1 || size != 10 {
		t.Errorf("负数应归一化为 1/10，实际 %d/%d", page, size)
	}
}

// TestNormPage_SizeCap — size 超限必须封顶 100（防大查询打满内存）
func TestNormPage_SizeCap(t *testing.T) {
	_, size := normPage(1, 99999)
	if size != 100 {
		t.Errorf("size=99999 应封顶为 100，实际 %d", size)
	}
	_, size = normPage(1, 101)
	if size != 100 {
		t.Errorf("size=101 应封顶为 100，实际 %d", size)
	}
}

// TestNormPage_ValidValues — 合法值原样返回
func TestNormPage_ValidValues(t *testing.T) {
	page, size := normPage(3, 20)
	if page != 3 || size != 20 {
		t.Errorf("合法输入应原样返回，实际 %d/%d", page, size)
	}
}

// TestNormPage_SizeCapBoundary — 边界值：100 合法，101 封顶
func TestNormPage_SizeCapBoundary(t *testing.T) {
	_, size := normPage(1, 100)
	if size != 100 {
		t.Errorf("size=100 应保持 100，实际 %d", size)
	}
}

// TestToListItems_EmptyInput — 空列表返回空切片（非 nil）
func TestToListItems_EmptyInput(t *testing.T) {
	out := toListItems(nil, nil)
	if out == nil {
		t.Error("空输入应返回空切片而非 nil")
	}
	if len(out) != 0 {
		t.Errorf("空输入应返回 0 项，实际 %d", len(out))
	}
}

// TestToListItems_WithCategory — 有分类映射时填充分类
func TestToListItems_WithCategory(t *testing.T) {
	cats := map[int64]*Category{1: {ID: 1, Name: "快速开始", Slug: "quickstart"}}
	rows := []Article{
		{ID: 10, CategoryID: 1, Title: "A", Summary: "s"},
	}
	out := toListItems(rows, cats)
	if len(out) != 1 {
		t.Fatalf("应返回 1 项，实际 %d", len(out))
	}
	if out[0].Category.ID != 1 || out[0].Category.Name != "快速开始" {
		t.Errorf("分类填充错误: %+v", out[0].Category)
	}
}

// TestToListItems_MissingCategory — 分类映射缺失时 Category 字段保持零值（不 panic）
func TestToListItems_MissingCategory(t *testing.T) {
	cats := map[int64]*Category{} // 空映射
	rows := []Article{
		{ID: 10, CategoryID: 999, Title: "A"}, // 引用了不存在的分类
	}
	out := toListItems(rows, cats)
	if len(out) != 1 {
		t.Fatalf("应返回 1 项，实际 %d", len(out))
	}
	if out[0].Category.ID != 0 || out[0].Category.Name != "" {
		t.Errorf("分类缺失时 Category 应为零值，实际 %+v", out[0].Category)
	}
	if out[0].ID != 10 {
		t.Errorf("文章 ID 不应丢失，实际 %d", out[0].ID)
	}
}

// TestToJSONOK — 成功响应结构
func TestToJSONOK_DataField(t *testing.T) {
	s := toJSONOK(map[string]interface{}{"id": 1})
	if s == "" {
		t.Error("不应返回空串")
	}
}
