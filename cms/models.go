package main

import (
	"time"
	"gorm.io/gorm"
)

// ============ 模型定义 ============

// Category 分类表
type Category struct {
	ID        int64          `gorm:"primaryKey" json:"id"`
	TenantID  int64          `gorm:"index" json:"tenant_id"`
	PID       int64          `gorm:"column:pid;index" json:"pid"`        // 父分类ID，0=顶级
	Name      string         `json:"name"`
	Slug      string         `json:"slug"`
	Sort      int32          `json:"sort"`
	Status    int8           `json:"status"`                 // 0禁用 1启用
	CreatedAt time.Time      `json:"created_at"`
	UpdatedAt time.Time      `json:"updated_at"`
}

func (Category) TableName() string { return "cms_category" }

// Article 文章主表（不含正文）
type Article struct {
	ID         int64          `gorm:"primaryKey" json:"id"`
	TenantID   int64          `gorm:"index" json:"tenant_id"`
	Title      string         `json:"title"`
	Slug       string         `json:"slug"`
	Summary    string         `json:"summary"`
	Cover      string         `json:"cover"`
	CategoryID int64          `gorm:"index" json:"category_id"`
	IsBanner   bool           `json:"is_banner"`
	IsTop      bool           `json:"is_top"`
	IsFocus    bool           `json:"is_focus"`
	Sort       int32          `json:"sort"`
	Type       string         `json:"type"`                 // article/tutorial/doc/news
	AuthorID   int64          `json:"author_id"`
	Source     string         `json:"source"`
	ViewCount  int64          `json:"view_count"`
	Status     int8           `json:"status"`              // 0草稿 1发布 2归档
	PublishAt  time.Time      `json:"publish_at"`
	CreatedAt  time.Time      `json:"created_at"`
	UpdatedAt  time.Time      `json:"updated_at"`
	DeletedAt  gorm.DeletedAt `gorm:"index" json:"-"`
}

func (Article) TableName() string { return "cms_article" }

// ArticleBody 文章正文表（分离存储）
type ArticleBody struct {
	ArticleID int64          `gorm:"primaryKey" json:"article_id"`
	TenantID  int64          `gorm:"index" json:"tenant_id"`
	Body      string         `json:"body"`              // MEDIUMTEXT HTML
	CreatedAt time.Time      `json:"created_at"`
	UpdatedAt time.Time      `json:"updated_at"`
}

func (ArticleBody) TableName() string { return "cms_article_body" }

// Config 站点配置表
type Config struct {
	ID          int64          `gorm:"primaryKey" json:"id"`
	TenantID    int64          `gorm:"index" json:"tenant_id"`
	ConfigKey   string         `json:"config_key"`
	ConfigValue string         `json:"config_value"`
	GroupName   string         `json:"group_name"`
	Remark      string         `json:"remark"`
	CreatedAt   time.Time      `json:"created_at"`
	UpdatedAt   time.Time      `json:"updated_at"`
}

func (Config) TableName() string { return "cms_config" }

// Member 成员表
type Member struct {
	ID        int64          `gorm:"primaryKey" json:"id"`
	TenantID  int64          `gorm:"index" json:"tenant_id"`
	Name      string         `json:"name"`
	Avatar    string         `json:"avatar"`
	Title     string         `json:"title"`
	Bio       string         `json:"bio"`
	Role      string         `json:"role"`
	Sort      int32          `json:"sort"`
	Status    int8           `json:"status"`
	CreatedAt time.Time      `json:"created_at"`
	UpdatedAt time.Time      `json:"updated_at"`
}

func (Member) TableName() string { return "cms_member" }

// Media 媒体文件表
type Media struct {
	ID        int64          `gorm:"primaryKey" json:"id"`
	TenantID  int64          `gorm:"index" json:"tenant_id"`
	Name      string         `json:"name"`
	Path      string         `json:"path"`
	URL       string         `json:"url"`
	Size      int64          `json:"size"`
	Mime      string         `json:"mime"`
	Driver    string         `json:"driver"`           // local/oss
	CreatedAt time.Time      `json:"created_at"`
	UpdatedAt time.Time      `json:"updated_at"`
}

func (Media) TableName() string { return "cms_media" }

// User 用户表
type User struct {
	ID           int64          `gorm:"primaryKey" json:"id"`
	TenantID     int64          `gorm:"index" json:"tenant_id"`
	Username     string         `json:"username"`
	Email        string         `json:"email"`
	PasswordHash string         `json:"-"`
	Nickname     string         `json:"nickname"`
	Avatar       string         `json:"avatar"`
	Role         string         `json:"role"`              // user/editor/admin
	Status       int8           `json:"status"`
	CreatedAt    time.Time      `json:"created_at"`
	UpdatedAt    time.Time      `json:"updated_at"`
}

func (User) TableName() string { return "users" }

// ============ 响应结构 ============

// Response 统一响应格式
type Response struct {
	Code int         `json:"code"`
	Msg  string      `json:"msg"`
	Data interface{} `json:"data"`
}

func OK(data interface{}) Response {
	return Response{Code: 0, Msg: "success", Data: data}
}

func Fail(msg string) Response {
	return Response{Code: -1, Msg: msg, Data: nil}
}

// PageList 分页响应
type PageList struct {
	List  interface{} `json:"list"`
	Total int64      `json:"total"`
	Page  int32      `json:"page"`
	Size  int32      `json:"size"`
}

// ArticleListItem 文章列表项（不含正文）
type ArticleListItem struct {
	ID        int64  `json:"id"`
	Title     string `json:"title"`
	Summary   string `json:"summary"`
	Cover     string `json:"cover"`
	Category  struct {
		ID   int64  `json:"id"`
		Name string `json:"name"`
	} `json:"category"`
	Type      string `json:"type"`
	ViewCount int64  `json:"view_count"`
	PublishAt string `json:"publish_at"`
	Sort      int32  `json:"sort"`
}

// CategoryNode 分类树节点
type CategoryNode struct {
	ID       int64           `json:"id"`
	Name     string          `json:"name"`
	Slug     string          `json:"slug"`
	PID      int64           `json:"pid"`
	Sort     int32           `json:"sort"`
	Children []*CategoryNode `json:"children"`
}

// HomeData 首页聚合数据
type HomeData struct {
	Banners       []ArticleListItem `json:"banners"`
	TopArticles   []ArticleListItem `json:"topArticles"`
	FocusArticles []ArticleListItem `json:"focusArticles"`
	Latest        []ArticleListItem `json:"latest"`
	Categories   []*CategoryNode   `json:"categories"`
	Config       map[string]string `json:"config"`
}

// ArticleDetail 文章详情（含正文）
type ArticleDetail struct {
	ID        int64  `json:"id"`
	Title     string `json:"title"`
	Summary   string `json:"summary"`
	Content   string `json:"content"`
	Cover     string `json:"cover"`
	Category  struct {
		ID   int64  `json:"id"`
		Name string `json:"name"`
	} `json:"category"`
	Author    struct {
		ID   int64  `json:"id"`
		Name string `json:"name"`
	} `json:"author"`
	Type      string `json:"type"`
	Source    string `json:"source"`
	ViewCount int64  `json:"view_count"`
	PublishAt string `json:"publish_at"`
}
