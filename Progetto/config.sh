#!/bin/bash

#Build dockerfile
cd firewall/
./build.sh
cd ..

cd host/
./build.sh
cd ..

cd ftpimmage/
./build.sh
cd ..

#Configurazione rete aziendale

##############################################################################################################################
#creo la sottorete "rete_esterna" e gli connetto un host							             #
##############################################################################################################################
docker network create --driver bridge --subnet=192.1.1.0/24 rete_esterna
docker run --privileged --network=rete_esterna --ip 192.1.1.2 -td --name=cliente1 hostubuntu bash

##############################################################################################################################
#creo la sottorete "dmz" e gli connetto un webserver							                     #
##############################################################################################################################
docker network create --driver bridge --subnet=192.1.2.0/24 dmz
docker run --privileged --network=dmz --ip 192.1.2.2 -p80:80 -p443:443 -tdi --name=webserver linode/lamp bash
docker exec --privileged -t webserver service apache2 start

##############################################################################################################################
#connetto FTP server a sottorete "dmz"						                     			     #
##############################################################################################################################
docker run --privileged --network=dmz --ip 192.1.2.4 -p20:20 -p21:21 -tdi --name=ftpserver ftpser bash

##############################################################################################################################
#connetto SMTP server a sottorete "dmz"						                     			     #
##############################################################################################################################
#docker run --privileged --network=dmz --ip 192.1.2.4 -p25:25 -tdi --name=smtpserver nsunina/postfix:v1.1 bash

##############################################################################################################################
#connetto DNS server a sottorete "dmz"						                     			     #
##############################################################################################################################
docker run --privileged --network=dmz --ip 192.1.2.3 -p53:53/udp -tdi --name=dnsser cosmicq/docker-bind:latest bash

##############################################################################################################################
#creo la sottorete "rete_interna" e gli connetto un host							             #
##############################################################################################################################
docker network create --driver bridge --subnet=192.1.3.0/24 rete_interna
docker run --privileged --network=rete_interna --ip 192.1.3.2 -td --name=host1 hostubuntu bash

##############################################################################################################################
#creo la sottorete "rete_intermedia"						                   			     #
##############################################################################################################################
docker network create --driver bridge --subnet=192.1.4.0/24 rete_intermedia

##############################################################################################################################
#run immagine firewall esterno e connessione a rete esterna						                     #
##############################################################################################################################
docker run --privileged --sysctl net.ipv4.ip_forward=1 --network=rete_esterna --ip 192.1.1.5 -td --name=firewall1 customfirewall bash

##############################################################################################################################
#run immagine firewall interno e connessione a rete interna						                     #
##############################################################################################################################
docker run --privileged --sysctl net.ipv4.ip_forward=1 --network=rete_interna --ip 192.1.3.6 -td --name=firewall2 customfirewall bash

##############################################################################################################################
#connetto firewall esterno a rete dmz						                                             #
##############################################################################################################################
docker network connect --ip 192.1.2.5 dmz firewall1

##############################################################################################################################
#connetto firewall esterno e interno a rete intermedia						                             #
##############################################################################################################################
docker network connect --ip 192.1.4.5 rete_intermedia firewall1
docker network connect --ip 192.1.4.6 rete_intermedia firewall2

##############################################################################################################################
#Assegno i gateway di default					                            				     #
##############################################################################################################################

docker exec firewall1 route add default gw firewall2
docker exec firewall2 route add default gw firewall1
docker exec cliente1  route add default gw firewall1
docker exec host1     route add default gw firewall2
docker exec webserver route add default gw firewall1
docker exec dnsser route add default gw firewall1
docker exec ftpserver route add default gw firewall1


echo "Ispezione reti:"
docker network inspect rete_interna 
docker network inspect rete_esterna 
docker network inspect dmz
docker network inspect rete_intermedia
docker ps 

#SETTO IPTABLES

# Cancellazione delle regole presenti nelle chains
docker exec --privileged -t firewall1 iptables -F
docker exec --privileged -t firewall2 iptables -F
docker exec --privileged -t firewall1 iptables -F -t nat
docker exec --privileged -t firewall2 iptables -F -t nat

# Eliminazione delle chains non standard vuote
docker exec --privileged -t firewall1 iptables -X
docker exec --privileged -t firewall2 iptables -X

# Policy di base per firewall1(blocco tutto quello che non è esplicitamente consentito)
docker exec --privileged -t firewall1 iptables -P INPUT DROP
docker exec --privileged -t firewall1 iptables -P OUTPUT DROP
docker exec --privileged -t firewall1 iptables -P FORWARD DROP

# Policy di base per firewall2(blocco tutto quello che non è esplicitamente consentito)
docker exec --privileged -t firewall2 iptables -P INPUT DROP
docker exec --privileged -t firewall2 iptables -P OUTPUT DROP
docker exec --privileged -t firewall2 iptables -P FORWARD DROP

#Firewall Esterno (firewall1)

# Protezione da syn flood
# Vedere il rate medio per protezione adeguata
docker exec --privileged -t firewall1 iptables -A FORWARD -p tcp --syn -m limit --limit 1/s -j ACCEPT
docker exec --privileged -t firewall2 iptables -A FORWARD -p tcp --syn -m limit --limit 1/s -j ACCEPT

