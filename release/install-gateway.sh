#!/usr/bin/env bash
# ================================================================
# install-gateway.sh — 独立部署 TarsGateway（从 release 包）
# ================================================================
# 【功能】
#   1. 上传 release/gateway/GatewayServer.tgz 到 TarsWeb
#   2. 注册 Base.GatewayServer（ProxyObj 8200 + FlowControlObj 18212）
#   3. 发布并启动网关
#   4. 起 GatewayWebServer（容器内，15535，动态路由管理 API）
#   5. 验证端口与 API
#
# 【前提】 tars-mysql / tars-framework / tars-node 3 容器已运行
# 【用法】 bash install-gateway.sh          # 全量
#         bash install-gateway.sh --no-web # 不起 GatewayWeb（static 模式）
# ================================================================
set -euo pipefail

# 凭据从环境读取（不硬编码）
: "${CMS_DB_PASS:?请设置 CMS_DB_PASS（db_base root 密码）}"
DB_HOST="${CMS_DB_HOST:-172.25.0.2}"
DB_PORT="${CMS_DB_PORT:-3306}"
DB_USER="${CMS_DB_USER:-root}"
DB_PASS="$CMS_DB_PASS"
NODE_IP="${CMS_NODE_IP:-172.25.0.5}"
TARS_FW_CTN="${CMS_FW_CTN:-tars-framework}"
TARS_NODE_CTN="${CMS_NODE_CTN:-tars-node}"
GW_WEB_PORT="${CMS_GW_WEB_PORT:-15535}"
MODE="web"
[ "${1:-}" = "--no-web" ] && MODE="static"

REL_DIR="$(cd "$(dirname "$0")" && pwd)"
TGZ="$REL_DIR/gateway/GatewayServer.tgz"
[ -f "$TGZ" ] || { echo "❌ 缺少 $TGZ（见 README 说明如何生成）"; exit 1; }

C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_END=$'\033[0m'
ok()   { echo "${C_GREEN}✔ $1${C_END}"; }
warn() { echo "${C_YELLOW}⚠ $1${C_END}"; }
err()  { echo "${C_RED}✘ $1${C_END}" >&2; }

echo "=== install-gateway（mode=$MODE）==="
echo "  tgz: $TGZ"
echo "  db:  $DB_HOST:$DB_PORT/db_base"
echo "  node: $NODE_IP:8200/18212"
echo ""

# 1) 取 ticket
echo "[1/5] 获取 TarsWeb ticket..."
TOKEN=$(docker exec "$TARS_FW_CTN" curl -s --max-time 8 -X POST \
  "http://127.0.0.1:3000/pages/server/api/login" \
  -H 'Content-Type: application/json' \
  -d "{\"uid\":\"${TARS_USER:-admin}\",\"password\":\"${TARS_PASS:-admin123}\"}" \
  | python3 -c "import json,sys;print(json.load(sys.stdin).get('data',{}).get('ticket',''))" 2>/dev/null || true)
[ -n "$TOKEN" ] || { err "ticket 获取失败（检查 TarsWeb 与账号密码）"; exit 1; }
ok "ticket 已获取"

# 2) 注册 Base.GatewayServer
echo "[2/5] 注册 Base.GatewayServer..."
docker exec "$TARS_FW_CTN" curl -s -X POST \
  "http://127.0.0.1:3000/pages/server/api/add_application?ticket=$TOKEN" \
  -H "Content-Type: application/json" -d '{"f_name":"Base"}' >/dev/null 2>&1 || true
