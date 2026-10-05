#!/usr/bin/env bash
# ================================================================
# n14-compose-deploy.sh — Docker Compose 一次性部署（全新环境用）
# ================================================================
# 【用途】
#   在一台**新机器**上用 docker compose 一条命令起 TARS 全家桶，
#   然后发布 cms 业务服务。
#
#   ⚠️ 本脚本**不会**影响现有运行中的环境：
#     - --dry-run  默认模式，只校验 + 报告
#     - --up       需要确认（无容器冲突），且仅当 compose 服务未占用名
#     - 现有环境已有 4 个容器时，--up 会因 container_name 冲突而失败（安全）
#
# 【用法】
#   bash deploy/n14-compose-deploy.sh            # 仅校验（不改任何东西）
#   bash deploy/n14-compose-deploy.sh --up       # 一键起（全新环境）
#   bash deploy/n14-compose-deploy.sh --down     # 停 compose 起的容器
#
# 【链路】
#   compose 起：mysql / framework / node / gateway-nginx
#   然后宿主机跑：bash deploy/deploy.sh（发布 cms 三服务到 tarsnode）
# ================================================================
set -uo pipefail

cd "$(dirname "$0")/.."
COMPOSE_FILE="deploy/docker-compose.yml"
MODE="${1:-check}"

banner() { printf "\n\033[1m════ %s ════\033[0m\n" "$1"; }

check() {
  banner "1. compose 文件语法"
  if docker compose -f "$COMPOSE_FILE" config --quiet 2>/dev/null; then
    echo "  ✅ 语法正确"
  else
    echo "  ❌ 语法错误"
    docker compose -f "$COMPOSE_FILE" config --quiet 2>&1 | sed 's/^/    /'
    return 1
  fi

  banner "2. compose 服务 vs 现有容器"
  local conflict=0
  for s in $(docker compose -f "$COMPOSE_FILE" config --services 2>/dev/null); do
    name=$(docker compose -f "$COMPOSE_FILE" config --services 2>/dev/null | grep -x "$s")
    # container_name 从 config 里抓
    cname=$(docker compose -f "$COMPOSE_FILE" config 2>/dev/null | grep -A2 "^  ${s}:$" | grep "container_name:" | awk '{print $2}')
    exists=$(docker ps -a --format '{{.Names}}' | grep -c "^${cname}$" || true)
    if [ "$exists" -gt 0 ]; then
      running=$(docker ps --format '{{.Names}}' | grep -c "^${cname}$" || true)
      echo "  ⚠ $s → $cname 已存在（运行中 $running）"
      conflict=$((conflict+1))
    else
      echo "  ✅ $s → $cname 未占用（可 up）"
    fi
  done

  banner "3. 结论"
  if [ "$conflict" -gt 0 ]; then
    echo "  现有环境已有 $conflict 个容器 → **不要 --up**（会名称冲突）"
    echo "  现有环境继续用 n01~n13 脚本维护即可"
    echo "  本 compose 仅用于**全新机器**从零部署"
  else
    echo "  无冲突 → 可执行: $0 --up"
  fi

  banner "4. compose 依赖的前置目录"
  for d in /docker/tars/mysql/data /docker/tars/framework/data /docker/tars/node/data /docker/tars/gateway-nginx; do
    if [ -e "$d" ]; then
      echo "  ✅ $d"
    else
      echo "  ⚠ $d 不存在（up 前需创建或挂载为空卷）"
    fi
  done
}

do_up() {
  banner "确认 up"
  echo "  将启动: tars-mysql, tars-framework, tars-node, tars-gateway-nginx"
  echo "  数据目录: /docker/tars/{mysql,framework,node}（已存在则复用）"
  echo ""
  read -rp "  确认执行？[y/N] " a
  case "$a" in
    y|Y) ;;
    *) echo "  已取消"; return 0 ;;
  esac

  docker compose -f "$COMPOSE_FILE" up -d 2>&1 | sed 's/^/  /'
  echo ""
  banner "启动状态"
  docker compose -f "$COMPOSE_FILE" ps 2>&1 | sed 's/^/  /'
  echo ""
  echo "  → 框架首次启动初始化 DB 需 30~60s，tars-node 需 framework 就绪"
  echo "  → 然后宿主机发布 cms 业务: bash deploy/deploy.sh"
}

do_down() {
  banner "停止 compose 起的容器"
  docker compose -f "$COMPOSE_FILE" down 2>&1 | sed 's/^/  /'
}

case "$MODE" in
  check|"") check ;;
  --up)     do_up ;;
  --down)   do_down ;;
  *) echo "用法: $0 [check|--up|--down]"; exit 1 ;;
esac