# Protezione da ping of death
# Anche qui vedi rate medio
docker exec --privileged -t firewall1 iptables -A FORWARD -p icmp --icmp-type echo-request -m limit --limit 1/s -j ACCEPT
docker exec --privileged -t firewall2 iptables -A FORWARD -p icmp --icmp-type echo-request -m limit --limit 1/s -j ACCEPT

#1-Inoltra tutti i pacchetti provenienti dall'esterno sull'interfaccia della DMZ
docker exec --privileged -t firewall1 iptables -t filter -A FORWARD -i eth0 -o eth1 -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
docker exec --privileged -t firewall1 iptables -t filter -A FORWARD -i eth1 -o eth0 -m state --state ESTABLISHED,RELATED -j ACCEPT

#2-Inoltro tutti i pacchetti provenienti dall'interno eth2 a eth1 
docker exec --privileged -t firewall1 iptables -t filter -A FORWARD -i eth2 -o eth1 -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
docker exec --privileged -t firewall1 iptables -t filter -A FORWARD -i eth1 -o eth2 -m state --state ESTABLISHED,RELATED -j ACCEPT

#Firewall Interno (firewall2)
#1-Inoltro Pacchetti icmp da rete interna a rete intermedia
#Un host interno non puo' raggiungere un cliente che fa parte della rete esterna
docker exec --privileged -t firewall2 iptables -t filter -A FORWARD -p icmp -i eth0 -o eth1 -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
docker exec --privileged -t firewall2 iptables -t filter -A FORWARD -p icmp -i eth1 -o eth0 -m state --state ESTABLISHED,RELATED -j ACCEPT
# Droppo tutti i tentativi di connessione provenienti dalla DMZ verso la rete interna (non matcha è solo un controllo ulteriore)
docker exec --privileged -t firewall2 iptables -A FORWARD -p tcp -s 192.1.2.0/24 --syn -j DROP

#Natting da qualsiasi host della rete esterna dmz
#1-Web Server
docker exec --privileged -t firewall1 iptables -t nat -A PREROUTING -p tcp -i eth0 --dport 80 -j DNAT --to-dest 192.1.2.2
docker exec --privileged -t firewall1 iptables -t nat -A PREROUTING -p tcp -i eth0 --dport 443 -j DNAT --to-dest 192.1.2.2

#2-DNS Server
docker exec --privileged -t firewall1 iptables -t nat -A PREROUTING -p udp -i eth0 --dport 53 -j DNAT --to-dest 192.1.2.3

#3-FTP Server
docker exec --privileged -t firewall1 iptables -t nat -A PREROUTING -p tcp -i eth0 --dport 21 -j DNAT --to-dest 192.1.2.4

# Elimino pacchetti non validi
docker exec --privileged -t firewall1 iptables -A INPUT -m state --state INVALID -j DROP
docker exec --privileged -t firewall1 iptables -A FORWARD -m state --state INVALID -j DROP
docker exec --privileged -t firewall1 iptables -A OUTPUT -m state --state INVALID -j DROP

# Elimino pacchetti non validi
docker exec --privileged -t firewall2 iptables -A INPUT -m state --state INVALID -j DROP
docker exec --privileged -t firewall2 iptables -A FORWARD -m state --state INVALID -j DROP
docker exec --privileged -t firewall2 iptables -A OUTPUT -m state --state INVALID -j DROP

# Security 
docker exec --privileged -t firewall1 iptables -A FORWARD -p ip -f -j DROP
docker exec --privileged -t firewall1 iptables -A FORWARD -p tcp --tcp-flags ALL ACK,RST,SYN,FIN -j DROP
docker exec --privileged -t firewall1 iptables -A FORWARD -p tcp --tcp-flags SYN,FIN SYN,FIN -j DROP
docker exec --privileged -t firewall1 iptables -A FORWARD -p tcp --tcp-flags SYN,RST SYN,RST -j DROP

docker exec --privileged -t firewall2 iptables -A FORWARD -p ip -f -j DROP
docker exec --privileged -t firewall2 iptables -A FORWARD -p tcp --tcp-flags ALL ACK,RST,SYN,FIN -j DROP
docker exec --privileged -t firewall2 iptables -A FORWARD -p tcp --tcp-flags SYN,FIN SYN,FIN -j DROP
docker exec --privileged -t firewall2 iptables -A FORWARD -p tcp --tcp-flags SYN,RST SYN,RST -j DROP


#filtraggio per evitare ping of death 
#check per ipspoofing
#filtraggio pacchetti in cui i server della dmz tentano di stabilire connessioni con gli host interni (da impostare nel fw interno)
#stabilire regole piu' nel dettaglio, solo per accedere ai servizi messi a disposizione
#fare un log di tutti i pacchetti che vengono scartati (o di tutti in generale)

#Apertura terminal in root, per testing della rete
echo "Sono host1"
docker exec -i -t host1 bash
echo "Sono cliente"
docker exec -i -t cliente1 bash
echo "Sono webserver"
docker exec -i -t webserver bash
echo "Sono DNS server"
docker exec -i -t dnsser bash
echo "Sono FTP server"
docker exec -i -t ftpserver bash
