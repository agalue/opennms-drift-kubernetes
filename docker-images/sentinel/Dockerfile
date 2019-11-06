FROM opennms/openjdk:11.0.4.11

ARG MIRROR_HOST=yum.opennms.org
ARG SENTINEL_VERSION=stable
ARG SENTINEL_UID=10001

ENV SENTINEL_HOME="/opt/sentinel" \
    SENTINEL_ID="" \
    SENTINEL_LOCATION="Docker" \
    OPENNMS_BROKER_URL="tcp://127.0.0.1:61616" \
    OPENNMS_HTTP_URL="http://127.0.0.1:8980/opennms" \
    OPENNMS_HTTP_USER="admin" \
    OPENNMS_HTTP_PASS="admin" \
    OPENNMS_BROKER_USER="admin" \
    OPENNMS_BROKER_PASS="admin" \
    POSTGRES_HOST="database" \
    POSTGRES_PORT="5432" \
    POSTGRES_USER="postgres" \
    POSTGRES_PASSWORD="postgres" \
    POSTGRES_DB="opennms"

RUN yum -y --setopt=tsflags=nodocs update && \
    yum -y install net-tools openssh-clients && \
    groupadd -g ${SENTINEL_UID} sentinel && \
    useradd -u ${SENTINEL_UID} -g ${SENTINEL_UID} -d /opt/sentinel -s /usr/bin/bash sentinel && \
    mkdir /opt/sentinel/.ssh && \
    chmod 700 /opt/sentinel/.ssh && \
    ssh-keygen -t rsa -f /opt/sentinel/.ssh/id_rsa -q -N "" && \
    chown -R sentinel:sentinel /opt/sentinel/.ssh && \
    setcap cap_net_raw+ep ${JAVA_HOME}/bin/java && \
    echo ${JAVA_HOME}/lib/jli > /etc/ld.so.conf.d/java-latest.conf && \
    ldconfig && \
    rpm -Uvh https://${MIRROR_HOST}/repofiles/opennms-repo-${SENTINEL_VERSION/\//-}-rhel7.noarch.rpm && \
    rpm --import https://${MIRROR_HOST}/OPENNMS-GPG-KEY && \
    yum -y install opennms-sentinel && \
    yum clean all && \
    echo sentinel=$(cat /opt/sentinel/.ssh/id_rsa.pub | awk '{print $2}'),viewer > /opt/sentinel/etc/keys.properties && \
    echo "_g_\\:admingroup = group,admin,manager,viewer,systembundles,ssh" >> /opt/sentinel/etc/keys.properties && \
    sed -r -i '/RUNAS/s/.*/export RUNAS=sentinel/' /etc/sysconfig/sentinel && \
    chgrp -R 0 /opt/sentinel && \
    chmod -R g=u /opt/sentinel && \
    chmod 600 /opt/sentinel/.ssh/id_rsa

COPY ./assets/* /

WORKDIR /opt/sentinel
USER ${SENTINEL_UID}

LABEL maintainer="Alejandro Galue <agalue@opennms.org>" \
      license="AGPLv3" \
      org.opennms.sentinel.version="${SENTINEL_VERSION}" \
      vendor="OpenNMS Community" \
      name="Sentinel"

ENTRYPOINT [ "/docker-entrypoint.sh" ]

CMD [ "-f" ]

##------------------------------------------------------------------------------
## EXPOSED PORTS
##------------------------------------------------------------------------------
## -- Sentinel Karaf Debug 5005/TCP
## -- Sentinel KARAF SSH   8301/TCP
EXPOSE 8301
