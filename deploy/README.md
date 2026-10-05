# deploy —— 一键部署与运维脚本

本目录是 tars-cms 的**全自动化部署套件**。每个步骤是一个独立脚本，按序号执行即可从零搭起整套服务；每步都可单独重跑，失败可回退。

---

## 〇、一键部署（推荐）

```bash
cd /root/tars-cms

bash deploy/deploy.sh              # 顺序跑 n01~n09（幂等，可重跑）
bash deploy/deploy.sh --full       # 强制全量重装
bash deploy/deploy.sh --skip n02   # 跳过 n02 编译（复用已有包）
```

特性：**幂等**（重复执行安全）、**断点续跑**（中断后重跑从失败处继续）、**失败即停**、`--full` 强制重装、`--skip <n0X>` 跳步。



## 一、前置条件

| 依赖 | 说明 |
| --- | --- |
| TARS 平台 | 三个容器：`tars-mysql` / `tars-framework`（含 TarsWeb `:3000`）/ `tars-node` |
| Docker | 脚本通过 `docker exec` 操作容器，需宿主机有 docker 权限 |
| Go 1.21+ | 编译 `cms/`、`web/`、`gateway/bff/` 三个 Go 服务 |
| Node.js 18+ | 编译 `h5/`、`admin/` 前端 |

**本环境实测参数**（均可通过 `deploy/env.sh` 覆盖，默认值如下）：

```
tars-mysql      root 密码（env.sh 的 CMS_DB_PASS）  容器 IP 172.25.0.2
tars-node       节点 IP 172.25.0.5（CMS_NODE_IP，留空自动探测）
tars-framework  Web 平台 127.0.0.1:3000
网关            CMS_GATEWAY（留空自动取本机 IP:8200）
```

> **干净机部署**：先 `cp deploy/env.sh.example deploy/env.sh` 改密码，再跑 `n00-get-token.sh` 拿 ticket。
> 脚本内已**无硬编码 IP/密码**，全部收敛到 `env.sh` + `common.sh`。

---

## 二、执行顺序

```bash
cd /root/tars-cms

# ── 干净机第 0 步（可选：自动获取/验证 ticket，写入 env.sh）──
bash deploy/n00-get-token.sh

# ── 基础（业务服务 + 数据）──
bash deploy/n01-init-db.sh            # 建库建表 + 初始数据
bash deploy/n02-package.sh            # 编译打包 cms.CmsServer
bash deploy/n03-deploy.sh             # 上传发布到 tarsnode
bash deploy/n04-verify.sh             # 验证业务服务（RPC 连通性）

# ── 网关 ──
bash deploy/n05-config-gateway.sh     # 注册 station/upstream/httprouter

# ── 静态站（h5 + admin + 上传）──
bash deploy/n06-deploy-web.sh         # 编译打包发布 cms.CmsWeb（端口 13103）
bash deploy/n07-config-web-gateway.sh # 网关路由：/ /admin/ /uploads/ → CmsWeb

# ── BFF（HTTP ⇄ TARS 协议转换）──
bash deploy/n09-deploy-bff.sh         # 编译打包发布 cms.CmsBff（端口 3103）

# ── 平台状态修正（必做，否则 not_tars 服务显示 inactive）──
bash deploy/n08-fix-pid.sh            # 安装 cron，每分钟同步真实 PID

# ── 路由自检（防服务迁移后残留旧 IP）──
bash deploy/n10-fix-routes.sh         # 诊断 + 幂等修复网关路由
bash deploy/n10-fix-routes.sh --check # 只诊断不改动
bash deploy/n11-test.sh               # 全栈测试套件（9 层）
bash deploy/n12-health-monitor.sh --install  # 安装健康巡检 cron（每 5 分钟）
bash deploy/n13-logrotate.sh --install       # 安装日志轮转 cron（每小时）
bash deploy/n14-compose-deploy.sh     # Docker Compose 校验（全新机部署用）
```

### 全新机器从零部署（Docker Compose 一键）

现有环境的 4 个容器是用 `docker run` 起的，**不要在此机器上 `--up`**（会因 `container_name` 冲突失败）。全新机器从零部署：

```bash
# 1. 起基础设施（mysql + framework + node + nginx）
docker compose -f deploy/docker-compose.yml up -d

# 2. 等框架就绪（首次初始化 DB 需 30~60 秒）
docker compose -f deploy/docker-compose.yml ps

# 3. 发布 cms 业务服务到 tarsnode
bash deploy/deploy.sh

# 4. 自检
bash deploy/n14-compose-deploy.sh
```

**compose 文件说明**：`deploy/docker-compose.yml` 定义 4 个服务（tars-mysql / tars-framework / tars-node / tars-gateway-nginx），复用 `/docker/tars/` 下现有数据目录，网络固定 `172.25.0.0/16`。tars-gateway-nginx 用 `network_mode: host` 以监听宿主机 8200 端口。

---

## 三、脚本职责一览

