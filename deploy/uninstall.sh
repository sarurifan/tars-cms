#!/usr/bin/env bash
# ================================================================
# uninstall.sh — tars-cms 卸载 / 清理脚本
#
# 作用：彻底移除 tars-cms 部署产物，把机器还原到"部署前"状态。
#       供「测试环境清理」或「重装前全清」使用。
#
# 安全铁律（共享宿主机！）：
#   1. 只删本项目（tars/cms）的东西，绝不碰 easyai/gitlab/redis/
#      gpu-exporter/node-exporter/mongo/rabbitmq/runner 等其他项目。
#   2. 删除前先盘点（列清单），删完再核对（确认归零）。
#   3. 数据目录 /docker/tars 需 sudo（容器内进程写的文件归 root）。
#
# 用法：
#   bash deploy/uninstall.sh            # 全量卸载（交互确认）
#   bash deploy/uninstall.sh --force    # 跳过确认
#   bash deploy/uninstall.sh --dry-run  # 只列要删的，不真删
#   bash deploy/uninstall.sh --keep-toolchain  # 保留 go/node（如他处也在用）
# ================================================================
set -uo pipefail

FORCE=0; DRY=0; KEEP_TC=0
for a in "$@"; do
  case "$a" in
    --force) FORCE=1 ;;
    --dry-run) DRY=1 ;;
    --keep-toolchain) KEEP_TC=1 ;;
    *) echo "未知参数: $a (支持: --force / --dry-run / --keep-toolchain)"; exit 1 ;;
  esac
done

C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_END=$'\033[0m'
ok()   { echo "${C_GREEN}✔ $1${C_END}"; }
warn() { echo "${C_YELLOW}⚠ $1${C_END}"; }
err()  { echo "${C_RED}✘ $1${C_END}" >&2; }

# 非 root 时用 sudo（本脚本大部分操作需要 root 权限）
if [ "$(id -u)" -ne 0 ]; then
  SUDO="sudo"
else
  SUDO=""
fi

# ── 容器清单（只删本项目）──
CMS_CTNS="tars-mysql tars-framework tars-node tars-gateway-nginx"
# ── 镜像（tarscloud 全家桶 + 本项目用的 nginx/mysql）──
CMS_IMAGES_PAT="tarscloud|^nginx:1\.24|^mysql:5\.6"
# ── compose 网络（项目名 tars-cms）──
CMS_NETWORKS="tars-cms_tars tars-cms_default"
# ── 数据/构建目录 ──
CMS_BASE_DIR="${CMS_BASE_DIR:-/docker/tars}"
# ── 断点续跑状态文件（在 /tmp，清容器/目录不会带走它，必须单删）──
CMS_STATE_FILE="/tmp/tars-cms-deploy.state"
# ── 部署时注入的 profile / bashrc ──
CMS_PROFILES="/etc/profile.d/tars-toolchain.sh /etc/profile.d/toolchain.sh /etc/profile.d/cms-env.sh"
# ── 工具链（--keep-toolchain 可跳过）──
CMS_TOOLCHAIN_DIRS="/usr/local/go /usr/local/node /usr/local/node-v20.19.0-linux-x64"

echo "══════════════════════════════════════════════"
echo "  tars-cms 卸载脚本"
echo "  模式: $([ $DRY -eq 1 ] && echo 'DRY-RUN(只列不删)' || echo '执行')"
echo "══════════════════════════════════════════════"

# ── 1. 盘点（先列出现状）──
echo ""
echo "=== [1/8] 盘点 tars/cms 相关资源 ==="
echo "容器:"
docker ps -a --format '  {{.Names}}' 2>/dev/null | grep -E "^(tars-)" | sed 's/^/    /' || true
[ -z "$(docker ps -a --format '{{.Names}}' 2>/dev/null | grep -E '^(tars-)')" ] && echo "    (无)"
echo "镜像:"
docker images --format '  {{.Repository}}:{{.Tag}}' 2>/dev/null | grep -E "$CMS_IMAGES_PAT" | sed 's/^/    /' || true
echo "网络:"
docker network ls --format '  {{.Name}}' 2>/dev/null | grep -E "tars" | sed 's/^/    /' || true
echo "数据目录: $CMS_BASE_DIR"
[ -d "$CMS_BASE_DIR" ] && du -sh "$CMS_BASE_DIR" 2>/dev/null | sed 's/^/    /' || echo "    (不存在)"
echo "状态文件: $CMS_STATE_FILE"
[ -f "$CMS_STATE_FILE" ] && echo "    (存在)" || echo "    (不存在)"

# ── 2. 确认 ──
if [ $DRY -eq 0 ] && [ $FORCE -eq 0 ]; then
  echo ""
  read -r -p "确认卸载以上 tars/cms 资源？(y/N) " ans
  case "$ans" in
    y|Y|yes|YES) ;;
    *) echo "已取消"; exit 0 ;;
  esac
