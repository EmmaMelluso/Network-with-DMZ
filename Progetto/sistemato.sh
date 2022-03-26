#!/bin/bash

#Build dockerfile
#cd firewall/
#./build.sh
#cd ..

cd host/
./build.sh
cd ..

cd ftpimmage/
./build.sh
cd ..

						#Configurazione rete aziendale

##############################################################################################################################
#				Creo la sottorete "rete_esterna" e gli connetto un host					     #
##############################################################################################################################
docker network create --driver bridge --subnet=192.1.1.0/24 rete_esterna
docker run --privileged --network=rete_esterna --ip 192.1.1.2 -td --name=cliente1 hostubuntu bash

##############################################################################################################################
#				Creo la sottorete "dmz" e gli connetto un webserver					     #
##############################################################################################################################
docker network create --driver bridge --subnet=192.1.2.0/24 dmz
docker run --privileged --network=dmz --ip 192.1.2.2 -p80:80 -p443:443 -tdi --name=webserver linode/lamp bash
docker exec --privileged -t webserver service apache2 start

##############################################################################################################################
#				Connetto FTP server a sottorete "dmz"						             #
##############################################################################################################################
docker run --privileged --network=dmz --ip 192.1.2.4 -p20:20 -p21:21 -tdi --name=ftpserver ftpser bash

##############################################################################################################################
#				Connetto DNS server a sottorete "dmz"						             #
##############################################################################################################################
docker run --privileged --network=dmz --ip 192.1.2.3 -p53:53/udp -tdi --name=dnsser cosmicq/docker-bind:latest bash

##############################################################################################################################
#				Creo la sottorete "rete_interna" e gli connetto un host				             #
##############################################################################################################################
docker network create --driver bridge --subnet=192.1.3.0/24 rete_interna
docker run --privileged --network=rete_interna --ip 192.1.3.2 -td --name=host1 hostubuntu bash

##############################################################################################################################
#				Creo la sottorete "rete_intermedia"						             #
##############################################################################################################################
docker network create --driver bridge --subnet=192.1.4.0/24 rete_intermedia

##############################################################################################################################
#				Run immagine firewall esterno e connessione a rete esterna				     #
##############################################################################################################################
docker run --privileged --sysctl net.ipv4.ip_forward=1 --network=rete_esterna --ip 192.1.1.5 -td --name=firewall1 emmame/firewall_ulogd2 bash
docker exec --privileged -t firewall1 service ulogd2 restart

##############################################################################################################################
#				Run immagine firewall interno e connessione a rete interna				     #
##############################################################################################################################
docker run --privileged --sysctl net.ipv4.ip_forward=1 --network=rete_interna --ip 192.1.3.6 -td --name=firewall2 emmame/firewall_ulogd2 bash
docker exec --privileged -t firewall2 service ulogd2 restart
##############################################################################################################################
#				Connetto firewall esterno a rete dmz						             #
##############################################################################################################################
docker network connect --ip 192.1.2.5 dmz firewall1

##############################################################################################################################
#				Connetto firewall esterno e interno a rete intermedia					     #
##############################################################################################################################
docker network connect --ip 192.1.4.5 rete_intermedia firewall1
docker network connect --ip 192.1.4.6 rete_intermedia firewall2

##############################################################################################################################
#				Assegno i gateway di default					                            				     #
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


#SETTO I DUE FIREWALLS CON IPTABLES
##############################################################################################################################
#				Cancellazione delle regole presenti nelle chains		                             #
##############################################################################################################################
docker exec --privileged -t firewall1 iptables -F
docker exec --privileged -t firewall2 iptables -F
docker exec --privileged -t firewall1 iptables -F -t nat
docker exec --privileged -t firewall2 iptables -F -t nat

##############################################################################################################################
#				Eliminazione delle chains non standard vuote			                             #
##############################################################################################################################
docker exec --privileged -t firewall1 iptables -X
docker exec --privileged -t firewall2 iptables -X


##############################################################################################################################
#		Policy di base per firewall1 e firewall2 (blocco tutto quello che non è esplicitamente consentito)           #
##############################################################################################################################
docker exec --privileged -t firewall1 iptables -P INPUT DROP
docker exec --privileged -t firewall1 iptables -P OUTPUT DROP
docker exec --privileged -t firewall1 iptables -P FORWARD DROP

docker exec --privileged -t firewall2 iptables -P INPUT DROP
docker exec --privileged -t firewall2 iptables -P OUTPUT DROP
docker exec --privileged -t firewall2 iptables -P FORWARD DROP



# docker exec --privileged -t firewall1 iptables -A FORWARD -j NFLOG --nflog-prefix="FORWARD Log nuovo1 : "

# Elimino pacchetti non validi 1 - VERIFICATO
docker exec --privileged -t firewall1 iptables -A INPUT -m state --state INVALID -j DROP
docker exec --privileged -t firewall1 iptables -A FORWARD -m state --state INVALID -j DROP
docker exec --privileged -t firewall1 iptables -A OUTPUT -m state --state INVALID -j DROP


