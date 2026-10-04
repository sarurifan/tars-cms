# 测试说明

## 一、三层测试体系

```bash
# 全部三层（推荐）
bash deploy/n11-test.sh

# 只跑单元测试（无需服务在跑）
bash deploy/n11-test.sh --unit

# 只跑端到端（需服务已部署）
bash deploy/n11-test.sh --e2e
```

| 层级 | 范围 | 工具 | 依赖 |
| --- | --- | --- | --- |
| 第一层 单元测试 | 纯函数：XSS 过滤、分类树、分页、文件名消毒等 | `go test` | 无（31 用例） |
| 第二层 服务存活 | 4 个服务端口监听 | `ss` | 服务已部署 |
| 第三层 端到端 | 前端→网关→BFF→TARS→MySQL 全链路 | `curl` + 网关 | 全栈已部署 |
| 第四层 数据契约 | 响应字段存在性与类型（尤其 `author` 是对象非字符串） | `python3 json` | 网关 |
| 第五层 XSS 防护 | 写入 `<script>` → 读回验证已净化 | 登录+创建+读取 | 网关+DB |
| 第六层 鉴权边界 | 未授权访问 `/api/admin/*` 应 401 | `curl` | 网关+BFF |
| 第七层 错误处理 | 非法输入（page=abc / size=99999 / 不存在 id）应优雅降级 | `curl` | 网关 |

退出码非 0 即失败（`exit $((FAIL>0))`），可直接接 CI。

## 二、单元测试文件

| 文件 | 覆盖 | 用例 |
| --- | --- | --- |
| `cms/util_test.go` | XSS 过滤、摘要截取、分类树构建（含孤儿提升/排序）、时间格式化、模型转换、响应包装 | 16 |
| `cms/upload_test.go` | 文件名消毒（路径穿越/中文保留）、MIME 检测（16 种扩展名） | 2 |
| `gateway/bff/main_test.go` | 参数解析、token 提取（Header 优先/Query 回退）、JSON body 解析、错误响应格式 | 12 |

```bash
cd cms && go test -v ./...
cd gateway/bff && go test -v ./...
```

## 三、测试抓到并已修复的两个真实 bug

### 1. `/api/admin/*` 零鉴权（安全漏洞）
- **现象**：不带 token 即可读写全部 CMS 内容（含未发布草稿、成员列表）
- **根因**：BFF 所有后台 handler 直接调 TARS RPC，无任何鉴权中间件
- **修复**：新增 `authMiddleware`，用 `AuthObj.GetUserInfo` 校验 token，无效返回 401
- **验证**：未授权 401 / 伪造 token 401 / 真 token 200 / 公开接口不受影响

### 2. `init.sql` 声称幂等但实际重复插入
- **现象**：连跑 4 次 `n01`，文章 11→41、分类 5→20
- **根因**：`cms_article`/`cms_category` 用纯 `VALUES` 且无业务唯一键
- **修复**：改 `INSERT ... SELECT ... WHERE NOT EXISTS`；`category_id` 按分类名动态关联
- **验证**：连跑 3 次数据量恒定 `10/5/10`

## 四、部署后必须跑测试的场景

改以下任何一处后运行 `bash deploy/n11-test.sh`：

- `cms/*.go`（业务逻辑、模型）
- `gateway/bff/main.go`（路由、鉴权、参数解析）
- `deploy/sql/init.sql`（数据契约）
- 网关路由（`t_http_router`）

## 五、已知限制

| 限制 | 说明 |
| --- | --- |
| 无自动化 CI | 当前需手动执行；接入时按第四节配置 |
| 单元测试不覆盖 RPC 层 | TARS 服务的 RPC 方法只在端到端层验证 |
| 前端无组件测试 | h5/admin 未引入测试框架，仅通过端到端 + 截图验证 |
| XSS 测试有副作用 | 第五层会创建再删除一篇测试文章 |
