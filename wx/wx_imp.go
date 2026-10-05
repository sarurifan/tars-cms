package main

import (
	"context"
	"encoding/json"
	"fmt"
	"sync"
	"time"

	"github.com/tars-cms/wx/tars-protocol/wx"
)

// ================================================================
// mpServantImp — 公众号 (MpObj) 实现
// ================================================================
type mpServantImp struct{}

func (imp *mpServantImp) Init() error { return nil }

// getWxAccount 按 appid 查账号（含 secret）
func getWxAccount(appid string) (*WxAccount, error) {
	var acct WxAccount
	if err := DB().Where("appid = ? AND status = 1", appid).First(&acct).Error; err != nil {
		return nil, err
	}
	return &acct, nil
}

// ---- access_token 中控（核心职责） ----
// 微信要求：必须用中控统一获取/刷新，禁止各自刷新互相覆盖失效。

var (
	tokenMu   sync.Mutex
	tokenMemo = map[string]*WxAccessToken{} // appid -> 内存缓存
)

// fetchTokenFromWx 真正向微信拉取 token（带锁，同一 appid 同时只拉一次）
func fetchTokenFromWx(appid, secret string) (string, int, error) {
	url := fmt.Sprintf(
		"https://api.weixin.qq.com/cgi-bin/token?grant_type=client_credential&appid=%s&secret=%s",
		appid, secret,
	)
	var r struct {
		AccessToken string `json:"access_token"`
		ExpiresIn   int    `json:"expires_in"`
		Errcode     int    `json:"errcode"`
		Errmsg      string `json:"errmsg"`
	}
	if err := httpGetJSON(url, &r); err != nil {
		return "", 0, err
	}
	if r.Errcode != 0 {
		return "", 0, fmt.Errorf("wx err %d: %s", r.Errcode, r.Errmsg)
	}
	return r.AccessToken, r.ExpiresIn, nil
}

// getAccessToken 中控读取：内存 → DB → 微信
// 返回 access_token（微信 API 调用凭据）
func getAccessToken(appid string) (string, error) {
	// 1. 内存缓存（提前 5 分钟视为过期）
	tokenMu.Lock()
	if m, ok := tokenMemo[appid]; ok && time.Now().Before(m.ExpiresAt.Add(-5*time.Minute)) {
		t := m.Token
		tokenMu.Unlock()
		return t, nil
	}
	tokenMu.Unlock()

	// 2. DB 缓存
	var rec WxAccessToken
	if err := DB().Where("appid = ?", appid).First(&rec).Error; err == nil &&
		time.Now().Before(rec.ExpiresAt.Add(-5*time.Minute)) {
		tokenMu.Lock()
		tokenMemo[appid] = &rec
		tokenMu.Unlock()
		return rec.Token, nil
	}

	// 3. 拉微信（必须带锁防并发击穿）
	return refreshAccessToken(appid)
}

// refreshAccessToken 强制刷新（内存 + DB 双写）
func refreshAccessToken(appid string) (string, error) {
	acct, err := getWxAccount(appid)
	if err != nil {
		return "", fmt.Errorf("账号未配置: %w", err)
	}

	tokenMu.Lock()
	defer tokenMu.Unlock()

	tk, expiresIn, err := fetchTokenFromWx(appid, acct.AppSecret)
	if err != nil {
		return "", err
	}

	expiresAt := time.Now().Add(time.Duration(expiresIn) * time.Second)
	rec := WxAccessToken{
		AppID:     appid,
		Token:     tk,
		ExpiresAt: expiresAt,
		UpdatedAt: time.Now(),
	}

	// upsert DB
	DB().Where("appid = ?", appid).Delete(&WxAccessToken{})
	DB().Create(&rec)

	// 写内存
	tokenMemo[appid] = &rec
	return tk, nil
}

// ---- MpObj 接口实现 ----

