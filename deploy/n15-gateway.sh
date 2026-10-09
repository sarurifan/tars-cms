#!/usr/bin/env bash
# ================================================================
# n15-gateway.sh — 一键部署 TarsGateway 全家桶（编译+部署+发布+web管理）
# ================================================================
# 【架构】
#   Base.GatewayServer (C++, not_tars+8200) ── tarsnode 托管
#   GatewayWebServer   (Node.js, :15535)   ── 宿主机独立进程（不进 tarsnode）
#   db_base (MySQL)    静态路由 + 流控
#
# 【模式选择】CMS_GATEWAY_MODE（env.sh 可覆盖）
#   a) static  — 源码编译 + install.sh（静态路由，无需 GatewayWeb）
#   b) web     — 源码编译 + install.sh + GatewayWebServer（动态路由，默认）
#
# 【用法】
#   bash deploy/n15-gateway.sh             # 编译+部署+发布+web管理（默认 web 模式）
#   bash deploy/n15-gateway.sh --build     # 只编译
#   bash deploy/n15-gateway.sh --deploy    # 只部署+发布
#   bash deploy/n15-gateway.sh --web       # 只起 GatewayWebServer
#   bash deploy/n15-gateway.sh --check     # 只读验证
# ================================================================
set -euo pipefail

# 加载部署环境变量 + 公共库
_ENV_SH="$(cd "$(dirname "$0")" && pwd)/env.sh"
if [ -f "$_ENV_SH" ]; then . "$_ENV_SH"; fi
_COMMON_SH="$(cd "$(dirname "$0")" && pwd)/common.sh"
if [ -f "$_COMMON_SH" ]; then . "$_COMMON_SH"; fi

MODE="${CMS_GATEWAY_MODE:-web}"   # a) static | b) web（默认 b）
STAGE="${1:-all}"                 # --build | --deploy | --web | --check | all
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

# ── 常量 ──
# 源码固化在仓库 gateway/tarsgateway/（v1.3.3 快照），不再依赖外部路径。
# 可用 CMS_GW_SRC 覆盖（例如指向 /opt/TarsGateway 的独立 clone）。
GW_SRC_DIR="${CMS_GW_SRC:-$(cd "$(dirname "$0")/.." && pwd)/gateway/tarsgateway}"
GW_BUILD_OUT="${CMS_BUILD_DIR}/gateway"               # 输出目录（含 .tgz + release 物料）
TARS_MYSQL_CTN="${CMS_MYSQL_CTN:-tars-mysql}"
TARS_FW_CTN="${CMS_FW_CTN:-tars-framework}"
TARS_NODE_CTN="${CMS_NODE_CTN:-tars-node}"
NODE_IP="${CMS_NODE_IP:-172.25.0.5}"
DB_HOST="${CMS_DB_HOST:-172.25.0.2}"
DB_PORT="${CMS_DB_PORT:-3306}"
DB_USER="${CMS_DB_USER:-root}"
DB_PASS="${CMS_DB_PASS}"
GW_WEB_PORT="${CMS_GW_WEB_PORT:-15535}"
TOKEN="$(require_ticket)"

echo "══════════════════════════════════════════════════════════════════"
echo "  n15-gateway — TarsGateway 部署（mode=$MODE, stage=$STAGE）"
echo "══════════════════════════════════════════════════════════════════"
echo "  源码: $GW_SRC_DIR"
echo "  产物: $GW_BUILD_OUT"
echo "  节点: $NODE_IP:8200/18212"
echo "  DB:   $DB_HOST:$DB_PORT/db_base"
echo ""

# ── 工具函数 ──
C_CYAN=$'\033[36m'
ok()   { echo "  ${C_GREEN}✔ $1${C_END}"; }
warn() { echo "  ${C_YELLOW}⚠ $1${C_END}"; }
err()  { echo "  ${C_RED}✘ $1${C_END}" >&2; }
step() { echo; echo "${C_CYAN}═══ $1 ═══${C_END}"; }

sql()  { docker exec "$TARS_MYSQL_CTN" mysql -uroot -p"$DB_PASS" db_tars -sN -e "$1" 2>/dev/null; }
sqlb() { docker exec "$TARS_MYSQL_CTN" mysql -uroot -p"$DB_PASS" db_base -sN -e "$1" 2>/dev/null; }

