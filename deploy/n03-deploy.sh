#!/usr/bin/env bash
# ================================================================
# n03-deploy.sh — 部署 cms.CmsServer 到 tarsnode（tars_go 服务）
# ================================================================
# 【端口规划】
#   13101  adapter (protocol=tars) —— ArticleObj servant
#   13102  adapter (protocol=tars) —— AuthObj servant
#   （注意：两个 servant 端口必须不同，否则第二个 bind 冲突秒退）
#
# 【前提】
#   1. /root/tars-cms/deploy/sql/init.sql 已执行（n01）
#   2. /docker/tars/build/tars-cms/CmsServer.tgz 已生成（n02）
#
# 【步骤】
#   1. 注册服务到 db_tars（t_server_conf + t_adapter_conf ×2）
#   2. 上传发布包
#   3. add_task 发布 + start
#   4. 验证（平台 active + 端口监听）
# ================================================================
set -euo pipefail

# 加载部署环境变量（密码等凭据不硬编码在脚本里）
_ENV_SH="$(cd "$(dirname "$0")" && pwd)/env.sh"
if [ -f "$_ENV_SH" ]; then . "$_ENV_SH"; fi
_COMMON_SH="$(cd "$(dirname "$0")" && pwd)/common.sh"
if [ -f "$_COMMON_SH" ]; then . "$_COMMON_SH"; fi

PKG="$CMS_BUILD_DIR/CmsServer.tgz"
TOKEN=$(require_ticket)
API="http://127.0.0.1:3000/pages/server/api"
MYSQL="docker exec -i tars-mysql mysql -uroot -p${CMS_DB_PASS} db_tars"

# 坑3：发布前先把运行环境写进 tars-node 的 /etc/profile.d/cms-env.sh
# （CmsServer 的 tars_start.sh 依赖它取 CMS_DB_PASS，全新机上不存在会起不来）
init_node_env

if [ ! -f "$PKG" ]; then
    echo "❌ 找不到发布包: $PKG（先跑 n02-package.sh）" >&2
    exit 1
fi

APP="cms"
SVR="CmsServer"
NODE="172.25.0.5"

echo "=== 1. 注册服务到平台 DB ==="
$MYSQL <<SQL
-- 服务注册（幂等：有则更新，无则插入）
INSERT INTO t_server_conf
    (application, server_name, node_group, node_name, base_path, exe_path,
     template_name, bak_flag, setting_state, present_state, server_type,
     posttime, lastuser)
VALUES
    ('$APP', '$SVR', '', '$NODE', '', '', 'tars.default', 0,
     'active', 'setting', 'tars_go', NOW(), 'deploy')
ON DUPLICATE KEY UPDATE
    server_type='tars_go', setting_state='active', lastuser='deploy',
    present_state='setting';

-- adapter 1: tars 协议 servant（业务 RPC + tarsnode 探测）
INSERT INTO t_adapter_conf
    (application, server_name, node_name, adapter_name, registry_timestamp,
     thread_num, endpoint, max_connections, allow_ip, servant,
     queuecap, queuetimeout, posttime, lastuser, protocol, handlegroup)
VALUES
    ('$APP', '$SVR', '$NODE', '$APP.$SVR.ArticleObjAdapter', NOW(),
     5, 'tcp -h $NODE -t 60000 -p 13101 -e 0', 100000, '',
     '$APP.$SVR.ArticleObj', 50000, 20000, NOW(), 'deploy', 'tars', ''),
    ('$APP', '$SVR', '$NODE', '$APP.$SVR.AuthObjAdapter', NOW(),
     5, 'tcp -h $NODE -t 60000 -p 13102 -e 0', 100000, '',
     '$APP.$SVR.AuthObj', 50000, 20000, NOW(), 'deploy', 'tars', '')
ON DUPLICATE KEY UPDATE
    protocol='tars',
    endpoint=VALUES(endpoint);
SQL

