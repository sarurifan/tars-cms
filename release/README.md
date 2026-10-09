# TarsGateway 交付包 (release/)

本目录是 tars-cms 项目一键部署所需的**网关组件交付物**。

## 目录结构

```
release/
├── gateway/                     # GatewayServer 交付物
│   ├── GatewayServer            # C++ 编译产物（27MB，v1.3.3 快照编译，不入 git）
│   ├── GatewayServer.tgz        # tarsnode 可部署发布包（已注入 conf，不入 git）
│   ├── GatewayServer.conf       # 网关配置模板（db 段指向 db_base）
│   ├── httpheader.conf          # 响应头协议映射
│   └── db_base.sql              # 网关路由/站点/流控表结构（7 张表）
├── web/                         # GatewayWebServer 源码（Node/Koa，动态路由管理 API）
│   ├── src/                     # 后端源码（app.js + gateway 控制器/DAO）
│   ├── client/                  # 管理界面前端（已 build）
│   ├── package.json             # 依赖清单（35 deps，npm install 安装）
│   └── publish.sh               # 官方发布脚本（可选）
└── install-gateway.sh           # 一键部署脚本（见下）
```

## 两种部署模式

| 模式 | 说明 | 适用 |
|------|------|------|
| **A. static** | 仅 GatewayServer（C++，8200），路由写在 db_base 表 | 不需要管理界面，最小部署 |
| **B. web**（默认） | A + GatewayWebServer（Node，15535），n05/n07 通过它写路由 | 完整功能，含 web 管理 API |

> **本仓库部署脚本 n05/n07 依赖模式 B**（通过 `http://127.0.0.1:15535/plugins/base/gateway/api` 注册 station/upstream/router）。

## 一键部署

### 方式一：随 tars-cms 仓库整体部署

```bash
# 1. 配置环境（密码等凭据，不硬编码）
cp deploy/env.sh.example deploy/env.sh
vim deploy/env.sh    # 填 CMS_DB_PASS 等

# 2. 一键部署（基础设施已有 4 容器时）
bash deploy/deploy.sh

# 只部署网关（编译 + 部署 + 起 GatewayWeb）
bash deploy/n15-gateway.sh
bash deploy/n15-gateway.sh --build   # 只编译
bash deploy/n15-gateway.sh --deploy  # 只部署发布到 tarsnode
bash deploy/n15-gateway.sh --web     # 只起 GatewayWebServer（容器内）
bash deploy/n15-gateway.sh --check   # 只验证
```

### 方式二：release 包独立部署

```bash
# 在目标机（已有 tars 4 容器）执行：
bash release/install-gateway.sh
```

## 二进制来源

`gateway/GatewayServer` 由 **TarsGateway v1.3.3 源码** 编译：

```bash
# 官方 zipball（含配套 tarscpp，一次编译通过，无需 patch）
curl -LO https://github.com/TarsCloud/TarsGateway/archive/refs/tags/v1.3.3.zip
unzip v1.3.3.zip && cd TarsGateway-1.3.3

# 用 base-compiler 容器编译（已实测通过，输出 26MB GatewayServer）
cat > /tmp/build-gateway.sh <<'EOF'
#!/bin/bash
set -e
cd /src
rm -rf build && mkdir -p build && cd build
cmake .. -DTARS_MYSQL=ON -DTARS_SSL=OFF -DTARS_HTTP2=OFF -DTARS_GPREF=OFF
make -j$(nproc)
EOF
docker run --rm -v $PWD:/src -v /tmp/build-gateway.sh:/tmp/build-gateway.sh:ro \
  tarscloud/base-compiler:latest bash /tmp/build-gateway.sh
# 产物: build/bin/GatewayServer
```

> 注意：**不要用 master 分支编译**（新版 tarscpp 有 `getModuleName` 废弃 API，报错
> `getModuleName was not declared in this scope`）。必须用 v1.3.3 tag 的源码。

## 发布包说明

`GatewayServer.tgz` 是 **tarsnode 可部署包**（结构：`GatewayServer/GatewayServer`），
已注入 `GatewayServer.conf` + `httpheader.conf`（db 段指向 `db_base`）。

发布方式（与 deploy/n15-gateway.sh 一致）：
1. `deploy_server` 注册 Base.GatewayServer（ProxyObj not_tars 8200 + FlowControlObj tars 18212）
2. `upload_patch_package` 上传 tgz
3. `add_task patch_tars` 发布
4. `add_task start` 启动

## 已应用的三个补丁（v1.3.3 上游 bug）

| 补丁 | 位置 | 说明 |
|------|------|------|
| **logger 缺失** | `web/src/logger.js` | 上游 `require('../../logger')` 引用了 `src/logger/` 目录但该目录不存在。Node require 优先命中 `logger.js` 文件，故本补丁创建单文件 shim（优先 `@tars/logs`，退化为 console）。 |
| **本地免登录** | `web/src/midware/loginMidware.js` + `web/src/config/webConf.js` | 上游 `localAuth.localIp` 字段定义了但未实现。本补丁让白名单 IP（127.0.0.1 等容器 IP）旁路 AdminReg.checkTicket，本地 curl/容器内调用免 ticket，旁路时 `ctx.uid='local'`。 |
| **local 视为管理员** | `web/src/gateway/controller/GatewayController.js` | `getFilterUid` 在免登录旁路时把 `local` 直接返回 null（=管理员，可读写全部站点/路由），否则 AdminReg RPC 传 undefined 报 `Received undefined`。 |

> 这三个补丁是 **v1.3.3 上游源码的缺陷修复**，不在上游 master（master 有更严重的 `getModuleName` 废弃 API 不兼容 TarsCpp 3.x）。

## 依赖清单

| 组件 | 版本 | 说明 |
|------|------|------|
| tars-framework | v3.0.15 | 含 TarsWeb（:3000） |
| tars-node | stable | 托管业务服务 |
| tars-mysql | 5.6 | db_tars / db_base / tars_cms |
| GatewayServer | v1.3.3 | C++ 网关（8200） |
| GatewayWebServer | v3.0.0 | Node/Koa 管理 API（15535） |
| Node.js | 16+ | 容器内运行 GatewayWeb |
