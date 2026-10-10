#!/usr/bin/env bash
# ================================================================
# n09-deploy-bff.sh — 将 cms BFF(3103) 部署为 tarsnode 托管服务
# ================================================================
# 【架构】
#   BFF (HTTP → TARS RPC) 作为独立 TARS node 服务
#   - tars_cpp + not_tars 协议，端口 3103
#   - 容器内直接连接 cms.CmsServer (172.25.0.5:13101/13102)
#   - 上传目录 /data/tars/cms/uploads（与 CmsWeb 共享）
#
# 【包结构】（仿照 n06，扁平结构，避免 bin/bin 陷阱）
#   CmsBff.tgz
#   ├── CmsBff            # 包装脚本 (exec)
#   ├── CmsBff_bin        # 真实二进制
#   ├── tars_start.sh
#   └── tars_stop.sh
#
# 【依赖】
#   1. gateway/bff 源码
#   2. cms.CmsServer 已在 13101/13102 active
#
# 【可逆】
#   回滚: bash n10-rollback-bff.sh
# ================================================================
set -euo pipefail

# 加载部署环境变量（密码等凭据不硬编码在脚本里）
_ENV_SH="$(cd "$(dirname "$0")" && pwd)/env.sh"
if [ -f "$_ENV_SH" ]; then . "$_ENV_SH"; fi
_COMMON_SH="$(cd "$(dirname "$0")" && pwd)/common.sh"
if [ -f "$_COMMON_SH" ]; then . "$_COMMON_SH"; fi

APP="cms"
SERVER="CmsBff"
PORT="3103"
NODE_IP="$CMS_NODE_IP"
BUILD_DIR="$CMS_BUILD_DIR"
PKG="$BUILD_DIR/CmsBff.tgz"
TOKEN=$(require_ticket)
API="http://127.0.0.1:3000/pages/server/api"

# 坑3：发布前先确保 tars-node 容器里有 /etc/profile.d/cms-env.sh
# （CmsBff 包装脚本的 PID 守护靠它取 CMS_DB_PASS，全新机上缺失）
init_node_env

mysql_q() {
    docker exec tars-mysql mysql -uroot -p${CMS_DB_PASS} db_tars -sN -e "$1" 2>/dev/null
}

echo "================================================"
echo "  n09: 部署 $APP.$SERVER (tars_cpp / not_tars, :$PORT)"
echo "================================================"
echo ""

# ---------- [1/6] 编译 ----------
echo "[1/6] 编译 BFF (CGO_ENABLED=0 静态)"
cd "$CMS_REPO_DIR/gateway/bff"
CGO_ENABLED=0 go build -o /tmp/CmsBff .
echo "  ✅ 编译成功: $(ls -lh /tmp/CmsBff | awk '{print $5}')"

# ---------- [2/6] 构建发布包 ----------
echo ""
echo "[2/6] 打包 CmsBff.tgz（扁平结构）"
STAGE="$BUILD_DIR/pkg/CmsBff"
rm -rf "$STAGE"
mkdir -p "$STAGE"

cp /tmp/CmsBff "$STAGE/CmsBff_bin"
chmod +x "$STAGE/CmsBff_bin"

# 入口包装脚本：拦截 --config + exec 保持 PID
cat > "$STAGE/CmsBff" << 'WRAPPER'
#!/bin/sh
# CmsBff 入口包装脚本（方案 A：启动自愈 + 方案 B：n08 cron 兜底）
# tarsnode 注入 --config=<conf>，本服务不读该参数，直接忽略。
# 必须 exec 替换进程镜像，保持 PID ($$) 不变。
DIR=$(dirname "$0")

export PORT="${PORT:-3103}"
export CMS_UPLOAD_DIR="${CMS_UPLOAD_DIR:-/data/tars/cms/uploads}"

# 【方案 A：启动自愈 + 持续守护】
# tarsnode 记录的是 tars_start.sh 的死 PID，并每约 60s 覆盖一次 DB。
# setsid 派生常驻守护，每 1s 把真实 PID ($$) 写回 DB（实测 95% active）。
MY_PID=$$
if command -v setsid >/dev/null 2>&1 && command -v mysql >/dev/null 2>&1; then
    setsid sh -c '
        MY_PID='"$MY_PID"'
        while kill -0 $MY_PID 2>/dev/null; do
            . /etc/profile.d/cms-env.sh 2>/dev/null
            mysql -uroot -p"$CMS_DB_PASS" -h172.25.0.2 db_tars -e \
                "UPDATE t_server_conf SET process_id=$MY_PID, present_state=\"active\" WHERE application=\"cms\" AND server_name=\"CmsBff\";" >/dev/null 2>&1
            sleep 1
        done
    ' >/dev/null 2>&1 < /dev/null &
fi

exec "$DIR/CmsBff_bin" "$@"
WRAPPER
chmod +x "$STAGE/CmsBff"

# 启动脚本（exec 前台，保持 PID）
cat > "$STAGE/tars_start.sh" << 'START'
#!/bin/sh
DIR=$(dirname "$0")
cd "$DIR"
trap 'exit' SIGTERM SIGINT

exec "$DIR/CmsBff" --config="$DIR/../conf/cms.CmsBff.config.conf"
START
chmod +x "$STAGE/tars_start.sh"

cat > "$STAGE/tars_stop.sh" << 'STOP'
#!/bin/sh
pkill -f "CmsBff_bin" 2>/dev/null || true
sleep 1
exit 0
STOP
chmod +x "$STAGE/tars_stop.sh"

