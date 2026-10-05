# tars-cms-mp（小程序端 · 占位）

> 当前状态：**占位目录，尚未开发。**

## 规划

按项目设计，tars-cms 前端分三端：

| 端 | 技术栈 | 状态 |
|---|---|---|
| `h5/` | Vue 3 + Vite + 手写 CSS | ✅ 已完成 |
| `admin/` | Vue 3 + Element Plus + Vite | ✅ 已完成 |
| `mp/` | 微信小程序（原生 / uni-app） | ⏸ 占位 |

## 接口复用

小程序端将来**同样只调用网关 HTTP 接口**，不需要新的后端服务：

```
mp (小程序)
    ↓ HTTPS
TarsGateway :8200   (Host: cms)
    ↓
BFF :3103           (HTTP → TARS RPC)
    ↓
cms.CmsServer :13101 / :13102
```

## 待办

- [x] 微信后端节点（`wx.WxServer` TARS 服务）：access_token 中控、code2session、模板/订阅消息 —— **已完成并部署**
- [x] `wx.WxBff` (3203) + 网关路由 `/api/wx/*` —— **已完成**
- [ ] 选择框架（原生小程序 / uni-app / Taro）
- [ ] 登录态适配（`cms_session` token 存 `wx.setStorageSync`）
- [ ] 页面：首页 / 分类 / 文章详情 / 我的

## 微信后端节点（wx）

小程序后端能力已由 TARS 节点提供（见 `wx/` 与 `deploy/n2x-wx-*.sh`）：

```
mp (小程序)  →  wx.login 拿 code
    ↓ HTTPS
TarsGateway :8200   (/api/wx/*)
    ↓
wx-bff :3203        (HTTP → TARS RPC)
    ↓
wx.WxServer :13201(公众号) / :13202(小程序)
    ↓
tars_wx 库
```

已就绪接口（经网关 `Host: cms`）：

| 接口 | 说明 |
|---|---|
| `POST /api/wx/ma/code2session` | 小程序 code 换 openid（登录） |
| `GET /api/wx/ma/token` | 小程序 access_token（中控） |
| `POST /api/wx/ma/subscribe/send` | 订阅消息 |
| `GET /api/wx/mp/token` | 公众号 access_token（中控） |
| `GET /api/wx/mp/userinfo` | 关注用户信息 |
| `POST /api/wx/mp/template/send` | 模板消息 |
| `GET /api/wx/verify` | 微信验签 |

> 接入真实 AppID 后，在小程序里 `wx.login` → 拿 code → 调 `code2session` 即可。

## 注意

- 小程序**不能跨域**，必须在微信后台配置 `request 合法域名` 指向网关。
- 组件同样遵循项目约定：**各端组件独立实现，不跨端复用。**
