#!/bin/bash
set -euo pipefail

## TEMP File
TFILE=`mktemp --tmpdir tfile.XXXX`
trap "rm -f $TFILE" 0 1 2 3 15
## trap Deletes TFILE on Exit

# usage: file_env VAR [DEFAULT]
#    ie: file_env 'XYZ_DB_PASSWORD' 'example'
# (will allow for "$XYZ_DB_PASSWORD_FILE" to fill in the value of
#  "$XYZ_DB_PASSWORD" from a file, especially for Docker's secrets feature)
file_env() {
    local var="$1"
    local fileVar="${var}_FILE"
    local def="${2:-}"
    if [ "${!var:-}" ] && [ "${!fileVar:-}" ]; then
        echo >&2 "error: both $var and $fileVar are set (but are exclusive)"
        exit 1
    fi
    local val="$def"
    if [ "${!var:-}" ]; then
        val="${!var}"
    elif [ "${!fileVar:-}" ]; then
        val="$(< "${!fileVar}")"
    fi
    export "$var"="$val"
    unset "$fileVar"
}

if [[ "$1" == apache2* ]]; then
    hostname="${SERVER_HOSTNAME:-localhost}"
    : ${HTTPS_ENABLED:=true}
    if [[ $HTTPS_ENABLED == "true" ]]; then
        if [ ! -e /etc/apache2/ssl/${hostname}.crt ] || [ ! -e /etc/apache2/ssl/${hostname}.key ]; then
            # if the certificates don't exist then make them
            mkdir -p /etc/apache2/ssl
            openssl req -days 356 -x509 -out /etc/apache2/ssl/${hostname}.crt -keyout /etc/apache2/ssl/${hostname}.key \
                -newkey rsa:2048 -nodes -sha256 \
                -subj '/CN='${hostname} -extensions EXT -config <( \
            printf "[dn]\nCN=${hostname}\n[req]\ndistinguished_name = dn\n[EXT]\nsubjectAltName=DNS:${hostname}\nkeyUsage=digitalSignature\nextendedKeyUsage=serverAuth")
        fi
        cat > /etc/apache2/sites-available/${hostname}-ssl.conf <<EOL
        <IfModule mod_ssl.c>
            <VirtualHost *:443>
                ServerName ${hostname}
                DocumentRoot /var/www/html
                ErrorLog \${APACHE_LOG_DIR}/error.log
                CustomLog \${APACHE_LOG_DIR}/access.log combined
                SSLEngine on
                SSLCertificateFile /etc/apache2/ssl/${hostname}.crt
                SSLCertificateKeyFile /etc/apache2/ssl/${hostname}.key
            </VirtualHost>
        </IfModule>
EOL
        a2enmod ssl
        a2ensite ${hostname}-ssl
    fi
fi

if [[ "$1" == apache2* ]] || [ "$1" == php-fpm ]; then
    if [ ! -e index.php ] && [ ! -e redcap_connect.php ]; then
        echo >&2 'REDCap does not appear to be installed. Please map the redcap folder as a docker volume.'
        exit 1
    fi
    uniqueEnvs=(
        'salt'
    )
    envs=(
        REDCAP_DB_HOST
        REDCAP_DB_USER
        REDCAP_DB_PASSWORD
        REDCAP_DB_NAME
        "${uniqueEnvs[@]/#/REDCAP_}"
        REDCAP_DEBUG
    )
    haveConfig=
    for e in "${envs[@]}"; do
        file_env "$e"
        if [ -z "$haveConfig" ] && [ -n "${!e}" ]; then
            haveConfig=1
        fi
    done

    # only update "database.php" if we have environment-supplied configuration values
    if [ "$haveConfig" ]; then
        : "${REDCAP_DB_HOST:=mysql}"
        : "${REDCAP_DB_USER:=root}"
        : "${REDCAP_DB_PASSWORD:=}"
        : "${REDCAP_DB_NAME:=redcap}"

        # Ensure unix line endings
        sed -r -e 's/\r$//' database.php > "$TFILE"
        cat "$TFILE" > database.php

        # see http://stackoverflow.com/a/2705678/433558
        sed_escape_lhs() {
            echo "$@" | sed -e 's/[]\/$*.^|[]/\\&/g'
        }
        sed_escape_rhs() {
            echo "$@" | sed -e 's/[\/&]/\\&/g'
        }
        php_escape() {
            local escaped="$(php -r 'var_export(('"$2"') $argv[1]);' -- "$1")"
            if [ "$2" = 'string' ] && [ "${escaped:0:1}" = "'" ]; then
                escaped="${escaped//$'\n'/"' + \"\\n\" + '"}"
            fi
            echo "$escaped"
        }
        set_config() {
            key="$1"
            value="$2"
            var_type="${3:-string}"
            start="(['\"])$(sed_escape_lhs "$key")\2\s*,"
            end="\);"
            if [ "${key:0:1}" = '$' ]; then
                start="^(\s*)$(sed_escape_lhs "$key")\s*="
                end=";"
            fi
            # VirtioFS on Mac OS has a problem with newly created files on a shared directory.
            sed -r -e "s/($start\s*).*($end)$/\1$(sed_escape_rhs "$(php_escape "$value" "$var_type")")\3/" database.php > "$TFILE"
            cat "$TFILE" > database.php 
        }
        set_config '$hostname' "$REDCAP_DB_HOST"
        set_config '$db'       "$REDCAP_DB_NAME"
        set_config '$username' "$REDCAP_DB_USER"
        set_config '$password' "$REDCAP_DB_PASSWORD"

        for unique in "${uniqueEnvs[@]}"; do
            uniqVar="REDCAP_$unique"
            if [ -n "${!uniqVar}" ]; then
                set_config "\$${unique}" "${!uniqVar}"
            else
                # if not specified, let's generate a random value
                currentVal="$(sed -rn -e "s/\\\$$unique[ \t]*=[ \t]*('|\")([^\1]*)('|\")[ \t]*;/\2/p" database.php)"
                if [ "$currentVal" = '' ]; then
                    set_config "\$${unique}" "$(head -c1m /dev/urandom | sha1sum | cut -d' ' -f1)"
                fi
            fi
        done

        if [ "$REDCAP_DEBUG" ]; then
            export DEV
        fi

        if ! TERM=dumb php -- <<'EOPHP'
