#!/usr/bin/env bash
# ================================================================
# n00-get-token.sh — 获取 TarsWeb ticket（干净机部署第 0 步）
#
# 用法:
#   bash deploy/n00-get-token.sh
#   bash deploy/n00-get-token.sh --user admin --pass <密码>
#
# 原理:
#   1. 优先读 env.sh 里的 TARS_TICKET（用户手动填或已自动获取）
#   2. 尝试调用 TarsWeb 登录接口自动获取（如果容器里能调通）
#   3. 兜底读 /docker/tars/scripts/c03-deploy-chisha.sh（兼容现有环境）
#   4. 成功后写入 env.sh 的 TARS_TICKET 供后续脚本用
# ================================================================
set -euo pipefail

_ENV_SH="$(cd "$(dirname "$0")" && pwd)/env.sh"
if [ -f "$_ENV_SH" ]; then . "$_ENV_SH"; fi

# 参数解析
TARS_USER="${TARS_USER:-admin}"
TARS_PASS="${TARS_PASS:-admin123}"
for a in "$@"; do
  case "$a" in
    --user=*) TARS_USER="${a#--user=}" ;;
    --pass=*) TARS_PASS="${a#--pass=}" ;;
    -h|--help)
      grep "^#   " "$0" | sed 's/^#   //'
      exit 0 ;;
  esac
done

C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_END=$'\033[0m'
ok()   { echo "${C_GREEN}✔ $1${C_END}"; }
warn() { echo "${C_YELLOW}⚠ $1${C_END}"; }
err()  { echo "${C_RED}✘ $1${C_END}" >&2; }

# ── 前置检查 ──
docker inspect tars-framework >/dev/null 2>&1 || {
  err "tars-framework 容器不存在，请先起 TARS 平台"; exit 1; }

WEB="http://127.0.0.1:3000/pages/server/api"

echo "=== 1. 检查已有 TARS_TICKET ==="
if [ -n "${TARS_TICKET:-}" ]; then
  # 测试有效性
  RC=$(docker exec tars-framework curl -s --max-time 5 \
    "$WEB/server_list?ticket=${TARS_TICKET}" 2>&1)
  if echo "$RC" | grep -q '"ret_code":200'; then
    ok "env.sh 里的 TARS_TICKET 有效"
    exit 0
  else
    warn "env.sh 里的 TARS_TICKET 已失效，重新获取"
  fi
fi

echo "=== 2. 尝试自动登录 TarsWeb ==="
# 真实端点（已在 framework v3.0.15 实测）：
#   POST /pages/server/api/login  body: {"uid":"<用户>","password":"<密码>"}
#   返回: {"data":{"ticket":"<值>"},"ret_code":200}
# 注意：参数名是 uid（不是 username）；captcha 缺省时该版本不强制
RC=$(docker exec tars-framework curl -s --max-time 8 \
  -X POST "$WEB/login" \
  -H 'Content-Type: application/json' \
  -d "{\"uid\":\"$TARS_USER\",\"password\":\"$TARS_PASS\"}" 2>&1)
echo "  登录响应: $(echo "$RC" | head -c 200)"

TICKET=$(echo "$RC" | python3 -c "import json,sys
try:
    d=json.load(sys.stdin)
    print(d.get('data',{}).get('ticket',''))
except Exception:
    print('')" 2>/dev/null || true)

if [ -n "$TICKET" ]; then
  ok "自动登录成功"
  # 写入 env.sh
  if grep -q '^export TARS_TICKET=' "$_ENV_SH" 2>/dev/null; then
    sed -i "s|^export TARS_TICKET=.*|export TARS_TICKET=\"$TICKET\"|" "$_ENV_SH"
  else
    echo "export TARS_TICKET=\"$TICKET\"" >> "$_ENV_SH"
  fi
  ok "已写入 env.sh"
  exit 0
fi

echo "=== 3. 兜底：读 c03-deploy-chisha.sh ==="
if [ -f /docker/tars/scripts/c03-deploy-chisha.sh ]; then
  TICKET=$(grep "^TOKEN=" /docker/tars/scripts/c03-deploy-chisha.sh | cut -d'"' -f2)
  if [ -n "$TICKET" ]; then
    # 测试有效性
    RC=$(docker exec tars-framework curl -s --max-time 5 \
      "$WEB/server_list?ticket=$TICKET" 2>&1)
    if echo "$RC" | grep -q '"ret_code"'; then
      warn "从 c03-deploy-chisha.sh 读取到 ticket"
      warn "建议手动填入 env.sh 的 TARS_TICKET"
      # 仍写入 env.sh（下次直接用）
      if grep -q '^export TARS_TICKET=' "$_ENV_SH" 2>/dev/null; then
        sed -i "s|^export TARS_TICKET=.*|export TARS_TICKET=\"$TICKET\"|" "$_ENV_SH"
      else
        echo "export TARS_TICKET=\"$TICKET\"" >> "$_ENV_SH"
      fi
      ok "已写入 env.sh"
      exit 0
    fi
  fi
fi

err "无法自动获取 ticket"
echo ""
echo "【手动获取 ticket 步骤】"
echo "  1. 浏览器打开 TarsWeb: http://<本机IP>:3000"
echo "  2. 登录（默认 admin/admin123）"
echo "  3. F12 → Network → 任一请求 → 复制 ticket 参数值"
echo "  4. 填入 deploy/env.sh:  export TARS_TICKET=\"<值>\""
echo "  5. 重跑本脚本"
exit 1
