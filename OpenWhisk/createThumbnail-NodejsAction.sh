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
# Build ThumbnailAction node package
#------------------------------
echo "Creating ThumbnailAction NodeJS bundle"
cd ThumbnailAction
thumbnail_build_img="thumbnailbuild"
docker build -t ${thumbnail_build_img} .
mkdir output
docker run --rm --name ${thumbnail_build_img} -v $(pwd)/output:/root/output ${thumbnail_build_img}
echo ""
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
        --kind nodejs:6 \
        output/thumbnail-action.zip
else
    echo "Creating whisk action: ${action_name}"
    ${HOME}/openwhisk/bin/wsk --auth ${swiftdemo_auth} \
        action create \
        ${action_name} \
        --kind nodejs:6 \
        output/thumbnail-action.zip
fi
echo ""

${HOME}/openwhisk/bin/wsk action list \
    --auth ${swiftdemo_auth}
echo ""

# cleanup
echo "Cleaning up temp artifacts..."
rm -rf output/
docker rmi ${thumbnail_build_img}
echo ""
echo "Action ${action_name} created."
echo ""
exit 0
