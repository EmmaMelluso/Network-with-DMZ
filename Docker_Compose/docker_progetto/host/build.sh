#!/bin/bash

docker build -t hostubuntu .
docker run --privileged -t hostubuntu
