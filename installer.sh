#!/bin/bash
set -euo pipefail

# Composer install
EXPECTED_CHECKSUM="$(curl -Lsf https://composer.github.io/installer.sig)"
php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
ACTUAL_CHECKSUM="$(php -r "echo hash_file('sha384', 'composer-setup.php');")"

if [ "$EXPECTED_CHECKSUM" != "$ACTUAL_CHECKSUM" ]
then
    >&2 echo 'ERROR: Invalid installer checksum'
    rm composer-setup.php
    exit 1
fi

php composer-setup.php
rm composer-setup.php
# End composer install

# Golang install
case $(uname -m) in
    i386) ;&
    i686)   curl -Lsf 'https://golang.org/dl/go1.16.7.linux-386.tar.gz' | tar -C '/usr/local' -xvzf - ;;
    x86_64) curl -Lsf 'https://golang.org/dl/go1.16.7.linux-amd64.tar.gz' | tar -C '/usr/local' -xvzf - ;;
    armv6l) ;&
    armv7l) curl -Lsf 'https://golang.org/dl/go1.16.7.linux-armv6l.tar.gz' | tar -C '/usr/local' -xvzf - ;;
    aarch64)  curl -Lsf 'https://golang.org/dl/go1.16.7.linux-arm64.tar.gz' | tar -C '/usr/local' -xvzf - ;;
    ppc64)  curl -Lsf 'https://golang.org/dl/go1.16.7.linux-ppc64le.tar.gz' | tar -C '/usr/local' -xvzf - ;;
    s390x)  curl -Lsf 'https://golang.org/dl/go1.16.7.linux-s390x.tar.gz' | tar -C '/usr/local' -xvzf - ;;
esac
# End golang insall

# Mailhog client install
PATH=/usr/local/go/bin:$PATH
sleep 5
go get github.com/mailhog/mhsendmail && cp ~/go/bin/mhsendmail /usr/local/bin/
# End mailhog install
