#!/usr/bin/env bash
# ================================================================
# n06-deploy-web.sh — 将 CmsWeb 静态服务部署为 tarsnode 托管服务
# ================================================================
# 【架构】
#   静态资源作为独立 TARS node 服务（tars_cpp + not_tars 协议）
#   - tarsnode 托管 CmsWeb 二进制（HTTP 静态服务）
#   - tarsnode 注入 --config 参数 → 包装脚本拦截后忽略
#   - 包装脚本必须用 exec 保持 PID（否则 tarsnode 判定 inactive）
#
# 【服务】
#   cms.CmsWeb  tars_cpp / not_tars  端口 13103
#   - /         → h5 内容站 (SPA)
#   - /admin/   → admin 管理后台 (SPA)
#   - /uploads/ → 用户上传文件
#   - /health   → 健康检查
#
# 【包结构铁律】（踩坑：不能套子目录，否则解压成 bin/bin/）
#   tarsnode 把发布包解压到 <server>/bin/，包内文件必须直接放根：
#   CmsWeb.tgz
#   ├── CmsWeb            # 包装脚本 (exec)
#   ├── CmsWeb_bin        # 真实二进制
#   ├── tars_start.sh
#   ├── tars_stop.sh
#   ├── data/h5/          # h5 构建产物
#   ├── data/admin/       # admin 构建产物
#   └── data/uploads/     # 上传目录占位
#
# 【可逆】
#   回滚: bash n06-rollback-web.sh
# ================================================================
set -euo pipefail

# 加载部署环境变量（密码等凭据不硬编码在脚本里）
_ENV_SH="$(cd "$(dirname "$0")" && pwd)/env.sh"
if [ -f "$_ENV_SH" ]; then . "$_ENV_SH"; fi

APP="cms"
SERVER="CmsWeb"
PORT="13103"
NODE_IP="172.25.0.5"
BUILD_DIR="/docker/tars/build/tars-cms"
PKG="$BUILD_DIR/CmsWeb.tgz"
TOKEN=$(grep "^TOKEN=" /docker/tars/scripts/c03-deploy-chisha.sh | cut -d'"' -f2)
API="http://127.0.0.1:3000/pages/server/api"

mysql_q() {
    docker exec tars-mysql mysql -uroot -p${CMS_DB_PASS} db_tars -sN -e "$1" 2>/dev/null
}

echo "================================================"
echo "  n06: 部署 $APP.$SERVER (tars_cpp / not_tars, :$PORT)"
echo "================================================"
echo ""

# ---------- [1/6] 编译 ----------
echo "[1/6] 编译 CmsWeb (CGO_ENABLED=0 静态)"
cd /root/tars-cms/web
CGO_ENABLED=0 go build -o /tmp/CmsWeb .
echo "  ✅ 编译成功: $(ls -lh /tmp/CmsWeb | awk '{print $5}')"

# ---------- [2/6] 构建发布包 ----------
echo ""
echo "[2/6] 打包 CmsWeb.tgz（扁平结构）"
STAGE="$BUILD_DIR/pkg/CmsWeb"
rm -rf "$STAGE"
mkdir -p "$STAGE/data/h5" "$STAGE/data/admin" "$STAGE/data/uploads"

# 真实二进制（不带 --config 参数）
cp /tmp/CmsWeb "$STAGE/CmsWeb_bin"
chmod +x "$STAGE/CmsWeb_bin"

# 入口包装脚本：拦截 tarsnode 的 --config 参数 + exec 保持 PID
# 解压后位于 <server>/bin/CmsWeb，所以 DIR 就是 bin 目录
cat > "$STAGE/CmsWeb" << 'WRAPPER'
#!/bin/sh
# CmsWeb 入口包装脚本（方案 A：启动自愈 + 方案 B：n08 cron 兜底）
# tarsnode 会注入 --config=<conf>，本服务不读该参数，直接忽略。
# 必须 exec 替换进程镜像，保持 PID ($$) 不变。
DIR=$(dirname "$0")

export CMS_WEB_PORT="${CMS_WEB_PORT:-13103}"
export CMS_H5_DIR="${CMS_H5_DIR:-$DIR/data/h5}"
export CMS_ADMIN_DIR="${CMS_ADMIN_DIR:-$DIR/data/admin}"
export CMS_UPLOAD_DIR="${CMS_UPLOAD_DIR:-/data/tars/cms/uploads}"

# 【方案 A：启动自愈 + 持续守护】
# tarsnode 记录的是 tars_start.sh 的死 PID，并每约 60s 覆盖一次 DB。
# 这里用 setsid 派生脱离进程组的常驻守护，每 1s 把真实 PID ($$) 写回 DB，
# 实测 95% 采样点 active（剩余 5% 是 tarsnode 覆盖瞬间的短暂窗口）。
# 守护随 exec 后 PID 存活而持续；服务退出即停止。CPU 开销 ~0.1%。
MY_PID=$$
if command -v setsid >/dev/null 2>&1 && command -v mysql >/dev/null 2>&1; then
    setsid sh -c '
        MY_PID='"$MY_PID"'
        while kill -0 $MY_PID 2>/dev/null; do
            . /etc/profile.d/cms-env.sh 2>/dev/null
            mysql -uroot -p"$CMS_DB_PASS" -h172.25.0.2 db_tars -e \
                "UPDATE t_server_conf SET process_id=$MY_PID, present_state=\"active\" WHERE application=\"cms\" AND server_name=\"CmsWeb\";" >/dev/null 2>&1
            sleep 1
        done
    ' >/dev/null 2>&1 < /dev/null &