func (imp *mpServantImp) GetAccessToken(_ context.Context, _ int32, appid string) (string, error) {
	tk, err := getAccessToken(appid)
	if err != nil {
		return toJSONFail(err.Error()), nil
	}
	return toJSONOK(map[string]interface{}{"access_token": tk}), nil
}

func (imp *mpServantImp) RefreshAccessToken(_ context.Context, _ int32, appid string) (string, error) {
	tk, err := refreshAccessToken(appid)
	if err != nil {
		return toJSONFail(err.Error()), nil
	}
	return toJSONOK(map[string]interface{}{"access_token": tk}), nil
}

func (imp *mpServantImp) GetUserInfo(_ context.Context, _ int32, appid, openid string) (string, error) {
	tk, err := getAccessToken(appid)
	if err != nil {
		return toJSONFail(err.Error()), nil
	}
	url := fmt.Sprintf(
		"https://api.weixin.qq.com/cgi-bin/user/info?access_token=%s&openid=%s&lang=zh_CN",
		tk, openid,
	)
	var r struct {
		Subscribe int    `json:"subscribe"`
		Openid    string `json:"openid"`
		Nickname  string `json:"nickname"`
		Sex       int    `json:"sex"`
		City      string `json:"city"`
		Province  string `json:"province"`
		Country   string `json:"country"`
		Unionid   string `json:"unionid"`
		Errcode   int    `json:"errcode"`
		Errmsg    string `json:"errmsg"`
	}
	if err := httpGetJSON(url, &r); err != nil {
		return toJSONFail(err.Error()), nil
	}
	if r.Errcode != 0 {
		return toJSONFail(fmt.Sprintf("wx err %d: %s", r.Errcode, r.Errmsg)), nil
	}
	return toJSONOK(map[string]interface{}{
		"openid":    r.Openid,
		"nickname":  r.Nickname,
		"sex":       r.Sex,
		"city":      r.City,
		"province":  r.Province,
		"country":   r.Country,
		"unionid":   r.Unionid,
		"subscribe": r.Subscribe,
	}), nil
}

func (imp *mpServantImp) SendTemplateMsg(_ context.Context, tenantId int32, appid, openid, templateId, dataJson, url string) (string, error) {
	tk, err := getAccessToken(appid)
	if err != nil {
		return toJSONFail(err.Error()), nil
	}

	var data map[string]interface{}
	json.Unmarshal([]byte(dataJson), &data)

	payload := map[string]interface{}{
		"touser":      openid,
		"template_id": templateId,
		"url":         url,
		"data":        data,
	}
	api := fmt.Sprintf("https://api.weixin.qq.com/cgi-bin/message/template/send?access_token=%s", tk)
	var r struct {
		Errcode int    `json:"errcode"`
		Errmsg  string `json:"errmsg"`
	}
	if err := httpPostJSON(api, payload, &r); err != nil {
		return toJSONFail(err.Error()), nil
	}
	// 记录消息
	DB().Create(&WxMessage{
		TenantID: tenantId, AppID: appid, MsgType: "template_msg", Direction: "out",
		ToUser: openid, Content: dataJson,
		Status: map[bool]string{true: "success", false: "failed"}[r.Errcode == 0],
	})
	if r.Errcode != 0 {
		return toJSONFail(fmt.Sprintf("wx err %d: %s", r.Errcode, r.Errmsg)), nil
	}
	return toJSONOK(map[string]interface{}{"msgid": r.Errcode}), nil
}

func (imp *mpServantImp) VerifySignature(_ context.Context, token, timestamp, nonce, signature string) (string, error) {
	ok := verifyWxSignature(token, timestamp, nonce, signature)
	return toJSONOK(map[string]interface{}{"valid": ok}), nil
}

// ================================================================
// maServantImp — 小程序 (MaObj) 实现
// ================================================================
type maServantImp struct{}

func (imp *maServantImp) Init() error { return nil }

