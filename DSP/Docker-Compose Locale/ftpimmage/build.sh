#!/bin/bash

docker build -t ftpser .
docker run --privileged -t ftpser
