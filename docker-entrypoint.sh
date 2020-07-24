#!/bin/bash

# Define '**' behavior explicitly
shopt -s globstar

# start container with shell
if [[ "$1" = "/bin/sh" || "$1" = "/bin/bash" ]]; then
	exec "$1"
	exit 0
fi

# get local address
LOCAL_IP=`ip a|grep inet|grep -v inet6|grep -v "127.0.0.1"|awk '{print $2}'|awk -F '/' '{print $1}'|head -1`

# get ip address for needed service
REDIS_SERVER_HOST=${REDIS_IP_ADDRESS:-${LOCAL_IP}}
DB_HOST=${MYSQL_IP_ADDRESS:-${LOCAL_IP}}
RABBITMQ_SERVER_URL="amqp://admin:guoguo@${RABBITMQ_IP_ADDRESS:-${LOCAL_IP}}"

# path info
APP_DIR="/usr/local/onlyoffice/documentserver"
DATA_DIR="/usr/local/onlyoffice/Data"
LOG_DIR="/var/log/onlyoffice"
DS_LOG_DIR="${LOG_DIR}/documentserver"
LIB_DIR="/var/lib/onlyoffice"
DS_LIB_DIR="${LIB_DIR}/documentserver"
CONF_DIR="/etc/onlyoffice/documentserver"

# configure file for https
SSL_CERTIFICATES_DIR="${DATA_DIR}/certs"
if [[ -z $SSL_CERTIFICATE_PATH ]] && [[ -f ${SSL_CERTIFICATES_DIR}/onlyoffice.crt ]]; then
	SSL_CERTIFICATE_PATH=${SSL_CERTIFICATES_DIR}/onlyoffice.crt
else
	SSL_CERTIFICATE_PATH=${SSL_CERTIFICATE_PATH:-${SSL_CERTIFICATES_DIR}/tls.crt}
fi
if [[ -z $SSL_KEY_PATH ]] && [[ -f ${SSL_CERTIFICATES_DIR}/onlyoffice.key ]]; then
	SSL_KEY_PATH=${SSL_CERTIFICATES_DIR}/onlyoffice.key
else
	SSL_KEY_PATH=${SSL_KEY_PATH:-${SSL_CERTIFICATES_DIR}/tls.key}
fi
CA_CERTIFICATES_PATH=${CA_CERTIFICATES_PATH:-${SSL_CERTIFICATES_DIR}/ca-certificates.pem}
SSL_DHPARAM_PATH=${SSL_DHPARAM_PATH:-${SSL_CERTIFICATES_DIR}/dhparam.pem}
SSL_VERIFY_CLIENT=${SSL_VERIFY_CLIENT:-off}
USE_UNAUTHORIZED_STORAGE=${USE_UNAUTHORIZED_STORAGE:-false}
ONLYOFFICE_HTTPS_HSTS_ENABLED=${ONLYOFFICE_HTTPS_HSTS_ENABLED:-true}
ONLYOFFICE_HTTPS_HSTS_MAXAGE=${ONLYOFFICE_HTTPS_HSTS_MAXAGE:-31536000}

# nginx info
NGINX_CONFD_PATH="/etc/nginx/conf.d";
NGINX_ONLYOFFICE_PATH="${CONF_DIR}/nginx"
NGINX_ONLYOFFICE_CONF="${NGINX_ONLYOFFICE_PATH}/ds.conf"
NGINX_ONLYOFFICE_EXAMPLE_PATH="${CONF_DIR}-example/nginx"
NGINX_ONLYOFFICE_EXAMPLE_CONF="${NGINX_ONLYOFFICE_EXAMPLE_PATH}/includes/ds-example.conf"
NGINX_CONFIG_PATH="/etc/nginx/nginx.conf"
NGINX_WORKER_PROCESSES=${NGINX_WORKER_PROCESSES:-1}
NGINX_WORKER_CONNECTIONS=${NGINX_WORKER_CONNECTIONS:-$(ulimit -n)}

# enable/disable json web token
JWT_ENABLED=${JWT_ENABLED:-false}
JWT_SECRET=${JWT_SECRET:-secret}
JWT_HEADER=${JWT_HEADER:-Authorization}
JWT_IN_BODY=${JWT_IN_BODY:-false}

# configure file for documentserver
ONLYOFFICE_DEFAULT_CONFIG=${CONF_DIR}/local.json
ONLYOFFICE_LOG4JS_CONFIG=${CONF_DIR}/log4js/production.json
ONLYOFFICE_EXAMPLE_CONFIG=${CONF_DIR}-example/local.json

