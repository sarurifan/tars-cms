#!/usr/bin/env bash
# ================================================================
# n25-wx-test.sh — 微信节点端到端测试套件
# ================================================================
# 测试范围:
#   1. 健康检查: WxBff /health 和 /health/full (调底层 RPC)
#   2. 公众号验签: /api/wx/verify (sha1 算法严格对比)
#   3. access_token 中控读取: /api/wx/mp/token 与 /api/wx/ma/token
#   4. 小程序 code2session 接口契约
#   5. 数据库落表: wx_account, wx_user, wx_access_token 结构
# ================================================================
set -uo pipefail

_ENV_SH="$(cd "$(dirname "$0")" && pwd)/env.sh"
if [ -f "$_ENV_SH" ]; then . "$_ENV_SH"; fi
_COMMON_SH="$(cd "$(dirname "$0")" && pwd)/common.sh"
if [ -f "$_COMMON_SH" ]; then . "$_COMMON_SH"; fi

GW="${CMS_GATEWAY}"
PASS=0
FAIL=0

ok()   { echo "  ✔ $1"; PASS=$((PASS + 1)); }
err()  { echo "  ✘ $1 (实际: $2)"; FAIL=$((FAIL + 1)); }

assert_contains() {
    local name="$1" resp="$2" expect="$3"
    if echo "$resp" | grep -q "$expect"; then
        ok "$name"
    else
        err "$name" "$(echo "$resp" | head -c 120)"
    fi
}

echo "================================================"
echo "  微信节点 (wx) 全链路测试"
echo "  网关(8200) → wx-bff(3203) → wx.WxServer(13201) → tars_wx"
echo "================================================"

echo ""
echo "━━━ 第一层：服务存活与 RPC 连通 ━━━"
# 1. 直接访问 WxBff 端口
BFF_HC=$(docker exec tars-node curl -s --max-time 5 "http://127.0.0.1:3203/health" 2>/dev/null || echo "000")
assert_contains "WxBff :3203 /health 存活" "$BFF_HC" '"status":"ok"'

# 2. 深度探测 RPC 到 WxServer
BFF_FULL=$(docker exec tars-node curl -s --max-time 5 "http://127.0.0.1:3203/health/full" 2>/dev/null || echo "000")
assert_contains "WxBff -> WxServer TARS RPC 连通" "$BFF_FULL" '"rpc":"up"'

# 3. 平台 DB 状态
STATE=$(docker exec tars-mysql mysql -uroot -p${CMS_DB_PASS} db_tars -sN -e \
    "SELECT present_state FROM t_server_conf WHERE application='wx' AND server_name='WxServer';" 2>/dev/null || echo "")
if [ "$STATE" = "active" ]; then
    ok "wx.WxServer 平台状态 active"
else
    err "wx.WxServer 状态" "$STATE"
fi

echo ""
echo "━━━ 第二层：网关路由透传 (/api/wx/*) ━━━"
GW_RESP=$(curl -s --max-time 5 "$GW/api/wx/verify?token=test_token_123&timestamp=1700000000&nonce=999999&signature=d9e3c0b0a0123" 2>/dev/null || echo "000")
assert_contains "网关 8200 转发 /api/wx/verify" "$GW_RESP" '"code":0'

echo ""
echo "━━━ 第三层：微信公众号能力 ━━━"
# 1. 签名校验真实算法验证
# 计算已知正确签名: sort(["mytoken","123","456"]) -> "123456mytoken" -> sha1
EXPECT_SIG=$(python3 -c "import hashlib; print(hashlib.sha1('123456mytoken'.encode()).hexdigest())")
SIG_RESP=$(curl -s --max-time 5 "$GW/api/wx/verify?token=mytoken&timestamp=123&nonce=456&signature=$EXPECT_SIG")
assert_contains "sha1 签名校验合法 (valid=true)" "$SIG_RESP" '"valid":true'

BAD_RESP=$(curl -s --max-time 5 "$GW/api/wx/verify?token=mytoken&timestamp=123&nonce=456&signature=bad_signature_xyz")
assert_contains "sha1 签名校验非法 (valid=false)" "$BAD_RESP" '"valid":false'

# 2. access_token 中控读取 (账号未配置应优雅报错，而非 panic/崩溃)
TK_RESP=$(curl -s --max-time 5 "$GW/api/wx/mp/token?appid=non_exist_appid")
assert_contains "不存在 appid 优雅返回错误" "$TK_RESP" '"code":-1'

echo ""
echo "━━━ 第四层：微信小程序能力 ━━━"
# 1. code2session 接口契约
C2S_RESP=$(curl -s --max-time 5 -X POST "$GW/api/wx/ma/code2session" \
    -H "Content-Type: application/json" \
    -d '{"appid":"non_exist_ma","code":"dummy_code"}')
assert_contains "小程序 code2session 优雅报错" "$C2S_RESP" '"code":-1'

echo ""
echo "━━━ 第五层：数据库隔离与表结构 ━━━"
COUNT=$(docker exec tars-mysql mysql -uroot -p${CMS_DB_PASS} -sN -e \
    "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='tars_wx';" 2>/dev/null || echo 0)
if [ "$COUNT" -ge 4 ]; then
    ok "tars_wx 拥有完整 4 张业务表 ($COUNT 张)"
else
    err "tars_wx 表数量不足" "$COUNT"
fi

echo ""
echo "================================================"
echo "  通过: $PASS    失败: $FAIL"
echo "================================================"
if [ "$FAIL" -eq 0 ]; then
    echo "🎉 微信节点 (wx) 全链路验证通过！"
    exit 0
else
    echo "⚠️  有 $FAIL 项失败"
    exit 1
fi
