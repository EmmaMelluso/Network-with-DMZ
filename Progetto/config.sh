#!/bin/bash

						#Configurazione rete aziendale
##############################################################################################################################
#				Creo la sottorete "rete_esterna" e gli connetto un host					     #
##############################################################################################################################
docker network create --driver bridge --subnet=192.1.1.0/24 rete_esterna
docker run --privileged --network=rete_esterna --ip 192.1.1.2 -td --name=cliente1 emmame/simpleubuntu bash

##############################################################################################################################
#			Creo la sottorete "dmz" e gli connetto un webserver, server FTP e server DNS			     #
##############################################################################################################################
docker network create --driver bridge --subnet=192.1.2.0/24 dmz
docker run  --privileged --network=dmz --ip 192.1.2.2 -p80:80 -p443:443 -tdi --name=webserver linode/lamp bash
docker exec --privileged -t webserver service apache2 start
docker run  --privileged --network=dmz --ip 192.1.2.4 -p20:20 -p21:21 -tdi --name=ftpserver ftpser bash
docker run  --privileged --network=dmz --ip 192.1.2.3 -p53:53/udp -tdi --name=dnsser cosmicq/docker-bind:latest bash

##############################################################################################################################
#				Creo la sottorete "rete_interna" e gli connetto un host				             #
##############################################################################################################################
docker network create --driver bridge --subnet=192.1.3.0/24 rete_interna
docker run --privileged --network=rete_interna --ip 192.1.3.2 -td --name=host1 emmame/simpleubuntu bash

##############################################################################################################################
#				Run immagine firewall esterno e connessione a rete esterna				     #
##############################################################################################################################
docker run  --privileged --sysctl net.ipv4.ip_forward=1 --network=rete_esterna --ip 192.1.1.5 -td --name=firewall1 emmame/firewall_ulogd2 bash
docker exec --privileged -t firewall1 service ulogd2 restart

##############################################################################################################################
#				Run immagine firewall interno e connessione a rete interna				     #
##############################################################################################################################
docker run  --privileged --sysctl net.ipv4.ip_forward=1 --network=rete_interna --ip 192.1.3.6 -td --name=firewall2 emmame/firewall_ulogd2 bash
docker exec --privileged -t firewall2 service ulogd2 restart

##############################################################################################################################
#				Connetto firewall esterno e interno a rete dmz						     #
##############################################################################################################################
docker network connect --ip 192.1.2.5 dmz firewall1
docker network connect --ip 192.1.2.6 dmz firewall2

##############################################################################################################################
#				Assegno i gateway di default					                             #
##############################################################################################################################
docker exec cliente1  route add default   gw firewall1
docker exec host1     route add default   gw firewall2
docker exec webserver route add 192.1.1.2 gw firewall1
docker exec webserver route add 192.1.3.2 gw firewall2
docker exec dnsser    route add 192.1.1.2 gw firewall1
docker exec dnsser    route add 192.1.3.2 gw firewall2
docker exec ftpserver route add 192.1.1.2 gw firewall1
docker exec ftpserver route add 192.1.3.2 gw firewall2

echo "Ispezione reti:"
docker network inspect rete_interna 
docker network inspect rete_esterna 
docker network inspect dmz
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

# Elimino pacchetti non validi 1 - VERIFICATO
docker exec --privileged -t firewall1 iptables -A INPUT   -m state --state INVALID -j DROP
docker exec --privileged -t firewall1 iptables -A FORWARD -m state --state INVALID -j DROP
docker exec --privileged -t firewall1 iptables -A OUTPUT  -m state --state INVALID -j DROP

# Elimino pacchetti non validi 2 - VERIFICATO
docker exec --privileged -t firewall2 iptables -A INPUT   -m state --state INVALID -j DROP
docker exec --privileged -t firewall2 iptables -A FORWARD -m state --state INVALID -j DROP
docker exec --privileged -t firewall2 iptables -A OUTPUT  -m state --state INVALID -j DROP

