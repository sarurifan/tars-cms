#!/usr/bin/env bash
# ================================================================
# n23-wx-bff.sh — 部署 wx.WxBff 到 tarsnode (not_tars 模式, 端口 3203)
# ================================================================
set -euo pipefail

_ENV_SH="$(cd "$(dirname "$0")" && pwd)/env.sh"
if [ -f "$_ENV_SH" ]; then . "$_ENV_SH"; fi
_COMMON_SH="$(cd "$(dirname "$0")" && pwd)/common.sh"
if [ -f "$_COMMON_SH" ]; then . "$_COMMON_SH"; fi

SRC="$(cd "$(dirname "$0")/../gateway/wx-bff" && pwd)"
BUILD_DIR="$CMS_BUILD_DIR"
PKG_DIR="$BUILD_DIR/pkg/WxBff"
BIN_NAME="WxBff"
PKG_NAME="WxBff.tgz"
TOKEN=$(require_ticket)
API="$CMS_WEB_API"
MYSQL="docker exec -i $CMS_MYSQL_CTN mysql -uroot -p${CMS_DB_PASS} db_tars"

# 坑3：发布前先确保 tars-node 容器里有 /etc/profile.d/cms-env.sh
# （下方 tars_start.sh 里 source 它取 CMS_DB_PASS，全新机上缺失则服务起不来）
init_node_env

echo "=== n23-wx-bff.sh: 打包 + 部署 wx.WxBff (端口 3203) ==="
rm -rf "$PKG_DIR"
mkdir -p "$PKG_DIR"

echo "1. 静态编译..."
cd "$SRC"
CGO_ENABLED=0 go build -ldflags="-s -w" -o "$PKG_DIR/$BIN_NAME" .

echo "2. 生成启动脚本..."
cat << 'EOF' > "$PKG_DIR/tars_start.sh"
#!/bin/bash
DIR=$(cd $(dirname $0); pwd)

LOG=/usr/local/app/tars/app_log/wx/WxBff/wxbff.log
mkdir -p $(dirname $LOG)

if [ -f /etc/profile.d/cms-env.sh ]; then
    . /etc/profile.d/cms-env.sh
fi
export CMS_DB_PASS

/usr/local/app/tars/tarsnode/data/wx.WxBff/bin/WxBff \
    --config=/usr/local/app/tars/tarsnode/data/wx.WxBff/conf/wx.WxBff.config.conf \
    >> $LOG 2>&1 &

echo $! > /usr/local/app/tars/tarsnode/data/wx.WxBff/bin/WxBff.pid
EOF

cat << 'EOF' > "$PKG_DIR/tars_stop.sh"
#!/bin/bash
PID_FILE=/usr/local/app/tars/tarsnode/data/wx.WxBff/bin/WxBff.pid
if [ -f "$PID_FILE" ]; then
    kill $(cat $PID_FILE) 2>/dev/null || true
    rm -f $PID_FILE
fi
pkill -f "/bin/WxBff" 2>/dev/null || true
EOF

chmod +x "$PKG_DIR/tars_start.sh" "$PKG_DIR/tars_stop.sh" "$PKG_DIR/$BIN_NAME"

echo "3. 打包..."
cd "$PKG_DIR"
tar czf "$BUILD_DIR/$PKG_NAME" *
PKG="$BUILD_DIR/$PKG_NAME"

echo "4. 注册 wx.WxBff (not_tars, tars_cpp 伪装) 到平台 DB..."
APP="wx"
SVR="WxBff"
NODE="$CMS_NODE_IP"

$MYSQL <<SQL
INSERT INTO t_server_conf
    (application, server_name, node_group, node_name, base_path, exe_path,
     template_name, bak_flag, setting_state, present_state, server_type,
     posttime, lastuser)
VALUES
    ('$APP', '$SVR', '', '$NODE', '', '', 'tars.default', 0,
     'active', 'setting', 'tars_cpp', NOW(), 'deploy')
ON DUPLICATE KEY UPDATE
    server_type='tars_cpp', setting_state='active', lastuser='deploy',
    present_state='setting';

INSERT INTO t_adapter_conf
    (application, server_name, node_name, adapter_name, registry_timestamp,
     thread_num, endpoint, max_connections, allow_ip, servant,
     queuecap, queuetimeout, posttime, lastuser, protocol, handlegroup)
VALUES
    ('$APP', '$SVR', '$NODE', '$APP.$SVR.Adapter', NOW(),
     5, 'tcp -h $NODE -t 60000 -p 3203 -e 0', 100000, '',
     '', 10000, 60000, NOW(), 'deploy', 'not_tars', '$APP.$SVR.Adapter')
ON DUPLICATE KEY UPDATE
    endpoint='tcp -h $NODE -t 60000 -p 3203 -e 0', lastuser='deploy';
SQL

echo "5. 上传发布包..."
docker cp "$PKG" tars-framework:/tmp/WxBff.tgz
UP_RSP=$(docker exec tars-framework curl -s -X POST "$API/upload_patch_package?ticket=$TOKEN" \
    -F "application=$APP" \
    -F "module_name=$SVR" \
    -F "suse=@/tmp/WxBff.tgz;filename=WxBff.tgz")
PATCH_ID=$(echo "$UP_RSP" | python3 -c "import json,sys; print(json.load(sys.stdin).get('data',{}).get('id',''))" 2>/dev/null || true)
if [ -z "$PATCH_ID" ]; then
    err "上传失败: $UP_RSP"
    exit 1
fi
ok "发布包上传成功, patch_id=$PATCH_ID"

echo "6. 发布启动..."
SID=$($MYSQL -sN -e "SELECT id FROM t_server_conf WHERE application='$APP' AND server_name='$SVR';")
docker exec tars-framework curl -s -X POST "$API/add_task?ticket=$TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"serial\":true,\"items\":[{\"server_id\":\"$SID\",\"command\":\"patch_tars\",\"parameters\":{\"patch_id\":$PATCH_ID}}]}" >/dev/null

echo "等待 8 秒..."
sleep 8

# 同步 PID (not_tars 模式必备)
REAL_PID=$(docker exec tars-node pgrep -f "/bin/WxBff" | head -1 || true)
if [ -n "$REAL_PID" ]; then
    $MYSQL -e "UPDATE t_server_conf SET present_state='active', process_id=$REAL_PID WHERE application='$APP' AND server_name='$SVR';" >/dev/null
fi

echo "=== 验证 ==="
STATUS=$($MYSQL -sN -e "SELECT present_state, process_id FROM t_server_conf WHERE application='$APP' AND server_name='$SVR';")
echo "  DB 状态: $STATUS"
docker exec tars-node netstat -tlnp 2>/dev/null | grep 3203 || true
ok "wx.WxBff 部署完成"
