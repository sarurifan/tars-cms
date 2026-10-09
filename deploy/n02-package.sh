#!/usr/bin/env bash
# n02-package.sh — 打包 cms 服务为发布包 tgz（tarsnode 可部署）
#
# 包内结构（必须与 AuthServer.tgz 一致）：
#   CmsServer/
#   ├── CmsServer            # 二进制
#   ├── tars_start.sh        # 启动脚本（带 & + 输出重定向）
#   └── tars_stop.sh         # 停止脚本
set -euo pipefail

# 加载部署环境变量 + 公共库（BUILD_DIR/TOKEN/IP 统一走 env.sh/common.sh）
_ENV_SH="$(cd "$(dirname "$0")" && pwd)/env.sh"
if [ -f "$_ENV_SH" ]; then . "$_ENV_SH"; fi
_COMMON_SH="$(cd "$(dirname "$0")" && pwd)/common.sh"
if [ -f "$_COMMON_SH" ]; then . "$_COMMON_SH"; fi

SRC="$(cd "$(dirname "$0")/../cms" && pwd)"
BUILD_DIR="$CMS_BUILD_DIR"
PKG_DIR="$BUILD_DIR/pkg/CmsServer"
BIN_NAME="CmsServer"
PKG_NAME="CmsServer.tgz"

echo "=== n02-package.sh ==="
echo "  源码: $SRC"
echo "  输出: $BUILD_DIR"

rm -rf "$BUILD_DIR"
mkdir -p "$PKG_DIR"
cd "$SRC"

# 1. 编译
echo ""
echo "[1/4] 编译二进制..."
CGO_ENABLED=0 go build -ldflags="-s -w" -o "$PKG_DIR/$BIN_NAME" .
ls -la "$PKG_DIR/$BIN_NAME" || true   # 展示用途，避免环境级 ls 退出码触发 set -e

# 2. 生成 tars_start.sh / tars_stop.sh（复用 AuthServer 三铁律模板）
echo ""
echo "[2/4] 生成启动/停止脚本 ..."

cat > "$PKG_DIR/tars_start.sh" <<'EOF'
#!/bin/sh
. /etc/profile
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/app/tars/tarsnode/data/cms.CmsServer/bin/:/usr/local/app/tars/tarsnode/data/lib/
trap 'exit' SIGTERM SIGINT

# 数据库密码从环境注入（不硬编码进仓库）
# 优先级: 已有的 CMS_DB_PASS > /etc/profile.d/cms-env.sh > 部署机环境变量
if [ -z "$CMS_DB_PASS" ] && [ -f /etc/profile.d/cms-env.sh ]; then
    . /etc/profile.d/cms-env.sh
fi
export CMS_DB_PASS

# 铁律1: 带 & 后台启动（tarsnode 等 stdout EOF，不带 & 会超 activating-timeout=10s 反复重启）
# 铁律2: 输出重定向到独立日志（继承 stdout 会写满 pipe buffer → HTTP Empty reply）
# 铁律3: 文件必须存在于包内
LOG=/usr/local/app/tars/app_log/cms/CmsServer/cms.log
mkdir -p $(dirname $LOG)

/usr/local/app/tars/tarsnode/data/cms.CmsServer/bin/CmsServer \
    --config=/usr/local/app/tars/tarsnode/data/cms.CmsServer/conf/cms.CmsServer.config.conf \
    >> $LOG 2>&1 &
EOF

cat > "$PKG_DIR/tars_stop.sh" <<'EOF'
#!/bin/sh
killall -9 CmsServer 2>/dev/null
exit 0
EOF

chmod +x "$PKG_DIR/tars_start.sh" "$PKG_DIR/tars_stop.sh"

# 3. 打 tgz 包（顶层目录就是 CmsServer/）
echo ""
echo "[3/4] 打包 $PKG_NAME ..."
tar czf "$BUILD_DIR/$PKG_NAME" -C "$BUILD_DIR/pkg" CmsServer
ls -la "$BUILD_DIR/$PKG_NAME" || true  # 展示用途

echo ""
echo "[4/4] 包内容："
tar tzf "$BUILD_DIR/$PKG_NAME"

echo ""
echo "✅ 发布包就绪: $BUILD_DIR/$PKG_NAME"