# GatewayWebServer 在容器内，对外可达地址（宿主机通过容器 IP 直连）
gw_web_base() {
    local ip
    ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$TARS_FW_CTN" 2>/dev/null | head -1)
    printf 'http://%s:%s/plugins/base/gateway/api' "${ip:-172.25.0.3}" "$GW_WEB_PORT"
}

wait_for_port() {
    local ip="$1" port="$2" timeout="${3:-30}"
    for i in $(seq 1 "$timeout"); do
        curl -sf --max-time 2 "http://$ip:$port/" -o /dev/null 2>&1 && return 0
        sleep 1
    done
    return 1
}

# ── 模式 1: 编译 GatewayServer ──
do_build() {
    step "[1/4] 编译 GatewayServer (tars-framework 容器)"

    if [ ! -d "$GW_SRC_DIR/src" ]; then
        err "源码目录不存在或缺少 src/: $GW_SRC_DIR"
        err "应随仓库附带（gateway/tarsgateway/）。确认是否完整 clone。"
        exit 1
    fi

    mkdir -p "$GW_BUILD_OUT"

    # 同步源码进容器
    docker exec "$TARS_FW_CTN" mkdir -p /tmp/tarsgw
    docker cp "$GW_SRC_DIR/." "$TARS_FW_CTN:/tmp/tarsgw/"

    # 源码已含生成好的 .h（v1.3.3 快照带），不覆盖。
    # 仅当 .h 缺失（例如从零 clone）时才生成，避免 tars2cpp 新版覆盖已 patch 的有效头文件。
    docker exec "$TARS_FW_CTN" sh -c '
        cd /tmp/tarsgw/src
        if [ ! -f Verify.h ] || [ ! -f FlowControl.h ]; then
            echo "缺失 .h，tars2cpp 生成..."
            /usr/local/tars/cpp/tools/tars2cpp Verify.tars
            /usr/local/tars/cpp/tools/tars2cpp FlowControl.tars
        else
            echo "源码已含 .h，跳过生成"
        fi
    '

    # 编译
    echo "  cmake + make GatewayServer..."
    docker exec "$TARS_FW_CTN" sh -c '
        cd /tmp/tarsgw
        rm -rf build && mkdir -p build && cd build
        cmake .. -DCMAKE_BUILD_TYPE=Release 2>&1 | tail -5
        make GatewayServer -j$(nproc) 2>&1 | tail -10
        make GatewayServer-tar 2>&1 | tail -5
    '

    # 复制产物
    docker cp "$TARS_FW_CTN:/tmp/tarsgw/build/GatewayServer.tgz" "$GW_BUILD_OUT/GatewayServer.tgz" 2>/dev/null || \
    docker cp "$TARS_FW_CTN:/tmp/tarsgw/build/bin/GatewayServer" "$GW_BUILD_OUT/GatewayServer.tgz" 2>/dev/null || true

    if [ ! -f "$GW_BUILD_OUT/GatewayServer.tgz" ]; then
        err "GatewayServer.tgz 未生成，检查编译日志"
        exit 1
    fi
    ok "编译成功: $(ls -lh "$GW_BUILD_OUT/GatewayServer.tgz" | awk '{print $5}')"

    # 注入 conf 到 tgz（自包含发布包）——GatewayServer 从 bin/ 读 conf，
    # 发布时 tarsnode 会解包 tgz 覆盖 bin/，因此 conf 必须随包发布。
    _inject_conf_into_tgz "$GW_BUILD_OUT/GatewayServer.tgz"

    # release 物料归集（conf/sql 模板，供人工核对与 web 模式用）
    # 官方 conf 模板在 conf/ 目录（注意官方文件名拼写为 GatwayServer.conf）
    mkdir -p "$GW_BUILD_OUT/release"
    cp "$GW_SRC_DIR/conf/GatwayServer.conf"    "$GW_BUILD_OUT/release/GatewayServer.conf" 2>/dev/null || \
       cp "$GW_SRC_DIR/conf/config.conf"       "$GW_BUILD_OUT/release/GatewayServer.conf" 2>/dev/null || \
       warn "未找到 conf 模板（release/GatewayServer.conf 缺，tgz 内已有注入版）"
    cp "$GW_SRC_DIR/conf/httpheader.conf"      "$GW_BUILD_OUT/release/httpheader.conf" 2>/dev/null || \
       warn "未找到 httpheader.conf 模板"
    cp "$GW_SRC_DIR/install/db_base.sql"       "$GW_BUILD_OUT/release/db_base.sql" 2>/dev/null || \
       warn "未找到 db_base.sql"
    ok "release 物料已放入 $GW_BUILD_OUT/release/（含注入版 conf 的 tgz）"
}