docker exec --privileged -t firewall1 iptables -A FORWARD -f -j DROP					# Droppo pacchetti ip frammentati
docker exec --privileged -t firewall2 iptables -A FORWARD -f -j DROP

# Security  - VERIFICATO (SONO CONSIDERATI TUTTI PACCHETTI INVALIDI)												
docker exec --privileged -t firewall1 iptables -A FORWARD -p tcp --tcp-flags ALL ACK,RST,SYN,FIN -j DROP	# Droppo pacchetti no-sense
docker exec --privileged -t firewall1 iptables -A FORWARD -p tcp --tcp-flags ALL ALL -j DROP
docker exec --privileged -t firewall1 iptables -A FORWARD -p tcp --tcp-flags ALL NONE -j DROP
docker exec --privileged -t firewall1 iptables -A FORWARD -p tcp --tcp-flags SYN,FIN SYN,FIN -j DROP
docker exec --privileged -t firewall1 iptables -A FORWARD -p tcp --tcp-flags SYN,RST SYN,RST -j DROP

docker exec --privileged -t firewall2 iptables -A FORWARD -p tcp --tcp-flags ALL ACK,RST,SYN,FIN -j DROP
docker exec --privileged -t firewall2 iptables -A FORWARD -p tcp --tcp-flags ALL ALL -j DROP
docker exec --privileged -t firewall2 iptables -A FORWARD -p tcp --tcp-flags ALL NONE -j DROP			# Per evitare TCP null scan
docker exec --privileged -t firewall2 iptables -A FORWARD -p tcp --tcp-flags SYN,FIN SYN,FIN -j DROP
docker exec --privileged -t firewall2 iptables -A FORWARD -p tcp --tcp-flags SYN,RST SYN,RST -j DROP

# Protezione Ip Spoofing
# Tutti i pacchetti che provengono dall'esterno e hanno source address interno vengono scartati
docker exec --privileged -t firewall1 iptables -A FORWARD -s 192.1.3.0/24  -i eth0 -j DROP

# Protezione Syn Flood Attack 
# Creo nuova catena SYN_FLOOD

docker exec --privileged -t firewall1 iptables -N SYN_FLOOD		
# Eseguo le regole della catena SYN_FLOOD se il pacchetto in ingresso è tcp e ha il flag syn = 1		
docker exec --privileged -t firewall1 iptables -A FORWARD -p tcp --syn -j SYN_FLOOD		
# Il pacchetto viene fatto passare se rispetta i limiti prefissati
# Numero massimo di confronti al secondo (in media) = 1
# Numero massimo di confronti iniziali (in media) = 5 default
docker exec --privileged -t firewall1 iptables -A SYN_FLOOD -m limit --limit 1/s -j RETURN
# Se non ha un match con la regola precedente il pacchetto viene scartato
docker exec --privileged -t firewall1 iptables -A SYN_FLOOD -j DROP


docker exec --privileged -t firewall2 iptables -N SYN_FLOOD			
docker exec --privileged -t firewall2 iptables -A FORWARD -p tcp --syn -j SYN_FLOOD		
docker exec --privileged -t firewall2 iptables -A SYN_FLOOD -m limit --limit 1/s -j RETURN
docker exec --privileged -t firewall2 iptables -A SYN_FLOOD -j DROP

# Protezione Ping of Death Attack
docker exec --privileged -t firewall1 iptables -A FORWARD -j NFLOG --nflog-prefix="FORWARD Log pre-regola: "
docker exec --privileged -t firewall1 iptables -N PING_OF_DEATH
docker exec --privileged -t firewall1 iptables -A FORWARD -p icmp -j PING_OF_DEATH
# Accetto tutte le richieste se rispettano i limiti prefissati
docker exec --privileged -t firewall1 iptables -A PING_OF_DEATH -p icmp --icmp-type echo-request -m limit --limit 1/s -j RETURN
# Se non ho un match con la regola di sopra il pacchetto va necessariamente scartato
docker exec --privileged -t firewall1 iptables -A PING_OF_DEATH -p icmp --icmp-type echo-request -j DROP
docker exec --privileged -t firewall1 iptables -A FORWARD -j NFLOG --nflog-prefix="FORWARD Log post-regola: "