# docker exec --privileged -t firewall1 iptables -A FORWARD -j NFLOG --nflog-prefix="FORWARD Log nuovo2 : "

# Elimino pacchetti non validi 2 - VERIFICATO
docker exec --privileged -t firewall2 iptables -A INPUT -m state --state INVALID -j DROP
docker exec --privileged -t firewall2 iptables -A FORWARD -m state --state INVALID -j DROP
docker exec --privileged -t firewall2 iptables -A OUTPUT -m state --state INVALID -j DROP

# DA TESTARE
# docker exec --privileged -t firewall1 iptables -A FORWARD -j NFLOG --nflog-prefix="FORWARD Log frag1: "
docker exec --privileged -t firewall1 iptables -A FORWARD -p ip -f -j DROP	
# docker exec --privileged -t firewall1 iptables -A FORWARD -j NFLOG --nflog-prefix="FORWARD Log frag2: "

# Security  - VERIFICATO (SONO CONSIDERATI TUTTI PACCHETTI INVALIDI)															
docker exec --privileged -t firewall1 iptables -A FORWARD -p tcp --tcp-flags ALL ACK,RST,SYN,FIN -j DROP	# Droppo pacchetti no-sense

docker exec --privileged -t firewall1 iptables -A FORWARD -p tcp --tcp-flags SYN,FIN SYN,FIN -j DROP
docker exec --privileged -t firewall1 iptables -A FORWARD -p tcp --tcp-flags SYN,RST SYN,RST -j DROP

docker exec --privileged -t firewall2 iptables -A FORWARD -p ip -f -j DROP
docker exec --privileged -t firewall2 iptables -A FORWARD -p tcp --tcp-flags ALL ACK,RST,SYN,FIN -j DROP
docker exec --privileged -t firewall2 iptables -A FORWARD -p tcp --tcp-flags SYN,FIN SYN,FIN -j DROP
docker exec --privileged -t firewall2 iptables -A FORWARD -p tcp --tcp-flags SYN,RST SYN,RST -j DROP

# DA QUI IN POI E' DA TESTARE
# Limito connessioni per IP sorgente
docker exec --privileged -t firewall1 iptables -A INPUT -p tcp -m connlimit --connlimit-above 80 -j REJECT --reject-with tcp-reset
docker exec --privileged -t firewall2 iptables -A INPUT -p tcp -m connlimit --connlimit-above 80 -j REJECT --reject-with tcp-reset

# Droppo pacchetti TCP che sono relativi a nuove connessioni ma che non hanno il flag syn = 1
docker exec --privileged -t firewall1 iptables -A INPUT -p tcp ! --syn -j DROP
docker exec --privileged -t firewall2 iptables -A INPUT -p tcp ! --syn -j DROP

# 1 - Protezione Ip Spoofing
# Tutti i pacchetti che provengono dall'esterno e hanno source address interno vengono scartati
docker exec --privileged -t firewall1 iptables -A FORWARD -s 192.1.3.0/24  -i eth0 -j DROP

# 2 - Protezione Smurf Attack
# Tutti i pacchetti diretti all'indirizzo broadcast della rete DMZ, interna e intermedia vengono scartati
docker exec --privileged -t firewall1 iptables -A FORWARD -p icmp -i eth0 -d 192.1.2.255 -j DROP
docker exec --privileged -t firewall1 iptables -A FORWARD -p icmp -i eth0 -d 192.1.3.255 -j DROP
docker exec --privileged -t firewall1 iptables -A FORWARD -p icmp -i eth0 -d 192.1.4.255 -j DROP

docker exec --privileged -t firewall2 iptables -A FORWARD -p icmp -i eth0 -d 192.1.2.255 -j DROP
docker exec --privileged -t firewall2 iptables -A FORWARD -p icmp -i eth0 -d 192.1.3.255 -j DROP
docker exec --privileged -t firewall2 iptables -A FORWARD -p icmp -i eth0 -d 192.1.4.255 -j DROP

# 3 - Protezione Syn Flood Attack 
# Creo nuova catena SYN_FLOOD
docker exec --privileged -t firewall1 iptables -N SYN_FLOOD		
# Eseguo le regole della catena SYN_FLOOD se il pacchetto in ingresso è tcp e ha il flag syn = 1		
docker exec --privileged -t firewall1 iptables -A INPUT -p tcp --syn -j SYN_FLOOD		
# Il pacchetto viene fatto passare se rispetta i limiti prefissati
# Numero massimo di confronti al secondo (in media) = 1
# Numero massimo di confronti iniziali (in media) = 3
docker exec --privileged -t firewall1 iptables -A SYN_FLOOD -m limit --limit 1/s --limit-burst 3 -j RETURN
# Se non ha un match con la regola precedente il pacchetto viene scartato
docker exec --privileged -t firewall1 iptables -A SYN_FLOOD -j DROP


