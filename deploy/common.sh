# ================================================================
# common.sh — tars-cms 部署脚本公共库（被各 n0X 脚本 source）
#
# 作用：把「干净机可移植性」相关的取值逻辑集中到一处：
#   1. TARS ticket 获取（多级回退，不再硬依赖 c03-deploy-chisha.sh）
#   2. 网关地址 / 节点 IP / 构建目录（全部可用环境变量覆盖）
#   3. 统一的日志与断言函数
#
# 用法：在各脚本 env.sh 加载之后 source 本文件
#   _COMMON_SH="$(cd "$(dirname "$0")" && pwd)/common.sh"
#   [ -f "$_COMMON_SH" ] && . "$_COMMON_SH"
# ================================================================

# ── 目录（可用环境变量覆盖，默认沿用 /docker/tars）──
export CMS_BASE_DIR="${CMS_BASE_DIR:-/docker/tars}"
export CMS_BUILD_DIR="${CMS_BUILD_DIR:-$CMS_BASE_DIR/build/tars-cms}"
export CMS_SCRIPTS_DIR="${CMS_SCRIPTS_DIR:-$CMS_BASE_DIR/scripts}"

# ── 仓库根目录（common.sh 位于 deploy/，父目录即仓库根）──
# 用于替代脚本里的硬编码 /root/tars-cms（换机/换路径自动适配）
_CMS_COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
if [ -n "${_CMS_COMMON_DIR:-}" ]; then
  export CMS_REPO_DIR="${CMS_REPO_DIR:-$(cd "$_CMS_COMMON_DIR/.." && pwd)}"
fi

# ── 网络 ──
# CMS_GATEWAY 优先（env.sh 可配）；否则按本机 IP 拼
if [ -z "${CMS_GATEWAY:-}" ]; then
  _LOCAL_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
  export CMS_GATEWAY="http://${_LOCAL_IP:-127.0.0.1}:8200"
fi
export CMS_GW_PORT="${CMS_GW_PORT:-8200}"

# ── 容器名（可用环境变量覆盖）──
export CMS_MYSQL_CTN="${CMS_MYSQL_CTN:-tars-mysql}"
export CMS_FW_CTN="${CMS_FW_CTN:-tars-framework}"
export CMS_NODE_CTN="${CMS_NODE_CTN:-tars-node}"

# ── TARS 节点 IP（tarsnode 容器地址）──
if [ -z "${CMS_NODE_IP:-}" ]; then
  CMS_NODE_IP="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' \
    "${CMS_NODE_CTN}" 2>/dev/null | head -1)"
  export CMS_NODE_IP="${CMS_NODE_IP:-172.25.0.5}"
fi

# ── TarsWeb 管理端地址（容器内访问）──
export CMS_WEB_API="${CMS_WEB_API:-http://127.0.0.1:3000/pages/server/api}"

# ── GatewayWebServer API 地址（动态路由管理）──
# 自动探测 tars-framework 容器 IP；可用 CMS_GW_WEB_API 覆盖。
if [ -z "${CMS_GW_WEB_API:-}" ]; then
  _GW_FW_IP="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${CMS_FW_CTN}" 2>/dev/null | head -1 || true)"
  export CMS_GW_WEB_API="http://${_GW_FW_IP:-172.25.0.3}:${CMS_GW_WEB_PORT:-15535}/plugins/base/gateway/api"
fi
export CMS_GW_WEB_PORT="${CMS_GW_WEB_PORT:-15535}"

# ── 日志函数（若调用方已定义则不覆盖）──
if ! declare -F ok >/dev/null 2>&1; then
  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_END=$'\033[0m'
  ok()   { echo "${C_GREEN}✔ $1${C_END}"; }
  warn() { echo "${C_YELLOW}⚠ $1${C_END}"; }
  err()  { echo "${C_RED}✘ $1${C_END}" >&2; }
fi

# ── TARS ticket 获取（多级回退）──
# 优先级：env.sh 的 TARS_TICKET > c03-deploy-chisha.sh（兼容旧环境）
# 干净机上请先跑 n00-get-token.sh 写入 env.sh
tars_ticket() {
  if [ -n "${TARS_TICKET:-}" ]; then
    printf '%s' "$TARS_TICKET"; return 0
  fi
  local f="$CMS_SCRIPTS_DIR/c03-deploy-chisha.sh"
  if [ -f "$f" ]; then
    local t; t="$(grep '^TOKEN=' "$f" | cut -d'"' -f2)"
    if [ -n "$t" ]; then printf '%s' "$t"; return 0; fi
  fi
  return 1
}

# 取 ticket，失败则明确报错并提示跑 n00
require_ticket() {
  local t
  if ! t="$(tars_ticket)"; then
    err "无法获取 TARS ticket（干净机请先跑: bash deploy/n00-get-token.sh）" >&2
    exit 1
  fi
  printf '%s' "$t"
}

# ── mysql 快捷执行（走容器）──
cms_mysql() {
  docker exec "$CMS_MYSQL_CTN" mysql -uroot -p"${CMS_DB_PASS}" "$@" 2>/dev/null
}
