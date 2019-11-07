FROM opennms/openjdk:11.0.5.10

ARG MIRROR_HOST=yum.opennms.org
ARG OPENNMS_VERSION="stable"
ARG OPENNMS_UID=10001

ENV OPENNMS_KARAF_SSH_HOST="0.0.0.0" \
    OPENNMS_KARAF_SSH_PORT="8101" \
    OPENNMS_DBNAME="opennms" \
    POSTGRES_HOST="database" \
    POSTGRES_PORT="5432" \
    POSTGRES_USER="postgres" \
    POSTGRES_PASSWORD="postgres" \
    OPENNMS_DBNAME="opennms" \
    OPENNMS_DBUSER="opennms" \
    OPENNMS_DBPASS="opennms" \
    JAVA_OPTS="-Xmx1024m -XX:MaxMetaspaceSize=512m"

RUN dnf -y --setopt=tsflags=nodocs update && \
    dnf -y install net-tools openssh-clients && \
    groupadd -g ${OPENNMS_UID} opennms && \
    useradd -u ${OPENNMS_UID} -g ${OPENNMS_UID} -d /opt/opennms -s /usr/bin/bash opennms && \
    setcap cap_net_raw+ep ${JAVA_HOME}/bin/java && \
    echo ${JAVA_HOME}/lib/jli > /etc/ld.so.conf.d/java-latest.conf && \
    ldconfig && \
    rpm -Uvh https://${MIRROR_HOST}/repofiles/opennms-repo-${OPENNMS_VERSION/\//-}-rhel8.noarch.rpm && \
    rpm --import https://${MIRROR_HOST}/OPENNMS-GPG-KEY && \
    dnf -y install epel-release && \
    dnf -y install rsync jq && \
    dnf -y install 'perl(LWP)' 'perl(XML::Twig)' && \
    dnf -y install gettext \
                   rrdtool \
                   jrrd2 \
                   opennms-core \
                   opennms-webapp-jetty \
                   opennms-plugin-protocol-cifs \
                   opennms-webapp-hawtio && \
    dnf clean all && \
    rm -rf /opt/opennms/logs \
           /var/opennms/rrd \
           /var/opennms/reports && \
    mkdir -p /opennms-data/logs \
             /opennms-data/rrd \
             /opennms-data/mibs \
             /opennms-data/reports \
             /opt/opennms-etc-overlay \
             /opt/opennms/assets && \
    mv /var/opennms/mibs/compiled /opennms-data/mibs/ && \
    rm -rf /var/opennms/mibs && \
    ln -s /opennms-data/logs /opt/opennms/logs && \
    ln -s /opennms-data/rrd /var/opennms/rrd && \
    ln -s /opennms-data/mibs /var/opennms/mibs && \
    ln -s /opennms-data/reports /var/opennms/reports && \
    mkdir -p /var/opennms/data-pristine && \
    cp -r /opennms-data/* /var/opennms/data-pristine/ && \
    sed -r -i '/RUNAS/s/root/opennms/' /opt/opennms/bin/opennms && \
    sed -r -i '/RUNAS/s/root/opennms/' /opt/opennms/bin/install && \
    sed -r -i '/RUNAS/s/root/opennms/' /opt/opennms/bin/upgrade && \
    sed -r -i '/^myuser/s/=.*/=$RUNAS/' /opt/opennms/bin/install && \
    sed -r -i '/^myuser/s/=.*/=$RUNAS/' /opt/opennms/bin/upgrade && \
    sed -r -i '/^myuser/s/=.*/=$RUNAS/' /opt/opennms/bin/opennms && \
    sed -r -i 's/"162"/"1162"/' /opt/opennms/etc/trapd-configuration.xml && \
    sed -r -i 's/"162"/"1162"/' /opt/opennms/share/etc-pristine/trapd-configuration.xml && \
    chown opennms:opennms -R /opt/opennms /opennms-data /opt/opennms-etc-overlay && \
    chgrp -R 0 /opt/opennms /opennms-data /opt/opennms-etc-overlay && \
    chmod -R g=u /opt/opennms /opennms-data /opt/opennms-etc-overlay

COPY ./assets/* /opt/opennms/assets/
COPY ./docker-entrypoint.sh /

WORKDIR /opt/opennms
USER ${OPENNMS_UID}

LABEL maintainer="Alejandro Galue <agalue@opennms.org>" \
      license="AGPLv3" \
      org.opennms.horizon.version="${OPENNMS_VERSION}" \
      vendor="OpenNMS Community" \
      name="Horizon"

ENTRYPOINT [ "/docker-entrypoint.sh" ]

CMD [ "-s" ]

##------------------------------------------------------------------------------
## EXPOSED PORTS
##------------------------------------------------------------------------------
## -- OpenNMS HTTP        8980/TCP
## -- OpenNMS JMX        18980/TCP
## -- OpenNMS KARAF SSH   8101/TCP
## -- OpenNMS ActiveMQ   61616/TCP
## -- OpenNMS Eventd      5817/TCP
## -- SNMP Trapd          1162/UDP
## -- Syslog Receiver    10514/UDP
EXPOSE 8980 8101 61616 1162/udp 10514/udp
