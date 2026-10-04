# tars-cms 五轮调研报告 — 改进决策文档

**日期**：2026-10-05
**范围**：代码质量 / 运行性能 / 安全 / 运维 / 架构
**结论**：3 个高危安全问题必须修，其余按 ROI 分级排期

---

## 执行摘要

| 轮次 | 维度 | 结论 |
| --- | --- | --- |
| 1 | 代码质量 | ✅ 良好——go vet 全过、零 TODO，但密码硬编码 |
| 2 | 运行性能 | ⚠️ 接口延迟极低(1-3ms)，但**热门查询全表扫描** |
| 3 | 安全 | 🔴 **上传无限制 = 存储型 XSS 可打穿**；CORS 反射任意 Origin |
| 4 | 运维可观测 | ⚠️ 无监控、无定时备份、**恶意文件删不掉** |
| 5 | 架构与文档 | ⚠️ **4 个目录是空壳**但 README 宣称有；401 前后端契约不匹配 |

**一句话**：功能与性能都好，**安全是短板**，文档有夸大。

---

## 🔴 P0 — 必须立即修复（3 项）

### P0-1 上传功能无类型限制 → 存储型 XSS（已实测利用）

**复现**：上传 `evil.html` 到 `/api/admin/upload/file` → 存于同源 `/uploads/` → 浏览器打开即执行脚本（实测渲染出 `pwned`）。

**危害**：同源 XSS 可窃取管理员 localStorage 里的 token、以管理员身份调后台接口、篡改/删除全部内容。SVG 同样可携带 `<script>`。

**根因**：`cms/article_imp.go` 的 `upload()` 未校验扩展名/MIME，任何文件都能传。

**修复方案**（三选一，推荐 a）：
- **a. 白名单 + 强制后缀**（最稳）：图片仅 `jpg/png/gif/webp/svg`（svg 需再过滤 `<script>`），文件仅 `pdf/txt/md/zip`；扩展名与 MIME 双向校验
- **b. 独立域名/端口隔离**：`uploads.example.com` 与主站不同源，XSS 打不到 session（但需额外域名）
- **c. 强制 `Content-Disposition: attachment`** + `X-Content-Type-Options: nosniff`：浏览器不渲染直接下载（牺牲在线预览）

**工作量**：a 方案约 1 小时（后端白名单 + 测试用例）。

### P0-2 `/api/admin/*` 鉴权已修，但**前端 401 契约不匹配**

**现状**：BFF 已返回 **HTTP 401 + body `{"code":-1,...}`**，但前端 `request.ts` 检查 `res.code === 401`。

**实测后果**：token 过期时前端拿到 `code:-1` → 只弹「请求失败」**不会自动登出跳登录页**，用户卡死在无权限状态。

**修复**（2 行，h5 + admin 各一处）：
```ts
// request.ts 响应拦截器，把 res.code===401 改为：
if (res.code === 401 || res.code === -1 && /unauthorized/i.test(res.msg || '')) {
  clearToken(); window.location.href = '/login'
}
// 或后端在 body 里补 code:401（二选一，保持契约统一）
```

**工作量**：15 分钟。

### P0-3 密码硬编码在 10 个 sh 脚本 + 1 处 Go 默认值

**现状**：`tars@root.2026` 写死在 `deploy/*.sh`（10 个）和 `cms/db.go:38`。

**风险**：仓库公开后凭据泄露；换环境要改 11 处。

**修复**：统一走环境变量 + `.env.example`：
```bash
# deploy/env.sh（新增）
export CMS_DB_PASS="${CMS_DB_PASS:?请设置}"
```
脚本首行 `source` 它；`go` 侧已有 `envOr`，去掉默认值即可。

**工作量**：1 小时。

---

## 🟡 P1 — 本季度内（3 项）

### P1-1 热门查询全表扫描

**证据**：`EXPLAIN ... ORDER BY sort ASC, id DESC` → `type=ALL`，`key=NULL`。现有 `idx_tenant_sort(tenant_id, sort)` 不匹配（还按 `id` 排序且要过滤 `status`）。

**当前无感**（数据 10 篇、延迟 2ms），但数据过万后会劣化。

**修复**：加复合索引
```sql
ALTER TABLE cms_article ADD INDEX idx_list (tenant_id, status, sort, id);
```

**工作量**：5 分钟 + 重启服务。

### P1-2 CORS 反射任意 Origin + `Access-Control-Allow-Credentials: true`

**现状**：`corsMiddleware` 把请求头 `Origin` 原样回写，且允许带 cookie。任意站点可跨域带凭据调后台接口。

**修复**：白名单 `http://192.168.1.95:8200`（+ 可选的域名），非白名单返回空。

**工作量**：20 分钟。

### P1-3 恶意文件删除不生效

**现象**：`/api/admin/media/delete` 删了 DB 记录，但 `/uploads/` 物理文件仍可访问（实测 `evil.html` 删除后 HTTP 200）。