docker exec --privileged -t firewall2 iptables -N SYN_FLOOD			
docker exec --privileged -t firewall2 iptables -A INPUT -p tcp --syn -j SYN_FLOOD		
docker exec --privileged -t firewall2 iptables -A SYN_FLOOD -m limit --limit 1/s --limit-burst 3 -j RETURN
docker exec --privileged -t firewall2 iptables -A SYN_FLOOD -j DROP

# 4 - Protezione Ping of Death Attack
# Accetto tutte le richieste se rispettano i limiti prefissati
docker exec --privileged -t firewall1 iptables -A INPUT -p icmp --icmp-type echo-request -m limit --limit 1/s --limit-burst 1 -j ACCEPT
# Se non ho un match con la regola di sopra il pacchetto va necessariamente scartato
docker exec --privileged -t firewall1 iptables -A INPUT -p icmp --icmp-type echo-request -j DROP
# Accetto le ping req provenienti da connessioni già stabilite
docker exec --privileged -t firewall1 iptables -A OUTPUT -p icmp --icmp-type echo-request -j ACCEPT

docker exec --privileged -t firewall2 iptables -A INPUT -p icmp --icmp-type echo-request -m limit --limit 1/s --limit-burst 1 -j ACCEPT
docker exec --privileged -t firewall2 iptables -A INPUT -p icmp --icmp-type echo-request -j DROP
docker exec --privileged -t firewall2 iptables -A OUTPUT -p icmp --icmp-type echo-request -j ACCEPT


# Droppo tutti i pacchetti provenienti dall'esterno e che hanno per ip destinazione quello di un host interno
docker exec --privileged -t firewall1 iptables -t filter -A FORWARD -i eth0 -o eth2 -m state --state NEW,ESTABLISHED,RELATED -j DROP

# Accetto tutto il traffico diretto alla porta 53 protocollo tcp
docker exec --privileged -t firewall1 iptables -t filter -A FORWARD -i eth0 -o eth1 -p udp --dport 53 -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT

# Droppo tutto il resto del traffico UDP
docker exec --privileged -t firewall1 iptables -t filter -A FORWARD -i eth0 -o eth1 -p udp -m state --state NEW,ESTABLISHED,RELATED -j DROP

docker exec --privileged -t firewall2 iptables -t filter -A FORWARD -i eth0 -o eth1 -p udp --dport 53 -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
docker exec --privileged -t firewall2 iptables -t filter -A FORWARD -i eth0 -o eth1 -p udp -m state --state NEW,ESTABLISHED,RELATED -j DROP

# Inoltro tutto il resto dei pacchetti provenienti dall'esterno (eth0) sull'interfaccia della DMZ (eth1)	                     
docker exec --privileged -t firewall1 iptables -t filter -A FORWARD -i eth0 -o eth1 -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
docker exec --privileged -t firewall1 iptables -t filter -A FORWARD -i eth1 -o eth0 -m state --state ESTABLISHED,RELATED -j ACCEPT

# Inoltro tutti i pacchetti provenienti dall'interno (eth2) sull'interfaccia della DMZ (eth1) 	                     
docker exec --privileged -t firewall1 iptables -t filter -A FORWARD -i eth2 -o eth1 -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
docker exec --privileged -t firewall1 iptables -t filter -A FORWARD -i eth1 -o eth2 -m state --state ESTABLISHED,RELATED -j ACCEPT

# Droppo tutti i tentativi di connessione su tcp provenienti dalla DMZ 
docker exec --privileged -t firewall2 iptables -A FORWARD -p tcp -s 192.1.2.0/24 --syn -j DROP

# Droppo tentativi di connessione rete interna - rete esterna
docker exec --privileged -t firewall2 iptables -A FORWARD -d 192.1.1.0/24 -j DROP

# Consento comunicazione rete interna - DMZ
docker exec --privileged -t firewall2 iptables -t filter -A FORWARD -i eth0 -o eth1 -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
docker exec --privileged -t firewall2 iptables -t filter -A FORWARD -i eth1 -o eth0 -m state --state ESTABLISHED,RELATED -j ACCEPT

#Natting da qualsiasi host della rete esterna dmz
##############################################################################################################################
#							1-Web Server				                  	     #
##############################################################################################################################
docker exec --privileged -t firewall1 iptables -t nat -A PREROUTING -p tcp -i eth0 --dport 80 -j DNAT --to-dest 192.1.2.2
docker exec --privileged -t firewall1 iptables -t nat -A PREROUTING -p tcp -i eth0 --dport 443 -j DNAT --to-dest 192.1.2.2

##############################################################################################################################
#							2-DNS Server				                  	     #
##############################################################################################################################
docker exec --privileged -t firewall1 iptables -t nat -A PREROUTING -p udp -i eth0 --dport 53 -j DNAT --to-dest 192.1.2.3

##############################################################################################################################
#							3-FTP Server				                  	     #
##############################################################################################################################
docker exec --privileged -t firewall1 iptables -t nat -A PREROUTING -p tcp -i eth0 --dport 21 -j DNAT --to-dest 192.1.2.4
docker exec --privileged -t firewall1 iptables -t nat -A PREROUTING -p tcp -i eth0 --dport 20 -j DNAT --to-dest 192.1.2.4



