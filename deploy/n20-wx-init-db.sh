#!/usr/bin/env bash
# ================================================================
# n20-wx-init-db.sh — 初始化微信节点数据库 (tars_wx)
# ================================================================
set -euo pipefail

_ENV_SH="$(cd "$(dirname "$0")" && pwd)/env.sh"
if [ -f "$_ENV_SH" ]; then . "$_ENV_SH"; fi
_COMMON_SH="$(cd "$(dirname "$0")" && pwd)/common.sh"
if [ -f "$_COMMON_SH" ]; then . "$_COMMON_SH"; fi

SQL_FILE="$(cd "$(dirname "$0")" && pwd)/sql/wx-init.sql"
if [ ! -f "$SQL_FILE" ]; then
    err "SQL 文件不存在: $SQL_FILE"
    exit 1
fi

echo "=== n20-wx-init-db.sh: 执行 $SQL_FILE ==="
docker exec -i "$CMS_MYSQL_CTN" mysql -uroot -p"${CMS_DB_PASS}" < "$SQL_FILE"

echo "=== 验证表创建 ==="
TABLES=$(docker exec "$CMS_MYSQL_CTN" mysql -uroot -p"${CMS_DB_PASS}" tars_wx -sN -e "SHOW TABLES;" 2>/dev/null)
echo "$TABLES" | while read -r t; do
    count=$(docker exec "$CMS_MYSQL_CTN" mysql -uroot -p"${CMS_DB_PASS}" tars_wx -sN -e "SELECT COUNT(*) FROM \`$t\`;" 2>/dev/null)
    printf "  ✔ %-20s (行数: %s)\n" "$t" "$count"
done

ok "tars_wx 数据库初始化成功"
