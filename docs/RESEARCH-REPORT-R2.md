# tars-cms 第二轮五轮调研报告 — 改进决策文档

**日期**：2026-10-05
**前提**：第一轮 P0/P1/P2 已全部修复（方案 A + 完整 P1/P2）
**方法**：每轮聚焦一个维度，实测取证，逐项判定

---

## 执行摘要

| 轮次 | 维度 | 结论 |
| --- | --- | --- |
| 1 | 安全与凭据 | 🔴 **GitHub 仓库是 public 的，git 历史含 35 处密码**（已泄漏公网）；无安全响应头；/uploads/ 目录列表开放 |
| 2 | 代码质量 | ⚠️ 测试覆盖率仅 1.4%/6.3%；BFF `main()` 511 行单函数 |
| 3 | 运行时性能 | ✅ 延迟 1-4ms，内存正常；⚠️ 日志无轮转（TLOG.log 已 8.3MB） |
| 4 | 运维自动化 | ✅ 13 脚本全过语法、cron 就绪（备份/巡检/PID 修正）；⚠️ n12 脚本有硬编码密码 |
| 5 | 文档一致性 | ⚠️ 上轮 README 修正已生效；deploy/README 缺 n11/n12 记录；mp/README 仍宣称已实现 |

**最高优先级**：git 历史里的密码已随 public 仓库泄漏到公网（35 处），需立即处理。

---

## 🔴 P0 — 必须立即处理（1 项）

### P0-A git 历史密码泄漏（公网）

**证据**：
- `git log --all -p | grep -c "tars@root.2026"` → **35 处**
- GitHub API `sarurifan/tars-cms` → `visibility: public`
- 密码 `tars@root.2026` 出现在 10+ 提交，覆盖 `deploy/*.sh`、`cms/db.go`

**风险**：任何人 clone 仓库即可拿到数据库 root 密码。若这台 MySQL 暴露公网或同机有其他服务，风险更大。

**三条路径（需你决策）**：

| 方案 | 做法 | 代价 | 有效性 |
| --- | --- | --- | --- |
| **A. 仓库转私有** | GitHub Settings → Danger Zone → Change visibility → Private | 5 分钟，开源目标放弃 | 立即阻断 |
| **B. 改密 + 清历史** | ① 改 DB root 密码 ② 用 `git filter-repo` 清历史 ③ force push 三端 | 30-60 分钟，所有 fork/clone 失效 | 事后清除 |
| **C. 保持现状** | 接受泄漏（假设内网 MySQL 未暴露公网） | 0 | 风险保留 |

**我的推荐**：**A 或 B**。这个密码是 MySQL root，不只是 tars-cms 一个库（同实例还有 `db_tars` 平台库、`db_base` 网关库）。若该 MySQL 只在内网且不暴露公网，风险降低但仍不建议留。

**同时要修**：`deploy/n12-health-monitor.sh` 里我上轮忘了删硬编码密码（`DBPASS="${CMS_DB_PASS:-tars@root.2026}"`）—— 这是本次新增的、当前代码仍在泄漏的。

---

## 🟡 P1 — 本季度内（4 项）

### P1-1 HTTP 安全响应头缺失
**证据**：`curl -I` 无 `X-Content-Type-Options`/`X-Frame-Options`/`CSP`/`Strict-Transport-Security` 任一。
**影响**：缺少 `X-Content-Type-Options: nosniff` 时 MIME 嗅探可能把上传的 txt 当 html 解析；`X-Frame-Options` 缺失允许 iframe 嵌套（点击劫持）。
**修复**：BFF `corsMiddleware` 里统一加：
```go
w.Header().Set("X-Content-Type-Options", "nosniff")
w.Header().Set("X-Frame-Options", "SAMEORIGIN")
w.Header().Set("X-XSS-Protection", "0")
w.Header().Set("Referrer-Policy", "strict-origin-when-cross-origin")
```
**工作量**：20 分钟。

### P1-2 `/uploads/` 目录列表开放
**证据**：`curl http://192.168.1.95:8200/uploads/` → HTTP 200 + `<pre><a href="2026/">2026/</a></pre>`，可枚举所有上传文件。
**影响**：枚举敏感文件（虽然文件名含时间戳，但目录结构暴露）。
**修复**：CmsWeb（C++ 静态站服务）关闭 autoindex，或在网关 `t_http_router` 加规则返回 403。
**工作量**：30 分钟。

