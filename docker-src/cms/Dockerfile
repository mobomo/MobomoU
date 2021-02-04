FROM php:7.3-fpm-alpine as php-base

ENV PHP_TIMEZONE America/Chicago
RUN echo "date.timezone = \"$PHP_TIMEZONE\"" > /usr/local/etc/php/conf.d/timezone.ini

RUN cat /dev/urandom | LC_CTYPE=C tr -dc 'a-zA-Z0-9' | fold -w 64 | head -n 1 > /var/www/salt.txt

WORKDIR /var/www

RUN apk add --no-cache --virtual .build-deps \
             # Misc dependencies
             autoconf \
             g++ \
             pcre-dev \
             libtool \
             make \
             curl \
             git \
             # Needed base depend
             coreutils

RUN apk add --no-cache --update mysql-client

# Install PHP memcached extension
RUN set -xe \
    && apk add --no-cache --update libmemcached-libs zlib \
    && apk add --no-cache --update --virtual .memcached-build-deps \
               zlib-dev \
               libmemcached-dev \
    && pecl install memcached \
    && docker-php-ext-enable memcached \
    # Cleanup
    && rm -rf /tmp/* ~/.pearrc /usr/share/php7 \
    && docker-php-source delete \
    && apk del .memcached-build-deps

# Install PHP extensions
# install the PHP extensions we need
RUN set -ex \
  && apk add --no-cache --virtual .build-php-exts \
             # GD depends
             freetype-dev \
             libjpeg-turbo-dev \
             libpng-dev \
             # xmlrpc depends
             libxml2-dev \
             libxslt-dev \
             libzip-dev \
  # Configure and Install PHP extensions
  && docker-php-ext-configure gd  \
       --with-freetype-dir=/usr/include/ \
       --with-jpeg-dir=/usr/include/ \
       --with-png-dir=/usr/include/ \
  && docker-php-ext-install -j "$(nproc)" \
             gd \
             iconv \
             mysqli \
             opcache \
             pdo_mysql \
             xmlrpc \
             xsl \
             zip \
  && runDeps="$( \
    scanelf --needed --nobanner --format '%n#p' --recursive /usr/local \
      | tr ',' '\n' \
      | sort -u \
      | awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
  )" \
  && apk add --virtual .drupal-phpexts-rundeps $runDeps \
  # Cleanup
  && rm -rf /tmp/pear ~/.pearrc \
  && chown -R www-data:www-data /usr/local/var/log \
  && docker-php-source delete \
  && apk del .build-deps .build-php-exts \
  && rm -rf /tmp/* /var/cache/apk/*

COPY docker-src/cms/php-conf.d/* /usr/local/etc/php/conf.d/

##
# web dev
##

FROM nginx:stable-alpine as web-dev

RUN rm /etc/nginx/conf.d/default.conf
COPY ./docker-src/cms/nginx/ssl-cert-snakeoil.key /etc/nginx/private.key
COPY ./docker-src/cms/nginx/ssl-cert-snakeoil.pem /etc/nginx/public.pem
COPY ./docker-src/cms/nginx/drupal.conf /etc/nginx/conf.d/drupal.conf

WORKDIR /var/www/web

################################################################################
# php dev                                                                      #
################################################################################
FROM scratch as php-dev
COPY --from=php-base . /

ENV PHP_INI_DIR /usr/local/etc/php
ENV PHP_EXTRA_CONFIGURE_ARGS --enable-fpm --with-fpm-user=www-data --with-fpm-group=www-data --disable-cgi
ENV PHP_TIMEZONE America/New_York
ENV PHP_LDFLAGS -Wl,-O1 -Wl,--hash-style=both -pie
ENV PHP_CFLAGS -fstack-protector-strong -fpic -fpie -O2
ENV PHP_CPPFLAGS -fstack-protector-strong -fpic -fpie -O2

COPY docker-src/cms/entrypoint /usr/local/bin/entrypoint
RUN echo $PATH
RUN ls /usr/local/bin/
ENTRYPOINT ["/usr/local/bin/entrypoint"]

WORKDIR /var/www

RUN  apk add --no-cache \
             git \
             curl \
             vim \
             unzip \
             wget \
             ncurses \
             ncurses-terminfo \
  && apk add --no-cache --virtual .build-deps \
             # unknown needed
             autoconf \
             g++ \
             pcre-dev \
             libtool \
             make \
             # Needed base depend
             coreutils \
  && pecl install xdebug \
  && docker-php-ext-enable xdebug \
  && echo "xdebug.remote_enable=on" >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini \
  && echo "xdebug.remote_autostart=on" >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini \
  # Remote connect_back only works on Linux systems because OSX abstracts it away into a VM
  && echo 'xdebug.remote_connect_back="${CONNECTBACK}"' >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini \
  && echo "xdebug.remote_host=host.docker.internal" >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini \
  && apk del .build-deps

# color avaiable thanks to ncurses packages above
ENV TERM xterm-256color

COPY docker-src/cms/php-conf.d.dev/* /usr/local/etc/php/conf.d/

WORKDIR /var/www/web

CMD ["php-fpm"]

##
# composer prod
##

FROM composer:latest as composer-prod

# Install tool to make composer download packages in parallel.
RUN composer global require hirak/prestissimo \
  && mkdir -p /var/www/web/core \
      /var/www/web/libraries \
      /var/www/web/modules/contrib \
      /var/www/web/profiles/contrib \
      /var/www/web/themes/contrib \
      /var/www/web/sites/all/drush/contrib \
      /var/www/vendor

COPY composer.json composer.lock /var/www
COPY scripts /var/www/scripts

WORKDIR /var/www

# The flag breaks drupal: --classmap-authoritative
RUN composer install \
      --ignore-platform-reqs \
      --optimize-autoloader \
      --no-interaction \
      --no-progress \
      --prefer-dist \
      --no-scripts \
      --no-ansi \
      --no-dev

WORKDIR /var/www/web

################################################################################
# php prod                                                                     #
################################################################################
FROM scratch as php-prod
COPY --from=php-base . /

COPY web /var/www/web
COPY config /var/www/config

RUN  rm -rf \
       web/core/* \
       web/libraries/* \
       web/modules/contrib/* \
       web/profiles/contrib/* \
       web/themes/contrib/* \
       web/sites/all/drush/contrib/*

COPY --from=composer-prod /var/www/web/core web/core
COPY --from=composer-prod /var/www/web/libraries web/libraries
COPY --from=composer-prod /var/www/web/modules/contrib web/modules/contrib
COPY --from=composer-prod /var/www/web/profiles/contrib web/profiles/contrib
COPY --from=composer-prod /var/www/web/themes/contrib web/themes/contrib
COPY --from=composer-prod /var/www/web/sites/all/drush/contrib web/sites/all/drush/contrib
COPY --from=composer-prod /var/www/scripts scripts
COPY --from=composer-prod /var/www/vendor vendor

WORKDIR /var/www/web

RUN ln -s /var/www/vendor/bin/* /bin/

################################################################################
# web prod                                                                     #
################################################################################
FROM scratch as web-prod
COPY --from=web-dev . /

COPY --from=php-prod /var/www/web /var/www/web

WORKDIR /var/www/web