docker exec --privileged -t firewall2 iptables -N PING_OF_DEATH
docker exec --privileged -t firewall2 iptables -A FORWARD -p icmp -j PING_OF_DEATH
docker exec --privileged -t firewall2 iptables -A PING_OF_DEATH -p icmp --icmp-type echo-request -m limit --limit 1/s -j RETURN
docker exec --privileged -t firewall2 iptables -A PING_OF_DEATH -p icmp --icmp-type echo-request -j DROP

# Droppo tutti i pacchetti provenienti dall'esterno e che hanno per ip destinazione quello di un host interno
docker exec --privileged -t firewall1 iptables -t filter -A FORWARD -i eth0 -o eth2 -m state --state NEW,ESTABLISHED,RELATED -j DROP

# Evito UDP-flood Attacks
docker exec --privileged -t firewall1 iptables -N UDP_FLOOD
docker exec --privileged -t firewall1 iptables -A FORWARD -p udp -j UDP_FLOOD
docker exec --privileged -t firewall1 iptables -A UDP_FLOOD -p udp -m limit --limit 1/s -j RETURN
docker exec --privileged -t firewall1 iptables -A UDP_FLOOD -j DROP

docker exec --privileged -t firewall2 iptables -N UDP_FLOOD
docker exec --privileged -t firewall2 iptables -A FORWARD -p udp -j UDP_FLOOD
docker exec --privileged -t firewall2 iptables -A UDP_FLOOD -p udp -m limit --limit 1/s -j RETURN
docker exec --privileged -t firewall2 iptables -A UDP_FLOOD -j DROP

# Accetto tutto il traffico diretto alla porta 53 protocollo udp
docker exec --privileged -t firewall1 iptables -t filter -A FORWARD -i eth0 -o eth1 -p udp -d 192.1.2.3 --dport 53 -j ACCEPT
docker exec --privileged -t firewall1 iptables -t filter -A FORWARD -i eth1 -o eth0 -p udp -j ACCEPT

# Droppo tutto il resto del traffico UDP
docker exec --privileged -t firewall1 iptables -t filter -A FORWARD -i eth0 -o eth1 -p udp -j DROP

docker exec --privileged -t firewall2 iptables -t filter -A FORWARD -i eth0 -o eth1 -p udp -d 192.1.2.3 --dport 53 -j ACCEPT
docker exec --privileged -t firewall2 iptables -t filter -A FORWARD -i eth1 -o eth0 -p udp -j ACCEPT
docker exec --privileged -t firewall2 iptables -t filter -A FORWARD -i eth0 -o eth1 -p udp -j DROP

# Inoltro tutto il resto dei pacchetti provenienti dall'esterno (eth0) sull'interfaccia della DMZ (eth1)	                     
docker exec --privileged -t firewall1 iptables -t filter -A FORWARD -i eth0 -o eth1 -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
docker exec --privileged -t firewall1 iptables -t filter -A FORWARD -i eth1 -o eth0 -m state --state ESTABLISHED,RELATED -j ACCEPT

# Inoltro tutto il resto dei pacchetti provenienti dall'esterno (eth0) sull'interfaccia della DMZ (eth1)	                     
docker exec --privileged -t firewall2 iptables -t filter -A FORWARD -i eth0 -o eth1 -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
docker exec --privileged -t firewall2 iptables -t filter -A FORWARD -i eth1 -o eth0 -m state --state ESTABLISHED,RELATED -j ACCEPT

# Droppo tutti i tentativi di connessione su tcp provenienti dalla DMZ 
docker exec --privileged -t firewall2 iptables -A FORWARD -p tcp -s 192.1.2.0/24 --syn -j DROP

# Droppo tentativi di connessione rete interna - rete esterna
docker exec --privileged -t firewall2 iptables -A FORWARD -d 192.1.1.0/24 -j DROP


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