### P1-3 日志无轮转
**证据**：`/usr/local/app/tars/app_log/cms/CmsServer/TLOG.log` 8.3MB 且持续增长，无 logrotate 配置。
**影响**：长期运行磁盘耗尽。
**修复**：加 logrotate 配置（`/etc/logrotate.d/tars-cms`，size 100M 轮转保留 7 份）。
**工作量**：20 分钟。

### P1-4 `deploy/README.md` 未记录 n11/n12
**证据**：README 脚本清单只到 n10，实际已有 n11-test.sh、n12-health-monitor.sh。
**修复**：补两行。
**工作量**：5 分钟。

---

## 🟢 P2 — 择机优化（4 项）

| # | 问题 | 现状 | 建议 | 工作量 |
| --- | --- | --- | --- | --- |
| P2-1 | 测试覆盖率低 | cms 1.4%、bff 6.3% | 优先给 `article_imp.go`（749 行核心）和 BFF handler 补集成测试 | 4h |
| P2-2 | BFF `main()` 511 行 | 单函数，难维护 | 拆 `registerArticleRoutes`/`registerAuthRoutes` 等（纯重构，行为不变） | 2h |
| P2-3 | `mp/README.md` 宣称已实现 | 目录只有 README，却标 h5/admin "✅ 已完成" | 改为「规划中」或删掉该表 | 10min |
| P2-4 | 注释覆盖率 8.5% | 偏薄 | 导出函数补 doc comment（`go doc` 可见） | 1h |

---

## 决策建议

| 方案 | 内容 | 工时 |
| --- | --- | --- |
| **A（推荐）** | P0-A 密码泄漏处理 + P1-1/2/3/4 | 2-3h（含清历史则 ~1h） |
| B | A + P2-3 文档修正 | 3h |
| C | 全量（含 P2-1 覆盖率、P2-2 重构） | 9h |
| D | 只修 n12 硬编码密码（5min）+ 其余挂起 | 10min |

**关键分叉点**：**git 历史密码泄漏怎么处理**（转私有 vs 清历史 vs 保留）——这决定 P0-A 的方向，且需你拍板，因为影响开源策略。

**我建议方案 A**，但 P0-A 具体走哪条路要你定：
- 若这项目**要开源** → 选 **B 清历史**（保留 public 但删密码）
- 若**暂不打算开源** → 选 **A 转私有**（最省事，改密也建议做）
- 若**确认 MySQL 只在内网**且可以接受 → 选 **C**，但至少修 n12 那个正在泄漏的

---

## 附录：五轮原始证据

### R1 安全
```
GitHub visibility: public
git 历史密码: 35 处
Go 源码硬编码: 0（已修）
sh 硬编码: 2 个（env.sh 预期内 + n12 ⚠ 新增未修）
安全响应头: 无任一
/uploads/ 目录列表: HTTP 200 + 内容枚举
登录响应: 用户名存在与不存在响应一致 ✅
.env/密钥文件误提交: 无 ✅
```

### R2 代码质量
```
cms 覆盖率: 1.4%   bff: 6.3%
go vet: 全过
main() 最长: 511 行（BFF）
注释率: 8.5%（2796 行 / 239 注释）
TODO/FIXME: 0
长文件: article_imp.go 749 行 / bff main.go 739 行
```

### R3 性能
```
延迟: home 4ms / articles 2ms / admin 1ms
内存: Gateway 19.9M / CmsServer 19.1M / CmsBff 14.7M / CmsWeb 6.4M
tars-node CPU: 53%（来自 Tars 官方 demo：HelloGo/AuthServer/logicServer 非我们服务）
索引: 6 个索引就位，慢查询 0
数据: article 18 / media 11 / users 6
日志: 11M，TLOG.log 8.3M 无轮转 ⚠
```

### R4 运维
```
13 个 sh 脚本: 全部语法通过
cron: n08 PID 每分钟 / backup 每日3点 / n12 巡检每5分钟
备份: 2 份 96K
```

### R5 文档
```
README 虚构脚本: 0（上轮已修）
deploy/README 缺: n11-test.sh / n12-health-monitor.sh
mp/README 宣称已实现: 2 处 ⚠
auth/base/Benchmark README: 已改「待补全」✅
docs/: architecture / README / RESEARCH-REPORT / TESTING
git: 19 提交（feat 8 / docs 5 / fix 2 / chore 2 / security 1）
```
