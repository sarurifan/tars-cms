#!/usr/bin/env bash
# ================================================================
# n13-logrotate.sh — 日志轮转（P1-3）
# ================================================================
# 【问题】
#   Tars 服务日志无轮转，TLOG.log 已 8.1MB 且持续增长，长期运行耗尽磁盘。
#
# 【约束】
#   - 日志在容器 tars-node 内（app_log 非挂载卷）
#   - 容器内没有 logrotate 命令
#   → 用宿主机 cron + docker exec 自实现轮转（copytruncate 语义）
#
# 【策略】
#   单文件 > 50M 时：gzip 归档 → 原文件截断为 0（进程无需重启）
#   每个文件保留 7 份归档，超出删除
#
# 【用法】
#   bash deploy/n13-logrotate.sh             # 执行一次轮转（cron 调用）
#   bash deploy/n13-logrotate.sh --check     # 只看体积
#   bash deploy/n13-logrotate.sh --install   # 安装 cron（每小时）
#   bash deploy/n13-logrotate.sh --uninstall
# ================================================================
set -uo pipefail

CONTAINER="tars-node"
LOG_DIR="/usr/local/app/tars/app_log/cms"
MAX_SIZE_MB="${MAX_SIZE_MB:-50}"
KEEP="${KEEP:-7}"
SELF="${CMS_REPO_DIR:-$(cd "$(dirname "$0")/.." && pwd)}/deploy/n13-logrotate.sh"
MODE="${1:-rotate}"

check_sizes() {
  echo "════ 当前日志体积 ════"
  docker exec "$CONTAINER" sh -c "du -sh $LOG_DIR 2>/dev/null" 2>/dev/null
  docker exec "$CONTAINER" sh -c "find $LOG_DIR -name '*.log' -size +512k 2>/dev/null" | \
    while read -r f; do
      [ -z "$f" ] && continue
      sz=$(docker exec "$CONTAINER" sh -c "stat -c %s '$f' 2>/dev/null || echo 0")
      printf "  %6.1f MB  %s\n" "$(awk "BEGIN{printf \"%.1f\", $sz/1048576}")" "$f"
    done
}

rotate() {
  ts=$(date +%Y%m%d-%H%M%S)
  rotated=0

  # 收集超限文件（容器内执行；find -size 不接受小数，转 KB）
  threshold_kb=$(awk "BEGIN{printf \"%d\", $MAX_SIZE_MB*1024}")
  files=$(docker exec "$CONTAINER" sh -c \
    "find $LOG_DIR -name '*.log' -size +${threshold_kb}k 2>/dev/null")

  if [ -z "$files" ]; then
    echo "$(date '+%F %T') 无需轮转（无 >${MAX_SIZE_MB}M 文件）"
    return 0
  fi

  while IFS= read -r f; do
    [ -z "$f" ] && continue
    docker exec "$CONTAINER" sh -c \
      "gzip -c '$f' > '$f.$ts.gz' 2>/dev/null && : > '$f'" \
      && echo "  ✅ 轮转 $(basename "$f") → $(basename "$f").$ts.gz" \
      && rotated=$((rotated+1))
  done <<< "$files"

  # 清理超额归档（每个文件保留最近 KEEP 份）
  docker exec "$CONTAINER" sh -c "
    for f in \$(find $LOG_DIR -name '*.log' 2>/dev/null); do
      base=\$(basename \$f)
      cnt=\$(find $LOG_DIR -name \"\$base.*.gz\" 2>/dev/null | wc -l)
      if [ \"\$cnt\" -gt $KEEP ]; then
        find $LOG_DIR -name \"\$base.*.gz\" 2>/dev/null | sort | head -n \$((cnt - $KEEP)) | xargs -r rm -f
      fi
    done"

  echo "$(date '+%F %T') 轮转 $rotated 个文件"
}

install_cron() {
  (crontab -l 2>/dev/null | grep -v n13-logrotate
   echo "0 * * * * $SELF >> ${CMS_REPO_DIR:-$(cd "$(dirname "$0")/.." && pwd)}/backup/logrotate.log 2>&1") | crontab -
  echo "  ✅ cron 已安装（每小时）"
  crontab -l | grep n13-logrotate
}

uninstall_cron() {
  crontab -l 2>/dev/null | grep -v n13-logrotate | crontab -
  echo "  ✅ cron 已卸载"
}

case "$MODE" in
  --check)     check_sizes ;;
  --install)   install_cron ;;
  --uninstall) uninstall_cron ;;
  rotate)      rotate ;;
  *) echo "用法: $0 [--check|--install|--uninstall]"; exit 1 ;;
esac
