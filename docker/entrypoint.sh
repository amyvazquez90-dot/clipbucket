#!/bin/sh
set -e

PORT="${PORT:-8080}"
SOCK="/run/mysqld/mysqld.sock"
DB_NAME="clipbucket"
DB_USER="cb"
DB_PASS="${CB_DB_PASS:-cbpass}"

echo "[entrypoint] starting on port ${PORT}"

# --- render nginx config with the runtime port -------------------------------
sed "s/__PORT__/${PORT}/g" /opt/appjet/nginx.conf.template > /tmp/nginx.conf

# --- start embedded MariaDB --------------------------------------------------
mkdir -p /run/mysqld /tmp/nginx/body /tmp/nginx/fastcgi /tmp/nginx/proxy /tmp/nginx/uwsgi /tmp/nginx/scgi

mariadbd \
  --datadir=/var/lib/mysql \
  --socket="$SOCK" \
  --bind-address=127.0.0.1 \
  --port=3306 \
  --innodb-buffer-pool-size=64M \
  --performance-schema=0 \
  --max-connections=40 \
  --skip-name-resolve &
MARIADB_PID=$!

i=0
while [ "$i" -lt 60 ]; do
  if mariadb-admin --socket="$SOCK" -uroot ping >/dev/null 2>&1; then
    echo "[entrypoint] mariadb ready"
    break
  fi
  i=$((i + 1))
  sleep 1
done

if ! mariadb-admin --socket="$SOCK" -uroot ping >/dev/null 2>&1; then
  echo "[entrypoint] ERROR: mariadb did not start" >&2
fi

# --- database + user ---------------------------------------------------------
mariadb --socket="$SOCK" -uroot <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'127.0.0.1';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL

TABLES=$(mariadb --socket="$SOCK" -uroot -N -B \
  -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}'")

if [ "$TABLES" = "0" ]; then
  echo "[entrypoint] importing ClipBucket schema"
  mariadb --socket="$SOCK" -uroot "$DB_NAME" < /opt/appjet/cb_new_install.sql
  echo "[entrypoint] schema imported"
fi

# --- application config (same template the ClipBucket installer writes) ------
if [ ! -f /var/www/html/includes/config.php ]; then
  echo "[entrypoint] writing includes/config.php"
  sed -e "s|_DB_HOST_|127.0.0.1|" \
      -e "s|_DB_NAME_|${DB_NAME}|" \
      -e "s|_DB_USER_|${DB_USER}|" \
      -e "s|_DB_PASS_|${DB_PASS}|" \
      -e "s|_TABLE_PREFIX_|cb_|" \
      /var/www/html/cb_install/dbconnect.php > /var/www/html/includes/config.php
fi

# --- PHP-FPM + nginx ---------------------------------------------------------
php-fpm83 -F \
  -d auto_prepend_file=/var/www/html/includes/php8_compat.php \
  -d memory_limit=256M \
  -d upload_max_filesize=512M \
  -d post_max_size=512M \
  -d max_execution_time=300 \
  -d error_log=/dev/stderr \
  -d log_errors=On \
  -d display_errors=Off &
PHP_FPM_PID=$!

echo "[entrypoint] starting nginx"
exec nginx -c /tmp/nginx.conf -g "daemon off;"
