FROM opennms/openjdk:11

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
    groupadd -g ${SENTINEL_UID} sentinel && \
    useradd -u ${SENTINEL_UID} -g ${SENTINEL_UID} -d /opt/sentinel -s /usr/bin/bash sentinel && \
    setcap cap_net_raw+ep ${JAVA_HOME}/bin/java && \
    echo ${JAVA_HOME}/lib/jli > /etc/ld.so.conf.d/java-latest.conf && \
    ldconfig && \
    rpm -Uvh https://${MIRROR_HOST}/repofiles/opennms-repo-${SENTINEL_VERSION/\//-}-rhel7.noarch.rpm && \
    rpm --import https://${MIRROR_HOST}/OPENNMS-GPG-KEY && \
    yum -y install opennms-sentinel && \
    yum -y install net-tools sshpass openssh-clients && \
    yum clean all && \
    rm -rf /var/cache/yum && \
    chown -R sentinel:sentinel /opt/sentinel && \
    sed -r -i '/RUNAS/s/.*/export RUNAS=sentinel/' /etc/sysconfig/sentinel && \
    chgrp -R 0 /opt/sentinel && \
    chmod -R g=u /opt/sentinel

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