// Code2Session 登录凭证校验：code 换 openid + session_key + unionid
func (imp *maServantImp) Code2Session(_ context.Context, _ int32, appid, jsCode string) (string, error) {
	acct, err := getWxAccount(appid)
	if err != nil {
		return toJSONFail(fmt.Sprintf("小程序账号未配置: %v", err)), nil
	}
	url := fmt.Sprintf(
		"https://api.weixin.qq.com/sns/jscode2session?appid=%s&secret=%s&js_code=%s&grant_type=authorization_code",
		appid, acct.AppSecret, jsCode,
	)
	var r struct {
		Openid     string `json:"openid"`
		SessionKey string `json:"session_key"`
		Unionid    string `json:"unionid"`
		Errcode    int    `json:"errcode"`
		Errmsg     string `json:"errmsg"`
	}
	if err := httpGetJSON(url, &r); err != nil {
		return toJSONFail(err.Error()), nil
	}
	if r.Errcode != 0 {
		return toJSONFail(fmt.Sprintf("wx err %d: %s", r.Errcode, r.Errmsg)), nil
	}

	// upsert 用户（session_key 存库不返回）
	if r.Openid != "" {
		var u WxUser
		DB().Where("appid = ? AND openid = ?", appid, r.Openid).First(&u)
		u.TenantID = 1
		u.AppID = appid
		u.OpenID = r.Openid
		u.UnionID = r.Unionid
		u.SessionKey = r.SessionKey
		if u.ID == 0 {
			DB().Create(&u)
		} else {
			DB().Save(&u)
		}
	}

	// 返回不暴露 session_key
	return toJSONOK(map[string]interface{}{
		"openid":  r.Openid,
		"unionid": r.Unionid,
	}), nil
}

// GetAccessToken 小程序也复用中控
func (imp *maServantImp) GetAccessToken(_ context.Context, _ int32, appid string) (string, error) {
	tk, err := getAccessToken(appid)
	if err != nil {
		return toJSONFail(err.Error()), nil
	}
	return toJSONOK(map[string]interface{}{"access_token": tk}), nil
}

// SendSubscribeMsg 发送订阅消息
func (imp *maServantImp) SendSubscribeMsg(_ context.Context, tenantId int32, appid, openid, templateId, dataJson, page string) (string, error) {
	tk, err := getAccessToken(appid)
	if err != nil {
		return toJSONFail(err.Error()), nil
	}
	var data map[string]interface{}
	json.Unmarshal([]byte(dataJson), &data)

	payload := map[string]interface{}{
		"touser":      openid,
		"template_id": templateId,
		"page":        page,
		"data":        data,
	}
	api := fmt.Sprintf("https://api.weixin.qq.com/cgi-bin/message/subscribe/send?access_token=%s", tk)
	var r struct {
		Errcode int    `json:"errcode"`
		Errmsg  string `json:"errmsg"`
	}
	if err := httpPostJSON(api, payload, &r); err != nil {
		return toJSONFail(err.Error()), nil
	}
	DB().Create(&WxMessage{
		TenantID: tenantId, AppID: appid, MsgType: "subscribe_msg", Direction: "out",
		ToUser: openid, Content: dataJson,
		Status: map[bool]string{true: "success", false: "failed"}[r.Errcode == 0],
	})
	if r.Errcode != 0 {
		return toJSONFail(fmt.Sprintf("wx err %d: %s", r.Errcode, r.Errmsg)), nil
	}
	return toJSONOK(map[string]interface{}{"msgid": r.Errcode}), nil
}

// CheckSession 校验 session_key 是否有效
func (imp *maServantImp) CheckSession(_ context.Context, _ int32, openid, sessionKey string) (string, error) {
	var u WxUser
	if err := DB().Where("openid = ? AND session_key = ?", openid, sessionKey).First(&u).Error; err != nil {
		return toJSONOK(map[string]interface{}{"valid": false}), nil
	}
	return toJSONOK(map[string]interface{}{"valid": true}), nil
}

// 保持编译时校验接口实现
var _ wx.MpObjServantWithContext = (*mpServantImp)(nil)
var _ wx.MaObjServantWithContext = (*maServantImp)(nil)
