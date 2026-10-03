package main

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"gorm.io/gorm"
)

// ============ ArticleObj 实现（内容服务） ============

type articleServantImp struct{}

func (imp *articleServantImp) Init() error {
	println("cms article servant initialized")
	return nil
}

func (imp *articleServantImp) Destroy() {
	println("cms article servant destroyed")
}

// ---------- 首页聚合 ----------

func (imp *articleServantImp) GetHome(ctx context.Context, tenantId int32) (string, error) {
	db := DB()
	tid := int64(tenantId)

	// 分类映射（用于填充列表项的 category 字段）
	cats, _ := loadCategoryMap(tid)

	// 轮播图：is_banner=1
	var banners []Article
	db.Where("tenant_id = ? AND is_banner = 1 AND status = 1", tid).
		Order("sort ASC, id DESC").Limit(5).Find(&banners)

	// 置顶：is_top=1
	var tops []Article
	db.Where("tenant_id = ? AND is_top = 1 AND status = 1", tid).
		Order("sort ASC, id DESC").Limit(8).Find(&tops)

	// 焦点：is_focus=1
	var focuses []Article
	db.Where("tenant_id = ? AND is_focus = 1 AND status = 1", tid).
		Order("sort ASC, id DESC").Limit(6).Find(&focuses)

	// 最新：按发布时间倒序（只取列表字段，不加载正文）
	var latest []Article
	db.Where("tenant_id = ? AND status = 1", tid).
		Order("publish_at DESC, id DESC").Limit(10).Find(&latest)

	// 分类树
	var catRows []Category
	db.Where("tenant_id = ? AND status = 1", tid).Find(&catRows)

	// 站点配置
	cfg := loadConfigMap(tid)

	data := HomeData{
		Banners:       toListItems(banners, cats),
		TopArticles:   toListItems(tops, cats),
		FocusArticles: toListItems(focuses, cats),
		Latest:        toListItems(latest, cats),
		Categories:    buildCategoryTree(catRows),
		Config:        cfg,
	}
	return toJSONOK(data), nil
}

// ---------- 分类 ----------

func (imp *articleServantImp) GetCategories(ctx context.Context, tenantId int32) (string, error) {
	var rows []Category
	DB().Where("tenant_id = ? AND status = 1", int64(tenantId)).
		Order("sort ASC, id ASC").Find(&rows)
	return toJSONOK(rows), nil
}

func (imp *articleServantImp) GetCategoryTree(ctx context.Context, tenantId int32) (string, error) {
	var rows []Category
	DB().Where("tenant_id = ? AND status = 1", int64(tenantId)).
		Order("sort ASC, id ASC").Find(&rows)
	return toJSONOK(buildCategoryTree(rows)), nil
}

// ---------- 文章列表（分页） ----------

func (imp *articleServantImp) GetArticleList(ctx context.Context, tenantId int32, categoryId int32, keyword string, page int32, size int32) (string, error) {
	tid := int64(tenantId)
	page, size = normPage(page, size)

	q := DB().Model(&Article{}).Where("tenant_id = ? AND status = 1", tid)
	if categoryId > 0 {
		// 含子分类
		ids := descendantIDs(tid, int64(categoryId))
		q = q.Where("category_id IN ?", ids)
	}
	if keyword != "" {
		kw := "%" + keyword + "%"
		q = q.Where("title LIKE ? OR summary LIKE ?", kw, kw)
	}

	var total int64
	q.Count(&total)

	var rows []Article
	q.Order("sort ASC, publish_at DESC, id DESC").
		Offset(int((page - 1) * size)).Limit(int(size)).Find(&rows)

	cats, _ := loadCategoryMap(tid)
	return toJSONOK(PageList{
		List:  toListItems(rows, cats),
		Total: total,
		Page:  page,
		Size:  size,
	}), nil
}

// ---------- 文章详情 ----------

func (imp *articleServantImp) GetArticleDetail(ctx context.Context, tenantId int32, id int32) (string, error) {
	tid := int64(tenantId)

	var a Article
	if err := DB().Where("tenant_id = ? AND id = ? AND status = 1", tid, id).First(&a).Error; err != nil {
		return toJSONFail("article not found"), nil
	}

	// 浏览量原子自增
	DB().Model(&Article{}).Where("id = ?", a.ID).UpdateColumn("view_count", gorm.Expr("view_count + 1"))
	a.ViewCount++

	// 正文（分离表）
	var body ArticleBody
	DB().Where("article_id = ?", a.ID).First(&body)

	// 分类
	var cat *Category
	if a.CategoryID > 0 {
		var c Category
		if DB().Where("id = ?", a.CategoryID).First(&c).Error == nil {
			cat = &c
		}
	}

	// 作者
	var m *Member
	if a.AuthorID > 0 {
		var mem Member
		if DB().Where("id = ?", a.AuthorID).First(&mem).Error == nil {
			m = &mem
		}
	}

	return toJSONOK(toDetail(a, body.Body, cat, m)), nil
}