# 把 GatewayServer.conf + httpheader.conf 注入 tgz（生成指向 $DB 的 conf）
_inject_conf_into_tgz() {
    local tgz="$1"
    local tmpd; tmpd="$(mktemp -d)"
    tar xzf "$tgz" -C "$tmpd"
    local pkgdir; pkgdir="$(ls "$tmpd")"   # 顶层目录 GatewayServer/

    # GatewayServer.conf：db 段指向环境变量里的 DB
    cat > "$tmpd/$pkgdir/GatewayServer.conf" << WCEOF
<main>
    filterheaders = X-GUID|X-XUA|Host
    auto_proxy=1
    flow_report_obj=Base.GatewayServer.FlowControlObj
    <base>
        rspsize=5242880
        tup_host=
        tup_path=/tup
        json_path=/json
        monitor_url=/monitor/monitor.html
    </base>
    <http_retcode>
        inactive=2|6
        timeout=1|3
    </http_retcode>
    <http_router>
    </http_router>
    <proxy>
    </proxy>
    <db>
        charset=utf8
        dbhost =$DB_HOST
        dbname =db_base
        dbpass =$DB_PASS
        dbport =$DB_PORT
        dbuser =$DB_USER
    </db>
</main>
WCEOF

    cat > "$tmpd/$pkgdir/httpheader.conf" << HHEOF
<httprsp_headers>
    <protocol_map>
        tars-tars=application/x-tar
        tars-tup=application/x-tup
        tars-json=application/json
    </protocol_map>
</httprsp_headers>
HHEOF

    tar czf "$tgz" -C "$tmpd" "$pkgdir"
    rm -rf "$tmpd"
    ok "已注入 conf → tgz (dbhost=$DB_HOST, db_base)"
}

# ── 模式 2: 部署到平台（Base.GatewayServer）──
do_deploy() {
    step "[2/4] 部署 Base.GatewayServer (tarsnode 托管)"

    PKG="$GW_BUILD_OUT/GatewayServer.tgz"
    if [ ! -f "$PKG" ]; then
        err "找不到 $PKG，先跑 --build"
        exit 1
    fi

    # 创建 Base 应用（如不存在）
    echo "  创建 Base 应用..."
    docker exec "$TARS_FW_CTN" curl -s -X POST \
        "http://127.0.0.1:3000/pages/server/api/add_application?ticket=$TOKEN" \
        -H "Content-Type: application/json" \
        -d '{"f_name": "Base"}' || true

    # 平台部署 Base.GatewayServer
    echo "  平台部署 Base.GatewayServer (node=$NODE_IP)..."
    DEPLOY_RSP=$(docker exec "$TARS_FW_CTN" curl -s -X POST \
        "http://127.0.0.1:3000/pages/server/api/deploy_server?ticket=$TOKEN" \
        -H "Content-Type: application/json" \
        -d "{
            \"application\": \"Base\",
            \"server_name\": \"GatewayServer\",
            \"node_name\": \"$NODE_IP\",
            \"server_type\": \"tars_cpp\",
            \"template_name\": \"tars.cpp.default\",
            \"setting_state\": \"active\",
            \"enable_set\": false,
            \"set_name\": \"\",
            \"set_area\": \"\",
            \"set_group\": \"\",
            \"adapters\": [
                {
                    \"obj_name\": \"ProxyObj\",
                    \"bind_ip\": \"$NODE_IP\",
                    \"port\": \"8200\",
                    \"port_type\": \"tcp\",
                    \"protocol\": \"not_tars\",
                    \"thread_num\": 5,
                    \"max_connections\": 100000,
                    \"queuecap\": 50000,
                    \"queuetimeout\": 20000
                },
                {
                    \"obj_name\": \"FlowControlObj\",
                    \"bind_ip\": \"$NODE_IP\",
                    \"port\": \"18212\",
                    \"port_type\": \"tcp\",
                    \"protocol\": \"tars\",
                    \"thread_num\": 1,
                    \"max_connections\": 100000,
                    \"queuecap\": 50000,
                    \"queuetimeout\": 20000
                }
            ]
        }")
    echo "  部署响应: $(echo "$DEPLOY_RSP" | head -c 200)"

    # 生成 GatewayServer.conf（指向 db_base）
    echo "  生成 GatewayServer.conf..."
    CFG=$(cat <<EOF
<main>
    filterheaders = X-GUID|X-XUA|Host
    auto_proxy=1
    flow_report_obj=Base.GatewayServer.FlowControlObj
    <base>
        rspsize=5242880
        tup_host=
        tup_path=/tup
        json_path=/json
        monitor_url=/monitor/monitor.html
    </base>
    <http_retcode>
        inactive=2|6
        timeout=1|3
    </http_retcode>
    <http_router>
    </http_router>
    <proxy>
    </proxy>
    <db>
        charset=utf8
        dbhost =$DB_HOST
        dbname =db_base
        dbpass =$DB_PASS
        dbport =$DB_PORT
        dbuser =$DB_USER
    </db>
</main>
EOF
)
    python3 -c "
