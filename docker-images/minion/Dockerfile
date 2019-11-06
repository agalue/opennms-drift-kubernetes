FROM opennms/openjdk:11.0.4.11

ARG MIRROR_HOST=yum.opennms.org
ARG MINION_VERSION=stable
ARG MINION_UID=10001

ENV MINION_HOME="/opt/minion" \
    MINION_CONFIG="/opt/minion/etc/org.opennms.minion.controller.cfg" \
    MINION_ID="00000000-0000-0000-0000-deadbeef0001" \
    MINION_LOCATION="Docker" \
    OPENNMS_BROKER_URL="tcp://127.0.0.1:61616" \
    OPENNMS_HTTP_URL="http://127.0.0.1:8980/opennms" \
    OPENNMS_HTTP_USER="admin" \
    OPENNMS_HTTP_PASS="admin" \
    OPENNMS_BROKER_USER="admin" \
    OPENNMS_BROKER_PASS="admin"

RUN yum -y --setopt=tsflags=nodocs update && \
    yum -y install net-tools openssh-clients && \
    groupadd -g ${MINION_UID} minion && \
    useradd -u ${MINION_UID} -g ${MINION_UID} -d /opt/minion -s /usr/bin/bash minion && \
    mkdir /opt/minion/.ssh && \
    chmod 700 /opt/minion/.ssh && \
    ssh-keygen -t rsa -f /opt/minion/.ssh/id_rsa -q -N "" && \
    chown -R minion:minion /opt/minion/.ssh && \
    setcap cap_net_raw+ep ${JAVA_HOME}/bin/java && \
    echo ${JAVA_HOME}/lib/jli > /etc/ld.so.conf.d/java-latest.conf && \
    ldconfig && \
    rpm -Uvh https://${MIRROR_HOST}/repofiles/opennms-repo-${MINION_VERSION/\//-}-rhel7.noarch.rpm && \
    rpm --import https://${MIRROR_HOST}/OPENNMS-GPG-KEY && \
    yum -y install opennms-minion && \
    yum clean all && \
    echo minion=$(cat /opt/minion/.ssh/id_rsa.pub | awk '{print $2}'),viewer > /opt/minion/etc/keys.properties && \
    echo "_g_\\:admingroup = group,admin,manager,viewer,systembundles,ssh" >> /opt/minion/etc/keys.properties && \
    sed -r -i '/RUNAS/s/.*/export RUNAS=minion/' /etc/sysconfig/minion && \
    chgrp -R 0 /opt/minion && \
    chmod -R g=u /opt/minion && \
    chmod 600 /opt/minion/.ssh/id_rsa

COPY ./assets/* /

WORKDIR /opt/minion
USER ${MINION_UID}

LABEL maintainer="Alejandro Galue <agalue@opennms.org>" \
      license="AGPLv3" \
      org.opennms.minion.version="${MINION_VERSION}" \
      vendor="OpenNMS Community" \
      name="Minion"

ENTRYPOINT [ "/docker-entrypoint.sh" ]

CMD [ "-f" ]

##------------------------------------------------------------------------------
## EXPOSED PORTS
##------------------------------------------------------------------------------
## -- OpenNMS KARAF SSH   8201/TCP
## -- SNMP Trapd          1162/UDP
## -- Syslog              1514/UDP
EXPOSE 8201 1162/udp 1514/udp
