package main

import (
	"crypto/rand"
	"encoding/base64"
	"fmt"
	"time"

	"gorm.io/gorm"
)

// ============ 微信登录 → cms 会话打通 ============
//
// 链路：
//   wx.login 拿 code → POST /api/wx/ma/login → wx.WxServer.MaObj.Login
//     → 微信 code2session 换 openid
//     → 查/建 tars_cms.users（复用 cms 用户体系）
//     → 签发 cms_session token（与 h5/admin 登录同一套）
//     → 返回 {token, user}
//
// 跨库说明：wx 连的是 tars_wx，但可直接用 `tars_cms.xxx` 限定名访问
// 同实例下的 cms 库（root 权限），无需第二个连接。

// cmsUser 对应 tars_cms.users（只用登录必需字段）
type cmsUser struct {
	ID       int64  `gorm:"primaryKey" json:"id"`
	TenantID int64  `json:"tenant_id"`
	Username string `json:"username"`
	Password string `json:"-"`
	Nickname string `json:"nickname"`
	Email    string `json:"email"`
	Avatar   string `json:"avatar"`
	Role     string `json:"role"`
}

func (cmsUser) TableName() string { return "tars_cms.users" }

// cmsSession 对应 tars_cms.cms_session
type cmsSession struct {
	ID        int64     `gorm:"primaryKey" json:"id"`
	TenantID  int64     `json:"tenant_id"`
	UserID    int64     `json:"user_id"`
	Token     string    `json:"-"`
	ExpiresAt time.Time `json:"expires_at"`
	CreatedAt time.Time `json:"created_at"`
}

func (cmsSession) TableName() string { return "tars_cms.cms_session" }

const cmsTokenTTL = 7 * 24 * time.Hour // 与 cms/auth_imp.go 一致

var _ = gorm.ErrRecordNotFound

// findOrCreateUserByOpenid 按 openid 找（或建）cms 用户，并回写绑定
func findOrCreateUserByOpenid(tenantID int64, openid, unionid, appid string) (*cmsUser, error) {
	var wxu WxUser
	hasWx := DB().Where("openid = ?", openid).First(&wxu).Error == nil

	// 1) 已绑定：直接取 cms 用户
	if hasWx && wxu.CmsUserID > 0 {
		var u cmsUser
		if err := DB().Where("id = ?", wxu.CmsUserID).First(&u).Error; err == nil {
			return &u, nil
		}
	}

	// 2) 未绑定：新建 cms 用户（username 用 openid 后 12 位防冲突）
	suffix := openid
	if len(suffix) > 12 {
		suffix = suffix[len(suffix)-12:]
	}
	u := &cmsUser{
		TenantID: tenantID,
		Username: "wx_" + suffix,
		Nickname: "微信用户",
		Email:    "wx_" + suffix + "@wx.local",
		Role:     "user",
	}
	if err := DB().Create(u).Error; err != nil {
		return nil, fmt.Errorf("创建微信用户失败: %w", err)
	}

	// 3) 回写绑定关系（WxUser.TenantID 是 int32）
	if hasWx {
		DB().Model(&WxUser{}).Where("id = ?", wxu.ID).Update("cms_user_id", u.ID)
	} else {
		DB().Create(&WxUser{
			TenantID:  int32(tenantID),
			AppID:     appid,
			OpenID:    openid,
			UnionID:   unionid,
			Nickname:  "微信用户",
			CmsUserID: u.ID,
		})
	}
	return u, nil
}

// issueCmsToken 签发 cms_session token（与 cms.AuthObj 同机制）
func issueCmsToken(tenantID, userID int64) (string, time.Time, error) {
	buf := make([]byte, 32)
	if _, err := rand.Read(buf); err != nil {
		return "", time.Time{}, err
	}
	token := base64.RawURLEncoding.EncodeToString(buf)
	expires := time.Now().Add(cmsTokenTTL)

	s := cmsSession{
		TenantID:  tenantID,
		UserID:    userID,
		Token:     token,
		ExpiresAt: expires,
	}
	if err := DB().Create(&s).Error; err != nil {
		return "", time.Time{}, fmt.Errorf("签发 token 失败: %w", err)
	}
	return token, expires, nil
}
