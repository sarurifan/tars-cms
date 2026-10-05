# tars-cms-mp（微信小程序端）

> **演示小程序**：内容与 `h5/` 一致，全部是文档与项目介绍，数据由 CMS 自身管理。

原生小程序（无构建链），用微信开发者工具直接打开本目录即可运行。

## 目录结构

```
mp/
├── app.js / app.json / app.wxss     # 全局入口与样式
├── sitemap.json
├── pages/
│   ├── home/       # 首页：轮播 + 分类入口 + 置顶/焦点/最新
│   ├── category/   # 分类页：筛选 chips + 分页列表
│   ├── article/    # 文章详情：rich-text 渲染 HTML 正文
│   └── about/      # 关于项目：介绍 + 架构图 + 接口清单
├── components/
│   ├── article-card/   # 文章卡片（对应 h5 H5ArticleCard）
│   └── banner/         # 轮播图（对应 h5 H5Banner）
└── utils/
    └── api.js          # 接口层（对应 h5 api/content.ts）
```

## 页面与 h5 的对应关系

| 小程序页面 | 对应 h5 | 说明 |
|---|---|---|
| `pages/home` | `HomePage.vue` | 首页聚合数据（banners/topArticles/focusArticles/latest） |
| `pages/category` | `CategoryPage.vue` | 分类筛选 + 分页 |
| `pages/article` | `ArticlePage.vue` | 正文 rich-text 渲染 |
| `pages/about` | — | 项目介绍页（小程序独有） |

## 数据来源

小程序不新增后端服务，**只调用网关 HTTP 接口**：

```
mp (小程序)
    ↓ HTTP
TarsGateway :8200   (Host: cms)
    ↓
BFF :3103           (HTTP → TARS RPC)
    ↓
cms.CmsServer :13101
    ↓
MySQL tars_cms
```

使用的接口（与 h5 完全一致）：

| 接口 | 用途 |
|---|---|
| `GET /api/cms/home?tenantId=1` | 首页聚合 |
| `GET /api/cms/categories?tenantId=1` | 分类列表 |
| `GET /api/cms/articles?tenantId=1&categoryId=&page=&size=` | 文章列表（分页） |
| `GET /api/cms/articles/:id?tenantId=1` | 文章详情 |

## 运行方式

1. 打开 **微信开发者工具** → 导入项目 → 选择 `mp/` 目录
2. AppID 使用**测试号**（或在 mp/app.js 保持默认）
3. 修改 `app.js` 的 `baseUrl` 为你的网关地址（默认 `http://192.168.1.95:8200`）
4. 编译即可看到 4 个页面

> 小程序在正式环境必须走 **HTTPS** 且域名需在微信后台配置 `request 合法域名`；
> 本地开发勾选「不校验合法域名」即可用 HTTP。

## 验证

接口数据契约测试 25/25 通过（覆盖 4 页面全部数据字段）：

```bash
node /tmp/mp-verify.js    # 模拟 api.js 请求逻辑，断言字段契约
```

## 关键实现说明（踩坑记录）

- **列表字段是 `list` 不是 `records`**：后端 `PageList.List` 序列化为 `data.list`；
  h5 的变量名叫 `records` 但实际取的是 `res.data.list`，小程序同款取法。
- **WXML 不支持 `Math.ceil`**：总页数在 JS 算好存 `totalPages`，模板只渲染变量。
- **原生小程序用 CommonJS**：`utils/api.js` 是 `module.exports`，不是 ES `export`。
- **rich-text 渲染 HTML**：正文由服务端 bluemonday 净化，小程序直接 `rich-text` 节点渲染。

## 待办

- [x] 框架选型 → **原生小程序**（无构建链，演示最轻）
- [x] 页面：首页 / 分类 / 文章详情 / 关于
- [x] 网关接口打通（25/25 契约验证）
- [ ] 登录态适配（`cms_session` token 存 `wx.setStorageSync`）
- [ ] 微信登录接入（`wx.login` → `/api/wx/ma/code2session`）

## 微信后端节点（wx）

小程序登录/消息能力由 TARS 节点 `wx` 提供，接口见 `deploy/n25-wx-test.sh` 验证的 7 个端点：
`/api/wx/ma/code2session`、`/api/wx/ma/token`、`/api/wx/ma/subscribe/send`、
`/api/wx/mp/token`、`/api/wx/mp/userinfo`、`/api/wx/mp/template/send`、`/api/wx/verify`。
