#!/usr/bin/env bash
##----------------------------------------------------------------------------------------------------------##
# This script will test the Thubnail webhook installed in OpenStack swift with the OpenWhisk ThumbnailAction
#
# Pre:
#       - OpenStack Swift webhook is installed
#       - OpenWhisk ThumbnailAction is installed
#
# Assumptions:
#       - OpenWhisk and OpenStack Swift are running on the same host
#       - OpenStack Swift is running in standalone mode with:
#           SwiftAccount="test"
#           SwiftUser="tester"
#           SwiftPassword="testing"
#       - The OpenWhisk user 'swiftdemo' will be used
#
##----------------------------------------------------------------------------------------------------------##

set -euo pipefail

echo "#========================================================================#"
echo "Testing the Thumbnail Action and Webhook"
echo ""

# ensure jq is installed
echo "Getting the required packages"
sudo apt-get install -y jq uuid-runtime wget
echo ""

WhiskUser="swiftdemo"
# work around for docker <1.10 (with DNS)
ThisHost=$(ip a show dev ens3 | grep 'inet ' | awk '{print $2}' | cut -d '/' -f1)
WhiskHost=${ThisHost}
WhiskAction="thumbnail"

# The Swift host IP should be the host IP
SwiftHost="${ThisHost}:8080"
SwiftAccount="test"
SwiftUser="tester"
SwiftPassword="testing"

WebhookURL="https://${WhiskHost}/api/v1/namespaces/${WhiskUser}/actions/${WhiskAction}"

TestContainer=$(uuidgen)

test_image="http://mars.nasa.gov/msl/images/pia16239_c-full.jpg"
image_name=$(basename ${test_image})
thumbnail_name="${image_name%.*}_thumbnail.${image_name##*.}"


# Create a WebHook on an OpenStack Swift Container
# Add the OpenWhisk Action's API as the WebHook
# Obtain a valid OpenStack Swift token
echo -n "Obtain a valid OpenStack Swift token ... "
SwiftToken=$( curl -sSLi \
           -X GET \
           -H "X-Storage-User: ${SwiftAccount}:${SwiftUser}" \
           -H "X-Storage-Pass: ${SwiftPassword}" \
           http://${SwiftHost}/auth/v1.0 \
           | grep 'X-Auth-Token:' | awk '{print $2}' | tr -d '\r' \
) || { echo "ERROR: failed to obtain the Swift auth token"; exit 1; }
SwiftURL=$( curl -sSLi \
           -X GET \
           -H "X-Storage-User: ${SwiftAccount}:${SwiftUser}" \
           -H "X-Storage-Pass: ${SwiftPassword}" \
           http://${SwiftHost}/auth/v1.0 \
           | grep 'X-Storage-Url:' | awk '{print $2}' | tr -d '\r' \
) || { echo "ERROR: failed to obtain the Swift storage url"; exit 1; }
echo "OK"
echo ""
echo "swift token: ${SwiftToken}"
echo "swift URL: ${SwiftURL}"


# Defining cleanup function
function cleanup {
    echo ""
    echo "Cleanup invoked...."
    echo ""
    # Delete test image
    echo "Attempting to delete test image"
    curl -i -X DELETE -H "X-Auth-Token: ${SwiftToken}" ${SwiftURL}/${TestContainer}/${image_name} || true
    echo ""
    # Delete test container
    echo "Attempting to delete test container"
    curl -i -X DELETE -H "X-Auth-Token: ${SwiftToken}" ${SwiftURL}/${TestContainer} || true
    echo ""
    # Delete thumbnail image
    echo "Attempting to delete test thumbnail"
    curl -i -X DELETE -H "X-Auth-Token: ${SwiftToken}" ${SwiftURL}/${TestContainer}_thumbnails/${thumbnail_name} || true
    echo ""
    # Delete thumbnail container
    echo "Attempting to delete test thumbnail container"
    curl -i -X DELETE -H "X-Auth-Token: ${SwiftToken}" ${SwiftURL}/${TestContainer}_thumbnails || true
    echo ""
}

#------------------------------
# Get Whisk credentials
#------------------------------
echo -n "Get whisk user credentials: ${WhiskUser} ... "
WhiskAuth=$(${HOME}/openwhisk/bin/wskadmin user get ${WhiskUser})
echo "OK"
lastActivation=$(${HOME}/openwhisk/bin/wsk activation list --auth ${WhiskAuth} | grep "${WhiskAction}" | head -1 | awk '{print $1}') || true
echo "Last whisk activation: ${lastActivation:-none}"
echo ""
newActivation="${lastActivation:-}"
echo ""

#------------------------------
# Configure Swift container
#------------------------------
# Create a container for the image and add the OpenWhisk "thumbnail" Action's API as the container WebHook
echo -n "Creating a test Swift container: ${TestContainer}"
curl -sSL  \
     -X PUT \
     -H "X-Auth-Token: ${SwiftToken}" \
     -H "X-Webhook: ${WebhookURL}" \
     -H "X-Webhook-Auth: ${WhiskAuth}" \
     ${SwiftURL}/${TestContainer} || { echo "ERROR: Failed to create test container."; exit 1; }
