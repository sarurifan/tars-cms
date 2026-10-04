#!/usr/bin/env bash
# ================================================================
# n12-health-monitor.sh — 最小健康巡检（P2-1 监控告警）
# ================================================================
# 【用途】
#   定时探测关键端点，异常时写告警日志 + 可选通知。
#   轻量方案：无 Prometheus/Grafana，仅靠 cron 巡检。
#
# 【巡检项】
#   1. 网关 8200 可达
#   2. 首页 / 200
#   3. 后台 /admin/ 200
#   4. API /api/cms/home 200
#   5. BFF /health 200
#   6. 三服务 present_state=active（查 DB）
#
# 【用法】
#   bash deploy/n12-health-monitor.sh          # 巡检一次，正常退出码 0
#   bash deploy/n12-health-monitor.sh --install # 安装 cron（每 5 分钟）
#   bash deploy/n12-health-monitor.sh --uninstall # 卸载 cron
#
# 【告警】
#   连续 3 次异常才写告警（避免重启窗口误报）
#   告警日志: /root/tars-cms/backup/health-alerts.log
# ================================================================
set -uo pipefail

GW="${CMS_GATEWAY:-http://192.168.1.95:8200}"
# 加载部署环境变量（DBPASS 不硬编码，从 env.sh 读；兜底空密码用于仅健康检查场景）
_ENV_SH="$(cd "$(dirname "$0")" && pwd)/env.sh"
[ -f "$_ENV_SH" ] && . "$_ENV_SH"
DBPASS="${CMS_DB_PASS:-}"
ALERT_LOG="/root/tars-cms/backup/health-alerts.log"
FAIL_COUNT_FILE="/tmp/cms-health-fail-count"
HEALTH_LOG="/root/tars-cms/backup/health-check.log"

mode="${1:-check}"

install_cron() {
  (crontab -l 2>/dev/null | grep -v n12-health-monitor
   echo "*/5 * * * * /root/tars-cms/deploy/n12-health-monitor.sh >> $HEALTH_LOG 2>&1") | crontab -
  echo "✅ cron 已安装（每 5 分钟）"
  crontab -l | grep n12-health-monitor
}

uninstall_cron() {
  crontab -l 2>/dev/null | grep -v n12-health-monitor | crontab -
  echo "✅ cron 已卸载"
}

[[ "$mode" == "--install" ]] && { install_cron; exit 0; }
[[ "$mode" == "--uninstall" ]] && { uninstall_cron; exit 0; }

# ── 巡检 ──
problems=()

check_http() {
  local name="$1" url="$2" code
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 -H "Host: cms" "$url" 2>/dev/null || echo 000)
  if [[ "$code" != "200" ]]; then
    problems+=("$name → HTTP $code")
    return 1
  fi
  return 0
}

check_http "网关首页"      "$GW/"
check_http "后台页"        "$GW/admin/"
check_http "API 首页"      "$GW/api/cms/home?tenantId=1"
check_http "BFF 健康检查"  "$GW/health"

# 三服务状态
states=$(docker exec tars-mysql mysql -uroot -p"$DBPASS" db_tars -sN -e \
  "SELECT server_name, present_state FROM t_server_conf WHERE application='cms';" 2>/dev/null)
while IFS=$'\t' read -r svc st; do
  [[ -z "$svc" ]] && continue
  if [[ "$st" != "active" ]]; then
    problems+=("服务 $svc → $st")
  fi
done <<< "$states"

# ── 判定 ──
ts=$(date '+%F %T')
if [[ ${#problems[@]} -eq 0 ]]; then
  echo "$ts OK"
  rm -f "$FAIL_COUNT_FILE"
  exit 0
fi

# 连续失败计数
count=$(( $(cat "$FAIL_COUNT_FILE" 2>/dev/null || echo 0) + 1 ))
echo "$count" > "$FAIL_COUNT_FILE"
echo "$ts FAIL($count): ${problems[*]}"

# 连续 3 次才告警
if [[ "$count" -ge 3 ]]; then
  {
    echo "[$ts] ⚠️  tars-cms 健康告警（连续 $count 次失败）"
    for p in "${problems[@]}"; do echo "  - $p"; done
    echo ""
  } >> "$ALERT_LOG"
  echo "$ts ALERT: ${problems[*]}"
  # 可选: 在此加通知渠道（钉钉/邮件/Telegram）
fi
exit 1
