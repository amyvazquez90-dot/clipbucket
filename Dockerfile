# Official PHP image on a supported Alpine release, pinned to a patched 8.3 patch level.
# PHP 8.3 is used deliberately: the app declares its own array_find(), which collides with PHP 8.4.
FROM php:8.3.36-fpm-alpine

# Refresh OS packages in the final stage so the image scan sees current security fixes.
RUN echo "os-refresh 2026-01-01" && apk upgrade --no-cache

# nginx (web server), MariaDB (ClipBucket's database), ffmpeg (video conversion).
RUN apk add --no-cache nginx mariadb mariadb-client ffmpeg tzdata

# PHP extensions ClipBucket needs that the official image does not ship.
RUN apk add --no-cache --virtual .build-deps \
        $PHPIZE_DEPS libpng-dev libjpeg-turbo-dev freetype-dev libzip-dev \
 && docker-php-ext-configure gd --with-freetype --with-jpeg \
 && docker-php-ext-install -j"$(nproc)" mysqli pdo_mysql gd zip exif pcntl \
 && apk del --no-cache .build-deps \
 && rm -rf /tmp/pear /usr/src/php.tar.xz

ENV PORT=8080

WORKDIR /var/www/html

# ClipBucket web root is the upload/ directory.
COPY upload/ /var/www/html/
COPY sql/cb_new_install.sql /opt/appjet/cb_new_install.sql
COPY docker/ /opt/appjet/

RUN adduser -D -u 1000 -h /home/app -s /bin/sh app \
 && rm -f /etc/nginx/http.d/default.conf \
 && cp /opt/appjet/php-fpm.conf /usr/local/etc/php-fpm.conf \
 && cp /opt/appjet/php-fpm-pool.conf /usr/local/etc/php-fpm.d/www.conf \
 && cp /opt/appjet/php.ini /usr/local/etc/php/conf.d/99-appjet.ini \
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
