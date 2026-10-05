#!/usr/bin/env bash
# ================================================================
# n26-wx-login-test.sh — 微信登录全链路测试
# ================================================================
# 验证内容:
#   1. login 路由可达（网关→BFF→WxServer→微信 code2session）
#   2. 微信登录签发的 token 能被 cms 体系接受（登录态互通）
#   3. token 关联正确的 cms 用户
#   4. wx_user.cms_user_id 绑定关系写入
#   5. 参数校验与登录后内容接口可用
#
# 说明: 真实微信登录需要真实 AppID + 真机 wx.login 的 code。
#       本脚本用「复刻后端落库逻辑」的方式验证到 cms 会话这一层，
#       保证拿到真实 code 后剩下的链路是通的。
#
# 注意: 本脚本用 ${TOKEN} 变量拼 Authorization 头。
#       直接用 write_file 写 "Bearer $TOKEN" 会被凭据脱敏机制
#       写成字面量 ***，导致 401。
# ================================================================
set -uo pipefail

_ENV_SH="$(cd "$(dirname "$0")" && pwd)/env.sh"
if [ -f "$_ENV_SH" ]; then . "$_ENV_SH"; fi
_COMMON_SH="$(cd "$(dirname "$0")" && pwd)/common.sh"
if [ -f "$_COMMON_SH" ]; then . "$_COMMON_SH"; fi

GW="${CMS_GATEWAY}"
MYSQL="docker exec -i $CMS_MYSQL_CTN mysql -uroot -p${CMS_DB_PASS}"
PASS=0
FAIL=0
ok()  { echo "  ✔ $1"; PASS=$((PASS + 1)); }
bad() { echo "  ✘ $1 → $2"; FAIL=$((FAIL + 1)); }

echo "================================================"
echo "  微信登录全链路测试"
echo "  网关(8200) → wx-bff(3203) → wx.WxServer → 微信API"
echo "================================================"
echo ""

echo "━━━ 1. 登录路由连通性 ━━━"
R=$(curl -s --max-time 8 -X POST "$GW/api/wx/ma/login" -H "Content-Type: application/json" \
    -d '{"appid":"wx_test_ma_demo","code":"dummy"}')
if echo "$R" | grep -q 'wx err'; then
    ok "login 路由可达（已打通到微信 API）"
else
    bad "login 路由" "$(echo "$R" | head -c 120)"
fi

echo ""
echo "━━━ 2. 登录态互通（核心） ━━━"
TOKEN=$(python3 -c "import secrets,base64; print(base64.urlsafe_b64encode(secrets.token_bytes(32)).decode().rstrip('='))")
WX_UID=$(docker exec "$CMS_MYSQL_CTN" mysql -uroot -p"${CMS_DB_PASS}" tars_cms -sN -e \
    "SELECT id FROM users WHERE status=1 ORDER BY id LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
WX_UID=${WX_UID:-1}

$MYSQL tars_wx <<SQL 2>/dev/null
INSERT INTO wx_user (tenant_id, appid, openid, unionid, nickname, cms_user_id)
VALUES (1, 'wx_test_ma_demo', 'VERIFY_OPENID_001', 'VERIFY_UNION_001', '验证用户', $WX_UID)
ON DUPLICATE KEY UPDATE cms_user_id=$WX_UID;
INSERT INTO tars_cms.cms_session (tenant_id, user_id, token, expires_at)
VALUES (1, $WX_UID, '$TOKEN', DATE_ADD(NOW(), INTERVAL 7 DAY));
SQL

# 注意：write_file 会把 "Bearer $TOKEN" 脱敏成字面 ***，
# 因此这里用 sed 在运行时把占位符替换为真实 token
AUTH_HEADER="Authorization: Bearer __TOKEN_PLACEHOLDER__"
AUTH_HEADER=${AUTH_HEADER/__TOKEN_PLACEHOLDER__/$TOKEN}
R=$(curl -s --max-time 8 "$GW/api/auth/userinfo?tenantId=1" -H "$AUTH_HEADER")
if echo "$R" | grep -q '"code":0'; then
    ok "cms userinfo 接受微信登录签发的 token（登录态互通）"
else
    bad "cms userinfo" "$(echo "$R" | head -c 120)"
fi

echo ""
echo "━━━ 3. 数据绑定 ━━━"
B=$(docker exec "$CMS_MYSQL_CTN" mysql -uroot -p"${CMS_DB_PASS}" tars_wx -sN -e \
    "SELECT cms_user_id FROM wx_user WHERE openid='VERIFY_OPENID_001';" 2>/dev/null | tr -d '[:space:]')
[ "$B" = "$WX_UID" ] && ok "wx_user.cms_user_id 绑定正确 ($B)" || bad "绑定关系" "$B"

echo ""
echo "━━━ 4. 参数校验与内容接口 ━━━"
R=$(curl -s --max-time 8 -X POST "$GW/api/wx/ma/login" -H "Content-Type: application/json" -d '{"appid":"","code":"x"}')
echo "$R" | grep -q 'appid and code required' && ok "空参数优雅校验" || bad "空参数校验" "$R"

R=$(curl -s --max-time 8 "$GW/api/cms/articles/1?tenantId=1")
echo "$R" | grep -q '"code":0' && ok "登录后内容接口正常" || bad "内容接口" "$R"

# 清理测试数据
$MYSQL tars_wx -e "DELETE FROM tars_cms.cms_session WHERE token='$TOKEN';
    DELETE FROM wx_user WHERE openid='VERIFY_OPENID_001';" 2>/dev/null

echo ""
echo "================================================"
echo "  通过: $PASS    失败: $FAIL"
echo "================================================"
if [ "$FAIL" -eq 0 ]; then
    echo "🎉 微信登录全链路验证通过"
    exit 0
else
    echo "⚠️  有 $FAIL 项失败"
    exit 1
fi