// ---------- 后台：文章列表 ----------

func (imp *articleServantImp) GetAdminArticleList(ctx context.Context, tenantId int32, categoryId int32, status int32, page int32, size int32) (string, error) {
	tid := int64(tenantId)
	page, size = normPage(page, size)

	q := DB().Model(&Article{}).Where("tenant_id = ?", tid)
	if categoryId > 0 {
		q = q.Where("category_id = ?", categoryId)
	}
	if status >= 0 {
		q = q.Where("status = ?", status)
	}

	var total int64
	q.Count(&total)

	var rows []Article
	q.Order("sort ASC, id DESC").Offset(int((page - 1) * size)).Limit(int(size)).Find(&rows)

	cats, _ := loadCategoryMap(tid)
	return toJSONOK(PageList{
		List:  toListItems(rows, cats),
		Total: total,
		Page:  page,
		Size:  size,
	}), nil
}

// ---------- 后台：文章增删改 ----------

func (imp *articleServantImp) CreateArticle(ctx context.Context, tenantId int32, title string, summary string, content string,
	categoryId int32, cover string, articleType string, isBanner bool, isTop bool, isFocus bool,
	sort int32, authorId int32, source string) (string, error) {

	tid := int64(tenantId)
	if title == "" {
		return toJSONFail("title required"), nil
	}
	if articleType == "" {
		articleType = "article"
	}
	if summary == "" {
		summary = truncateSummary(content, 60)
	}

	// XSS 净化（存储前必过）
	safeBody := SanitizeHTML(content)

	now := time.Now()
	a := Article{
		TenantID:   tid,
		Title:      title,
		Summary:    summary,
		Cover:      cover,
		CategoryID: int64(categoryId),
		IsBanner:   isBanner,
		IsTop:      isTop,
		IsFocus:    isFocus,
		Sort:       sort,
		Type:       articleType,
		AuthorID:   int64(authorId),
		Source:     source,
		Status:     1,
		PublishAt:  now,
	}

	err := DB().Transaction(func(tx *gorm.DB) error {
		if err := tx.Create(&a).Error; err != nil {
			return err
		}
		return tx.Create(&ArticleBody{
			ArticleID: a.ID,
			TenantID:  tid,
			Body:      safeBody,
		}).Error
	})
	if err != nil {
		return toJSONFail(err.Error()), nil
	}
	return toJSONOK(map[string]interface{}{"id": a.ID}), nil
}

func (imp *articleServantImp) UpdateArticle(ctx context.Context, tenantId int32, id int32, title string, summary string, content string,
	categoryId int32, cover string, articleType string, isBanner bool, isTop bool, isFocus bool,
	sort int32, authorId int32, source string) (string, error) {

	tid := int64(tenantId)

	var a Article
	if err := DB().Where("tenant_id = ? AND id = ?", tid, id).First(&a).Error; err != nil {
		return toJSONFail("article not found"), nil
	}

	if summary == "" {
		summary = truncateSummary(content, 60)
	}
	safeBody := SanitizeHTML(content)

	err := DB().Transaction(func(tx *gorm.DB) error {
		updates := map[string]interface{}{
			"title":       title,
			"summary":     summary,
			"cover":       cover,
			"category_id": categoryId,
			"is_banner":   isBanner,
			"is_top":      isTop,
			"is_focus":    isFocus,
			"sort":        sort,
			"type":        articleType,
			"author_id":   authorId,
			"source":      source,
		}
		if err := tx.Model(&Article{}).Where("id = ?", a.ID).Updates(updates).Error; err != nil {
			return err
		}
		// 正文 upsert
		var cnt int64
		tx.Model(&ArticleBody{}).Where("article_id = ?", a.ID).Count(&cnt)
		if cnt > 0 {
			return tx.Model(&ArticleBody{}).Where("article_id = ?", a.ID).
				Updates(map[string]interface{}{"body": safeBody}).Error
		}
		return tx.Create(&ArticleBody{ArticleID: a.ID, TenantID: tid, Body: safeBody}).Error
	})
	if err != nil {
		return toJSONFail(err.Error()), nil
	}
	return toJSONOK(map[string]interface{}{"id": a.ID}), nil
}

func (imp *articleServantImp) DeleteArticle(ctx context.Context, tenantId int32, id int32) (string, error) {
	// 软删除（GORM DeletedAt 自动过滤）
	res := DB().Where("tenant_id = ? AND id = ?", int64(tenantId), id).Delete(&Article{})
	if res.Error != nil {
		return toJSONFail(res.Error.Error()), nil
	}
	if res.RowsAffected == 0 {
		return toJSONFail("article not found"), nil
	}
	return toJSONOK(map[string]interface{}{"id": id}), nil
}