**修复**：删除记录时同步 `os.Remove()` 磁盘文件。

**工作量**：30 分钟。

---

## 🟢 P2 — 择机优化（6 项）

| # | 问题 | 现状 | 建议 | 工作量 |
| --- | --- | --- | --- | --- |
| P2-1 | 无监控告警 | 无 prometheus/grafana；服务挂了靠人工发现 | 最小方案：加 `/health` 到 BFF（现 404），网关 5xx 告警脚本 | 1h |
| P2-2 | 无 CMS 数据定时备份 | 仅手动备份过 1 次；hermes 有月备但不含 tars_cms | 加 cron 每日 `mysqldump tars_cms` | 30min |
| P2-3 | 登录无防暴力破解 | 5 次错误密码响应一致、无限流 | 失败 5 次锁 10 分钟（内存或 DB 计数） | 1h |
| P2-4 | BFF 无超时/重试 | TARS 调用挂起则 HTTP 请求无限等待 | `context.WithTimeout(5s)` 包每个 RPC 调用 | 1h |
| P2-5 | 4 个空壳目录 | `auth/ base/ mp/ Benchmark/` 仅 README | 二选一：补实现 **或** README 改为"规划中" | 1h（改文档） |
| P2-6 | admin bundle 1.2MB | 未压缩 1.2MB（gzip 后 ~300KB） | 开启路由懒加载 + 手动 chunk 拆分 | 1h |

---

## 📋 决策建议（供选择）

### 方案 A：安全冲刺（推荐先做）
> 只修 P0-1/2/3 + P1-2/3，约 **3 小时**，把高危面关掉

### 方案 B：A + 稳定性
> A 基础上加 P1-1、P2-1、P2-2、P2-4，约 **6 小时**

### 方案 C：全量
> A + B + P2-3/P2-5/P2-6，约 **10 小时**

### 方案 D：维持现状
> 仅修 P0-2（15 分钟，因它是**当前已上线功能的 bug**），其余挂起

**我的建议**：**方案 A**。理由：
1. P0-1 是**可被利用的存储型 XSS**，且上传功能已上线——这是"能偷 token 的洞"，不是理论风险
2. P0-2 是**前后端契约 bug**，token 过期后用户会卡死，属可用性缺陷
3. P0-3 关系仓库公开安全（项目已推 GitHub）
4. 其余 P1/P2 都不影响当前单机小数据量使用

---

## 附录：五轮调研原始证据

### 第 1 轮 代码质量
```
go vet: cms ✅ gateway/bff ✅ web ✅
TODO/FIXME/HACK: 0 处
硬编码密码: Go 1 处(db.go:38) + sh 10 处
单文件行数最大: gateway/bff/main.go 668 行
```

### 第 2 轮 性能
```
延迟: home 3ms / articles 2ms / tree 1ms
资源: GatewayServer 20MB / CmsServer 20MB / CmsBff 14MB / CmsWeb 7MB
连接池: MaxIdle=10 MaxOpen=100 ConnMaxLifetime=1h ✅
EXPLAIN: type=ALL key=NULL ← 全表扫描
admin bundle: 1.2MB (index-*.js) / h5 bundle: 148KB
slow_query_log: OFF（无法发现慢查询）
```

### 第 3 轮 安全（关键）
```
上传 .svg  → code:0 success（含 <script>）
上传 .html → code:0 success
上传 .php  → code:0 success
浏览器打开 evil.html → 渲染 "pwned"（执行了）
CORS: Access-Control-Allow-Origin = 反射任意 Origin
CORS: Allow-Credentials = true
8200 监听 0.0.0.0（0.0.0.0:8200）
uploads 目录与主站同源
```

### 第 4 轮 运维
```
监控栈: 无（无 prometheus/grafana）
CMS 定时备份: 无（仅 1 次手动备份）
恶意文件删除: media API 删成功，物理文件仍 HTTP 200
BFF /health: 404
CmsWeb /health: 200
部署脚本: 12 个，含回滚 2 个
CI: 无配置
```

### 第 5 轮 架构与文档
```
空壳目录: auth/(1 文件) base/(3) mp/(1) Benchmark/(2)
README 宣称: "自带 TarsBenchmark"、"多语言混合(Go/Java/C++/Node)" —— 与实际不符
git: 14 提交，feat 7/docs 4/fix 2
前端 401: request.ts 检查 res.code===401，实际返回 HTTP 401 + code:-1
登录防爆破: 5 次错误密码响应一致，无锁定
限流: t_flow_control 表 0 条规则
分支: main 单分支（无 develop/feature 分支）
```

### 测试套件状态
```
bash deploy/n11-test.sh → 21/21 通过 ✅
单元测试 31 用例全过
已修复的 2 个 bug: 零鉴权漏洞、init.sql 假幂等
```
