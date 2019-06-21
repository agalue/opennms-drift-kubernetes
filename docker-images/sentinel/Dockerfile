FROM opennms/openjdk:1.8.0

LABEL maintainer "Alejandro Galue <agalue@opennms.org>"

ARG SENTINEL_VERSION=stable
ARG MIRROR_HOST=yum.opennms.org

ENV SENTINEL_HOME=/opt/sentinel

# TODO MVR SENTINEL_LOCATION is not used at the moment
ENV SENTINEL_ID=
ENV SENTINEL_LOCATION=SENTINEL

ENV OPENNMS_BROKER_URL=tcp://127.0.0.1:61616
ENV OPENNMS_HTTP_URL=http://127.0.0.1:8980/opennms

ENV OPENNMS_HTTP_USER minion
ENV OPENNMS_HTTP_PASS minion
ENV OPENNMS_BROKER_USER minion
ENV OPENNMS_BROKER_PASS minion

ENV POSTGRES_HOST=localhost
ENV POSTGRES_PORT=5432
ENV POSTGRES_USER=postgres
ENV POSTGRES_PASSWORD=
ENV POSTGRES_DB=opennms

RUN yum -y --setopt=tsflags=nodocs update && \
    rpm -Uvh https://${MIRROR_HOST}/repofiles/opennms-repo-${SENTINEL_VERSION/\//-}-rhel7.noarch.rpm && \
    rpm --import https://${MIRROR_HOST}/OPENNMS-GPG-KEY && \
    yum -y install net-tools sshpass openssh-clients opennms-sentinel && \
    yum clean all && \
    rm -rf /var/cache/yum && \
    chown -R sentinel:sentinel /opt/sentinel && \
    chgrp -R 0 /opt/sentinel && \
    chmod -R g=u /opt/sentinel && \
    cp /etc/skel/.bash* /opt/sentinel/ && \
    setcap cap_net_raw+ep /usr/lib/jvm/java/bin/java && \
    echo /usr/lib/jvm/java/lib/amd64/jli > /etc/ld.so.conf.d/java-latest.conf && \
    ldconfig

USER 999

COPY ./docker-entrypoint.sh /

LABEL license="AGPLv3" \
      org.opennms.horizon.version="${SENTINEL_VERSION}" \
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
