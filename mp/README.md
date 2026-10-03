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

- [ ] 选择框架（原生小程序 / uni-app / Taro）
- [ ] 登录态适配（`cms_session` token 存 `wx.setStorageSync`）
- [ ] 微信登录对接（需小程序 AppID + 后端 `jscode2session`）
- [ ] 页面：首页 / 分类 / 文章详情 / 我的

## 注意

- 小程序**不能跨域**，必须在微信后台配置 `request 合法域名` 指向网关。
- 组件同样遵循项目约定：**各端组件独立实现，不跨端复用。**
