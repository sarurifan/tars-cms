package main

import (
	"time"
)

// WxAccount 微信账号配置表（支持多个公众号/小程序）
type WxAccount struct {
	ID          int64     `gorm:"primaryKey" json:"id"`
	TenantID    int32     `gorm:"index;not null" json:"tenant_id"`
	AppType     string    `gorm:"size:16;not null" json:"app_type"`      // "mp" (公众号) 或 "ma" (小程序)
	AppID       string    `gorm:"size:64;uniqueIndex;not null" json:"appid"`
	AppSecret   string    `gorm:"size:128;not null" json:"app_secret"`
	Token       string    `gorm:"size:64" json:"token"`                 // 公众号验证 Token
	EncodingAES string    `gorm:"size:64" json:"encoding_aes_key"`      // 消息加解密密钥
	Name        string    `gorm:"size:64" json:"name"`                  // 账号名称 (如 "知健园公众号")
	Status      int8      `gorm:"default:1" json:"status"`              // 1 启用 0 禁用
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}

func (WxAccount) TableName() string { return "wx_account" }

// WxAccessToken access_token 中控缓存表
type WxAccessToken struct {
	ID        int64     `gorm:"primaryKey" json:"id"`
	AppID     string    `gorm:"size:64;uniqueIndex;not null" json:"appid"`
	Token     string    `gorm:"size:512;not null" json:"token"`
	ExpiresAt time.Time `gorm:"not null" json:"expires_at"`           // 过期绝对时间
	UpdatedAt time.Time `json:"updated_at"`
}

func (WxAccessToken) TableName() string { return "wx_access_token" }

// WxUser 微信用户表（粉丝 / 小程序登录用户）
type WxUser struct {
	ID        int64     `gorm:"primaryKey" json:"id"`
	TenantID  int32     `gorm:"index;not null" json:"tenant_id"`
	AppID     string    `gorm:"size:64;index;not null" json:"appid"`
	OpenID    string    `gorm:"size:64;index;not null" json:"openid"`
	UnionID   string    `gorm:"size:64;index" json:"unionid"`
	Nickname  string    `gorm:"size:64" json:"nickname"`
	Avatar    string    `gorm:"size:255" json:"avatar"`
	Gender    int8      `gorm:"default:0" json:"gender"`
	City      string    `gorm:"size:32" json:"city"`
	Province  string    `gorm:"size:32" json:"province"`
	Country   string    `gorm:"size:32" json:"country"`
	Subscribe int8      `gorm:"default:0" json:"subscribe"`          // 公众号关注状态: 1已关注 0未关注
	SessionKey string   `gorm:"size:128" json:"-"`                   // 小程序 session_key (绝不对外暴露)
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

func (WxUser) TableName() string { return "wx_user" }

// WxMessage 消息流转记录表
type WxMessage struct {
	ID        int64     `gorm:"primaryKey" json:"id"`
	TenantID  int32     `gorm:"index;not null" json:"tenant_id"`
	AppID     string    `gorm:"size:64;index;not null" json:"appid"`
	MsgType   string    `gorm:"size:32;not null" json:"msg_type"`    // text/image/event/subscribe_msg
	Direction string    `gorm:"size:8;not null" json:"direction"`   // "in" 接收 "out" 发送
	FromUser  string    `gorm:"size:64;not null" json:"from_user"`
	ToUser    string    `gorm:"size:64;not null" json:"to_user"`
	Content   string    `gorm:"type:text" json:"content"`
	Status    string    `gorm:"size:16;default:'sent'" json:"status"`// sent/success/failed
	CreatedAt time.Time `json:"created_at"`
}

func (WxMessage) TableName() string { return "wx_message" }
