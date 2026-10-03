#!/usr/bin/env bash
# n01-init-db.sh — 初始化 tars_cms 数据库（幂等，可重复执行）
set -euo pipefail

MYSQL_HOST="${CMS_DB_HOST:-172.25.0.2}"
MYSQL_PORT="${CMS_DB_PORT:-3306}"
MYSQL_USER="${CMS_DB_USER:-root}"
MYSQL_PASS="${CMS_DB_PASS:-tars@root.2026}"
SQL_FILE="$(cd "$(dirname "$0")" && pwd)/sql/init.sql"

echo "=== n01-init-db.sh ==="
echo "  目标: mysql://${MYSQL_HOST}:${MYSQL_PORT}/tars_cms"
echo "  文件: ${SQL_FILE}"

if [ ! -f "$SQL_FILE" ]; then
    echo "❌ 找不到 SQL 文件: $SQL_FILE" >&2
    exit 1
fi

# 用 tars-mysql 容器执行（tars 网络内）
docker exec -i tars-mysql mysql -u"${MYSQL_USER}" -p"${MYSQL_PASS}" \
    --default-character-set=utf8mb4 < "$SQL_FILE"

echo ""
echo "=== 验证表数量 ==="
docker exec tars-mysql mysql -u"${MYSQL_USER}" -p"${MYSQL_PASS}" \
    -N -e "
        SELECT CONCAT('  表数: ', COUNT(*))
        FROM information_schema.TABLES
        WHERE TABLE_SCHEMA='tars_cms' AND TABLE_NAME LIKE 'cms_%' OR TABLE_NAME='users';
        SELECT '---';
        SELECT CONCAT('  cms_category: ', COUNT(*)) FROM tars_cms.cms_category;
        SELECT CONCAT('  cms_article:  ', COUNT(*)) FROM tars_cms.cms_article;
        SELECT CONCAT('  users:        ', COUNT(*)) FROM tars_cms.users;
    "

echo ""
echo "✅ 数据库初始化完成"
