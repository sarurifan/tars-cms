package main

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"errors"
	"fmt"
	"sync"
	"time"

	"golang.org/x/crypto/bcrypt"
	"gorm.io/gorm"
)

// ============ AuthObj 实现（认证服务） ============
//
// 设计说明：
//   - 密码用 bcrypt 哈希（cost=10）
//   - Token 用随机 32 字节 base64（不透明 token，非 JWT）
//   - Session 表存 token -> user_id 映射，支持登出吊销
//   - 前端把 token 放 Authorization: Bearer <token>，网关/BFF 校验

// Session 会话表（新增，存 token）
type Session struct {
	ID        int64     `gorm:"primaryKey" json:"id"`
	TenantID  int64     `gorm:"index" json:"tenant_id"`
	UserID    int64     `gorm:"index" json:"user_id"`
	Token     string    `gorm:"uniqueIndex" json:"-"`
	ExpiresAt time.Time `json:"expires_at"`
	CreatedAt time.Time `json:"created_at"`
}

func (Session) TableName() string { return "cms_session" }

const tokenTTL = 7 * 24 * time.Hour // token 有效期 7 天

type authServantImp struct{}

func (imp *authServantImp) Init() error {
	println("cms auth servant initialized")
	return nil
}

func (imp *authServantImp) Destroy() {
	println("cms auth servant destroyed")
}

// Login 登录：验证用户名+密码，签发 token
// 登录失败计数（P2-3：防暴力破解）
// key = tenantId:username，value = {失败次数, 首次失败时间}
var (
	loginAttempts   = make(map[string]*loginAttempt)
	loginAttemptsMu sync.Mutex
)

type loginAttempt struct {
	Count     int
	FirstFail time.Time
}

const (
	loginMaxFails   = 5                // 连续失败上限
	loginLockWindow = 10 * time.Minute // 锁定/统计窗口
)

// loginBlocked 检查是否已被锁定；返回剩余秒数（0 表示未锁）
func loginBlocked(key string) int {
	loginAttemptsMu.Lock()
	defer loginAttemptsMu.Unlock()
	a, ok := loginAttempts[key]
	if !ok {
		return 0
	}
	// 窗口过期 → 重置
	if time.Since(a.FirstFail) > loginLockWindow {
		delete(loginAttempts, key)
		return 0
	}
	if a.Count >= loginMaxFails {
		return int((loginLockWindow - time.Since(a.FirstFail)).Seconds())
	}
	return 0
}

func recordLoginFail(key string) {
	loginAttemptsMu.Lock()
	defer loginAttemptsMu.Unlock()
	a, ok := loginAttempts[key]
	if !ok || time.Since(a.FirstFail) > loginLockWindow {
		loginAttempts[key] = &loginAttempt{Count: 1, FirstFail: time.Now()}
		return
	}
	a.Count++
}

func clearLoginFail(key string) {
	loginAttemptsMu.Lock()
	defer loginAttemptsMu.Unlock()
	delete(loginAttempts, key)
}

func (imp *authServantImp) Login(ctx context.Context, tenantId int32, username string, password string) (string, error) {
	tid := int64(tenantId)

	// P2-3: 先查是否被锁定
	attemptKey := fmt.Sprintf("%d:%s", tid, username)
	if secs := loginBlocked(attemptKey); secs > 0 {
		return toJSONFail(fmt.Sprintf("too many failed attempts, try again in %d seconds", secs)), nil
	}

	var u User
	if err := DB().Where("tenant_id = ? AND username = ? AND status = 1", tid, username).First(&u).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			recordLoginFail(attemptKey)
			return toJSONFail("invalid username or password"), nil
		}
		return toJSONFail(err.Error()), nil
	}

	if err := bcrypt.CompareHashAndPassword([]byte(u.PasswordHash), []byte(password)); err != nil {
		recordLoginFail(attemptKey)
		return toJSONFail("invalid username or password"), nil
	}

	// 登录成功 → 清空失败计数
	clearLoginFail(attemptKey)

	token, err := issueToken(tid, u.ID)
	if err != nil {
		return toJSONFail(err.Error()), nil
	}

	return toJSONOK(map[string]interface{}{
		"token":      token,
		"expires_at": fmtTime(time.Now().Add(tokenTTL)),
		"user":       userVO(u),
	}), nil
}