fi

# ── 3. 停容器 ──
echo ""
echo "=== [3/8] 停止 tars 容器 ==="
for c in $CMS_CTNS; do
  if docker inspect "$c" >/dev/null 2>&1; then
    if [ $DRY -eq 1 ]; then echo "    [dry] docker stop $c"; else
      docker stop "$c" >/dev/null 2>&1 && ok "stop $c"
    fi
  fi
done

# ── 4. 删容器 ──
echo ""
echo "=== [4/8] 删除 tars 容器 ==="
for c in $CMS_CTNS; do
  if docker inspect "$c" >/dev/null 2>&1; then
    if [ $DRY -eq 1 ]; then echo "    [dry] docker rm $c"; else
      docker rm "$c" >/dev/null 2>&1 && ok "rm $c"
    fi
  fi
done

# ── 5. 删数据目录（需 sudo）──
echo ""
echo "=== [5/8] 删除数据/构建目录 ($CMS_BASE_DIR) ==="
if [ -d "$CMS_BASE_DIR" ]; then
  if [ $DRY -eq 1 ]; then echo "    [dry] sudo rm -rf $CMS_BASE_DIR"; else
    $SUDO rm -rf "$CMS_BASE_DIR" 2>/dev/null && ok "rm -rf $CMS_BASE_DIR"
  fi
else
  echo "    (不存在，跳过)"
fi

# ── 6. 删网络 ──
echo ""
echo "=== [6/8] 删除 compose 网络 ==="
for n in $CMS_NETWORKS; do
  if docker network inspect "$n" >/dev/null 2>&1; then
    if [ $DRY -eq 1 ]; then echo "    [dry] docker network rm $n"; else
      docker network rm "$n" >/dev/null 2>&1 && ok "rm network $n" || warn "network $n 删除失败(可能被占用)"
    fi
  fi
done

# ── 7. 删镜像 ──
echo ""
echo "=== [7/8] 删除 tarscloud 镜像 ==="
if [ $DRY -eq 1 ]; then
  docker images --format '{{.Repository}}:{{.Tag}}' | grep -E "$CMS_IMAGES_PAT" | sed 's/^/    [dry] docker rmi /'
else
  docker images --format '{{.Repository}}:{{.Tag}}' | grep -E "$CMS_IMAGES_PAT" \
    | xargs -r docker rmi -f >/dev/null 2>&1 \
    && ok "镜像已清理" || warn "镜像清理不完整(可能有容器引用)"
fi

# ── 8. 状态文件 / profile / 工具链 / bashrc / docker 组 ──
echo ""
echo "=== [8/8] 清理状态文件 / 环境注入 / 工具链 ==="
if [ $DRY -eq 1 ]; then
  echo "    [dry] rm -f $CMS_STATE_FILE"
  echo "    [dry] rm -f $CMS_PROFILES"
  [ $KEEP_TC -eq 0 ] && echo "    [dry] rm -rf $CMS_TOOLCHAIN_DIRS"
  echo "    [dry] sed -i '/GOPROXY/d; /tars-toolchain/d; /\/usr\/local\/go/d; /\/usr\/local\/node/d' ~/.bashrc"
else
  rm -f "$CMS_STATE_FILE" && ok "rm $CMS_STATE_FILE"
  for p in $CMS_PROFILES; do
    [ -f "$p" ] && $SUDO rm -f "$p" && ok "rm $p"
  done
  if [ $KEEP_TC -eq 0 ]; then
    for d in $CMS_TOOLCHAIN_DIRS; do
      [ -d "$d" ] && $SUDO rm -rf "$d" && ok "rm -rf $d"
    done
  else
    warn "--keep-toolchain: 保留 go/node"
  fi
  # bashrc 里的 GOPROXY / PATH 注入行
  sed -i '/GOPROXY/d;/tars-toolchain/d;/\/usr\/local\/go/d;/\/usr\/local\/node/d' "$HOME/.bashrc" 2>/dev/null \
    && ok "bashrc 注入行已清理"
fi

# ── 收尾核对 ──
echo ""
echo "══════════════════════════════════════════════"
if [ $DRY -eq 1 ]; then
  echo "  DRY-RUN 完成（以上为将执行的操作，未实际删除）"
else
  echo "  卸载完成，核对:"
  echo "    tars 容器: $(docker ps -a --format '{{.Names}}' | grep -cE '^tars-' || echo 0)"
  echo "    tarscloud 镜像: $(docker images --format '{{.Repository}}' | grep -c tarscloud || echo 0)"
  echo "    tars 数据目录: $([ -d "$CMS_BASE_DIR" ] && echo '仍存在!' || echo '已删除')"
  echo "    状态文件: $([ -f "$CMS_STATE_FILE" ] && echo '仍存在!' || echo '已删除')"
fi
echo "══════════════════════════════════════════════"