JSON_BIN=${APP_DIR}/npm/json
JSON="${JSON_BIN} -q -f ${ONLYOFFICE_DEFAULT_CONFIG}"
JSON_LOG="${JSON_BIN} -q -f ${ONLYOFFICE_LOG4JS_CONFIG}"
JSON_EXAMPLE="${JSON_BIN} -q -f ${ONLYOFFICE_EXAMPLE_CONFIG}"

# read settings from json file
read_setting(){
	DB_HOST=${DB_HOST:-$(${JSON} services.CoAuthoring.sql.dbHost)}
	DB_PORT=${DB_PORT:-$(${JSON} services.CoAuthoring.sql.dbPort)}
	DB_NAME=${DB_NAME:-$(${JSON} services.CoAuthoring.sql.dbName)}
	DB_USER=${DB_USER:-$(${JSON} services.CoAuthoring.sql.dbUser)}
	DB_PWD=${DB_PWD:-$(${JSON} services.CoAuthoring.sql.dbPass)}
	DB_TYPE=${DB_TYPE:-$(${JSON} services.CoAuthoring.sql.type)}

	RABBITMQ_SERVER_URL=${RABBITMQ_SERVER_URL:-$(${JSON} rabbitmq.url)}
	AMQP_URI=${AMQP_URI:-${AMQP_SERVER_URL:-${RABBITMQ_SERVER_URL}}}
	AMQP_TYPE=${AMQP_TYPE:-${AMQP_SERVER_TYPE:-rabbitmq}}
	parse_rabbitmq_url ${AMQP_URI}

	REDIS_SERVER_HOST=${REDIS_SERVER_HOST:-$(${JSON} services.CoAuthoring.redis.host)}
	REDIS_SERVER_PORT=${REDIS_SERVER_PORT:-9736}

	DS_LOG_LEVEL=${DS_LOG_LEVEL:-$(${JSON_LOG} categories.default.level)}
}

# parse amqp info from giving url
parse_rabbitmq_url(){
	local amqp=$1

	# extract the protocol
	local proto="$(echo $amqp | grep :// | sed -e's,^\(.*://\).*,\1,g')"
	# remove the protocol
	local url="$(echo ${amqp/$proto/})"

	# extract the user and password (if any)
	local userpass="`echo $url | grep @ | cut -d@ -f1`"
	local pass=`echo $userpass | grep : | cut -d: -f2`

	local user
	if [ -n "$pass" ]; then
		user=`echo $userpass | grep : | cut -d: -f1`
	else
		user=$userpass
	fi

	# extract the host
	local hostport="$(echo ${url/$userpass@/} | cut -d/ -f1)"
	local port=`echo $hostport | grep : | cut -d: -f2`

	local host
	if [ -n "$port" ]; then
		host=`echo $hostport | grep : | cut -d: -f1`
	else
		host=$hostport
		port="5672"
	fi

	# extract the path (if any)
	local path="$(echo $url | grep / | cut -d/ -f2-)"

	AMQP_SERVER_PROTO=${proto:0:-3}
	AMQP_SERVER_HOST=$host
	AMQP_SERVER_USER=$user
	AMQP_SERVER_PASS=$pass
	AMQP_SERVER_PORT=$port
}

# function for check connection
waiting_for_connection(){
	until nc -z -w 3 "$1" "$2"; do
		>&2 echo "Waiting for connection to the $1 host on port $2"
		sleep 1
	done
}
# check connection for database
waiting_for_db(){
	waiting_for_connection $DB_HOST $DB_PORT
}
# check connection for amqp
waiting_for_amqp(){
	waiting_for_connection ${AMQP_SERVER_HOST} ${AMQP_SERVER_PORT}
}
# check connection for redis
waiting_for_redis(){
	waiting_for_connection ${REDIS_SERVER_HOST} ${REDIS_SERVER_PORT}
}

# update settings for database
update_db_settings(){
	${JSON} -I -e "this.services.CoAuthoring.sql.type = '${DB_TYPE}'"
	${JSON} -I -e "this.services.CoAuthoring.sql.dbHost = '${DB_HOST}'"
	${JSON} -I -e "this.services.CoAuthoring.sql.dbPort = '${DB_PORT}'"
	${JSON} -I -e "this.services.CoAuthoring.sql.dbName = '${DB_NAME}'"
	${JSON} -I -e "this.services.CoAuthoring.sql.dbUser = '${DB_USER}'"
	${JSON} -I -e "this.services.CoAuthoring.sql.dbPass = '${DB_PWD}'"
}

