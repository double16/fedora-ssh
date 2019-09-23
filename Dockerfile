FROM fedora:30

ARG RELEASE_VERSION="30.0.0"
ARG YUM_PROXY=

# ------------------------------------------------------------------------------
# - Import the RPM GPG keys for repositories
# - Base install of required packages
# - Install supervisord (used to run more than a single process)
# - Install supervisor-stdout to allow output of services started by
#  supervisord to be easily inspected with "docker logs".
# ------------------------------------------------------------------------------
RUN rpm --rebuilddb \
	&& echo "proxy=${YUM_PROXY}" >> /etc/dnf/dnf.conf \
	&& dnf -y install \
			--setopt=tsflags=nodocs \
	    inotify-tools-3.14-17.fc30 \
		openssh-clients-8.0p1-5.fc30 \
		openssh-server-8.0p1-5.fc30 \
		openssl-1:1.1.1c-6.fc30 \
		python2-setuptools-40.8.0-1.fc30 \
		util-linux-user-2.33.2-2.fc30 \
		procps-ng-3.3.15-5.fc30 \
		findutils-4.6.0-22.fc30 \
		passwd-0.80-5.fc30 \
	&& dnf clean all \
	&& sed '/^proxy=/d' -i /etc/dnf/dnf.conf \
	&& easy_install \
		'supervisor == 4.0.4' \
		'supervisor-stdout == 0.1.1' \
	&& mkdir -p \
		/var/log/supervisor/ \
	&& rm -rf /etc/ld.so.cache \
	&& rm -rf /sbin/sln \
	&& rm -rf /usr/{{lib,share}/share/{man,doc,info,cracklib,i18n},{lib,lib64}/gconv,bin/localedef,sbin/build-locale-archive} \
	&& rm -rf /{root,tmp,var/cache/{ldconfig,yum}}/* \
	&& > /etc/sysconfig/i18n

# ------------------------------------------------------------------------------
# Copy files into place
# ------------------------------------------------------------------------------
ADD src /

# ------------------------------------------------------------------------------
# Provisioning
# - UTC Timezone
# - Networking
# - Configure SSH defaults for non-root public key authentication
# - Enable the wheel sudoers group
# - Replace placeholders with values in systemd service unit template
# - Set permissions
# ------------------------------------------------------------------------------
RUN ln -sf \
		/usr/share/zoneinfo/UTC \
		/etc/localtime \
	&& echo "NETWORKING=yes" \
		> /etc/sysconfig/network \
	&& sed -i \
		-e 's~^PasswordAuthentication yes~PasswordAuthentication no~g' \
		-e 's~^#PermitRootLogin yes~PermitRootLogin no~g' \
		-e 's~^#UseDNS yes~UseDNS no~g' \
		-e 's~^\(.*\)/usr/libexec/openssh/sftp-server$~\1internal-sftp~g' \
		/etc/ssh/sshd_config \
	&& sed -i \
		-e 's~^# %wheel\tALL=(ALL)\tALL~%wheel\tALL=(ALL) ALL~g' \
		-e 's~\(.*\) requiretty$~#\1requiretty~' \
		/etc/sudoers \
	&& sed -i \
		-e "s~{{RELEASE_VERSION}}~${RELEASE_VERSION}~g" \
		/etc/systemd/system/fedora-ssh@.service \
	&& chmod 644 \
		/etc/{supervisord.conf,supervisord.d/{20-sshd-bootstrap,50-sshd-wrapper}.conf} \
	&& chmod 700 \
		/usr/{bin/healthcheck,sbin/{scmi,sshd-{bootstrap,wrapper},system-{timezone,timezone-wrapper}}}

EXPOSE 22

# ------------------------------------------------------------------------------
# Set default environment variables
# ------------------------------------------------------------------------------
ENV \
	ENABLE_SSHD_BOOTSTRAP="true" \
	ENABLE_SSHD_WRAPPER="true" \
	ENABLE_SUPERVISOR_STDOUT="false" \
	SSH_AUTHORIZED_KEYS="" \
	SSH_CHROOT_DIRECTORY="%h" \
	SSH_INHERIT_ENVIRONMENT="false" \
	SSH_PASSWORD_AUTHENTICATION="false" \
	SSH_SUDO="ALL=(ALL) ALL" \
	SSH_USER="app-admin" \
	SSH_USER_FORCE_SFTP="false" \
	SSH_USER_HOME="/home/%u" \
	SSH_USER_ID="500:500" \
	SSH_USER_PASSWORD="" \
	SSH_USER_PASSWORD_HASHED="false" \
	SSH_USER_PRIVATE_KEY="" \
	SSH_USER_SHELL="/bin/bash" \
	SYSTEM_TIMEZONE="UTC"

# ------------------------------------------------------------------------------
# Set image metadata
# ------------------------------------------------------------------------------
LABEL \
	maintainer="Patrick Double <pat@patdouble.com>" \
	install="docker run \
--rm \
--privileged \
--volume /:/media/root \
pdouble16/fedora-ssh:${RELEASE_VERSION} \
/usr/sbin/scmi install \
--chroot=/media/root \
--name=\${NAME} \
--tag=${RELEASE_VERSION} \
--setopt='--volume {{NAME}}.config-ssh:/etc/ssh'" \
	uninstall="docker run \
--rm \
--privileged \
--volume /:/media/root \
pdouble16/fedora-ssh:${RELEASE_VERSION} \
/usr/sbin/scmi uninstall \
--chroot=/media/root \
--name=\${NAME} \
--tag=${RELEASE_VERSION} \
--setopt='--volume {{NAME}}.config-ssh:/etc/ssh'" \
	org.label-schema.name="fedora-ssh" \
	org.label-schema.version="${RELEASE_VERSION}" \
	org.label-schema.release="pdouble16/fedora-ssh:${RELEASE_VERSION}" \
	org.label-schema.license="MIT" \
	org.label-schema.vendor="pdouble16" \
	org.label-schema.url="https://github.com/pdouble16/fedora-ssh" \
	org.label-schema.description="Fedora 30 - Supervisor / OpenSSH."

HEALTHCHECK \
	--interval=1s \
	--timeout=1s \
	--retries=5 \
	CMD ["/usr/bin/healthcheck"]

CMD ["/usr/bin/supervisord", "--configuration=/etc/supervisord.conf"]