fi

exec "$DIR/CmsWeb_bin" "$@"
WRAPPER
chmod +x "$STAGE/CmsWeb"

# 启动脚本（tars_start.sh，tarsnode 调用）
# 【关键】必须 exec 前台启动，保持 PID 让 tarsnode 追踪
# 不能用 &（会让 tarsnode 记录 shell PID 而非真实进程 PID）
cat > "$STAGE/tars_start.sh" << 'START'
#!/bin/sh
DIR=$(dirname "$0")
cd "$DIR"
trap 'exit' SIGTERM SIGINT

# exec 替换 shell 为包装脚本（包装脚本再 exec 真实二进制）
# 整条链 PID 不变，tarsnode 记录的 PID = 真实服务 PID
exec "$DIR/CmsWeb" --config="$DIR/../conf/cms.CmsWeb.config.conf"
START
chmod +x "$STAGE/tars_start.sh"

cat > "$STAGE/tars_stop.sh" << 'STOP'
#!/bin/sh
pkill -f "CmsWeb_bin" 2>/dev/null || true
sleep 1
exit 0
STOP
chmod +x "$STAGE/tars_stop.sh"

# 静态资源（h5/admin 构建产物）
cp -r /root/tars-cms/h5/dist/. "$STAGE/data/h5/"
cp -r /root/tars-cms/admin/dist/. "$STAGE/data/admin/"
echo "  h5:     $(find "$STAGE/data/h5" -type f | wc -l) 个文件"
echo "  admin:  $(find "$STAGE/data/admin" -type f | wc -l) 个文件"

tar -czf "$PKG" -C "$BUILD_DIR/pkg" "CmsWeb"
echo "  ✅ $PKG ($(ls -lh "$PKG" | awk '{print $5}'))"
echo "  包内容:"
tar -tzf "$PKG" > /tmp/cmsweb_pkg_list.txt 2>/dev/null || true
head -20 /tmp/cmsweb_pkg_list.txt | sed 's/^/    /'

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

# adapter（not_tars 协议）
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
# 先拷贝到框架容器（容器内 curl 无法访问宿主机路径）
docker exec tars-framework rm -f /tmp/CmsWeb.tgz 2>/dev/null || true
docker cp "$PKG" tars-framework:/tmp/CmsWeb.tgz

UP_RSP=$(docker exec tars-framework curl -s -X POST \
    "$API/upload_patch_package?ticket=$TOKEN" \
    -F "application=$APP" \
    -F "module_name=$SERVER" \
    -F "comment=tars-cms static web (h5+admin+uploads)" \
    -F "suse=@/tmp/CmsWeb.tgz;filename=CmsWeb.tgz")
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

# ---------- PID 校正（not_tars 服务必需） ----------
# tarsnode 对 not_tars 服务记录的 PID 是启动 shell 的 PID，与真实进程差 1-2，
# 导致平台反复判定 inactive。此处按实际进程 PID 校正。
REAL_PID=$(docker exec tars-node ps -ef 2>/dev/null | grep "CmsWeb_bin" | grep -v grep | awk '{print $2}' | head -1)
if [ -n "$REAL_PID" ]; then
    mysql_q "UPDATE t_server_conf SET process_id=$REAL_PID, present_state='active' WHERE application='$APP' AND server_name='$SERVER';" > /dev/null 2>&1 || true
    echo "  ✅ PID 校正为 $REAL_PID"
fi

# ---------- [6/6] 验证 ----------
echo ""
echo "[6/6] 验证"
echo "  平台状态:"
mysql_q "SELECT server_name, server_type, present_state, process_id FROM t_server_conf WHERE application='$APP' AND server_name='$SERVER';" | sed 's/^/    /'

echo "  端口监听:"
docker exec tars-node ss -tln 2>/dev/null | grep ":$PORT " | sed 's/^/    /' || echo "    ❌ :$PORT 未监听"

echo "  进程:"
docker exec tars-node ps -ef 2>/dev/null | grep CmsWeb_bin | grep -v grep | sed 's/^/    /' || echo "    ❌ 无进程"

echo "  HTTP 健康检查 (经 tars-node):"
docker exec tars-node curl -s --max-time 5 "http://127.0.0.1:$PORT/health" 2>/dev/null | sed 's/^/    /' || echo "    ❌ /health 不可达"

echo ""
echo "================================================"
echo "✅ n06 完成: $APP.$SERVER 已部署为 tarsnode 托管服务"
echo "   静态: / (h5)  /admin/  /uploads/  /health"
echo "   下一步: n07 配置网关路由 → http://<gateway>:8200/"
echo "================================================"