// ---------- 后台：分类管理 ----------

func (imp *articleServantImp) GetAdminCategoryList(ctx context.Context, tenantId int32) (string, error) {
	var rows []Category
	DB().Where("tenant_id = ?", int64(tenantId)).Order("sort ASC, id ASC").Find(&rows)
	return toJSONOK(rows), nil
}

func (imp *articleServantImp) CreateCategory(ctx context.Context, tenantId int32, pid int32, name string, slug string, sort int32) (string, error) {
	if name == "" {
		return toJSONFail("name required"), nil
	}
	c := Category{
		TenantID: int64(tenantId),
		PID:      int64(pid),
		Name:     name,
		Slug:     slug,
		Sort:     sort,
		Status:   1,
	}
	if err := DB().Create(&c).Error; err != nil {
		return toJSONFail(err.Error()), nil
	}
	return toJSONOK(map[string]interface{}{"id": c.ID}), nil
}

func (imp *articleServantImp) UpdateCategory(ctx context.Context, tenantId int32, id int32, pid int32, name string, slug string, sort int32) (string, error) {
	res := DB().Model(&Category{}).
		Where("tenant_id = ? AND id = ?", int64(tenantId), id).
		Updates(map[string]interface{}{"pid": pid, "name": name, "slug": slug, "sort": sort})
	if res.Error != nil {
		return toJSONFail(res.Error.Error()), nil
	}
	if res.RowsAffected == 0 {
		return toJSONFail("category not found"), nil
	}
	return toJSONOK(map[string]interface{}{"id": id}), nil
}

func (imp *articleServantImp) DeleteCategory(ctx context.Context, tenantId int32, id int32) (string, error) {
	tid := int64(tenantId)
	// 有子分类则拒绝
	var childCnt int64
	DB().Model(&Category{}).Where("tenant_id = ? AND pid = ?", tid, id).Count(&childCnt)
	if childCnt > 0 {
		return toJSONFail("has children, delete them first"), nil
	}
	var artCnt int64
	DB().Model(&Article{}).Where("tenant_id = ? AND category_id = ?", tid, id).Count(&artCnt)
	if artCnt > 0 {
		return toJSONFail("has articles, move them first"), nil
	}
	res := DB().Where("tenant_id = ? AND id = ?", tid, id).Delete(&Category{})
	if res.Error != nil {
		return toJSONFail(res.Error.Error()), nil
	}
	return toJSONOK(map[string]interface{}{"id": id}), nil
}

// ---------- 站点配置 ----------

func (imp *articleServantImp) GetSiteConfig(ctx context.Context, tenantId int32) (string, error) {
	return toJSONOK(loadConfigMap(int64(tenantId))), nil
}

