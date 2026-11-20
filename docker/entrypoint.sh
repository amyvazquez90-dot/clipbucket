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
  --skip-networking=0 \
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
  -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}' AND table_name LIKE 'cb\\_%'")

SQL_DIR=/opt/appjet/install-sql
if [ "$TABLES" = "0" ]; then
  echo "[entrypoint] importing ClipBucket schema from ${SQL_DIR}"
  # The installer ships a prefixed schema; ClipBucket uses the cb_ prefix.
  for f in structure configs countries categories pages email_templates ads_placements add_admin; do
    if [ -f "${SQL_DIR}/${f}.sql" ]; then
      sed 's/{tbl_prefix}/cb_/g' "${SQL_DIR}/${f}.sql" \
        | mariadb --force --socket="$SOCK" -uroot "$DB_NAME" \
        || echo "[entrypoint] WARN: ${f}.sql reported errors" >&2
      echo "[entrypoint] imported ${f}.sql"
    fi
  done
fi

if [ "$(mariadb --socket="$SOCK" -uroot -N -B \
  -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}' AND table_name='cb_config'")" = "0" ]; then
  echo "[entrypoint] ERROR: cb_config table missing after schema import" >&2
  exit 1
fi

# --- application config (same template the ClipBucket installer writes) ------
# ClipBucket requires BOTH includes/dbconnect.php (required by common.php) and
# includes/config.php; the bundled installer writes dbconnect.php, so render both.
render_db_config() {
  # "localhost" makes mysqli use the unix socket above instead of TCP, which
  # is the path the embedded server is guaranteed to be reachable on.
  sed -e "s|_DB_HOST_|localhost|" \
      -e "s|_DB_NAME_|${DB_NAME}|" \
      -e "s|_DB_USER_|${DB_USER}|" \
      -e "s|_DB_PASS_|${DB_PASS}|" \
      -e "s|_TABLE_PREFIX_|cb_|" \
      /var/www/html/cb_install/dbconnect.php > "$1"
}

for cfg in /var/www/html/includes/dbconnect.php /var/www/html/includes/config.php; do
  if [ ! -s "$cfg" ]; then
    echo "[entrypoint] writing ${cfg#/var/www/html/}"
    render_db_config "$cfg"
    chown app:app "$cfg" 2>/dev/null || true
  fi
done

# --- PHP-FPM + nginx ---------------------------------------------------------
/usr/local/sbin/php-fpm -F \
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