import json, subprocess, sys
content = '''$CFG'''
payload = {
    'force': 'true',
    'application': 'Base',
    'server_name': 'GatewayServer',
    'filename': 'GatewayServer.conf',
    'level': 5,
    'set_area': '',
    'set_group': '',
    'set_name': '',
    'config': content
}
with open('/tmp/gw_cfg_payload.json', 'w') as f:
    json.dump(payload, f)
print(json.dumps(payload))
" > /tmp/gw_cfg.json
    docker cp /tmp/gw_cfg.json "$TARS_FW_CTN:/tmp/gw_cfg.json"
    docker exec "$TARS_FW_CTN" curl -s -X POST \
        "http://127.0.0.1:3000/pages/server/api/add_config_file?ticket=$TOKEN" \
        -H "Content-Type: application/json" -d @/tmp/gw_cfg.json

    # 下发 httpheader.conf
    cat << 'EOF' > /tmp/gw_hh.json
{"force":"true","application":"Base","server_name":"GatewayServer","filename":"httpheader.conf","level":5,"set_area":"","set_group":"","set_name":"","config":"<httprsp_headers><protocol_map><tars-tars>application/x-tar</tars-tars><tars-tup>application/x-tup</tars-tup><tars-json>application/json</tars-json></protocol_map></httprsp_headers>"}
EOF
    docker cp /tmp/gw_hh.json "$TARS_FW_CTN:/tmp/gw_hh.json"
    docker exec "$TARS_FW_CTN" curl -s -X POST \
        "http://127.0.0.1:3000/pages/server/api/add_config_file?ticket=$TOKEN" \
        -H "Content-Type: application/json" -d @/tmp/gw_hh.json

    # 上传包
    echo "  上传 GatewayServer.tgz..."
    docker exec "$TARS_FW_CTN" rm -f /tmp/GatewayServer.tgz 2>/dev/null || true
    docker cp "$PKG" "$TARS_FW_CTN:/tmp/GatewayServer.tgz"
    UP_RSP=$(docker exec "$TARS_FW_CTN" curl -s -X POST \
        "http://127.0.0.1:3000/pages/server/api/upload_patch_package?ticket=$TOKEN" \
        -F "application=Base" \
        -F "module_name=GatewayServer" \
        -F "comment=TarsGateway C++ GatewayServer" \
        -F "suse=@/tmp/GatewayServer.tgz;filename=GatewayServer.tgz")
    PATCH_ID=$(echo "$UP_RSP" | python3 -c "import json,sys; print(json.load(sys.stdin).get('data',{}).get('id',''))" 2>/dev/null || echo "")
    echo "  patch_id=$PATCH_ID"

    # 发布 + 启动
    echo "  发布 (patch_tars)..."
    GW_SID=$(sql "SELECT id FROM t_server_conf WHERE application='Base' AND server_name='GatewayServer'")
    TASK_NO=$(docker exec "$TARS_FW_CTN" curl -s -X POST \
        "http://127.0.0.1:3000/pages/server/api/add_task?ticket=$TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"serial\":true,\"items\":[{\"server_id\":\"$GW_SID\",\"command\":\"patch_tars\",\"parameters\":{\"patch_id\":$PATCH_ID}}]}" | \
        python3 -c "import json,sys; print(json.load(sys.stdin).get('data',''))")
    echo "  task_no=$TASK_NO"
    sleep 15

    echo "  启动 GatewayServer..."
    docker exec "$TARS_FW_CTN" curl -s -X POST \
        "http://127.0.0.1:3000/pages/server/api/add_task?ticket=$TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"serial\":true,\"items\":[{\"server_id\":\"$GW_SID\",\"command\":\"start\",\"parameters\":{}}]}" > /dev/null
    sleep 10

    # 验证端口
    echo "  验证端口 (8200/18212)..."
    for p in 8200 18212; do
        if docker exec "$TARS_NODE_CTN" ss -tln 2>/dev/null | grep -q ":$p "; then
            ok "  :$p 监听中"
        else
            warn "  :$p 未监听"
        fi
    done
    ok "部署完成"
}