DEPLOY_RSP=$(docker exec "$TARS_FW_CTN" curl -s -X POST \
  "http://127.0.0.1:3000/pages/server/api/deploy_server?ticket=$TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"application\":\"Base\",\"server_name\":\"GatewayServer\",
    \"node_name\":\"$NODE_IP\",\"server_type\":\"tars_cpp\",
    \"template_name\":\"tars.cpp.default\",\"setting_state\":\"active\",
    \"enable_set\":false,\"set_name\":\"\",\"set_area\":\"\",\"set_group\":\"\",
    \"adapters\":[
      {\"obj_name\":\"ProxyObj\",\"bind_ip\":\"$NODE_IP\",\"port\":\"8200\",
       \"port_type\":\"tcp\",\"protocol\":\"not_tars\",\"thread_num\":5,
       \"max_connections\":100000,\"queuecap\":50000,\"queuetimeout\":20000},
      {\"obj_name\":\"FlowControlObj\",\"bind_ip\":\"$NODE_IP\",\"port\":\"18212\",
       \"port_type\":\"tcp\",\"protocol\":\"tars\",\"thread_num\":1,
       \"max_connections\":100000,\"queuecap\":50000,\"queuetimeout\":20000}
    ]}")
echo "  注册响应: $(echo "$DEPLOY_RSP" | head -c 160)"

# 3) 上传 + 发布
echo "[3/5] 上传 tgz + patch_tars..."
docker exec "$TARS_FW_CTN" rm -f /tmp/GatewayServer.tgz 2>/dev/null || true
docker cp "$TGZ" "$TARS_FW_CTN:/tmp/GatewayServer.tgz"
UP_RSP=$(docker exec "$TARS_FW_CTN" curl -s -X POST \
  "http://127.0.0.1:3000/pages/server/api/upload_patch_package?ticket=$TOKEN" \
  -F "application=Base" -F "module_name=GatewayServer" \
  -F "comment=TarsGateway v1.3.3" \
  -F "suse=@/tmp/GatewayServer.tgz;filename=GatewayServer.tgz")
PATCH_ID=$(echo "$UP_RSP" | python3 -c "import json,sys;print(json.load(sys.stdin).get('data',{}).get('id',''))" 2>/dev/null || echo "")
[ -n "$PATCH_ID" ] || { err "上传失败: $(echo "$UP_RSP" | head -c 200)"; exit 1; }
ok "patch_id=$PATCH_ID"
GW_SID=$(docker exec tars-mysql mysql -uroot -p"$DB_PASS" db_tars -sN -e \
  "SELECT id FROM t_server_conf WHERE application='Base' AND server_name='GatewayServer'" 2>/dev/null || echo "")
docker exec "$TARS_FW_CTN" curl -s -X POST \
  "http://127.0.0.1:3000/pages/server/api/add_task?ticket=$TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"serial\":true,\"items\":[{\"server_id\":\"$GW_SID\",\"command\":\"patch_tars\",\"parameters\":{\"patch_id\":$PATCH_ID}}]}" >/dev/null
sleep 12
ok "patch_tars 已下发"

# 4) 启动
echo "[4/5] 启动 GatewayServer..."
docker exec "$TARS_FW_CTN" curl -s -X POST \
  "http://127.0.0.1:3000/pages/server/api/add_task?ticket=$TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"serial\":true,\"items\":[{\"server_id\":\"$GW_SID\",\"command\":\"start\",\"parameters\":{}}]}" >/dev/null
sleep 8

# 验证端口
for p in 8200 18212; do
  docker exec "$TARS_NODE_CTN" sh -c "netstat -tln 2>/dev/null | grep -q ':$p '" \
    && ok ":$p 监听中" || warn ":$p 未监听"
done

# 5) GatewayWeb（web 模式）
if [ "$MODE" = "web" ]; then
  echo "[5/5] 起 GatewayWebServer（容器 :$GW_WEB_PORT）..."
  WEB_DIR="$REL_DIR/web"
  [ -d "$WEB_DIR" ] || { err "缺少 $WEB_DIR"; exit 1; }
  docker exec "$TARS_FW_CTN" mkdir -p /opt/tarsgateway/web
  docker cp "$WEB_DIR/." "$TARS_FW_CTN:/opt/tarsgateway/web/"

  # webConf.js：dbConf + localAuth 必须在文件顶层（db/index.js 与 loginMidware
  # 在 server.listen 前 require，此刻 webConf.dbConf/localAuth 必须已存在，
  # 否则 dao 层 require 即崩 "Received undefined"、或鉴权 403 no auth。
  # 注意：config.json 仅在 process.env.TARS_CONFIG 被 Object.assign 合并，
  # 本地跑不会加载它 —— 所以这些字段必须写在 webConf.js 里。）
  _WCF="/tmp/gw_webConf.js"
  cat > "$_WCF" << WCF
let conf = {
    webConf: { port: $GW_WEB_PORT, alter: true },
    dbConf: {
        host: '$DB_HOST', database: 'db_base', port: '$DB_PORT',
        user: '$DB_USER', password: '$DB_PASS', charset: 'utf8',
        pool: { max: 10, min: 0, idle: 10000 }
    },
    localAuth: {
        localIp: ["127.0.0.1","::1","172.25.0.1","172.25.0.2","172.25.0.3","172.25.0.5"]
    },
    path: "/plugins/base/gateway"
};
module.exports = conf;
WCF
  docker cp "$_WCF" "$TARS_FW_CTN:/opt/tarsgateway/web/src/config/webConf.js"

  _CFG="/tmp/gw_config.json"
  cat > "$_CFG" << CFG
{
  "tars": { "application": { "server": { "app": "Base", "server": "TarsGatewayWeb" } },
            "locator": "tars.tarsregistry.QueryObj@tcp -h 172.25.0.3 -p 17890",
            "nodejs": { "strictMode": false } }
}
CFG
  docker cp "$_CFG" "$TARS_FW_CTN:/opt/tarsgateway/web/src/config/config.json"

  docker exec "$TARS_FW_CTN" sh -c 'cd /opt/tarsgateway/web && [ -d node_modules ] || npm install --registry=https://registry.npmmirror.com --no-audit --no-fund 2>&1 | tail -3'
  docker exec "$TARS_FW_CTN" sh -c 'ps -ef|grep "node src/app.js"|grep -v grep|awk "{print \\$2}"|xargs -r kill 2>/dev/null; sleep 1; cd /opt/tarsgateway/web && HTTP_PORT='$GW_WEB_PORT' nohup node src/app.js > /tmp/gateway-web.log 2>&1 &'
  sleep 8
  docker exec "$TARS_FW_CTN" sh -c "netstat -tln 2>/dev/null | grep -q ':$GW_WEB_PORT '" \
    && ok "GatewayWeb 运行中（容器 :$GW_WEB_PORT）" || { err "GatewayWeb 未起，看日志"; docker exec "$TARS_FW_CTN" tail -15 /tmp/gateway-web.log; exit 1; }
else
  echo "[5/5] 跳过 GatewayWeb（--no-web）"
fi

echo ""
echo "================================================"
echo "✅ TarsGateway 安装完成"
echo "   GatewayServer: $NODE_IP:8200 (host 头路由)"
[ "$MODE" = "web" ] && echo "   GatewayWeb:   容器 $TARS_FW_CTN:$GW_WEB_PORT (路由管理 API)"
echo "================================================"
