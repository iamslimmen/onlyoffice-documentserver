FROM oatos-office:5.5.3.39-ubuntu

FROM oatos-debian:10.4-buster

COPY --from=0 /var/www/html /usr/local/html
COPY --from=0 /etc/onlyoffice /etc/onlyoffice
COPY --from=0 /var/www/onlyoffice /usr/local/onlyoffice
COPY --from=0 /usr/bin/documentserver-*.sh /usr/local/bin/

ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8 DEBIAN_FRONTEND=noninteractive

RUN echo "#!/bin/sh\nexit 0" > /usr/sbin/policy-rc.d; \
	\
	sed -i "s/deb.debian.org/mirrors.aliyun.com/g" /etc/apt/sources.list; \
	sed -i "s/security.debian.org/mirrors.aliyun.com/g" /etc/apt/sources.list; \
	sed -i "s/snapshot.debian.org/mirrors.aliyun.com/g" /etc/apt/sources.list; \
	apt-get -y update && apt-get -yq install \
		cron \
		logrotate \
		gnupg \
		locales \
		iproute2 \
		netcat \
		nginx-extras \
		supervisor \
		mariadb-client \
	; \
	echo "en_US.UTF-8 UTF-8" > /etc/locale.gen; \
	locale-gen en_US.UTF-8; \
	#echo en_US.UTF-8 | dpkg-reconfigure locales; \
	dpkg-reconfigure locales; \
	/usr/sbin/update-locale LC_ALL=en_US.UTF-8; \
	\
	ln -s -f /etc/onlyoffice/documentserver/nginx/ds.conf /etc/nginx/conf.d/ds.conf; \
	mkdir -p /etc/nginx/includes; \
	for FILE in /etc/onlyoffice/documentserver/nginx/includes/*; do ln -s -f ${FILE} /etc/nginx/includes/${FILE##*/}; done; \
	for FILE in /etc/onlyoffice/documentserver/supervisor/*; do ln -s -f ${FILE} /etc/supervisor/conf.d/${FILE##*/}; done; \
	for FILE in /usr/local/onlyoffice/documentserver/server/FileConverter/bin/*.so*; do ln -s -f ${FILE} /usr/lib/${FILE##*/}; done; \
	ln -s -f /etc/onlyoffice/documentserver/logrotate/ds.conf /etc/logrotate.d/ds.conf; \
	\
	ls /usr/local/bin/documentserver-*.sh|xargs sed -i "s|/var/www|/usr/local|g"; \
	ls /usr/local/bin/documentserver-*.sh|xargs sed -i "s|ds:ds|onlyoffice:onlyoffice|g"; \
	ls /usr/local/bin/documentserver-*.sh|xargs sed -i "s|ds:|onlyoffice:|g"; \
	ls /etc/onlyoffice/documentserver/supervisor/ds-*.conf|xargs sed -i "s|/var/www|/usr/local|g"; \
	ls /etc/onlyoffice/documentserver/supervisor/ds-*.conf|xargs sed -i "s|user=ds|user=onlyoffice|g"; \
	ls /etc/onlyoffice/documentserver/supervisor/ds.conf|xargs sed -i "s|group:ds|group:onlyoffice|g"; \
	ls /etc/onlyoffice/documentserver/nginx/includes/*.conf|xargs sed -i "s|/var/www|/usr/local|g"; \
	ls /etc/onlyoffice/documentserver/*.json|xargs sed -i "s|/var/www|/usr/local|g"; \
	sed -i "s|postgres|mysql|g" /etc/onlyoffice/documentserver/local.json; \
	sed -i "s|5432|3306|g" /etc/onlyoffice/documentserver/local.json; \
	\
	rm -rf /etc/nginx/sites-enabled/default; \
	rm -rf /var/lib/apt/lists/*

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

VOLUME /var/log/onlyoffice /var/lib/onlyoffice /usr/local/onlyoffice/Data /usr/share/fonts/truetype/custom

ENTRYPOINT ["docker-entrypoint.sh"]

EXPOSE 80 443

CMD ["documentserver"]
