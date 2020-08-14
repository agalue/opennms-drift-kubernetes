FROM ubuntu:18.04

ENV MINION_SOURCE=stable
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -y && \
    apt-get upgrade -y && \
    apt-get install snmp snmp-mibs-downloader tzdata iproute2 iputils-ping curl rsync gnupg ca-certificates ssh sshpass openjdk-11-jre -y && \
    echo "deb https://debian.opennms.org $MINION_SOURCE main" | tee /etc/apt/sources.list.d/opennms.list && \
    curl https://debian.opennms.org/OPENNMS-GPG-KEY 2>/dev/null | apt-key add - && \
    apt-get update && \
    apt-get install opennms-minion -y && \
    apt-get clean && \
    ln -fs /usr/share/zoneinfo/America/New_York /etc/localtime && \
    dpkg-reconfigure --frontend noninteractive tzdata

USER root

COPY ./etc-overlay /usr/share/minion/etc-overlay
COPY ./entrypoint.sh /

LABEL maintainer "Alejandro Galue <agalue@opennms.org>" \
      license="AGPLv3" \
      name="Minion for GNS3"

ENTRYPOINT [ "/entrypoint.sh" ]

EXPOSE 8201/tcp 162/udp 514/udp 50001/udp 50002/udp 8877/udp 4729/udp 6343/udp 4738/udp
