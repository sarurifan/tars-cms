#!/usr/bin/env bash
# ================================================================
# one-click.sh — tars-cms 一条命令一键部署（干净机 / 已有4容器 通用）
#
# 目标：从零号机（TARS 4 容器已通 / 干净机）一条命令跑通全部服务
#   ┌─ 若 4 容器已存在（tars-mysql/framework/node/gateway-nginx）
#   │     → 跳过基础设施，直接：gateway(可选检测) → 业务 → 路由 → 验证
#   └─ 若全新机（无容器）→ 先 docker compose 起基础设施，再发业务
#
# 用法：
#   bash deploy/one-click.sh                 # 一键部署（自动检测）
#   bash deploy/one-click.sh --with-gateway  # 强制部署 TarsGateway（忽略检测）
#   bash deploy/one-click.sh --skip-token    # 跳过 ticket 获取（已手动填 env.sh）
#   bash deploy/one-click.sh --check         # 只读巡检，不改动
#
# 依赖：docker / go / node / npm / git（deploy.sh 已逐一检查）
# 环境变量（deploy/env.sh 可配）：CMS_DB_PASS / CMS_GATEWAY / TARS_USER / TARS_PASS
# ================================================================
set -euo pipefail

cd "$(dirname "$0")"
SELF="$(pwd)/$(basename "$0")"
ROOT="$(cd .. && pwd)"

# ── 参数解析 ──
WITH_GATEWAY=0
SKIP_TOKEN=0
CHECK_ONLY=0
for a in "$@"; do
  case "$a" in
    --with-gateway) WITH_GATEWAY=1 ;;
    --skip-token)   SKIP_TOKEN=1 ;;
    --check)        CHECK_ONLY=1 ;;
    -h|--help)
      grep "^#   " "$SELF" | sed 's/^#   //'
      exit 0 ;;
    *) echo "未知参数: $a (见 --help)"; exit 1 ;;
  esac
done

C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_CYAN=$'\033[36m'; C_END=$'\033[0m'
ok()   { echo "${C_GREEN}✔ $1${C_END}"; }
warn() { echo "${C_YELLOW}⚠ $1${C_END}"; }
err()  { echo "${C_RED}✘ $1${C_END}" >&2; }
step() { echo; echo "${C_CYAN}══════ $1 ══════${C_END}"; }

# 加载环境变量 + 公共库（CMS_DB_PASS/CMS_GATEWAY/CMS_NODE_IP/REPO_DIR）
_ENV_SH="$PWD/env.sh"
[ -f "$_ENV_SH" ] && . "$_ENV_SH"
_COMMON_SH="$PWD/common.sh"
[ -f "$_COMMON_SH" ] && . "$_COMMON_SH"

# ── 前置检查 ──
step "前置检查"
for c in docker go node npm git python3; do
  command -v "$c" >/dev/null 2>&1 || { err "缺少依赖: $c"; exit 1; }
done
ok "依赖齐全 (docker/go/node/npm/git/python3)"

# 判定基础设施状态
MYSQL_UP=$(docker inspect tars-mysql   >/dev/null 2>&1 && echo 1 || echo 0)
FW_UP=$(docker inspect tars-framework  >/dev/null 2>&1 && echo 1 || echo 0)
NODE_UP=$(docker inspect tars-node     >/dev/null 2>&1 && echo 1 || echo 0)
INFRA_UP=$((MYSQL_UP && FW_UP && NODE_UP))

if [[ "$CHECK_ONLY" == 1 ]]; then
  step "只读巡检"
  echo "  [1] TarsGateway:"
  bash n15-gateway.sh --check 2>&1 | sed 's/^/    /' || warn "n15 --check 失败"
  echo
  echo "  [2] cms 业务服务:"
  docker exec tars-mysql mysql -uroot -p"${CMS_DB_PASS}" db_tars -sN -e \
    "SELECT server_name, server_type, present_state, process_id FROM t_server_conf WHERE application IN ('cms','Base');" 2>/dev/null | \
    while IFS=$'\t' read -r svc typ state pid; do
      printf "    %-14s %-10s %-10s PID=%s\n" "$svc" "$typ" "$state" "$pid"
    done
  echo
  echo "  [3] 端到端:"
  GW="${CMS_GATEWAY:-http://$(hostname -I | awk '{print $1}'):8200}"
  for p in "/" "/api/cms/home?tenantId=1"; do
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 -H "Host: cms" "$GW$p")
    printf "    %-28s → %s\n" "$p" "$code"
  done
  exit 0
