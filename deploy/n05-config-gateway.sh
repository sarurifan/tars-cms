#!/usr/bin/env bash
# ================================================================
# n05-config-gateway.sh — 配置 TarsGateway 把 /api/* 路由到 cms BFF
# ================================================================
# 网关机制: TarsGateway 用 station + upstream + httprouter
#   station = 站点 (Host 头区分)
#   upstream = 上游服务 (BFF 地址)
#   httprouter = 路径规则 (/api/* → BFF)
#
# 【路由规则】
#   Host: cms (或 nerv) + /api/* → http://192.168.1.95:3103
#   这样前端统一访问: http://<网关>:8200/api/cms/home
# ================================================================
set -euo pipefail

BASE="http://127.0.0.1:15535/plugins/base/gateway/api"
GW_HTTP="http://127.0.0.1:8200"
BFF="192.168.1.95:3103"

post() { curl -s -X POST "$1" -H "Content-Type: application/json" -d "$2"; }
get()  { curl -s "$1"; }

echo "=== [1/5] 创建站点 cms ==="
post "$BASE/add_station" '{"f_station_id":"cms","f_name_cn":"tars-cms 站点"}' | head -c 200
echo ""

echo "=== [2/5] 创建上游 cms_bff (指向 $BFF) ==="
post "$BASE/add_upstream" "{\"f_upstream\":\"cms_bff\",\"f_addr\":\"$BFF\",\"f_weight\":\"100\",\"f_fusing_onoff\":\"0\"}" | head -c 200
echo ""

echo "=== [3/5] 获取 cms 站点 f_id ==="
STATION_ID=$(get "$BASE/station_list" | python3 -c "
import json,sys
rows = json.load(sys.stdin).get('data',{}).get('rows',[])
for r in rows:
    if r.get('f_station_id') == 'cms':
        print(r.get('f_id','')); break
")
echo "   cms 站点 f_id = $STATION_ID"

echo ""
echo "=== [4/5] 添加 HTTP 路由 /api/* → cms_bff ==="
post "$BASE/add_httprouter" "{\"f_station_id\":\"$STATION_ID\",\"f_path_rule\":\"/api/\",\"f_proxy_pass\":\"http://$BFF\"}" | head -c 200
echo ""
# 也加一条 / 兜底（首页静态也走 BFF 或直接返回提示）
post "$BASE/add_httprouter" "{\"f_station_id\":\"$STATION_ID\",\"f_path_rule\":\"/\",\"f_proxy_pass\":\"http://$BFF\"}" | head -c 200
echo ""

echo ""
echo "=== [5/5] 重启 GatewayServer 加载新配置 ==="
TOKEN=$(grep "^TOKEN=" /docker/tars/scripts/c03-deploy-chisha.sh | cut -d'"' -f2)
GW_SID=$(docker exec tars-mysql mysql -uroot -ptars@root.2026 db_tars -sN -e \
    "SELECT id FROM t_server_conf WHERE application='Base' AND server_name='GatewayServer';" 2>/dev/null)
docker exec tars-framework curl -s -X POST \
    "http://127.0.0.1:3000/pages/server/api/add_task?ticket=$TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"serial\":true,\"items\":[{\"server_id\":\"$GW_SID\",\"command\":\"restart\",\"parameters\":{}}]}" > /dev/null
sleep 10

echo ""
echo "=== 端到端验证: 经网关访问 cms ==="
echo -n "  GET /api/cms/home (Host: cms) -> "
curl -s --max-time 5 -H "Host: cms" "$GW_HTTP/api/cms/home?tenantId=1" | head -c 150
echo ""
echo -n "  GET /api/cms/articles (Host: cms) -> "
curl -s --max-time 5 -H "Host: cms" "$GW_HTTP/api/cms/articles?tenantId=1&page=1&size=2" | head -c 150
echo ""
echo -n "  POST /api/auth/login (Host: cms) -> "
curl -s --max-time 5 -X POST -H "Host: cms" -H "Content-Type: application/json" \
    -d '{"tenantId":1,"username":"admin","password":"admin123"}' \
    "$GW_HTTP/api/auth/login" | head -c 150
echo ""
echo ""
echo "================================================"
echo "✅ N05 完成: tars-cms 网关路由已配置"
echo "================================================"
