#Dockerfile per firewall con iptables

FROM ubuntu:latest

LABEL maintainer emme "emmamelluso@libero.it"

RUN apt-get update && apt-get install -y \
bridge-utils \
net-tools \
iptables \
ulogd2 \
nano

CMD echo "Dockerfile Firewall. Iptables : " && \
iptables -L
