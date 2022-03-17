#!/bin/bash

#Build dockerfile
cd firewall/
./build.sh
cd ..

cd host/
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
docker exec cliente1  route add default gw firewall1
docker exec host1     route add default gw firewall2
docker exec webserver route add default gw firewall1
docker exec firewall1 route add default gw firewall2
docker exec firewall2 route add default gw firewall1

echo "Ispezione reti:"
docker network inspect rete_interna 
docker network inspect rete_esterna 
docker network inspect dmz
docker network inspect rete_intermedia
docker ps 

#Apertura terminal in root, per testing della rete
echo "Sono host1"
docker exec -i -t host1 bash
echo "Sono cliente"
docker exec -i -t cliente1 bash
echo "Sono webserver"
docker exec -i -t webserver bash
