FROM alpine:3.21

# Refresh OS packages in the final stage so the image scan sees current security fixes.
RUN echo "os-refresh 2026-01-01" && apk upgrade --no-cache

RUN apk add --no-cache \
    nginx \
    php83 php83-fpm php83-mysqli php83-curl php83-gd php83-mbstring \
    php83-xml php83-session php83-zip php83-openssl php83-exif \
    php83-iconv php83-fileinfo php83-tokenizer php83-phar php83-pcntl \
    mariadb mariadb-client \
    ffmpeg \
    tzdata

ENV PORT=8080 \
    PHP_INI_SCAN_DIR=/etc/php83/conf.d

WORKDIR /var/www/html

# ClipBucket web root is the upload/ directory.
COPY upload/ /var/www/html/
COPY sql/cb_new_install.sql /opt/appjet/cb_new_install.sql
COPY docker/ /opt/appjet/

RUN adduser -D -u 1000 -h /home/app -s /bin/sh app \
 && rm -f /etc/nginx/http.d/default.conf \
 && cp /opt/appjet/php-fpm.conf /etc/php83/php-fpm.conf \
 && cp /opt/appjet/php-fpm-pool.conf /etc/php83/php-fpm.d/www.conf \
 && cp /opt/appjet/php.ini /etc/php83/conf.d/99-appjet.ini \
 && mkdir -p /run/mysqld /var/lib/mysql /tmp/nginx/body /tmp/nginx/fastcgi /tmp/nginx/proxy /tmp/nginx/uwsgi /tmp/nginx/scgi \
 && chmod +x /opt/appjet/entrypoint.sh \
 && chown -R app:app /var/www/html /var/lib/mysql /run/mysqld /tmp/nginx /opt/appjet /home/app

# Prepare the MariaDB data directory once at build time (container starts faster).
RUN mariadb-install-db --user=app --datadir=/var/lib/mysql \
      --auth-root-authentication-method=normal --skip-test-db \
 && chown -R app:app /var/lib/mysql

USER app

EXPOSE 8080

CMD ["/opt/appjet/entrypoint.sh"]