<?php
// database might not exist, so let's try creating it (just to be safe)

$stderr = fopen('php://stderr', 'w');

@list($host, $socket) = explode(':', getenv('REDCAP_DB_HOST'), 2);
$port = 0;
if (is_numeric($socket)) {
    $port = (int) $socket;
    $socket = null;
}
$user = getenv('REDCAP_DB_USER');
$pass = getenv('REDCAP_DB_PASSWORD');
$dbName = getenv('REDCAP_DB_NAME');

$maxTries = 10;
do {
    $mysql = new mysqli($host, $user, $pass, '', $port, $socket);
    if ($mysql->connect_error) {
        fwrite($stderr, "\n" . 'MySQL Connection Error: (' . $mysql->connect_errno . ') ' . $mysql->connect_error . "\n");
        --$maxTries;
        if ($maxTries <= 0) {
            exit(1);
        }
        sleep(3);
    }
} while ($mysql->connect_error);

if (!$mysql->query('CREATE DATABASE IF NOT EXISTS `' . $mysql->real_escape_string($dbName) . '`')) {
    fwrite($stderr, "\n" . 'MySQL "CREATE DATABASE" Error: ' . $mysql->error . "\n");
    $mysql->close();
    exit(1);
}
$mysql->close();
EOPHP
        then
            echo >&2
            echo >&2 "WARNING: unable to establish a database connection to '$REDCAP_DB_HOST'"
            echo >&2 '  continuing anyways (which might have unexpected results)'
            echo >&2
        elif ! TERM=dumb php -- <<'EOTBLCHK'
<?php
// If tables don't exist let the user know how to create them

$stderr = fopen('php://stderr', 'w');

@list($host, $socket) = explode(':', getenv('REDCAP_DB_HOST'), 2);
$port = 0;
if (is_numeric($socket)) {
    $port = (int) $socket;
    $socket = null;
}
$user = getenv('REDCAP_DB_USER');
$pass = getenv('REDCAP_DB_PASSWORD');
$dbName = getenv('REDCAP_DB_NAME');

$mysql = new mysqli($host, $user, $pass, $dbName, $port, $socket);

if ($mysql->connect_error) {
    exit(1);
}

if ($mysql->query('SELECT 1 FROM `redcap_config` LIMIT 1') === false) {
    $mysql->close();
    exit(1);
}

$mysql->close();
EOTBLCHK
        then
            echo >&2
            echo >&2 "WARNING: REDCap tables don't exist go to install.php to complete installation or"
            echo >&2 '  go to install.php?sql=1&auto=1 to auto install tables.'
            echo >&2
        fi
     else
        echo >&2
        echo >&2 'WARNING: environment variables "REDCAP_DB_HOST", "REDCAP_DB_USER", "REDCAP_DB_PASSWORD" and "REDCAP_DB_NAME" is not set.'
        echo >&2 '  The contents of these variables will _not_ be inserted into the existing "database.php" file.'
        echo >&2 '  You might have database connectivity issues if this has not been set up yet.'
        echo >&2
    fi

    # Unset environment varialbes so configuration variables does not leak out into phpinfo().
    for e in "${envs[@]}"; do
        unset "$e"
    done
fi

if [ -n "${MAILPIT_HOST:-}" ]; then
    echo "sendmail_path = \"/usr/sbin/sendmail -S $MAILPIT_HOST:1025 -t\"" > /usr/local/etc/php/conf.d/mailhog.ini
fi

/etc/init.d/cron start

exec docker-php-entrypoint "$@"
