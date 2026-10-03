#!/usr/bin/env bash
# ================================================================
# n03-deploy.sh — 部署 cms.CmsServer 到 tarsnode（tars_go 服务）
# ================================================================
# 【端口规划】
#   13101  adapter (protocol=tars) —— ArticleObj + AuthObj servant
#   13102  adapter (protocol=http) —— 静态/媒体文件（可选）
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

PKG="/docker/tars/build/tars-cms/CmsServer.tgz"
TOKEN=$(grep "^TOKEN=" /docker/tars/scripts/c03-deploy-chisha.sh | cut -d'"' -f2)
API="http://127.0.0.1:3000/pages/server/api"
MYSQL="docker exec tars-mysql mysql -uroot -ptars@root.2026 db_tars"

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
     5, 'tcp -h $NODE -t 60000 -p 13101 -e 0', 100000, '',
     '$APP.$SVR.AuthObj', 50000, 20000, NOW(), 'deploy', 'tars', '')
ON DUPLICATE KEY UPDATE
    protocol='tars',
    endpoint=VALUES(endpoint);
SQL
echo "   已注册"

echo ""
echo "=== 2. 验证注册 ==="
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
echo "   server_id=$SID"

TASK_RSP=$(docker exec tars-framework curl -s -X POST "$API/add_task?ticket=$TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"serial\":true,\"items\":[{\"server_id\":\"$SID\",\"command\":\"patch_tars\",\"parameters\":{\"patch_id\":$PID}}]}")
TASK_NO=$(echo "$TASK_RSP" | python3 -c "import json,sys; print(json.load(sys.stdin).get('data',''))")
echo "   task_no=$TASK_NO"
sleep 20

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