# update settings for amqp
update_rabbitmq_setting(){
	${JSON} -I -e "if(this.queue===undefined)this.queue={};"
	${JSON} -I -e "this.queue.type = 'rabbitmq'"
	${JSON} -I -e "this.rabbitmq.url = '${AMQP_URI}'"
}

# update settings for redis
update_redis_settings(){
	${JSON} -I -e "this.services.CoAuthoring.redis.host = '${REDIS_SERVER_HOST}'"
	${JSON} -I -e "this.services.CoAuthoring.redis.port = '${REDIS_SERVER_PORT}'"
}

# update settings for documentserver
update_ds_settings(){
	if [ "${JWT_ENABLED}" == "true" ]; then
		${JSON} -I -e "this.services.CoAuthoring.token.enable.browser = ${JWT_ENABLED}"
		${JSON} -I -e "this.services.CoAuthoring.token.enable.request.inbox = ${JWT_ENABLED}"
		${JSON} -I -e "this.services.CoAuthoring.token.enable.request.outbox = ${JWT_ENABLED}"

		${JSON} -I -e "this.services.CoAuthoring.secret.inbox.string = '${JWT_SECRET}'"
		${JSON} -I -e "this.services.CoAuthoring.secret.outbox.string = '${JWT_SECRET}'"
		${JSON} -I -e "this.services.CoAuthoring.secret.session.string = '${JWT_SECRET}'"

		${JSON} -I -e "this.services.CoAuthoring.token.inbox.header = '${JWT_HEADER}'"
		${JSON} -I -e "this.services.CoAuthoring.token.outbox.header = '${JWT_HEADER}'"

		${JSON} -I -e "this.services.CoAuthoring.token.inbox.inBody = ${JWT_IN_BODY}"
		${JSON} -I -e "this.services.CoAuthoring.token.outbox.inBody = ${JWT_IN_BODY}"

		if [ -f "${ONLYOFFICE_EXAMPLE_CONFIG}" ] && [ "${JWT_ENABLED}" == "true" ]; then
			${JSON_EXAMPLE} -I -e "this.server.token.enable = ${JWT_ENABLED}"
			${JSON_EXAMPLE} -I -e "this.server.token.secret = '${JWT_SECRET}'"
			${JSON_EXAMPLE} -I -e "this.server.token.authorizationHeader = '${JWT_HEADER}'"
		fi
	fi

	if [ "${USE_UNAUTHORIZED_STORAGE}" == "true" ]; then
		${JSON} -I -e "if(this.services.CoAuthoring.requestDefaults===undefined)this.services.CoAuthoring.requestDefaults={}"
		${JSON} -I -e "if(this.services.CoAuthoring.requestDefaults.rejectUnauthorized===undefined)this.services.CoAuthoring.requestDefaults.rejectUnauthorized=false"
	fi
}

# update page for welcome
update_welcome_page() {
	WELCOME_PAGE="${APP_DIR}-example/welcome/docker.html"
	if [[ -e $WELCOME_PAGE ]]; then
		DOCKER_CONTAINER_ID=$(basename $(cat /proc/1/cpuset))
		if [[ -x $(command -v docker) ]]; then
			DOCKER_CONTAINER_NAME=$(docker inspect --format="{{.Name}}" $DOCKER_CONTAINER_ID)
			sed 's/$(sudo docker ps -q)/'"${DOCKER_CONTAINER_NAME#/}"'/' -i $WELCOME_PAGE
		else
			sed 's/$(sudo docker ps -q)/'"${DOCKER_CONTAINER_ID::12}"'/' -i $WELCOME_PAGE
		fi
	fi
}