fi

if [[ "$INFRA_UP" == 0 ]]; then
  step "基础设施不存在 → 用 docker compose 拉起 (全新机)"
  warn "未检测到 tars-mysql/framework/node 容器，走全新机路径"
  if [[ ! -f docker-compose.yml ]]; then
    err "缺少 docker-compose.yml"; exit 1
  fi
  docker compose -f docker-compose.yml up -d
  # 等待框架初始化（healthcheck 已带 start_period 60s）
  echo "  等待 tars-framework healthy（最多 90s）..."
  for i in $(seq 1 30); do
    ST=$(docker inspect -f '{{.State.Health.Status}}' tars-framework 2>/dev/null || echo "starting")
    [[ "$ST" == "healthy" ]] && { ok "tars-framework healthy"; break; }
    sleep 3
  done
  INFRA_UP=1
else
  step "基础设施已就绪 (tars-mysql/framework/node)"
  ok "4 容器环境已存在，跳过 compose"
fi

# ── ticket 获取 ──
if [[ "$SKIP_TOKEN" == 0 ]]; then
  step "获取 TarsWeb ticket"
  if ! bash n00-get-token.sh; then
    warn "自动登录未成功——请手动填 deploy/env.sh 的 TARS_TICKET 后重跑（或加 --skip-token）"
  fi
fi

# ── 部署网关（检测 or 强制）──
GW_RUNNING=$(docker exec tars-node ss -tln 2>/dev/null | grep -q ':8200 ' && echo 1 || echo 0)
if [[ "$WITH_GATEWAY" == 1 || "$GW_RUNNING" == 0 ]]; then
  step "部署 TarsGateway（GatewayServer:8200/18212 + GatewayWeb:15535）"
  if [[ "$WITH_GATEWAY" == 1 ]]; then
    warn "--with-gateway 强制重部署（会重新编译+发布）"
  fi
  bash n15-gateway.sh all
else
  step "TarsGateway 已在运行 (8200/18212)，跳过部署"
  ok "网关就绪"
fi

# ── 业务服务（幂等，断点续跑）──
step "发布业务服务 (CmsServer/CmsWeb/CmsBff)"
# deploy.sh 已含网关检测，这里直接复用其编排；--skip 传 n15 避免重复
if [[ "$WITH_GATEWAY" == 1 ]]; then
  bash deploy.sh
else
  bash deploy.sh --skip n15-gateway
fi

# ── 最终验证 ──
step "最终验证"
GW="${CMS_GATEWAY:-http://$(hostname -I | awk '{print $1}'):8200}"
for p in "/" "/admin/" "/api/cms/home?tenantId=1"; do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 -H "Host: cms" "$GW$p")
  if [[ "$code" == "200" ]]; then
    ok "GET $p (Host: cms) → $code"
  else
    err "GET $p → $code (预期 200)"
  fi
done

docker exec tars-mysql mysql -uroot -p${CMS_DB_PASS} db_tars -sN -e \
  "SELECT server_name, present_state FROM t_server_conf WHERE application='cms' OR application='Base';" 2>/dev/null | \
  while IFS=$'\t' read -r svc state; do
    printf "  %-14s %-10s\n" "$svc" "$state"
  done

echo
echo "${C_GREEN}════════ 一键部署完成 ✅ ════════${C_END}"
echo "  前端:    $GW/            (Host: cms)"
echo "  Admin:   $GW/admin/"
echo "  网关管理: http://$(hostname -I | awk '{print $1}'):15535/plugins/base/gateway/"
echo