| 脚本 | 作用 | 端口/产物 |
| --- | --- | --- |
| `n00-get-token.sh` | **获取 ticket**：优先 env.sh > 自动登录 > c03 回退；写入 env.sh | ticket |
| `n01-init-db.sh` | 建 `tars_cms` 库、建表、插入示例文章与分类 | MySQL 13307 |
| `n02-package.sh` | `CGO_ENABLED=0` 静态编译 → 打扁平 tgz | `CmsServer.tgz` |
| `n03-deploy.sh` | 注册 `t_server_conf`/`t_adapter_conf` → 上传 → 发布 | `cms.CmsServer` |
| `n04-verify.sh` | RPC 冒烟：调 `ArticleObj`/`AuthObj` 验证 | — |
| `n05-config-gateway.sh` | 网关注册 `cms` station + 上游 + 路由 | 网关 8200 |
| `n06-deploy-web.sh` | 编译 `web/` + 打包前端 dist → 发布静态站 | `cms.CmsWeb` 13103 |
| `n07-config-web-gateway.sh` | 网关路由 `/`、`/admin/`、`/uploads/` | 网关 8200 |
| `n08-fix-pid.sh` | **安装 cron**：每分钟校正 not_tars 服务 PID | crontab |
| `n09-deploy-bff.sh` | 编译 `gateway/bff/` → 发布 BFF | `cms.CmsBff` 3103 |
| `n10-fix-routes.sh` | **路由自检**：诊断 + 幂等修复网关路由 | `t_http_router` |
| `n11-test.sh` | **测试套件**：9 层 30+ 断言（单元/端到端/契约/XSS/鉴权/上传/CORS） | 无（只读 + 临时测试数据） |
| `n12-health-monitor.sh` | **健康巡检**：每 5 分钟，连续 3 次异常才告警；`--install`/`--uninstall` 管 cron | 4 HTTP + 3 服务状态 |
| `n13-logrotate.sh` | **日志轮转**：>50M 归档并截断（gzip + 保留 7 份），`--install` 每小时 cron | 容器 tars-node 内 `app_log` |
| `n14-compose-deploy.sh` | **Compose 校验/部署**：全新机一键起 4 容器；现有环境只校验不改动 | `docker-compose.yml` |

---

## 为什么业务服务不能做成独立镜像

`cms.CmsServer` / `cms.CmsWeb` / `cms.CmsBff` **不是独立容器**，而是由 `tarsnode` 托管的进程（`not_tars` 模式）：

| 约束 | 说明 |
| --- | --- |
| **心跳与状态** | tarsnode 定期上报 `t_server_conf.present_state`，脱离则平台显示离线 |
| **PID 守护** | tarsnode 按 `process_id` 监控进程，异常自动拉起（见 `n08-fix-pid.sh`） |
| **TARS 寻址** | 服务间靠 `cms.CmsServer.ArticleObj@tcp -h 172.25.0.5 -p 13101` 寻址，需注册到框架 |
| **发布流程** | 二进制经 tarsnode 的 `/data/tars` 加载，不能挂载覆盖 |

**结论**：把 cms 三服务做成独立镜像 = 放弃 TARS 框架本身（本项目正是教 TARS 的）。因此采用**分层交付**：

```
docker compose up -d        # 基础设施（可容器化，已完成）
bash deploy/deploy.sh       # 业务服务（必须走 tarsnode 发布）
```

若确实需要"一条命令起全套"，可写一个 `cms-deploy` 一次性容器（挂载 `/var/run/docker.sock`，容器内跑 `deploy.sh`），但本质仍是调用同一套脚本，收益有限。

---

## 四、关键设计说明

### 1. 发布包必须扁平

`tarsnode` 把包解压到服务的 `bin/` 目录，包内**不能再套一层目录**：

```
CmsWeb.tgz
└── CmsWeb/
    ├── CmsWeb          ← 入口（包装脚本，必须与 server_name 同名）
    ├── CmsWeb_bin      ← 真实二进制
    ├── tars_start.sh
    ├── tars_stop.sh
    └── data/{h5,admin} ← 静态资源
# 解压后: <server>/bin/{CmsWeb, CmsWeb_bin, data/...}
```

套成 `bin/CmsWeb` 会解压出 `bin/bin/CmsWeb` → 启动失败。

### 2. not_tars 服务的 PID 自愈（方案 A）

`tarsnode` 启动 `not_tars` 服务时：
1. 用硬编码模板重写 `bin/tars_start.sh`，末尾强制 `&` 后台启动；
2. fork 该脚本并记录**脚本的 PID**，但脚本 2ms 内退出 → 记录的是死 PID；
3. 之后仅靠 `kill -0 <死PID>` 探测 → 平台永远 `inactive`；且每约 60s 覆盖一次 DB。

因此 `n06`/`n09` 生成的**入口包装脚本**内置了守护：

```sh
MY_PID=$$                       # exec 后 PID 不变，这就是最终服务 PID
setsid sh -c '
    MY_PID='"$MY_PID"'
    while kill -0 $MY_PID 2>/dev/null; do
        mysql ... "UPDATE t_server_conf SET process_id=$MY_PID, present_state=\"active\" ..."
        sleep 1
    done
' >/dev/null 2>&1 < /dev/null &
exec "$DIR/<Server>_bin" "$@"
```

