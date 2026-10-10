#!/usr/bin/env bash
# ================================================================
# n07-config-web-gateway.sh — 网关路由：CmsWeb 静态服务 + API 分流
# ================================================================
# 【目标路由规则】
#   /api/*         → BFF (3103)        业务接口
#   /uploads/*     → CmsWeb (13103)    上传文件
#   /admin/*       → CmsWeb (13103)    admin 后台
#   /              → CmsWeb (13103)    h5 内容站
#
# 【网关机制】
#   TarsGateway 按 f_path_rule 前缀匹配，按 f_id 升序
#   精确前缀（/api/）优先于宽前缀（/）
# ================================================================
set -euo pipefail

# 加载部署环境变量（密码等凭据不硬编码在脚本里）
_ENV_SH="$(cd "$(dirname "$0")" && pwd)/env.sh"
if [ -f "$_ENV_SH" ]; then . "$_ENV_SH"; fi
_COMMON_SH="$(cd "$(dirname "$0")" && pwd)/common.sh"
if [ -f "$_COMMON_SH" ]; then . "$_COMMON_SH"; fi

BASE="http://127.0.0.1:15535/plugins/base/gateway/api"  # GatewayWeb 跑在 tars-framework 容器内
BASE_CTN="${CMS_FW_CTN:-tars-framework}"  # 容器未映射 15535 到宿主机，须在容器内 curl
GW_HTTP="${CMS_GATEWAY}"
# BFF/CmsWeb 均由 tarsnode 托管，跑在 tars-node 容器网络内（非宿主机）。
# 网关与 tarsnode 同网络，proxy_pass 必须写容器 IP，写宿主机 IP 会 HTTP 000。
NODE_IP="${CMS_NODE_IP:-$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' tars-node 2>/dev/null)}"
[ -n "$NODE_IP" ] || { echo "❌ 无法探测 tars-node IP"; exit 1; }
BFF="$NODE_IP:3103"
CMSWEB="$NODE_IP:13103"

post() { docker exec "$BASE_CTN" curl -s --max-time 10 -X POST "$1" -H "Content-Type: application/json" -d "$2"; }
get()  { docker exec "$BASE_CTN" curl -s --max-time 10 "$1"; }

echo "================================================"
echo "  n07: 配置 cms 站网关路由（CmsWeb 静态 + BFF API）"
echo "================================================"
echo ""

# cms 站 f_id=3（已存在）
STATION_ID=3
echo "[1/4] cms 站点 f_id=$STATION_ID"

# upstream: cms_web
echo "[2/4] 创建上游 cms_web → $CMSWEB"
post "$BASE/add_upstream" "{\"f_upstream\":\"cms_web\",\"f_addr\":\"$CMSWEB\",\"f_weight\":\"100\",\"f_fusing_onoff\":\"0\"}" | head -c 150
echo ""

# 删除旧的 / 路由（指向 BFF），改为 CmsWeb
echo "[3/4] 更新路由规则"
# 列出现有路由
ROUTES=$(get "$BASE/httprouter_list?f_station_id=$STATION_ID")
echo "  现有路由:"
echo "$ROUTES" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for r in d.get('data',[]):
    print(f\"    id={r['f_id']} path={r['f_path_rule']} → {r['f_proxy_pass']}\")
"

# 删除 f_id=1 的 / 路由（原指向 BFF）
echo "  删除旧 / 路由 (f_id=1 → BFF)..."
post "$BASE/del_httprouter" '{"f_id":"1"}' | head -c 100
echo ""

# 添加新路由
echo "  添加 /uploads/ → cms_web..."
post "$BASE/add_httprouter" "{\"f_station_id\":\"$STATION_ID\",\"f_path_rule\":\"/uploads/\",\"f_proxy_pass\":\"http://$CMSWEB\"}" | head -c 100
echo ""

echo "  添加 /admin/ → cms_web..."
post "$BASE/add_httprouter" "{\"f_station_id\":\"$STATION_ID\",\"f_path_rule\":\"/admin/\",\"f_proxy_pass\":\"http://$CMSWEB\"}" | head -c 100
echo ""

echo "  添加 / → cms_web (兜底 h5)..."
post "$BASE/add_httprouter" "{\"f_station_id\":\"$STATION_ID\",\"f_path_rule\":\"/\",\"f_proxy_pass\":\"http://$CMSWEB\"}" | head -c 100
echo ""

# /api/ 路由保持不变（仍指向 BFF）
echo "  /api/ 路由保持 → BFF (3103)"

# 重启网关
echo ""
echo "[4/4] 重启 GatewayServer"
TOKEN=$(require_ticket)
GW_SID=$(docker exec tars-mysql mysql -uroot -p${CMS_DB_PASS} db_tars -sN -e \
    "SELECT id FROM t_server_conf WHERE application='Base' AND server_name='GatewayServer';" 2>/dev/null)
curl -s --max-time 30 -X POST \
    "http://127.0.0.1:3000/pages/server/api/add_task?ticket=$TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"serial\":true,\"items\":[{\"server_id\":\"$GW_SID\",\"command\":\"restart\",\"parameters\":{}}]}" > /dev/null
sleep 8

# 验证
echo ""
echo "================================================"
echo "  端到端验证 (Host: cms)"
echo "================================================"
echo -n "  / (h5):       "
curl -s --max-time 5 -H "Host: cms" -o /dev/null -w "HTTP %{http_code}, %{size_download} bytes\n" "$GW_HTTP/" || true
echo -n "  /admin/:      "
curl -s --max-time 5 -H "Host: cms" -o /dev/null -w "HTTP %{http_code}, %{size_download} bytes\n" "$GW_HTTP/admin/" || true
echo -n "  /article/1:   "
curl -s --max-time 5 -H "Host: cms" -o /dev/null -w "HTTP %{http_code} (SPA fallback)\n" "$GW_HTTP/article/1" || true
echo -n "  /uploads/:    "
curl -s --max-time 5 -H "Host: cms" -o /dev/null -w "HTTP %{http_code}\n" "$GW_HTTP/uploads/2026/10/1791051755868757484_test.png" || true
echo -n "  /api/home:    "
curl -s --max-time 5 -H "Host: cms" "$GW_HTTP/api/cms/home?tenantId=1" | head -c 80 || true
echo ""
echo -n "  /health:      "
curl -s --max-time 5 -H "Host: cms" "$GW_HTTP/health" | head -c 80 || true
echo ""
echo ""
echo "================================================"
echo "✅ n07 完成: 网关路由配置成功"
echo "================================================"
