#!/usr/bin/env bash
# ================================================================
# deploy.sh — tars-cms 一键部署脚本
#
# 用法:
#   bash deploy/deploy.sh             # 顺序跑 n01~n09（幂等，可重跑）
#   bash deploy/deploy.sh --full      # 强制全量重装（重新注册服务 + 重编译 + 重发布）
#   bash deploy/deploy.sh --skip n02  # 跳过 n02 编译（用已有包）
#
# 设计原则:
#   1. 每个 n0X 脚本保持独立可跑（一个操作一个 sh，可逆）
#   2. 本脚本只做「编排」：按顺序调用 + 失败即停 + 断点续跑
#   3. 全程幂等：重复执行安全，已存在的服务/路由自动跳过
#   4. --full 会删除已注册服务（走 n03/n06/n09 的完整流程）
# ================================================================
set -euo pipefail

# 加载部署环境变量（密码等凭据不硬编码在脚本里）
_ENV_SH="$(cd "$(dirname "$0")" && pwd)/env.sh"
if [ -f "$_ENV_SH" ]; then . "$_ENV_SH"; fi

SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"   # 绝对路径（供 --help 用）
cd "$(dirname "$0")"          # deploy/
ROOT="$(cd .. && pwd)"        # 仓库根目录

# ── 参数解析 ──
FULL=0
SKIP=()
for a in "$@"; do
  case "$a" in
    --full) FULL=1 ;;
    --skip) ;;
    --skip=*) SKIP+=("${a#--skip=}") ;;
    -h|--help)
      grep "^#   " "$SELF" | sed 's/^#   //'
      exit 0 ;;
    *)
      if [[ "$a" =~ ^[a-zA-Z0-9]+$ ]]; then SKIP+=("$a"); fi
      ;;
  esac
done

# ── 检查是否跳过某步 ──
# 支持写法：n02 / n02-package / n02-package.sh（双向前缀匹配，注意补 '-' 防 n0 误伤）
skip() {
  local base="${1%%.sh}"
  for s in "${SKIP[@]}"; do
    local sb="${s%%.sh}"
    [[ "$base" == "$sb" || "$base" == "$sb"-* || "$sb" == "$base"-* ]] && return 0
  done
  return 1
}

# ── 彩色输出 ──
C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_CYAN=$'\033[36m'; C_END=$'\033[0m'
ok()   { echo "${C_GREEN}✔ $1${C_END}"; }
warn() { echo "${C_YELLOW}⚠ $1${C_END}"; }
err()  { echo "${C_RED}✘ $1${C_END}" >&2; }
step() { echo; echo "${C_CYAN}══════ $1 ══════${C_END}"; }

# ── 断点记录（中断后重跑从失败处继续）──
STATE_FILE="/tmp/tars-cms-deploy.state"
mark_done() { echo "$1" >> "$STATE_FILE"; }
was_done()  { grep -qx "$1" "$STATE_FILE" 2>/dev/null; }
[[ -f "$STATE_FILE" ]] || : > "$STATE_FILE"

# ── 前置检查 ──
step "前置检查"
for c in docker go node npm git; do
  command -v "$c" >/dev/null 2>&1 || { err "缺少依赖: $c"; exit 1; }
done
ok "依赖齐全 (docker/go/node/npm/git)"
docker inspect tars-mysql >/dev/null 2>&1 || { err "tars-mysql 容器不存在，请先部署 TARS 平台"; exit 1; }
docker inspect tars-framework >/dev/null 2>&1 || { err "tars-framework 容器不存在"; exit 1; }
docker inspect tars-node >/dev/null 2>&1 || { err "tars-node 容器不存在"; exit 1; }
ok "TARS 平台容器齐全 (tars-mysql/tars-framework/tars-node)"

# ── 编排步骤 ──
run() {
  local n="$1" desc="$2"
  if was_done "$n" && [[ "$FULL" == 0 ]]; then
    warn "跳过 $n（已成功过，断点续跑）"
    return
  fi
  step "$n — $desc"
  if skip "$n"; then
    warn "跳过 $n（--skip 指定）"
    return
  fi
  # 注意：不传 "$@"，子脚本不认 deploy.sh 的参数（如 --full/--skip）
  if ! bash "$ROOT/deploy/${n%%.sh}.sh"; then
    err "$n 失败，终止（修复后重跑会自动从 $n 继续）"
    exit 1
  fi
  ok "$n 完成"
  mark_done "$n"
}

# 若 --full，重置断点记录
if [[ "$FULL" == 1 ]]; then
  warn "--full: 强制全量重装，清空断点记录"
  rm -f "$STATE_FILE"
  : > "$STATE_FILE"
fi

# ── 顺序执行 ──
# 网关（可选，若 Base.GatewayServer 未部署则自动检测并部署）
if skip "n15-gateway"; then
    warn "跳过 n15-gateway（--skip 指定）"
elif docker exec tars-node ss -tln 2>/dev/null | grep -q ':8200 ' && \
     docker exec tars-node ss -tln 2>/dev/null | grep -q ':18212 '; then
    warn "GatewayServer 已在运行（8200/18212），跳过部署"
else
    run n15-gateway.sh        "部署 TarsGateway（C++ 网关 + GatewayWeb）"
fi

run n01-init-db.sh        "初始化数据库（幂等）"
run n02-package.sh        "编译打包 cms.CmsServer"
run n03-deploy.sh         "部署 cms.CmsServer 到 tarsnode"
run n04-verify.sh         "验证业务服务 RPC 连通"
run n05-config-gateway.sh "注册网关注册 station/upstream/router"
run n06-deploy-web.sh     "编译打包发布 cms.CmsWeb（静态站+上传）"
run n07-config-web-gateway.sh "网关路由 / /admin/ /uploads/"
run n09-deploy-bff.sh     "编译打包发布 cms.CmsBff（BFF）"
run n08-fix-pid.sh        "安装 cron 修正 not_tars PID"
run n10-fix-routes.sh     "诊断并修正网关路由（防服务迁移残留旧 IP）"

# ── 最终验证 ──
step "最终验证"
GW="${CMS_GATEWAY}"
for p in "/" "/admin/" "/api/cms/home?tenantId=1"; do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$GW$p")
  if [[ "$code" == "200" ]]; then
    ok "GET $p → $code"
  else
    err "GET $p → $code (预期 200)"
  fi
done
docker exec tars-mysql mysql -uroot -p${CMS_DB_PASS} db_tars -sN -e \
  "SELECT server_name, present_state, process_id FROM t_server_conf WHERE application='cms';" 2>/dev/null | \
  while IFS=$'\t' read -r svc state pid; do
    printf "  %-14s %-8s PID=%s\n" "$svc" "$state" "$pid"
  done

echo
echo "${C_GREEN}════════ 一键部署完成 ✅ ════════${C_END}"