echo ""
echo ""

echo -n "Checking to make sure the webhook was added to the container successfully ... "
container_hook=$(curl -sSLi -X GET -H "X-Auth-Token: ${SwiftToken}" ${SwiftURL}/${TestContainer} | grep 'X-Webhook:' | awk '{print $2}' |tr -d '\r' ) || true
[ "${container_hook}" != "${WebhookURL}" ] && { echo "ERROR: Webhook not set"; cleanup; exit 1; }
echo "OK"
curl -i -X GET -H "X-Auth-Token: ${SwiftToken}" ${SwiftURL}/${TestContainer} || true

#------------------------------
# Add an image to the container
#------------------------------
# Download source image and upload it to the image container that was created earlier
echo -n "Adding test image [${test_image}] to the \"${TestContainer}\" container ... "
curl -sSL ${test_image} | curl -sSL -X PUT \
     -H "X-Auth-Token: ${SwiftToken}" \
     -T - \
     ${SwiftURL}/${TestContainer}/${image_name} \
     || { echo "ERROR: failed."; cleanup; exit 1; }
echo "OK"
echo ""

# Check that the image uploaded successfully
echo "Getting the image info:"
curl -sSL -X GET \
     -H "X-Auth-Token: ${SwiftToken}" \
     ${SwiftURL}/${TestContainer}?format=json | jq . \
     || { echo "ERROR: Failed to get image info."; cleanup; exit 1; }
echo ""

#------------------------------
# OpenWhisk verification
#------------------------------
# Wait a few seconds before checking for Action result
# Get last activation
#### Check that the thumbnail Action was triggered
timer=0
max_time=30
echo -n "Waiting for the Whisk action to be activated"
until [ ${timer} -eq ${max_time} ]; do
    newActivation=$(${HOME}/openwhisk/bin/wsk activation list --auth ${WhiskAuth} | grep "${WhiskAction}" | head -1 | awk '{print $1}') || true
    [ "${newActivation}" != "${lastActivation}" ] && { echo "done."; echo "New activation: ${newActivation}"; break; }
    echo -n "."
    sleep 1
    ((timer+=1))
done
[ "${newActivation}" == "${lastActivation}" ] && { echo "ERROR: Timed out"; cleanup; exit 1; }
echo ""

# Display results
echo "Action results: "
action_results=$(${HOME}/openwhisk/bin/wsk activation result ${newActivation} --auth ${WhiskAuth}) ||  { echo "ERROR: Could not get action results"; cleanup; exit 1; }
echo "${action_results}"
echo ""

# Display logs
echo "Action logs: "
${HOME}/openwhisk/bin/wsk activation logs ${newActivation} --auth ${WhiskAuth} || true
echo ""

[[ "${action_results}" =~ .*error.* ]] && { echo "ERROR: last action failed"; cleanup; exit 1; }

#### Check the OpenStack Swift for the new thumbnail
# The Whisk action creates a new Swift container where it places the new thumbnail images.
# The thumbnail container name takes the format `<original_container_name>_thumbnails`.
# The thumbnail image name takes the format `<original_image_name>_thumbnail.<original_extension>`.
echo "Checking OpenStack Swift for the new thumbnail"
curl -sSL -X GET \
     -H "X-Auth-Token: ${SwiftToken}" \
     ${SwiftURL}/${TestContainer}_thumbnails?format=json | jq . \
     || { echo "ERROR: New thumbnail can not be found."; cleanup; exit 1; }
echo ""

echo "Thumbnail Webhook testing complete: PASS"
echo ""

# Download and view the thumbnail image.
echo "To download and view the original and/or thumbnail images:"
echo "original: wget --header \"X-Auth-Token: ${SwiftToken}\" ${SwiftURL}/${TestContainer}/${image_name}"
echo "thumbnail: wget --header \"X-Auth-Token: ${SwiftToken}\" ${SwiftURL}/${TestContainer}_thumbnails/${thumbnail_name}"
echo ""
# Cleanup test conatiners and images
echo "To delete what was created, execute the following commands:"
# Delete test image
echo "curl -i -X DELETE -H \"X-Auth-Token: ${SwiftToken}\" ${SwiftURL}/${TestContainer}/${image_name}"
# Delete test container
echo "curl -i -X DELETE -H \"X-Auth-Token: ${SwiftToken}\" ${SwiftURL}/${TestContainer}"
# Delete thumbnail image
echo "curl -i -X DELETE -H \"X-Auth-Token: ${SwiftToken}\" ${SwiftURL}/${TestContainer}_thumbnails/${thumbnail_name}"
# Delete thumbnail container
echo "curl -i -X DELETE -H \"X-Auth-Token: ${SwiftToken}\" ${SwiftURL}/${TestContainer}_thumbnails"
echo ""

# End
echo "#========================================================================#"
exit 0
