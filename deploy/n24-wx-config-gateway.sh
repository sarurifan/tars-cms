#!/usr/bin/env bash
# ================================================================
# n24-wx-config-gateway.sh — 配置 TarsGateway 网关路由 (/api/wx/*)
# ================================================================
# 链路:
#   用户/小程序/公众号 → TarsGateway(8200) → /api/wx/* → wx.WxBff(3203)
#
# 踩坑规避（实测得出）:
#   TarsGateway 路由按 f_id 升序进行前缀匹配。
#   现有 /api/ 的 f_id=3；如果 /api/wx/ 的 f_id > 3，请求会被 /api/ 先命中
#   并转发给 cms.CmsBff(3103)，导致 404 page not found！
#   因此本脚本强制确保 /api/wx/ 的 f_id < /api/ 的 f_id（设为 2）。
# ================================================================
set -euo pipefail

_ENV_SH="$(cd "$(dirname "$0")" && pwd)/env.sh"
if [ -f "$_ENV_SH" ]; then . "$_ENV_SH"; fi
_COMMON_SH="$(cd "$(dirname "$0")" && pwd)/common.sh"
if [ -f "$_COMMON_SH" ]; then . "$_COMMON_SH"; fi

NODE_IP="$CMS_NODE_IP"
MYSQL="docker exec -i $CMS_MYSQL_CTN mysql -uroot -p${CMS_DB_PASS} db_base"

echo "=== n24-wx-config-gateway.sh: 注册网关路由 ==="

echo "[1/3] 注册/更新路由: /api/wx/ -> http://$NODE_IP:3203 (f_id=2)"
# 幂等操作：若存在先删后插（固定 f_id=2 保障匹配优先级高于 /api/）
$MYSQL <<SQL
DELETE FROM t_http_router WHERE f_path_rule = '/api/wx/';
INSERT INTO t_http_router
    (f_id, f_station_id, f_server_name, f_path_rule, f_proxy_pass, f_valid, f_update_person, f_update_time)
VALUES
    (2, '3', '', '/api/wx/', 'http://$NODE_IP:3203', 1, 'admin', NOW());
SQL

echo ""
echo "[2/3] 当前生效路由表:"
docker exec "$CMS_MYSQL_CTN" mysql -uroot -p"${CMS_DB_PASS}" db_base -e \
    "SELECT f_id, f_path_rule, f_proxy_pass FROM t_http_router WHERE f_station_id='3' ORDER BY f_id;" 2>/dev/null

echo ""
echo "[3/3] 重启 GatewayServer 加载新路由..."
TOKEN=$(require_ticket)
GW_SID=$(docker exec "$CMS_MYSQL_CTN" mysql -uroot -p"${CMS_DB_PASS}" db_tars -sN -e \
    "SELECT id FROM t_server_conf WHERE application='Base' AND server_name='GatewayServer';" 2>/dev/null)
docker exec tars-framework curl -s -X POST \
    "http://127.0.0.1:3000/pages/server/api/add_task?ticket=$TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"serial\":true,\"items\":[{\"server_id\":\"$GW_SID\",\"command\":\"restart\"}]}" >/dev/null

echo "等待 3 秒网关生效..."
sleep 3
ok "网关路由注册完成 (/api/wx/* 优先级高于 /api/)"
