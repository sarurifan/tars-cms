#!/usr/bin/env bash
# ================================================================
# n10-fix-routes.sh — cms 站网关路由诊断与幂等修复
# ================================================================
# 【用途】
#   服务从宿主机迁移到 tarsnode 托管后，t_http_router 里可能残留
#   旧宿主机 IP，导致部分路径 HTTP 000。本脚本诊断 + 一键修正。
#
# 【典型症状】
#   /api/*   → 000   （BFF 路由残留宿主机 IP）
#   /admin/  → 200   （本就指容器 IP，未受影响 → 迷惑性强）
#
# 【目标路由（全部指向 tars-node 容器 IP）】
#   /              → CmsWeb   (:13103)  h5 内容站
#   /admin/        → CmsWeb   (:13103)  后台
#   /uploads/      → CmsWeb   (:13103)  上传文件
#   /api/          → BFF      (:3103)   业务接口
#
# 【用法】
#   bash deploy/n10-fix-routes.sh          # 诊断 + 修复
#   bash deploy/n10-fix-routes.sh --check  # 只诊断，不改动
# ================================================================
set -euo pipefail

# 加载部署环境变量（密码等凭据不硬编码在脚本里）
_ENV_SH="$(cd "$(dirname "$0")" && pwd)/env.sh"
if [ -f "$_ENV_SH" ]; then . "$_ENV_SH"; fi
_COMMON_SH="$(cd "$(dirname "$0")" && pwd)/common.sh"
if [ -f "$_COMMON_SH" ]; then . "$_COMMON_SH"; fi

CHECK_ONLY=0
[[ "${1:-}" == "--check" ]] && CHECK_ONLY=1

STATION_ID="${CMS_STATION_ID:-3}"
MYSQL_PASS="${CMS_DB_PASS}"
NODE_IP="${CMS_NODE_IP:-$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' tars-node 2>/dev/null)}"
[ -n "$NODE_IP" ] || { echo "❌ 无法探测 tars-node IP（可用 CMS_NODE_IP 覆盖）"; exit 1; }

sql()  { docker exec tars-mysql mysql -uroot -p"$MYSQL_PASS" db_base -sN -e "$1" 2>/dev/null; }
sqlq() { docker exec tars-mysql mysql -uroot -p"$MYSQL_PASS" db_base -e "$1" 2>/dev/null; }

echo "================================================"
echo "  n10: cms 站网关路由诊断$([ "$CHECK_ONLY" = 1 ] && echo '（只读）' || echo ' + 修复')"
echo "  目标节点: $NODE_IP  站点: f_station_id=$STATION_ID"
echo "================================================"
echo ""

# ── 1. 期望路由表 ──
declare -A WANT=(
  ["/"]="http://$NODE_IP:13103"
  ["/admin/"]="http://$NODE_IP:13103"
  ["/uploads/"]="http://$NODE_IP:13103"
  ["/api/"]="http://$NODE_IP:3103"
)

echo "[1/4] 当前路由"
CURRENT=$(sqlq "SELECT f_id, f_path_rule, f_proxy_pass FROM t_http_router WHERE f_station_id='$STATION_ID' ORDER BY f_id;")
echo "$CURRENT" | sed 's/^/    /'
echo ""

# ── 2. 逐条比对 ──
echo "[2/4] 比对结果"
NEED_FIX=0
for path in "/" "/admin/" "/uploads/" "/api/"; do
  want="${WANT[$path]}"
  have=$(sql "SELECT f_proxy_pass FROM t_http_router WHERE f_station_id='$STATION_ID' AND f_path_rule='$path' LIMIT 1;")
  if [[ -z "$have" ]]; then
    echo "  ✘ $path  缺失（应为 $want）"
    NEED_FIX=1
  elif [[ "$have" != "$want" ]]; then
    echo "  ✘ $path  当前 $have"
    echo "           应为 $want"
    NEED_FIX=1
  else
    echo "  ✔ $path  $have"
  fi
done
echo ""

if [[ "$NEED_FIX" == 0 ]]; then
  echo "✅ 路由全部正确，无需修复"
else
  if [[ "$CHECK_ONLY" == 1 ]]; then
    echo "⚠ 发现偏差（--check 模式，未改动）"
    exit 1
  fi

  # ── 3. 修复 ──
  echo "[3/4] 执行修复"
  for path in "/" "/admin/" "/uploads/" "/api/"; do
    want="${WANT[$path]}"
    # 用 REPLACE INTO 依赖唯一键；没有则先 UPDATE，影响 0 行再 INSERT
    sql "UPDATE t_http_router SET f_proxy_pass='$want', f_valid=1
         WHERE f_station_id='$STATION_ID' AND f_path_rule='$path';" || true
    cnt=$(sql "SELECT COUNT(*) FROM t_http_router WHERE f_station_id='$STATION_ID' AND f_path_rule='$path';")
    if [[ "$cnt" == "0" ]]; then
      sql "INSERT INTO t_http_router (f_station_id, f_server_name, f_path_rule, f_proxy_pass, f_valid, f_update_person)
           VALUES ('$STATION_ID', '', '$path', '$want', 1, 'n10-fix-routes');"
      echo "  + $path → $want（新增）"
    else
      echo "  ~ $path → $want（更新）"
    fi
  done
  echo ""

  # ── 4. 重启网关 ──
  echo "[4/4] 重启 GatewayServer 加载新路由"
  TOKEN=$(require_ticket)
  GW_SID=$(docker exec tars-mysql mysql -uroot -p"$MYSQL_PASS" db_tars -sN -e \
    "SELECT id FROM t_server_conf WHERE application='Base' AND server_name='GatewayServer';" 2>/dev/null)
  docker exec tars-framework curl -s --max-time 30 -X POST \
    "http://127.0.0.1:3000/pages/server/api/add_task?ticket=$TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"serial\":true,\"items\":[{\"server_id\":\"$GW_SID\",\"command\":\"restart\",\"parameters\":{}}]}" > /dev/null
  sleep 10
  echo ""
fi

# ── 验证 ──
echo "================================================"
echo "  端到端验证 (Host: cms)"
echo "================================================"
GW="${CMS_GATEWAY}"
FAIL=0
for path in "/" "/admin/" "/api/cms/home?tenantId=1"; do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 -H "Host: cms" "$GW$path" || echo 000)
  if [[ "$code" == "200" ]]; then
    echo "  ✔ $path → $code"
  else
    echo "  ✘ $path → $code"
    FAIL=1
  fi
done
echo ""
if [[ "$FAIL" == 0 ]]; then
  echo "✅ n10 完成: 路由正确，全链路 200"
else
  echo "⚠ n10: 仍有路径非 200，检查服务是否存活（n04-verify.sh）"
  exit 1
fi
