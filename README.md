# Docker stack for Project REDCap

## About

Deploying a REDCap server requires several steps to be performed to get it up and running. As a developer this might happen several times during development. Thid project aid to make that deployment process quick and easy. :warning: You will have to have a copy of the REDCap software in order to use this project.

### What is REDCap

REDCap is a secure web application for building and managing online surveys and databases. While REDCap can be used to collect virtually any type of data in any environment (including compliance with 21 CFR Part 11, FISMA, HIPAA, and GDPR), it is specifically geared to support online and offline data capture for research studies and operations. The REDCap Consortium, a vast support network of collaborators, is composed of thousands of active institutional partners in over one hundred countries who utilize and support their own individual REDCap systems. Please visit the [Join](https://projectredcap.org/partners/join/) page to learn how your non-profit organization can join the consortium, or explore the first section on their [FAQ](https://projectredcap.org/about/faq/) for other options to use REDCap.

## Usage

You will need a mariadb or mysql server in order to use this project. You can also use [mailhog](https://hub.docker.com/repository/docker/bezuidenhout/mailhog) to capture outgoing e-mails and view them through a webpage.

Here is an example using docker-compose.yml:

```yaml
version: '3.7'

services:
  redcap:
    image: redcap
    ports:
     - '80:80'
     - '443:443'
    restart: unless-stopped
    networks:
      bridge:
    volumes:
     - ./redcap/redcap:/var/www/html:delegated
    depends_on:
     - "mysql"
     - "mailhog"
    environment:
     - REDCAP_DB_USER=redcap
     - REDCAP_DB_PASSWORD=MyDBPassword
     - REDCAP_DB_NAME=redcap
     - REDCAP_DB_HOST=mysql
     - REDCAP_DEBUG=true
     - MAILHOG_HOST=mailhog
  mailhog:
    image: bezuidenhout/mailhog
    restart: always
    ports:
     - 8025:8025 # web ui
    networks:
      bridge:
  mysql:
    image: linuxserver/mariadb
    restart: always
    environment:
     - PUID=501
     - MYSQL_USER=redcap
     - MYSQL_PASSWORD=MyDBPassword
     - MYSQL_ROOT_PASSWORD=MyRootPassword
     - MYSQL_DATABASE=redcap
    volumes:
     - ./mysql:/config/databases:cached
    networks:
      bridge:
networks:
  bridge:
``` 

:memo: Before you will be able to open your web page for the first time you will need to create a database. You can do this either by navigating to the install page a `http://localhost/install.php` or you can auto create the database with `http://localhost/install.php?sql=1&auto=1`

### Environment variables

* `REDCAP_DB_HOST`: Hostname for the database server. Use the service name if specified in a stack.
* `REDCAP_DB_USER`: Database username on `REDCAP_DB_HOST`.
* `REDCAP_DB_PASSWORD`: Database password on `REDCAP_DB_HOST`.
* `REDCAP_DB_NAME`: The database name to use. It will be auto created if it doesn't exist.
* `REDCAP_DEBUG`: If this environment varaible exists then REDCap will run in debug mode.
* `MAILHOG_HOST`: If you want your outgoing e-mails to be captured then specify the `MAILHOG_HOST` host/service name.

### Volumes

Map the location of your redcap folder to `/var/www/html` inside the container.

## Disclaimer

This github project is _**ONLY**_ intended for development work. Do not use this for a production server. 
The contributors and members to _**this**_ github project don't take any responsibility nor liability for using this software nor for the installation or any tips, advice, videos, etc. given by any member of this site or any related site.