tar -czf "$PKG" -C "$BUILD_DIR/pkg" "CmsBff"
echo "  ✅ $PKG ($(ls -lh "$PKG" | awk '{print $5}'))"
echo "  包内容:"
tar -tzf "$PKG" > /tmp/cmsbff_pkg_list.txt 2>/dev/null || true
head -8 /tmp/cmsbff_pkg_list.txt | sed 's/^/    /'

# ---------- [3/6] 注册服务 ----------
echo ""
echo "[3/6] 注册 t_server_conf + t_adapter_conf"

EXISTING=$(mysql_q "SELECT id FROM t_server_conf WHERE application='$APP' AND server_name='$SERVER';")
if [ -n "$EXISTING" ]; then
    echo "  服务已存在 (id=$EXISTING)，跳过注册"
    SERVER_ID="$EXISTING"
else
    mysql_q "INSERT INTO t_server_conf
        (application, server_name, node_group, node_name, base_path, exe_path,
         template_name, bak_flag, setting_state, present_state, server_type,
         posttime, lastuser)
    VALUES
        ('$APP', '$SERVER', '', '$NODE_IP', '', '', 'tars.default', 0,
         'active', 'setting', 'tars_cpp', NOW(), 'deploy');" || true
    SERVER_ID=$(mysql_q "SELECT id FROM t_server_conf WHERE application='$APP' AND server_name='$SERVER';")
    echo "  ✅ t_server_conf 注册成功 (id=$SERVER_ID)"
fi

# adapter（not_tars 协议，3103）
ADAPTER_EXISTING=$(mysql_q "SELECT id FROM t_adapter_conf WHERE application='$APP' AND server_name='$SERVER' AND adapter_name='$APP.$SERVER.Adapter';")
if [ -z "$ADAPTER_EXISTING" ]; then
    mysql_q "INSERT INTO t_adapter_conf
        (application, server_name, node_name, adapter_name, registry_timestamp,
         thread_num, endpoint, max_connections, allow_ip, servant,
         queuecap, queuetimeout, posttime, lastuser, protocol, handlegroup)
    VALUES
        ('$APP', '$SERVER', '$NODE_IP', '$APP.$SERVER.Adapter', NOW(),
         5, 'tcp -h $NODE_IP -t 60000 -p $PORT -e 0', 100000, '',
         '$APP.$SERVER.$SERVER', 50000, 20000, NOW(), 'deploy', 'not_tars', '')
    ON DUPLICATE KEY UPDATE protocol='not_tars', endpoint=VALUES(endpoint);" || true
    echo "  ✅ t_adapter_conf 注册成功 (not_tars, :$PORT)"
else
    echo "  adapter 已存在 (id=$ADAPTER_EXISTING)"
fi

# ---------- [4/6] 上传发布包 ----------
echo ""
echo "[4/6] 上传发布包"
docker exec tars-framework rm -f /tmp/CmsBff.tgz 2>/dev/null || true
docker cp "$PKG" tars-framework:/tmp/CmsBff.tgz

UP_RSP=$(docker exec tars-framework curl -s -X POST \
    "$API/upload_patch_package?ticket=$TOKEN" \
    -F "application=$APP" \
    -F "module_name=$SERVER" \
    -F "comment=tars-cms BFF (HTTP->TARS RPC)" \
    -F "suse=@/tmp/CmsBff.tgz;filename=CmsBff.tgz")
echo "  上传响应: $(echo "$UP_RSP" | head -c 300)"
PATCH_ID=$(echo "$UP_RSP" | python3 -c "import json,sys; print(json.load(sys.stdin).get('data',{}).get('id',''))" 2>/dev/null || echo "")
echo "  patch_id=$PATCH_ID"

# ---------- [5/6] 发布 + 启动 ----------
echo ""
echo "[5/6] 发布并启动"
TASK_RSP=$(docker exec tars-framework curl -s -X POST \
    "$API/add_task?ticket=$TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"serial\":true,\"items\":[{\"server_id\":\"$SERVER_ID\",\"command\":\"patch_tars\",\"parameters\":{\"patch_id\":$PATCH_ID}}]}")
TASK_NO=$(echo "$TASK_RSP" | python3 -c "import json,sys; print(json.load(sys.stdin).get('data',''))" 2>/dev/null || echo "")
echo "  task_no=$TASK_NO"

echo "  等待启动 (15s)..."
sleep 15

# 坑2：patch_tars 成功不代表包解进了 bin/（全新机可能不解压），缺二进制则手动解包
if ! ensure_pkg_extracted "cms.CmsBff" "CmsBff" "CmsBff_bin"; then
    err "坑2：cms.CmsBff/bin 缺发布文件且补解失败，服务将无法启动（find server exe）" >&2
    exit 1
fi

# ---------- [6/6] 验证 ----------
echo ""
echo "[6/6] 验证"
echo "  平台状态:"
mysql_q "SELECT server_name, server_type, present_state, process_id FROM t_server_conf WHERE application='$APP' AND server_name='$SERVER';" | sed 's/^/    /'

echo "  端口监听:"
docker exec tars-node ss -tln 2>/dev/null | grep ":$PORT " | sed 's/^/    /' || echo "    ❌ :$PORT 未监听"

echo "  进程:"
docker exec tars-node ps -ef 2>/dev/null | grep CmsBff_bin | grep -v grep | sed 's/^/    /' || echo "    ❌ 无进程"

echo "  HTTP 验证 (经 tars-node):"
docker exec tars-node curl -s --max-time 5 "http://127.0.0.1:$PORT/api/cms/config?tenantId=1" 2>/dev/null | head -c 100 | sed 's/^/    /' || echo "    ❌ API 不可达"

echo ""
echo "================================================"
echo "✅ n09 完成: $APP.$SERVER 已部署为 tarsnode 托管服务"
echo "   下一步: 更新网关 /api/ 路由 → 172.25.0.5:3103"
echo "================================================"
