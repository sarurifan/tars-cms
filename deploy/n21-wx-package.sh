#!/usr/bin/env bash
# ================================================================
# n21-wx-package.sh — 打包 wx.WxServer 为发布包 (tarsnode 可部署)
# ================================================================
set -euo pipefail

_ENV_SH="$(cd "$(dirname "$0")" && pwd)/env.sh"
if [ -f "$_ENV_SH" ]; then . "$_ENV_SH"; fi
_COMMON_SH="$(cd "$(dirname "$0")" && pwd)/common.sh"
if [ -f "$_COMMON_SH" ]; then . "$_COMMON_SH"; fi

SRC="$(cd "$(dirname "$0")/../wx" && pwd)"
BUILD_DIR="$CMS_BUILD_DIR"
PKG_DIR="$BUILD_DIR/pkg/WxServer"
BIN_NAME="WxServer"
PKG_NAME="WxServer.tgz"

echo "=== n21-wx-package.sh ==="
echo "  源码: $SRC"
echo "  输出: $BUILD_DIR"

rm -rf "$PKG_DIR"
mkdir -p "$PKG_DIR"

echo "1. 静态编译 $BIN_NAME..."
cd "$SRC"
CGO_ENABLED=0 go build -ldflags="-s -w" -o "$PKG_DIR/$BIN_NAME" .

echo "2. 生成 tars_start.sh..."
cat << 'EOF' > "$PKG_DIR/tars_start.sh"
#!/bin/bash
DIR=$(cd $(dirname $0); pwd)

# 注入 DB 凭据
if [ -z "$CMS_DB_PASS" ] && [ -f /etc/profile.d/cms-env.sh ]; then
    . /etc/profile.d/cms-env.sh
fi
export CMS_DB_PASS

LOG=/usr/local/app/tars/app_log/wx/WxServer/wx.log
mkdir -p $(dirname $LOG)

/usr/local/app/tars/tarsnode/data/wx.WxServer/bin/WxServer \
    --config=/usr/local/app/tars/tarsnode/data/wx.WxServer/conf/wx.WxServer.config.conf \
    >> $LOG 2>&1 &

echo $! > /usr/local/app/tars/tarsnode/data/wx.WxServer/bin/WxServer.pid
EOF

echo "3. 生成 tars_stop.sh..."
cat << 'EOF' > "$PKG_DIR/tars_stop.sh"
#!/bin/bash
PID_FILE=/usr/local/app/tars/tarsnode/data/wx.WxServer/bin/WxServer.pid
if [ -f "$PID_FILE" ]; then
    kill $(cat $PID_FILE) 2>/dev/null || true
    rm -f $PID_FILE
fi
pkill -f "/bin/WxServer" 2>/dev/null || true
EOF

chmod +x "$PKG_DIR/tars_start.sh" "$PKG_DIR/tars_stop.sh" "$PKG_DIR/$BIN_NAME"

echo "4. 打包发布包 (扁平结构)..."
cd "$PKG_DIR"
tar czf "$BUILD_DIR/$PKG_NAME" *

echo "✔ 打包完成: $BUILD_DIR/$PKG_NAME"
ls -lh "$BUILD_DIR/$PKG_NAME" || true  # 展示用途
