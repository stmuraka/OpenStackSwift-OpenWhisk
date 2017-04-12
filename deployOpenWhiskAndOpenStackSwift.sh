#!/usr/bin/env bash

#
# This script orchestrates the deployment of OpenWhisk and OpenStack Swift
#

set -e

dir=$(pwd)

# Deploy OpenWhisk
cd ${dir}/OpenWhisk
sudo ./deployOpenWhisk.sh

# Create ThumbnailAction
sudo ./createThumbnail-NodejsAction.sh

# Deploy OpenStack Swift
cd ${dir}/OpenStackSwift/
sudo ./deployOpenStackSwift.sh
# NOTE: after build, the deployment/initialization takes approximately 10 minutes to complete.

# Wait for Swift to initilize
timer=0
sleep=10
max_time=$((60*30))
echo -n "Waiting for Swift to be ready."
until [ ${timer} -eq ${max_time} ]; do
    ready=$(sudo docker logs saio 2>/dev/null | grep 'Swift SAIO ready' | wc -l)
    [ ${ready} -gt 0 ] && { echo "ready."; break; }
    echo -n "."
    sleep ${sleep}
    ((timer+=${sleep}))
done
[ ${ready} -eq 0 ] && { echo "ERROR: Timed out"; echo "Please check the saio container logs [docker logs saio]"; exit 1; }
echo ""

# Test it
cd ${dir}/Test
sudo ./testThumbnailWebhook.sh

# Ready for use
echo ""
echo "OpenWhisk and OpenStack Swift are ready for use"
echo ""