# ── 模式 3: 启动 GatewayWebServer（tars-framework 容器内，动态路由模式）──
# GatewayWeb 跑在 tars-framework 容器里：
#   - 避开宿主机 npm/node 权限沙箱与依赖问题
#   - 容器与 tars-mysql 同网段，直接连 db_base
#   - 容器 node 是 v16，GatewayWeb (koa+sequelize) 兼容性已验证
do_web() {
    step "[3/4] 启动 GatewayWebServer (tars-framework 容器 node :$GW_WEB_PORT)"

    if [ "$MODE" != "web" ]; then
        warn "MODE=$MODE ≠ web，跳过 GatewayWebServer"
        return 0
    fi

    # 同步 web 源码进容器
    echo "  同步 GatewayWeb 源码进 $TARS_FW_CTN..."
    docker exec "$TARS_FW_CTN" mkdir -p /opt/tarsgateway/web
    docker cp "$GW_SRC_DIR/web/." "$TARS_FW_CTN:/opt/tarsgateway/web/"

    # 写入 webConf + config.json（宿主机生成，docker cp 进容器 ——
    # 不用 heredoc 经 docker exec，因为 stdin 不透传进容器会导致文件为空）
    echo "  写入 webConf.js + config.json（db_base → $DB_HOST:$DB_PORT）..."

    # webConf.js：dbConf + localAuth 必须在文件顶层（db/index.js 与 loginMidware 在
    # server.listen 前 require，此刻 webConf.dbConf/localAuth 必须已存在，
    # 否则 dao 层 require 即崩 "Received undefined"、或鉴权 403 no auth。
    # 注意：config.json 仅在 process.env.TARS_CONFIG 被 Object.assign 合并，
    # 本地跑不会加载它 —— 所以这些字段必须写在 webConf.js 里。）
    _WCF="/tmp/gw_webConf.js"
    cat > "$_WCF" << WCF
// Auto-generated by n15-gateway.sh
const cwd = process.cwd();
const path = require('path');
const fs = require('fs-extra');

let conf = {
    webConf: {
        port: $GW_WEB_PORT,
        alter: true,
    },
    dbConf: {
        host: '$DB_HOST',
        database: 'db_base',
        port: '$DB_PORT',
        user: '$DB_USER',
        password: '$DB_PASS',
        charset: 'utf8',
        pool: { max: 10, min: 0, idle: 10000 }
    },
    localAuth: {
        localIp: ["127.0.0.1", "::1", "172.25.0.1", "172.25.0.2", "172.25.0.3", "172.25.0.5"]
    },
    path: "/plugins/base/gateway"
};

module.exports = conf;
WCF
    docker cp "$_WCF" "$TARS_FW_CTN:/opt/tarsgateway/web/src/config/webConf.js"

    _CFG="/tmp/gw_config.json"
    cat > "$_CFG" << CFG
{
    "tars": {
        "application": {
            "server": {
                "app": "Base",
                "server": "TarsGatewayWeb"
            }
        },
        "locator": "tars.tarsregistry.QueryObj@tcp -h 172.25.0.3 -p 17890",
        "nodejs": {"strictMode": false}
    },
    "localAuth": {
        "localIp": ["127.0.0.1", "::1", "172.25.0.1", "172.25.0.2", "172.25.0.3", "172.25.0.5"]
    },
    "dbConf": {
        "host": "$DB_HOST",
        "database": "db_base",
        "port": "$DB_PORT",
        "user": "$DB_USER",
        "password": "$DB_PASS",
        "charset": "utf8",
        "pool": { "max": 10, "min": 0, "idle": 10000 }
    }
}
CFG
    docker cp "$_CFG" "$TARS_FW_CTN:/opt/tarsgateway/web/src/config/config.json"

    # 安装依赖（容器内 npmmirror）
    echo "  安装 npm 依赖（容器内 npmmirror，需 1~2 分钟）..."
    docker exec "$TARS_FW_CTN" sh -c '
        cd /opt/tarsgateway/web
        if [ ! -d node_modules ] || [ -z "$(ls node_modules 2>/dev/null)" ]; then
            npm install --registry=https://registry.npmmirror.com --no-audit --no-fund 2>&1 | tail -10
        else
            echo "node_modules 已存在，跳过"
        fi
    '

    # 杀掉旧进程并启动
    echo "  重启 node src/app.js (port=$GW_WEB_PORT)..."
    docker exec "$TARS_FW_CTN" sh -c '
        ps -ef | grep "node src/app.js" | grep -v grep | awk "{print \$2}" | xargs -r kill 2>/dev/null || true
        sleep 1
        cd /opt/tarsgateway/web
        HTTP_PORT='$GW_WEB_PORT' nohup node src/app.js > /tmp/gateway-web.log 2>&1 &
    '
    sleep 8

    if ! docker exec "$TARS_FW_CTN" sh -c 'netstat -tln 2>/dev/null | grep -q ":$GW_WEB_PORT" || ss -tln 2>/dev/null | grep -q ":$GW_WEB_PORT"'; then
        warn "  容器内端口 $GW_WEB_PORT 未监听，看日志:"
        docker exec "$TARS_FW_CTN" tail -20 /tmp/gateway-web.log
        exit 1
    fi
    ok "  GatewayWebServer 运行中（容器 :$GW_WEB_PORT）"

    # 宿主机访问需要映射端口（若容器没暴露，从宿主机 nginx 反代或走容器 IP 直连）
    echo "  验证 /plugins/base/gateway/api/station_list (容器内)..."
    docker exec "$TARS_FW_CTN" curl -s --max-time 5 "http://127.0.0.1:$GW_WEB_PORT/plugins/base/gateway/api/station_list" | head -c 200
    echo ""
}

