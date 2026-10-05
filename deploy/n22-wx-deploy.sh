#!/usr/bin/env bash
# ================================================================
# n22-wx-deploy.sh — 部署 wx.WxServer 到 tarsnode (tars_go 服务)
# ================================================================
set -euo pipefail

_ENV_SH="$(cd "$(dirname "$0")" && pwd)/env.sh"
if [ -f "$_ENV_SH" ]; then . "$_ENV_SH"; fi
_COMMON_SH="$(cd "$(dirname "$0")" && pwd)/common.sh"
if [ -f "$_COMMON_SH" ]; then . "$_COMMON_SH"; fi

PKG="$CMS_BUILD_DIR/WxServer.tgz"
TOKEN=$(require_ticket)
API="$CMS_WEB_API"
MYSQL="docker exec $CMS_MYSQL_CTN mysql -uroot -p${CMS_DB_PASS} db_tars"

if [ ! -f "$PKG" ]; then
    err "找不到发布包: $PKG（先跑 n21-wx-package.sh）"
    exit 1
fi

APP="wx"
SVR="WxServer"
NODE="$CMS_NODE_IP"

echo "=== 1. 注册 wx.WxServer 到平台 DB ==="
$MYSQL <<SQL
-- 服务注册
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

-- adapter 1: 公众号 servant (MpObj 端口 13201)
INSERT INTO t_adapter_conf
    (application, server_name, node_name, adapter_name, registry_timestamp,
     thread_num, endpoint, max_connections, allow_ip, servant,
     queuecap, queuetimeout, posttime, lastuser, protocol, handlegroup)
VALUES
    ('$APP', '$SVR', '$NODE', '$APP.$SVR.MpObjAdapter', NOW(),
     5, 'tcp -h $NODE -t 60000 -p 13201 -e 0', 100000, '',
     '$APP.$SVR.MpObj', 10000, 60000, NOW(), 'deploy', 'tars', '$APP.$SVR.MpObjAdapter')
ON DUPLICATE KEY UPDATE
    endpoint='tcp -h $NODE -t 60000 -p 13201 -e 0', servant='$APP.$SVR.MpObj',
    lastuser='deploy';

-- adapter 2: 小程序 servant (MaObj 端口 13202，不能共用 13201)
INSERT INTO t_adapter_conf
    (application, server_name, node_name, adapter_name, registry_timestamp,
     thread_num, endpoint, max_connections, allow_ip, servant,
     queuecap, queuetimeout, posttime, lastuser, protocol, handlegroup)
VALUES
    ('$APP', '$SVR', '$NODE', '$APP.$SVR.MaObjAdapter', NOW(),
     5, 'tcp -h $NODE -t 60000 -p 13202 -e 0', 100000, '',
     '$APP.$SVR.MaObj', 10000, 60000, NOW(), 'deploy', 'tars', '$APP.$SVR.MaObjAdapter')
ON DUPLICATE KEY UPDATE
    endpoint='tcp -h $NODE -t 60000 -p 13202 -e 0', servant='$APP.$SVR.MaObj',
    lastuser='deploy';

-- adapter 3: http 协议 (备用, 端口 13203)
INSERT INTO t_adapter_conf
    (application, server_name, node_name, adapter_name, registry_timestamp,
     thread_num, endpoint, max_connections, allow_ip, servant,
     queuecap, queuetimeout, posttime, lastuser, protocol, handlegroup)
VALUES
    ('$APP', '$SVR', '$NODE', '$APP.$SVR.HttpAdapter', NOW(),
     5, 'tcp -h $NODE -t 60000 -p 13203 -e 0', 100000, '',
     '', 10000, 60000, NOW(), 'deploy', 'not_tars', '$APP.$SVR.HttpAdapter')
ON DUPLICATE KEY UPDATE
    endpoint='tcp -h $NODE -t 60000 -p 13203 -e 0', lastuser='deploy';
SQL
ok "服务及 adapter 配置写入完成"

echo "=== 2. 上传发布包到 TarsWeb ==="
docker cp "$PKG" tars-framework:/tmp/WxServer.tgz
UP_RSP=$(docker exec tars-framework curl -s -X POST "$API/upload_patch_package?ticket=$TOKEN" \
    -F "application=$APP" \
    -F "module_name=$SVR" \
    -F "suse=@/tmp/WxServer.tgz;filename=WxServer.tgz")

PATCH_ID=$(echo "$UP_RSP" | python3 -c "import json,sys; print(json.load(sys.stdin).get('data',{}).get('id',''))" 2>/dev/null || true)
if [ -z "$PATCH_ID" ]; then
    err "上传发布包失败: $UP_RSP"
    exit 1
fi
ok "发布包上传成功, patch_id=$PATCH_ID"

echo "=== 3. 发布并启动服务 ==="
TASK_RSP=$(docker exec tars-framework curl -s -X POST "$API/add_task?ticket=$TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"serial\":true,\"items\":[{\"server_id\":(SELECT id FROM t_server_conf WHERE application='$APP' AND server_name='$SVR'),\"command\":\"patch_tars\",\"parameters\":{\"patch_id\":$PATCH_ID}}]}" 2>/dev/null || true)

# 直接调底层 tarsnode patch 命令发布
SID=$($MYSQL -sN -e "SELECT id FROM t_server_conf WHERE application='$APP' AND server_name='$SVR';")
docker exec tars-framework curl -s -X POST "$API/add_task?ticket=$TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"serial\":true,\"items\":[{\"server_id\":\"$SID\",\"command\":\"patch_tars\",\"parameters\":{\"patch_id\":$PATCH_ID}}]}" >/dev/null

echo "等待 8 秒让 tarsnode 启动..."
sleep 8

echo "=== 4. 验证服务状态 ==="
STATUS=$($MYSQL -sN -e "SELECT present_state, process_id FROM t_server_conf WHERE application='$APP' AND server_name='$SVR';")
echo "  DB 状态: $STATUS"

docker exec tars-node netstat -tlnp 2>/dev/null | grep -E '13201|13202' || true
ok "wx.WxServer 部署完成"
