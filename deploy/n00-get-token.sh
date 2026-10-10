#!/usr/bin/env bash
# ================================================================
# n00-get-token.sh — 获取 TarsWeb ticket（干净机部署第 0 步）
#
# 用法:
#   bash deploy/n00-get-token.sh
#   bash deploy/n00-get-token.sh --user admin --pass <密码>
#   bash deploy/n00-get-token.sh --reset-pass        # 强制重置 admin 密码为 admin123 再登录
#   TARS_USER=admin TARS_PASS=<密码> bash deploy/n00-get-token.sh
#
# 账号密码来源（优先级从高到低）:
#   1. --user/--pass 命令行参数
#   2. 环境变量 TARS_USER/TARS_PASS（export 或 env 前缀传入）
#   3. env.sh 里的 export TARS_USER/TARS_PASS（见 env.sh.example）
#   4. 默认 admin/admin123
# 注：env.sh 的值会被 2 覆盖（脚本 source env.sh 在参数解析前），
#     即 shell/命令行显式传入优先于 env.sh 文件内配置。
#
# 全新机坑：TarsWeb 初始化后 admin 默认密码可能不是 admin123（登录报"密码错误"）。
#   本脚本检测到"密码错误"会自动把 admin 密码重置为 admin123 后重试登录；
#   也可用 --reset-pass 主动重置。
# ================================================================
set -euo pipefail

_ENV_SH="$(cd "$(dirname "$0")" && pwd)/env.sh"
if [ -f "$_ENV_SH" ]; then . "$_ENV_SH"; fi

# 参数解析（账号密码：--user/--pass > 环境变量 TARS_USER/TARS_PASS > env.sh > 默认 admin/admin123）
# 注：env.sh 已在上方 source，若用户在 env.sh 里 export TARS_USER/TARS_PASS，
#     且命令行/环境未显式传值，则会采用 env.sh 的值；显式传值则覆盖 env.sh。
RESET_PASS=0
TARS_USER="${TARS_USER:-admin}"
TARS_PASS="${TARS_PASS:-admin123}"
for a in "$@"; do
  case "$a" in
    --user=*) TARS_USER="${a#--user=}" ;;
    --pass=*) TARS_PASS="${a#--pass=}" ;;
    --reset-pass) RESET_PASS=1 ;;
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
docker inspect tars-mysql >/dev/null 2>&1 || {
  err "tars-mysql 容器不存在（--reset-pass 与自动重置需要它）"; exit 1; }

# CMS_DB_PASS 用于连 mysql 重置 admin 密码；未配则用 mysql 容器默认 root 密码探测
MYSQL_ROOT_PASS="${CMS_DB_PASS:-tars@root.2026}"

WEB="http://127.0.0.1:3000/pages/server/api"

# ── 登录尝试（抽成函数，供首次/重置后重试复用）──
try_login() {
  docker exec tars-framework curl -s --max-time 8 \
    -X POST "$WEB/login" \
    -H 'Content-Type: application/json' \
    -d "{\"uid\":\"$TARS_USER\",\"password\":\"$TARS_PASS\"}" 2>&1
}

# ── 重置 admin 密码为 admin123（sha1 存储，db_user_system.t_user_info）──
reset_admin_pass() {
  warn "重置 TarsWeb admin 密码为 admin123（全新机默认密码不匹配兜底）"
  docker exec -i tars-mysql mysql -uroot -p"$MYSQL_ROOT_PASS" db_user_system -e \
    "UPDATE t_user_info SET password=SHA1('admin123') WHERE uid='admin';" >/dev/null 2>&1 \
    || { err "重置失败：无法连 tars-mysql（检查 CMS_DB_PASS）"; return 1; }
  TARS_PASS="admin123"
  ok "已重置，TARS_PASS 切到 admin123"
}

# ── 把 ticket 写回 env.sh ──
save_ticket() {
  local t="$1"
  if grep -q '^export TARS_TICKET=' "$_ENV_SH" 2>/dev/null; then
    sed -i "s|^export TARS_TICKET=.*|export TARS_TICKET=\"$t\"|" "$_ENV_SH"
  else
    echo "export TARS_TICKET=\"$t\"" >> "$_ENV_SH"
  fi
  ok "已写入 env.sh"
}

parse_ticket() {
  python3 -c "import json,sys
try:
    d=json.load(sys.stdin); print(d.get('data',{}).get('ticket',''))
except Exception: print('')" 2>/dev/null || true
}

# ── 显式 --reset-pass：先重置再登录 ──
if [ "$RESET_PASS" = 1 ]; then
  reset_admin_pass || true
fi

echo "=== 1. 检查已有 TARS_TICKET ==="
if [ -n "${TARS_TICKET:-}" ]; then
  # 测试有效性：用 validate 接口（server_list 需要 tree_node_id，缺参会恒 500，会把有效 ticket 误判为失效）
  RC=$(docker exec tars-framework curl -s --max-time 5 \
    "$WEB/validate?ticket=${TARS_TICKET}&uid=${TARS_USER}" 2>&1)
  if echo "$RC" | grep -q '"result":true'; then
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
RC=$(try_login)
echo "  登录响应: $(echo "$RC" | head -c 200)"
TICKET=$(echo "$RC" | parse_ticket)

# 全新机坑：TarsWeb 初始化后 admin 默认密码可能不是 admin123（"密码错误"）。
# 检测到密码被拒 → 自动把 admin 密码重置为 admin123 再重试一次。
if [ -z "$TICKET" ] && echo "$RC" | grep -qE '"ret_code":500|passwordNoCorrect|密码错误'; then
  warn "检测到密码被拒绝（全新机常见：admin 默认密码 ≠ admin123）"
  warn "自动重置 admin 密码为 admin123 后重试登录..."
  if reset_admin_pass; then
    RC=$(try_login)
    echo "  重试响应: $(echo "$RC" | head -c 200)"
    TICKET=$(echo "$RC" | parse_ticket)
  fi
fi

if [ -n "$TICKET" ]; then
  ok "自动登录成功"
  save_ticket "$TICKET"
  exit 0
fi

# 显式传了账号/密码但登录失败（如密码错误）：显式警告，防止后续兜底掩盖问题
if echo "$RC" | grep -q '"ret_code":500' || echo "$RC" | grep -q 'passwordNoCorrect\|密码错误'; then
  warn "TarsWeb 自动登录失败（账号 $TARS_USER 的密码被拒绝）"
  warn "若你通过 env/--pass 传了新密码，请确认它与 TarsWeb 当前密码一致"
  warn "可用 --reset-pass 强制把 admin 密码重置为 admin123"
fi

echo "=== 3. 兜底：读 c03-deploy-chisha.sh ==="
if [ -f /docker/tars/scripts/c03-deploy-chisha.sh ]; then
  TICKET=$(grep "^TOKEN=" /docker/tars/scripts/c03-deploy-chisha.sh | cut -d'"' -f2)
  if [ -n "$TICKET" ]; then
    # 测试有效性：用 getUidByTicket（server_list 缺 tree_node_id 恒 500，会把有效 ticket 误判为失效）
    RC=$(docker exec tars-framework curl -s --max-time 5 \
      "$WEB/getUidByTicket?ticket=$TICKET" 2>&1)
    if echo "$RC" | grep -qE '"uid":"[^"]+"'; then
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