func (imp *articleServantImp) UpdateSiteConfig(ctx context.Context, tenantId int32, configJson string) (string, error) {
	var kv map[string]string
	if err := json.Unmarshal([]byte(configJson), &kv); err != nil {
		return toJSONFail("invalid config json: " + err.Error()), nil
	}
	tid := int64(tenantId)

	err := DB().Transaction(func(tx *gorm.DB) error {
		for k, v := range kv {
			var c Config
			err := tx.Where("tenant_id = ? AND config_key = ?", tid, k).First(&c).Error
			if err == gorm.ErrRecordNotFound {
				if err := tx.Create(&Config{
					TenantID: tid, ConfigKey: k, ConfigValue: v, GroupName: "site",
				}).Error; err != nil {
					return err
				}
				continue
			} else if err != nil {
				return err
			}
			if err := tx.Model(&Config{}).Where("id = ?", c.ID).
				Update("config_value", v).Error; err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		return toJSONFail(err.Error()), nil
	}
	return toJSONOK(map[string]interface{}{"updated": len(kv)}), nil
}

// ---------- 媒体 ----------

func (imp *articleServantImp) GetMediaList(ctx context.Context, tenantId int32, page int32, size int32) (string, error) {
	page, size = normPage(page, size)
	tid := int64(tenantId)

	var total int64
	DB().Model(&Media{}).Where("tenant_id = ?", tid).Count(&total)

	var rows []Media
	DB().Where("tenant_id = ?", tid).
		Order("id DESC").Offset(int((page - 1) * size)).Limit(int(size)).Find(&rows)

	return toJSONOK(PageList{List: rows, Total: total, Page: page, Size: size}), nil
}

func (imp *articleServantImp) UploadImage(ctx context.Context, tenantId int32, filename string, data string) (string, error) {
	return imp.upload(tenantId, filename, data, "image")
}

func (imp *articleServantImp) UploadFile(ctx context.Context, tenantId int32, filename string, data string) (string, error) {
	return imp.upload(tenantId, filename, data, "file")
}

// ---------- 成员 ----------

func (imp *articleServantImp) GetMemberList(ctx context.Context, tenantId int32) (string, error) {
	var rows []Member
	DB().Where("tenant_id = ? AND status = 1", int64(tenantId)).
		Order("sort ASC, id ASC").Find(&rows)
	return toJSONOK(rows), nil
}

func (imp *articleServantImp) CreateMember(ctx context.Context, tenantId int32, name string, avatar string, title string, bio string, role string, sort int32) (string, error) {
	if name == "" {
		return toJSONFail("name required"), nil
	}
	m := Member{
		TenantID: int64(tenantId),
		Name:     name,
		Avatar:   avatar,
		Title:    title,
		Bio:      bio,
		Role:     role,
		Sort:     sort,
		Status:   1,
	}
	if err := DB().Create(&m).Error; err != nil {
		return toJSONFail(err.Error()), nil
	}
	return toJSONOK(map[string]interface{}{"id": m.ID}), nil
}

func (imp *articleServantImp) UpdateMember(ctx context.Context, tenantId int32, id int32, name string, avatar string, title string, bio string, role string, sort int32) (string, error) {
	res := DB().Model(&Member{}).
		Where("tenant_id = ? AND id = ?", int64(tenantId), id).
		Updates(map[string]interface{}{
			"name": name, "avatar": avatar, "title": title,
			"bio": bio, "role": role, "sort": sort,
		})
	if res.Error != nil {
		return toJSONFail(res.Error.Error()), nil
	}
	if res.RowsAffected == 0 {
		return toJSONFail("member not found"), nil
	}
	return toJSONOK(map[string]interface{}{"id": id}), nil
}

func (imp *articleServantImp) DeleteMember(ctx context.Context, tenantId int32, id int32) (string, error) {
	res := DB().Where("tenant_id = ? AND id = ?", int64(tenantId), id).Delete(&Member{})
	if res.Error != nil {
		return toJSONFail(res.Error.Error()), nil
	}
	return toJSONOK(map[string]interface{}{"id": id}), nil
}

// ============ 内部辅助 ============

// normPage 归一化分页参数
func normPage(page, size int32) (int32, int32) {
	if page <= 0 {
		page = 1
	}
	if size <= 0 {
		size = 10
	}
	if size > 100 {
		size = 100
	}
	return page, size
}

// loadCategoryMap 加载分类 id->Category 映射
func loadCategoryMap(tid int64) (map[int64]*Category, error) {
	var rows []Category
	if err := DB().Where("tenant_id = ?", tid).Find(&rows).Error; err != nil {
		return nil, err
	}
	m := make(map[int64]*Category, len(rows))
	for i := range rows {
		m[rows[i].ID] = &rows[i]
	}
	return m, nil
}

// loadConfigMap 加载站点配置为 map
func loadConfigMap(tid int64) map[string]string {
	var rows []Config
	DB().Where("tenant_id = ?", tid).Find(&rows)
	m := make(map[string]string, len(rows))
	for _, c := range rows {
		m[c.ConfigKey] = c.ConfigValue
	}
	return m
}

// toListItems 批量转换列表项
func toListItems(rows []Article, cats map[int64]*Category) []ArticleListItem {
	out := make([]ArticleListItem, 0, len(rows))
	for _, a := range rows {
		var cat *Category
		if c, ok := cats[a.CategoryID]; ok {
			cat = c
		}
		out = append(out, toListItem(a, cat))
	}
	return out
}

// descendantIDs 返回分类自身 + 所有子孙分类 ID（用于列表按父分类筛选）
func descendantIDs(tid int64, rootID int64) []int64 {
	var all []Category
	DB().Where("tenant_id = ?", tid).Find(&all)

	children := make(map[int64][]int64, len(all))
	for _, c := range all {
		children[c.PID] = append(children[c.PID], c.ID)
	}

	var out []int64
	queue := []int64{rootID}
	for len(queue) > 0 {
		id := queue[0]
		queue = queue[1:]
		out = append(out, id)
		queue = append(queue, children[id]...)
	}
	return out
}

// upload 通用上传（本地存储实现，OSS 分支预留）
func (imp *articleServantImp) upload(tenantId int32, filename string, data string, kind string) (string, error) {
	if filename == "" || data == "" {
		return toJSONFail("filename and data required"), nil
	}
	// 注：data 为 base64 编码内容；driver 由配置决定（local/oss），默认 local。
	// 这里返回占位结构，实际落盘/OSS 在 deploy 阶段接入（见 docs）。
	return toJSONOK(map[string]interface{}{
		"name":   filename,
		"kind":   kind,
		"driver": "local",
		"msg":    "storage backend not wired yet",
	}), nil
}

var _ = fmt.Sprintf
