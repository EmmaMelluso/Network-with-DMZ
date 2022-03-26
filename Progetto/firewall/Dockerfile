#Dockerfile per firewall con iptables

FROM emmame/firewall_ulogd2:latest

LABEL maintainer emme "emmamelluso@libero.it"

RUN apt-get update && \
service ulogd2 restart

CMD echo "Dockerfile Firewall. Iptables : " && \
iptables -L 