# update settings for nginx
update_nginx_settings(){
	# Set up nginx
	sed 's/^worker_processes.*/'"worker_processes ${NGINX_WORKER_PROCESSES};"'/' -i ${NGINX_CONFIG_PATH}
	sed 's/worker_connections.*/'"worker_connections ${NGINX_WORKER_CONNECTIONS};"'/' -i ${NGINX_CONFIG_PATH}
	sed 's/access_log.*/'"access_log off;"'/' -i ${NGINX_CONFIG_PATH}

	# setup HTTPS
	if [ -f "${SSL_CERTIFICATE_PATH}" -a -f "${SSL_KEY_PATH}" ]; then
		cp -f ${NGINX_ONLYOFFICE_PATH}/ds-ssl.conf.tmpl ${NGINX_ONLYOFFICE_CONF}

		# configure nginx
		sed 's,{{SSL_CERTIFICATE_PATH}},'"${SSL_CERTIFICATE_PATH}"',' -i ${NGINX_ONLYOFFICE_CONF}
		sed 's,{{SSL_KEY_PATH}},'"${SSL_KEY_PATH}"',' -i ${NGINX_ONLYOFFICE_CONF}

		# turn on http2
		sed 's,\(443 ssl\),\1 http2,' -i ${NGINX_ONLYOFFICE_CONF}

		# if dhparam path is valid, add to the config, otherwise remove the option
		if [ -r "${SSL_DHPARAM_PATH}" ]; then
			sed 's,\(\#* *\)\?\(ssl_dhparam \).*\(;\)$,'"\2${SSL_DHPARAM_PATH}\3"',' -i ${NGINX_ONLYOFFICE_CONF}
		else
			sed '/ssl_dhparam/d' -i ${NGINX_ONLYOFFICE_CONF}
		fi

		sed 's,\(ssl_verify_client \).*\(;\)$,'"\1${SSL_VERIFY_CLIENT}\2"',' -i ${NGINX_ONLYOFFICE_CONF}

		if [ -f "${CA_CERTIFICATES_PATH}" ]; then
			sed '/ssl_verify_client/a '"ssl_client_certificate ${CA_CERTIFICATES_PATH}"';' -i ${NGINX_ONLYOFFICE_CONF}
		fi

		if [ "${ONLYOFFICE_HTTPS_HSTS_ENABLED}" == "true" ]; then
			sed 's,\(max-age=\).*\(;\)$,'"\1${ONLYOFFICE_HTTPS_HSTS_MAXAGE}\2"',' -i ${NGINX_ONLYOFFICE_CONF}
		else
			sed '/max-age=/d' -i ${NGINX_ONLYOFFICE_CONF}
		fi
	else
		ln -sf ${NGINX_ONLYOFFICE_PATH}/ds.conf.tmpl ${NGINX_ONLYOFFICE_CONF}
	fi

	# check if ipv6 supported otherwise remove it from nginx config
	if [ ! -f /proc/net/if_inet6 ]; then
		sed '/listen\s\+\[::[0-9]*\].\+/d' -i $NGINX_ONLYOFFICE_CONF
	fi

	if [ -f "${NGINX_ONLYOFFICE_EXAMPLE_CONF}" ]; then
		sed 's/linux/docker/' -i ${NGINX_ONLYOFFICE_EXAMPLE_CONF}
	fi
}

# update settings for loglevel
update_log_settings(){
	 ${JSON_LOG} -I -e "this.categories.default.level = '${DS_LOG_LEVEL}'"
}

# update settings for logrotate
update_logrotate_settings(){
	sed 's|\(^su\b\).*|\1 root root|' -i /etc/logrotate.conf
}

# create log folders for documentserver
for i in converter docservice spellchecker metrics; do
	mkdir -p "${DS_LOG_DIR}/$i"
done

mkdir -p ${DS_LOG_DIR}-example

# create app folders for documentserver
for i in ${DS_LIB_DIR}/App_Data/cache/files ${DS_LIB_DIR}/App_Data/docbuilder ${DS_LIB_DIR}-example/files; do
	mkdir -p "$i"
done

# create user for documentserver
if [ `cat /etc/passwd|grep onlyoffice -c` -eq 0 ]; then
	useradd onlyoffice -d /usr/local/onlyoffice/documentserver -s /usr/sbin/nologin
fi

# change folder rights for documentserver
for i in ${LOG_DIR} ${LIB_DIR} ${DATA_DIR}; do
	chown -R onlyoffice:onlyoffice "$i"
	chmod -R 755 "$i"
done

if [ "$1" = "documentserver" ]; then
	# read settings after the data container in ready state
	# to prevent get unconfigureted data
	read_setting
	update_welcome_page
	update_log_settings
	update_ds_settings

	# waiting for database service
	update_db_settings
	waiting_for_db

	# waiting for amqp service
	update_rabbitmq_setting
	waiting_for_amqp

	# waiting for redis service
	update_redis_settings
	waiting_for_redis

	# start documentserver service
	service supervisor start
	
	# start cron to enable log rotating
	update_logrotate_settings
	service cron start

	# nginx used as a proxy and status service.
	update_nginx_settings
	service nginx start

	# Regenerate the fonts list and the fonts thumbnails
	documentserver-generate-allfonts.sh false
	documentserver-static-gzip.sh false
fi

tail -f /var/log/onlyoffice/**/*.log
