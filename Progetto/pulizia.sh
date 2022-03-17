#!/bin/bash


#Pulizia
docker stop $(docker ps -a -q)
docker rm -f $(docker ps -a -q)
docker network rm rete_esterna
docker network rm dmz
docker network rm rete_interna
docker network rm rete_intermedia