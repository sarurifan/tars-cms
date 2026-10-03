#!/usr/bin/env bash
# ================================================================
# n04-verify.sh — tars-cms 全链路验证（前端 → 网关 → BFF → TARS → MySQL）
# ================================================================
# 验证范围:
#   1. 平台状态   cms.CmsServer active + 双 adapter
#   2. 网关连通   TarsGateway(8200) Host: cms 路由生效
#   3. 公开接口   /api/cms/home, categories, articles, articles/:id, config
#   4. 认证接口   /api/auth/register, login, userinfo, logout
#   5. 后台接口   /api/admin/articles, categories, members, media
#
# 用法: bash n04-verify.sh
# ================================================================
set -uo pipefail

GW="http://192.168.1.95:8200"
HOST_HDR="cms"
PASS=0
FAIL=0

mysql_q() {
    docker exec tars-mysql mysql -uroot -ptars@root.2026 db_tars -sN -e "$1" 2>/dev/null
}

assert_contains() {
    local name="$1" resp="$2" expect="$3"
    if echo "$resp" | grep -q "$expect"; then
        echo "  ✅ $name"
        PASS=$((PASS + 1))
    else
        echo "  ❌ $name"
        echo "     期望含: $expect"
        echo "     实际:   $(echo "$resp" | head -c 200)"
        FAIL=$((FAIL + 1))
    fi
}

gw_get()  { curl -s --max-time 8 -H "Host: $HOST_HDR" "$GW$1"; }
gw_post() { curl -s --max-time 8 -X POST -H "Host: $HOST_HDR" -H "Content-Type: application/json" -d "$2" "$GW$1"; }

echo "================================================"
echo "  tars-cms 全链路验证"
echo "  前端 → TarsGateway(8200) → BFF(3103) → cms TARS → MySQL"
echo "================================================"
echo ""

# ---------- 1. 平台状态 ----------
echo "[1/5] 平台服务状态"
STATE=$(mysql_q "SELECT present_state FROM t_server_conf WHERE application='cms' AND server_name='CmsServer';")
if [ "$STATE" = "active" ]; then
    echo "  ✅ cms.CmsServer active"
    PASS=$((PASS + 1))
else
    echo "  ❌ cms.CmsServer 状态: ${STATE:-未注册}"
    FAIL=$((FAIL + 1))
fi

ADAPTERS=$(mysql_q "SELECT COUNT(*) FROM t_adapter_conf WHERE application='cms';")
if [ "${ADAPTERS:-0}" -ge 2 ] 2>/dev/null; then
    echo "  ✅ adapter 数量: $ADAPTERS (ArticleObj + AuthObj)"
    PASS=$((PASS + 1))
else
    echo "  ❌ adapter 数量异常: ${ADAPTERS:-0}"
    FAIL=$((FAIL + 1))
fi
echo ""

# ---------- 2. 网关连通 ----------
echo "[2/5] 网关连通性 (TarsGateway :8200, Host: cms)"
assert_contains "网关可达 + cms 路由生效" "$(gw_get '/api/cms/config?tenantId=1')" '"code":0'
echo ""

# ---------- 3. 公开接口 ----------
echo "[3/5] 公开接口"
assert_contains "GET  /api/cms/home            首页聚合" "$(gw_get '/api/cms/home?tenantId=1')"                    '"banners"'
assert_contains "GET  /api/cms/categories      分类列表" "$(gw_get '/api/cms/categories?tenantId=1')"             '快速开始'
assert_contains "GET  /api/cms/categories/tree 分类树"  "$(gw_get '/api/cms/categories/tree?tenantId=1')"        '"children"'
assert_contains "GET  /api/cms/articles        文章列表" "$(gw_get '/api/cms/articles?tenantId=1&page=1&size=5')" '"total"'
assert_contains "GET  /api/cms/articles/1      文章详情" "$(gw_get '/api/cms/articles/1?tenantId=1')"             '"content"'
assert_contains "GET  /api/cms/config          站点配置" "$(gw_get '/api/cms/config?tenantId=1')"                 '"code":0'
echo ""

# ---------- 4. 认证接口 ----------
echo "[4/5] 认证接口"
RC=$(gw_post '/api/auth/register' "{\"tenantId\":1,\"username\":\"verify$RANDOM\",\"password\":\"vpass12345\",\"email\":\"v@t.com\"}")
assert_contains "POST /api/auth/register      注册"       "$RC" '"token"'

RC=$(gw_post '/api/auth/login' '{"tenantId":1,"username":"admin","password":"admin123"}')
assert_contains "POST /api/auth/login         登录 admin" "$RC" '"role":"admin"'

TOKEN=$(echo "$RC" | python3 -c "import json,sys; print(json.load(sys.stdin).get('data',{}).get('token',''))" 2>/dev/null)
if [ -n "$TOKEN" ]; then
    RC=$(curl -s --max-time 8 -H "Host: $HOST_HDR" -H "Authorization: Bearer $TOKEN" \
         "$GW/api/auth/userinfo?tenantId=1")
    assert_contains "GET  /api/auth/userinfo      用户信息" "$RC" '"username":"admin"'

    RC=$(curl -s --max-time 8 -X POST -H "Host: $HOST_HDR" -H "Authorization: Bearer $TOKEN" \
         "$GW/api/auth/logout?tenantId=1")
    assert_contains "POST /api/auth/logout        登出"     "$RC" '"code":0'
else
    echo "  ⚠️  登录未拿到 token，跳过 userinfo/logout"
    FAIL=$((FAIL + 2))
fi
echo ""

# ---------- 5. 后台接口 ----------
echo "[5/5] 后台管理接口"
assert_contains "GET  /api/admin/articles      后台文章列表" "$(gw_get '/api/admin/articles?tenantId=1&page=1&size=5')" '"total"'
assert_contains "GET  /api/admin/categories    后台分类列表" "$(gw_get '/api/admin/categories?tenantId=1')"            '快速开始'
assert_contains "GET  /api/admin/members       成员列表"     "$(gw_get '/api/admin/members?tenantId=1')"               '"code":0'
assert_contains "GET  /api/admin/media         媒体列表"     "$(gw_get '/api/admin/media?tenantId=1&page=1&size=5')"   '"code":0'
echo ""

# ---------- 汇总 ----------
echo "================================================"
echo "  通过: $PASS    失败: $FAIL"
echo "================================================"
if [ "$FAIL" -eq 0 ]; then
    echo "🎉 全链路验证通过：前端 → 网关 → BFF → TARS → MySQL"
    exit 0
else
    echo "⚠️  有 $FAIL 项失败，请检查上方详情"
    exit 1
fi
