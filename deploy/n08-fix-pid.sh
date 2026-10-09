#!/usr/bin/env bash
# ================================================================
# n08-fix-pid.sh — tars-cms 服务 PID 同步（not_tars + tars_go 都适用）
# ================================================================
# 【根因】
#   tarsnode 启动服务时记录的 PID 来自 tars_start.sh（末尾 & 派生的子进程 PID），
#   与真实监听进程 PID 存在偏移。tars_go/tars_java 通过心跳主动上报自身 PID 掩盖；
#   not_tars 无心跳，只能靠 PID 探测，故显示 inactive。
#
# 【解法】
#   周期性将 DB process_id 同步为端口实际监听进程的 PID（幂等 + 可逆）。
#
# 【服务清单】
#   cms.CmsWeb     端口 13103
#   cms.CmsBff     端口 3103（tarsnode 托管后）
#
# 【撤销】
#   crontab -l | grep -v n08-fix-pid | crontab -
# ================================================================
set -e

# 加载部署环境变量（密码等凭据不硬编码在脚本里）
_ENV_SH="$(cd "$(dirname "$0")" && pwd)/env.sh"
if [ -f "$_ENV_SH" ]; then . "$_ENV_SH"; fi

SCRIPT_PATH="${CMS_REPO_DIR:-$(cd "$(dirname "$0")/.." && pwd)}/deploy/n08-fix-pid.sh"
CRON_LINE="* * * * * /bin/bash $SCRIPT_PATH --sync >> /tmp/n08-cms-pid.log 2>&1"

sync_service() {
    local app=$1
    local server=$2
    local port=$3

    # 从端口反查真实 PID（容器内）
    REAL_PID=$(docker exec tars-node sh -c \
        "ss -tlnp 2>/dev/null | grep ':$port' | grep -oP 'pid=\K[0-9]+' | head -1" 2>/dev/null || echo "")

    if [ -z "$REAL_PID" ]; then
        echo "$(date '+%F %T') $app.$server :$port 未监听, 跳过"
        return
    fi

    CUR=$(docker exec tars-mysql mysql -uroot -p${CMS_DB_PASS} db_tars -sN -e \
        "SELECT CONCAT(process_id,'|',present_state) FROM t_server_conf
         WHERE application='$app' AND server_name='$server';" 2>/dev/null)

    CUR_PID=$(echo "$CUR" | cut -d'|' -f1)
    CUR_STATE=$(echo "$CUR" | cut -d'|' -f2)

    # 已一致则静默返回（避免日志噪音）
    if [ "$CUR_PID" = "$REAL_PID" ] && [ "$CUR_STATE" = "active" ]; then
        return
    fi

    docker exec tars-mysql mysql -uroot -p${CMS_DB_PASS} db_tars -e \
        "UPDATE t_server_conf SET process_id='$REAL_PID', present_state='active'
         WHERE application='$app' AND server_name='$server';" 2>/dev/null

    echo "$(date '+%F %T') $app.$server PID 同步: $CUR_PID -> $REAL_PID (active)"
}

if [ "${1:-}" = "--sync" ]; then
    sync_service cms CmsWeb 13103
    sync_service cms CmsBff 3103
    exit 0
fi

# ---------------- 安装模式 ----------------
echo "=== 1. 立即同步一次 ==="
bash "$SCRIPT_PATH" --sync

echo ""
echo "=== 2. 安装 cron (每分钟) ==="
crontab -l 2>/dev/null | grep -v "n08-fix-pid" > /tmp/cron.tmp || true
echo "$CRON_LINE" >> /tmp/cron.tmp
crontab /tmp/cron.tmp
rm -f /tmp/cron.tmp
echo "  ✅ cron 已安装"

echo ""
echo "=== 3. 当前状态 ==="
crontab -l | grep n08-fix-pid | sed 's/^/  /'
docker exec tars-mysql mysql -uroot -p${CMS_DB_PASS} db_tars -e \
    "SELECT CONCAT('  ', application, '.', server_name, '  ', server_type, '  ', present_state, '  PID=', process_id)
     FROM t_server_conf WHERE application='cms';" 2>/dev/null | grep -v Warning

echo ""
echo "================================================"
echo "✅ n08 完成: PID 同步已安装"
echo "   撤销: crontab -l | grep -v n08-fix-pid | crontab -"
echo "================================================"