echo ""
echo "=== 2. 验证注册（失败即退出，防止假成功）==="
REG_CHECK=$($MYSQL -sN -e \
    "SELECT COUNT(*) FROM t_server_conf WHERE application='$APP' AND server_name='$SVR';" 2>/dev/null)
if [ "${REG_CHECK:-0}" -ne 1 ]; then
    echo "❌ 服务注册失败：t_server_conf 无记录（application='$APP', server_name='$SVR'）" >&2
    exit 1
fi
echo "   服务已注册 ✔"
$MYSQL -e "
    SELECT id, application, server_name, server_type, setting_state, node_name
    FROM t_server_conf WHERE application='$APP' AND server_name='$SVR';
    SELECT adapter_name, protocol, endpoint
    FROM t_adapter_conf WHERE application='$APP' AND server_name='$SVR';"

echo ""
echo "=== 3. 上传发布包 ==="
docker exec tars-framework rm -f /tmp/$SVR.tgz 2>/dev/null || true
docker cp "$PKG" tars-framework:/tmp/$SVR.tgz
UP_RSP=$(docker exec tars-framework curl -s -X POST "$API/upload_patch_package?ticket=$TOKEN" \
    -F "application=$APP" -F "module_name=$SVR" \
    -F "comment=tars-cms init: ArticleObj + AuthObj servants" \
    -F "suse=@/tmp/$SVR.tgz;filename=$SVR.tgz")
echo "   上传响应: $(echo "$UP_RSP" | head -c 300)"
PID=$(echo "$UP_RSP" | python3 -c "import json,sys; print(json.load(sys.stdin).get('data',{}).get('id',''))")
echo "   patch_id=$PID"

echo ""
echo "=== 4. 发布任务 ==="
SID=$($MYSQL -sN -e \
    "SELECT id FROM t_server_conf WHERE application='$APP' AND server_name='$SVR';")
if [ -z "${SID:-}" ]; then
    echo "❌ 无法取得 server_id：t_server_conf 无记录（注册步骤失败？）" >&2
    exit 1
fi
echo "   server_id=$SID"

TASK_RSP=$(docker exec tars-framework curl -s -X POST "$API/add_task?ticket=$TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"serial\":true,\"items\":[{\"server_id\":\"$SID\",\"command\":\"patch_tars\",\"parameters\":{\"patch_id\":$PID}}]}")
TASK_NO=$(echo "$TASK_RSP" | python3 -c "import json,sys; print(json.load(sys.stdin).get('data',''))")
echo "   task_no=$TASK_NO"
sleep 20

# 坑2：patch_tars 显示成功不代表包真的解进了 bin/（全新机 tarsnode 有时不解压），
# 校验 bin/ 有二进制；没有则从 BatchPatchingLoad 缓存手动解到 bin/ 再启动。
echo "   校验 bin/ 发布文件..."
ensure_pkg_extracted "cms.CmsServer" "CmsServer" "CmsServer"

echo ""
echo "=== 5. 启动 ==="
docker exec tars-framework curl -s -X POST "$API/add_task?ticket=$TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"serial\":true,\"items\":[{\"server_id\":\"$SID\",\"command\":\"start\",\"parameters\":{}}]}" >/dev/null

echo "   等待激活 (activating-timeout=10s)..."
sleep 25

echo ""
echo "=== 6. 验证 ==="
echo "   进程:"
docker exec tars-node ps -eo pid,cmd 2>/dev/null | grep "[c]ms.CmsServer" | head -3
echo "   端口:"
docker exec tars-node ss -tlnp 2>/dev/null | grep -E "13101|13102" | awk '{print "     "$4}'

echo ""
echo "   平台状态:"
$MYSQL -e "SELECT server_name, server_type, present_state, process_id FROM t_server_conf WHERE application='$APP';"

echo ""
echo "================================================"
echo "✅ n03 完成: cms.CmsServer 已部署为 tars_go 服务"
echo "================================================"
