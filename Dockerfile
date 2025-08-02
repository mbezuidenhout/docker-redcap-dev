#
# REDCap Dockerfile
#

FROM php:8.3-apache
LABEL maintainer="Marius Bezuidenhout <marius.bezuidenhout@gmail.com>"

ENV PATH="/usr/local/bin:/usr/local/sbin:$PATH"
RUN apt-get update &&\
    apt-get install --no-install-recommends --assume-yes --quiet \
        ca-certificates openssl zlib1g-dev libpng-dev libzip-dev cron anacron git unzip p7zip imagemagick libmagick++-6.q16-dev sendmail &&\
    apt-get clean &&\
    rm -rf /var/lib/apt/lists/* &&\
    ldconfig

RUN update-ca-certificates -f \
    && docker-php-ext-install mysqli \
    && docker-php-ext-install gd \
    && docker-php-ext-install zip

COPY installer.sh /usr/local/bin/

# Install mailhog client, composer and xdebug and set development parameters
RUN chmod +x /usr/local/bin/installer.sh \
    && /usr/local/bin/installer.sh \
    && yes | pecl install xdebug \
    && echo "zend_extension=$(find /usr/local/lib/php/extensions/ -name xdebug.so)" > /usr/local/etc/php/conf.d/xdebug.ini \
    && echo "xdebug.mode=debug" >> /usr/local/etc/php/conf.d/xdebug.ini \
    && echo "xdebug.client_host=host.docker.internal" >> /usr/local/etc/php/conf.d/xdebug.ini \
    && printf "\n" | pecl install imagick \
    && echo "extension=$(find /usr/local/lib/php/extensions/ -name imagick.so)" > /usr/local/etc/php/conf.d/imagick.ini \
    && touch /usr/local/etc/php/conf.d/error-logging.ini \
    && sed -ri -e "s/^display_errors.*$/display_errors = On/" /usr/local/etc/php/conf.d/error-logging.ini \
    && sed -ri -e "s/^html_errors.*$/html_errors = On/" /usr/local/etc/php/conf.d/error-logging.ini \
    && sed -ri -e "s/^display_startup_errors.*$/display_startup_errors = On/" /usr/local/etc/php/conf.d/error-logging.ini \
    && sed -ri -e "s/rights=\"none\" pattern=\"PDF\"/rights=\"read\" pattern=\"PDF\"/" /etc/ImageMagick-6/policy.xml \
    && echo "# REDCap Cron Job (runs every minute)\n\nSHELL=/bin/sh\nPATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin\n\n" > /etc/cron.d/redcap \
    && echo "* * * * * root php /var/www/html/cron.php > /dev/null" >> /etc/cron.d/redcap

EXPOSE 80 443

COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh \
    && cp /usr/local/etc/php/php.ini-development /usr/local/etc/php/php.ini
ENTRYPOINT ["docker-entrypoint.sh"]

CMD ["apache2-foreground"]
