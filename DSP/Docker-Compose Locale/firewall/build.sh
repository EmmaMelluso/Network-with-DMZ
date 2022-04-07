#!/bin/bash

docker build -t customfirewall .
docker run --privileged -t customfirewall