# ── 验证 ──
do_check() {
    step "[4/4] 验证"

    echo "  GatewayServer 状态:"
    sql "SELECT server_name, server_type, present_state, process_id FROM t_server_conf WHERE application='Base' AND server_name='GatewayServer'" | sed 's/^/    /' || true

    echo "  端口监听 (8200/18212):"
    docker exec "$TARS_NODE_CTN" ss -tln 2>/dev/null | grep -E '8200|18212' | sed 's/^/    /' || warn "  未监听"

    if [ "$MODE" = "web" ]; then
        echo "  GatewayWebServer 端口 (容器内 :$GW_WEB_PORT):"
        docker exec "$TARS_FW_CTN" sh -c 'netstat -tln 2>/dev/null | grep ":$GW_WEB_PORT" || ss -tln 2>/dev/null | grep ":$GW_WEB_PORT"' | sed 's/^/    /' || warn "  未监听"
    fi
}

# ── 主流程 ──
case "$STAGE" in
    --build)  do_build ;;
    --deploy) do_deploy ;;
    --web)    do_web ;;
    --check)  do_check ;;
    all)
        do_build
        do_deploy
        do_web
        do_check
        ;;
    *) err "未知 stage: $STAGE"; exit 1 ;;
esac

echo
echo "══════════════════════════════════════════════════════════════════"
echo "✅ n15-gateway 完成"
echo "══════════════════════════════════════════════════════════════════"