// Register 注册：创建用户 + 签发 token
func (imp *authServantImp) Register(ctx context.Context, tenantId int32, username string, password string, email string) (string, error) {
	tid := int64(tenantId)

	if username == "" || password == "" {
		return toJSONFail("username and password required"), nil
	}
	if len(password) < 6 {
		return toJSONFail("password too short (min 6)"), nil
	}

	// 唯一性检查
	var cnt int64
	DB().Model(&User{}).Where("tenant_id = ? AND username = ?", tid, username).Count(&cnt)
	if cnt > 0 {
		return toJSONFail("username already exists"), nil
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return toJSONFail(err.Error()), nil
	}

	u := User{
		TenantID:     tid,
		Username:     username,
		Email:        email,
		PasswordHash: string(hash),
		Nickname:     username,
		Role:         "user",
		Status:       1,
	}
	if err := DB().Create(&u).Error; err != nil {
		return toJSONFail(err.Error()), nil
	}

	token, err := issueToken(tid, u.ID)
	if err != nil {
		return toJSONFail(err.Error()), nil
	}

	return toJSONOK(map[string]interface{}{
		"token":      token,
		"expires_at": fmtTime(time.Now().Add(tokenTTL)),
		"user":       userVO(u),
	}), nil
}

// GetUserInfo 校验 token，返回用户信息
func (imp *authServantImp) GetUserInfo(ctx context.Context, tenantId int32, token string) (string, error) {
	tid := int64(tenantId)

	s, err := lookupSession(tid, token)
	if err != nil {
		return toJSONFail("unauthorized"), nil
	}

	var u User
	if err := DB().Where("id = ? AND status = 1", s.UserID).First(&u).Error; err != nil {
		return toJSONFail("user not found or disabled"), nil
	}
	return toJSONOK(userVO(u)), nil
}

// RefreshToken 续期：删旧 token 发新 token
func (imp *authServantImp) RefreshToken(ctx context.Context, tenantId int32, token string) (string, error) {
	tid := int64(tenantId)

	s, err := lookupSession(tid, token)
	if err != nil {
		return toJSONFail("unauthorized"), nil
	}

	// 吊销旧 token，签发新 token
	DB().Where("id = ?", s.ID).Delete(&Session{})
	newToken, err := issueToken(tid, s.UserID)
	if err != nil {
		return toJSONFail(err.Error()), nil
	}
	return toJSONOK(map[string]interface{}{
		"token":      newToken,
		"expires_at": fmtTime(time.Now().Add(tokenTTL)),
	}), nil
}

// Logout 登出：吊销 token
func (imp *authServantImp) Logout(ctx context.Context, tenantId int32, token string) (string, error) {
	DB().Where("tenant_id = ? AND token = ?", int64(tenantId), token).Delete(&Session{})
	return toJSONOK(map[string]interface{}{"ok": true}), nil
}

// ---------- 内部辅助 ----------

// issueToken 生成不透明 token 并写 Session
func issueToken(tid, uid int64) (string, error) {
	buf := make([]byte, 32)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	token := base64.RawURLEncoding.EncodeToString(buf)

	s := Session{
		TenantID:  tid,
		UserID:    uid,
		Token:     token,
		ExpiresAt: time.Now().Add(tokenTTL),
	}
	if err := DB().Create(&s).Error; err != nil {
		return "", err
	}
	return token, nil
}

// lookupSession 根据 token 查会话（校验租户 + 有效期）
func lookupSession(tid int64, token string) (*Session, error) {
	var s Session
	err := DB().Where("tenant_id = ? AND token = ?", tid, token).First(&s).Error
	if err != nil {
		return nil, err
	}
	if time.Now().After(s.ExpiresAt) {
		DB().Where("id = ?", s.ID).Delete(&Session{})
		return nil, errors.New("token expired")
	}
	return &s, nil
}

// userVO 返回给前端的用户视图（脱敏，不含密码哈希）
func userVO(u User) map[string]interface{} {
	return map[string]interface{}{
		"id":       u.ID,
		"username": u.Username,
		"nickname": u.Nickname,
		"email":    u.Email,
		"avatar":   u.Avatar,
		"role":     u.Role,
	}
}
