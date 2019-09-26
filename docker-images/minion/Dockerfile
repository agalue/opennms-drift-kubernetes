FROM opennms/openjdk:11.0.4.11

ARG MINION_VERSION=stable

ENV MINION_HOME="/opt/minion" \
    MINION_CONFIG="/opt/minion/etc/org.opennms.minion.controller.cfg" \
    MINION_ID="00000000-0000-0000-0000-deadbeef0001" \
    MINION_LOCATION="Docker" \
    OPENNMS_BROKER_URL="tcp://127.0.0.1:61616" \
    OPENNMS_HTTP_URL="http://127.0.0.1:8980/opennms" \
    OPENNMS_HTTP_USER="minion" \
    OPENNMS_HTTP_PASS="minion" \
    OPENNMS_BROKER_USER="minion" \
    OPENNMS_BROKER_PASS="minion"

RUN yum -y --setopt=tsflags=nodocs update && \
    rpm -Uvh http://yum.opennms.org/repofiles/opennms-repo-${MINION_VERSION}-rhel7.noarch.rpm && \
    rpm --import http://yum.opennms.org/OPENNMS-GPG-KEY && \
    yum -y install opennms-minion && \
    yum -y install net-tools sshpass openssh-clients && \
    yum clean all && \
    rm -rf /var/cache/yum && \
    chown minion:minion /opt/minion && \
    sed -r -i '/RUNAS/s/.*/export RUNAS=minion/' /etc/sysconfig/minion && \
    chgrp -R 0 /opt/minion && \
    chmod -R g=u /opt/minion && \
    cp /etc/skel/.bash* /opt/minion/ && \
    setcap cap_net_raw+ep ${JAVA_HOME}/bin/java && \
    echo ${JAVA_HOME}/lib/jli > /etc/ld.so.conf.d/java-latest.conf && \
    ldconfig

USER 999

COPY ./assets/* /

LABEL maintainer="Alejandro Galue <agalue@opennms.org>" \
      license="AGPLv3" \
      org.opennms.horizon.version="${MINION_VERSION}" \
      vendor="OpenNMS Community" \
      name="Minion"

ENTRYPOINT [ "/docker-entrypoint.sh" ]

CMD [ "-f" ]

##------------------------------------------------------------------------------
## EXPOSED PORTS
##------------------------------------------------------------------------------
## -- OpenNMS KARAF SSH   8201/TCP
## -- OpenNMS JMX        18980/TCP
## -- SNMP Trapd          1162/UDP
## -- Syslog              1514/UDP
EXPOSE 8201 1162/udp 1514/udp