- **`setsid` 必须**：否则守护成为服务子进程，进程树畸形且随发布失效；
- 实测效果：仅方案 A → 95% 采样点 active；配合方案 B（`n08` cron）→ **100%**；
- CPU 开销约 0.1%。

### 3. 方案 B：cron 兜底（n08）

每分钟从端口反查真实 PID 写回 DB，防止任何后续漂移：

```bash
bash deploy/n08-fix-pid.sh            # 安装 + 立即同步一次
crontab -l | grep n08                 # 查看
crontab -l | grep -v n08-fix-pid | crontab -   # 撤销
```

### 4. 网关路由必须写**容器 IP**

`tarsnode` 托管的服务监听在容器网络内，不映射到宿主机。网关与 tarsnode 同网络，因此 `f_proxy_pass` 必须写 `http://172.25.0.5:<port>`，写宿主机 IP 会得到 HTTP 000。

**`n05`/`n07` 已自动探测**（`docker inspect tars-node`），可用 `CMS_NODE_IP` 覆盖：

```bash
# 探测逻辑
NODE_IP="${CMS_NODE_IP:-$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' tars-node)}"
BFF="$NODE_IP:3103"
CMSWEB="$NODE_IP:13103"
```

**典型故障**：BFF 从宿主机迁移为 tarsnode 托管后，路由表里仍是旧宿主机 IP → `/api/*` 全部 HTTP 000，但 `/admin/`（指 CmsWeb）正常。此时改 `t_http_router.f_proxy_pass` 为容器 IP 并重启 `Base.GatewayServer` 即可。

**路由归属**（`cms` 站点 `f_station_id=3`）：

| f_path_rule | 目标 | 说明 |
| --- | --- | --- |
| `/` | `http://172.25.0.5:13103` | CmsWeb → h5 首页 |
| `/admin/` | `http://172.25.0.5:13103` | CmsWeb → 后台 |
| `/uploads/` | `http://172.25.0.5:13103` | CmsWeb → 上传文件 |
| `/api/` | `http://172.25.0.5:3103` | BFF → TARS RPC |

> ⚠️ `/` 不要指向 BFF（BFF 只管 API，`GET /` 返回 404）。

改完 `db_base.t_http_router` 后需重启 `Base.GatewayServer` 生效。

### 5. 上传发布包的三个坑

```bash
# ① 包必须先 docker cp 进 tars-framework（容器内 curl 读不到宿主机路径）
docker cp "$PKG" tars-framework:/tmp/$SERVER.tgz

# ② 必须在 tars-framework 容器内 curl 127.0.0.1:3000（免登录白名单）
#    宿主机 curl 会报「您还没有登录」
docker exec tars-framework curl -s -X POST \
    "http://127.0.0.1:3000/pages/server/api/upload_patch_package?ticket=$TOKEN" \
    -F "application=$APP" -F "module_name=$SERVER" \
    -F "suse=@/tmp/$SERVER.tgz;filename=$SERVER.tgz"

# ③ add_task 的 command 是 patch_tars（不是 patch），patch_id 传数字
```

### 6. `TOKEN` 的来源

各脚本从 `/docker/tars/scripts/c03-deploy-chisha.sh` 提取 Web 平台 ticket：

```bash
TOKEN=$(grep "^TOKEN=" /docker/tars/scripts/c03-deploy-chisha.sh | cut -d'"' -f2)
```

**换环境注意**：该文件属于另一个项目（chisha），若不存在需自备 ticket，或改为登录 `TarsWeb` 获取。这是当前唯一的跨项目依赖。

---

## 五、验证清单

部署完成后逐项确认：

```bash
# 1. 平台状态（三服务应全部 active）
docker exec tars-mysql mysql -uroot -ptars@root.2026 db_tars -e \
  "SELECT server_name, present_state, process_id FROM t_server_conf WHERE application='cms';"

# 2. 全链路
GW=http://192.168.1.95:8200
curl -s -o /dev/null -w "h5:    %{http_code}\n" $GW/
curl -s -o /dev/null -w "admin: %{http_code}\n" $GW/admin/
curl -s -o /dev/null -w "api:   %{http_code}\n" "$GW/api/cms/home?tenantId=1"

# 3. 上传链路
curl -s -X POST "$GW/api/admin/upload/image?tenantId=1" -F "file=@/tmp/test.png"
```

---

## 六、已知限制

| 限制 | 说明 |
| --- | --- |
| `not_tars` 状态需守护 | tarsnode 每约 60s 覆盖 DB，靠 A+B 方案压制；采样仍可能偶见 inactive 瞬间，**不影响业务** |
| 网关不读 `present_state` | 平台状态纯属展示层，路由转发只依赖端口连通性 |
| `tars_start.sh` 不可定制 | 每次 activate 被 tarsnode 模板重写，改它无效（需改包装脚本） |
| 跨项目 TOKEN 依赖 | 见上文 §4.6 |
