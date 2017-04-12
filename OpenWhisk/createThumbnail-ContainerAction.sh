#!/usr/bin/env bash

##------------------------------------------------------------------------------------------------------------##
# This script will create a whisk user called 'swiftdemo' and install the ThumbnailAction under it's namespace #
##------------------------------------------------------------------------------------------------------------##

set -e
whisk_user="swiftdemo"
action_name="thumbnail"

echo "Creating OpenWhisk Action: ${action_name}"
#------------------------------
# Create Whisk sample user
#------------------------------
if [[ "$(${HOME}/openwhisk/bin/wskadmin user get ${whisk_user})" =~ ^Failed.* ]]; then
    echo "Creating whisk user: ${whisk_user}"
    swiftdemo_auth=$(${HOME}/openwhisk/bin/wskadmin user create ${whisk_user})
    echo ""
else
    echo "Found whisk user: ${whisk_user}"
    swiftdemo_auth=$(${HOME}/openwhisk/bin/wskadmin user get ${whisk_user})
fi
echo ""

#------------------------------
# Build ThumbnailAction image
#------------------------------
# OpenWhisk docker actions must be pulled from a docker distribution like dockerhub.com
image_name="stmuraka/ThumbnailActionContainer"
echo "Using ${image_name} image for action"
sudo docker pull ${image_name}
echo ""

#------------------------------
# Create the Whisk action
#------------------------------
action_exists=$(wsk action list --auth ${swiftdemo_auth} | grep "/${whisk_user}/${action_name} " | wc -l)
if [ ${action_exists} -eq 1 ]; then
    echo "Updating whisk action: ${action_name}"
    ${HOME}/openwhisk/bin/wsk --auth ${swiftdemo_auth} \
        action update \
        ${action_name} \
        --docker ${image_name}
else
    echo "Creating whisk action: ${action_name}"
    ${HOME}/openwhisk/bin/wsk --auth ${swiftdemo_auth} \
        action create \
        ${action_name} \
        --docker ${image_name}
fi
echo ""

${HOME}/openwhisk/bin/wsk action list \
    --auth ${swiftdemo_auth}
echo ""

# cleanup
echo "Action ${action_name} created."
echo ""
exit 0
