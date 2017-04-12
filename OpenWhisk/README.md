# ThumbnailAction
This is an OpenWhisk action written in JavaScript for NodeJS.
This action is used to show how OpenWhisk actions can be used in conjunction with OpenStack Swift WebHook middleware.

## Overview
This action will take a large image (from an OpenStack Swift Container), create a thumbnail image (300 px. wide), and upload it into another OpenStack Swift "thumbnail" Container.

*NOTE: The following instructions assume that you have already configured the OpenStack Swift webhook middleware*

Steps:
1. Create the OpenWhisk Action
2. Create a WebHook on an OpenStack Swift Container
3. Test: Upload an image into the OpenStack Swift Container
4. Validate the results

## 0. OpenWhisk server
The following instructions assume that you have access to an OpenWhisk server.  
If you don't, you can run the `deployOpenWhisk.sh` script provided to install OpenWhisk locally.

*NOTE: The deployOpenWhisk.sh script has been written to work on Ubuntu distros only (tested with 16.04.2 LTS)*

## 1. Create the OpenWhisk action
*On the OpenWhisk server*

### Automated
The Thumbnail Whisk action can be deployed using the createThumbnail-\*Action.sh scripts
 - **[createThumbnail-NodejsAction.sh](./createThumbnail-ContainerAction.sh)** - creates the action as a NodeJS action
 - **[createThumbnail-ContainerAction.sh](./createThumbnail-ContainerAction.sh)** - creates the action as a Docker (blackbox) action

### Manually
1. Get the OpenWhisk user auth credentials
  - e.g. for the user *swiftdemo*:
    `wskadmin user get swiftdemo`

  - or if you need to create a user:
    `wskadmin user create swiftdemo`


    result:
    ```
    dc40d73c-8127-4606-9478-278b01a262b9:aW5kEJhNg2AnwnWigJLRoNNgqWhXgEzgeZVACa3h34Cnqt8HtFUaxrwIOMQEi36g
    ```

2. Package the action
   - NodeJS bundle:

   - Docker image:
     - the docker image can be found on Dockerhub as `stmuraka/ThumbnailActionContainer`
     - `docker pull stmuraka/ThumbnailActionContainer`

3. Create the Whisk action
   ```
   wsk action create \
   --docker thumbnail thumbnail_action_img \
   --auth dc40d73c-8127-4606-9478-278b01a262b9:aW5kEJhNg2AnwnWigJLRoNNgqWhXgEzgeZVACa3h34Cnqt8HtFUaxrwIOMQEi36g
   ```
   result: `ok: created action thumbnail`

## 2. Create a WebHook on an OpenStack Swift Container
Add the OpenWhisk Action's API as the WebHook
*On the OpenStack Swift server*

1. Obtain a valid OpenStack Swift token

    - Swift account = test
    - Swift username = tester
    - Swift password = testing

   ```
   curl -v -H 'X-Storage-User: test:tester' \
           -H 'X-Storage-Pass: testing' \
           http://swift.api.server:8080/auth/v1.0
   ```
   The response should be something like the following:
   ```
   < HTTP/1.1 200 OK
   < X-Storage-Url: http://swift.api.server:8080/v1/AUTH_test
   < X-Auth-Token-Expires: 82270
   < X-Auth-Token: AUTH_tk7a1ab13a03ff4d2c9e07b202a7f8b846
   < Content-Type: text/html; charset=UTF-8
   < X-Storage-Token: AUTH_tk7a1ab13a03ff4d2c9e07b202a7f8b846
   < Content-Length: 0
   < X-Trans-Id: tx7fdd1700824047e6abdae-0057633931
   < Date: Thu, 16 Jun 2016 23:41:37 GMT
   ```
   The session token is: *`AUTH_tk7a1ab13a03ff4d2c9e07b202a7f8b846`*

2. Create a container called "images" and add the OpenWhisk "thumbnail" Action's API as the container WebHook

```
curl -v -X PUT \
        -H "X-Auth-Token: AUTH_tk7a1ab13a03ff4d2c9e07b202a7f8b846" \
        -H "X-Webhook: https://openwhisk/api/v1/namespaces/swiftdemo/actions/thumbnail" \
        -H "X-Webhook-Auth: dc40d73c-8127-4606-9478-278b01a262b9:aW5kEJhNg2AnwnWigJLRoNNgqWhXgEzgeZVACa3h34Cnqt8HtFUaxrwIOMQEi36g" \
        http://swift.api.server:8080/v1/AUTH_test/images
```

## 3. Test: Upload an image into the OpenStack Swift Container
1. Configure whisk to poll the "thumbnail" action

  *On the OpenWhisk server*

  `wsk activation poll thumbnail --auth dc40d73c-8127-4606-9478-278b01a262b9:aW5kEJhNg2AnwnWigJLRoNNgqWhXgEzgeZVACa3h34Cnqt8HtFUaxrwIOMQEi36g`

2. Upload an image into the "images" container
   ```
   curl -v -X PUT \
        -H "X-Auth-Token: AUTH_tk7a1ab13a03ff4d2c9e07b202a7f8b846" \
        -T my-large-image.jpg \
        http://swift.api.server:8080/v1/AUTH_test/images/my-large-image.jpg
   ```

## 4. Validate the results
#### Check that the image uploaded successfully
*On the OpenStack Swift server*
1. If the image uploaded successfully to Swift, you should receive a 201 response similar to the following:
    ```
    < HTTP/1.1 201 Created
    < Last-Modified: Fri, 17 Jun 2016 00:00:02 GMT
    < Content-Length: 0
    < Etag: 2227351809804d2267e7166da0d6e79a
    < Content-Type: text/html; charset=UTF-8
    < X-Trans-Id: tx47809c2c98764deaabdac-0057633d81
    < Date: Fri, 17 Jun 2016 00:00:03 GMT
    ```

2. Querying the "image" container will show us the file size and WebHook information:
    ```
    curl -i -X GET \
         -H "X-Auth-Token: AUTH_tk7a1ab13a03ff4d2c9e07b202a7f8b846" \
         http://swift.api.server:8080/v1/AUTH_test/images?format=json
    ```
    Results:
    ```
    HTTP/1.1 200 OK
    X-Webhook: https://openwhisk/api/v1/namespaces/swiftdemo/actions/thumbnail
    Content-Length: 187
    X-Container-Object-Count: 1
    X-Timestamp: 1466121227.54478
    Accept-Ranges: bytes
    X-Storage-Policy: gold
    X-Container-Bytes-Used: 2010789
    Content-Type: application/json; charset=utf-8
    X-Trans-Id: txc2b08301eb6445e6a9c7c-0057633f5b
    Date: Fri, 17 Jun 2016 00:07:55 GMT

    [{"hash": "2227351809804d2267e7166da0d6e79a", "last_modified": "2016-06-17T00:00:01.326220", "bytes": 2010789, "name": "goes-12-firstimage-large081701.jpg", "content_type": "image/jpeg"}]
    ```
The uploaded image size is `2010789 bytes`. Check to make sure that it's the same as the original image size.

#### Check that the thumbnail Action was triggered
*On the OpenWhisk server*
1. Since polling was configured for the "thumbnail" Action, you should see ouput similar to the following:

    ```
    Hit Ctrl-C to exit.
    Polling for logs

    Activation: thumbnail (bc834fdacd9d40aebfb8677d78f4c871)
    2016-06-17T00:00:06.457340945Z stdout: Starting image thumbnail action
    2016-06-17T00:00:09.170985444Z stdout: payload: {"object":"my-large-image.jpg","container":"images","method":"PUT"}
    2016-06-17T00:00:09.171066108Z stdout:
    2016-06-17T00:00:09.189807245Z stdout: Got Swift token: AUTH_tk7a1ab13a03ff4d2c9e07b202a7f8b846
    2016-06-17T00:00:09.242795861Z stdout: Object downloaded successfully to: /tmp/my-large-image.jpg
    2016-06-17T00:00:09.33880463Z  stdout: Image thumbnail created successfully: /tmp/my-large-image_thumbnail.jpg
    2016-06-17T00:00:09.365262151Z stdout: Container "images_thumbnails" created successfully
    2016-06-17T00:00:09.392243307Z stdout: Object [my-large-image_thumbnail.jpg] upload successful [rc: 201]
    2016-06-17T00:00:09.392524621Z stdout: Cleaning up temp images...
    2016-06-17T00:00:09.392789386Z stdout: Deleted /tmp/my-large-image.jpg
    2016-06-17T00:00:09.392825805Z stdout: Deleted /tmp/my-large-image_thumbnail.jpg
    2016-06-17T00:00:09.392891296Z stdout:
    2016-06-17T00:00:09.393561119Z stdout: Image thumbnail created successfully
    ```

#### Check OpenStack Swift for the new thumbnail
*On the OpenStack Swift server*
The Whisk action creates a new Swift container where it places the new thumbnail images. The thumbnail container name takes the format `<original_container_name>_thumbnails`. In this example the new container name is `images_thumbnails`.  The thumbnail image name takes the format `<original_image_name>_thumbnail.<original_extension>`. In this example the new image nam is `my-large-image_thumbnail.jpg`


1. Check the new thumbnail container for the new thumbnail image.
    ```
    curl -i -X GET \
         -H "X-Auth-Token: AUTH_tk7a1ab13a03ff4d2c9e07b202a7f8b846" \
         http://swift.api.server:8080/v1/AUTH_test/images_thumbnails?format=json
    ```
    Results:
    ```
    HTTP/1.1 200 OK
    Content-Length: 195
    X-Container-Object-Count: 1
    X-Timestamp: 1466121609.87790
    Accept-Ranges: bytes
    X-Storage-Policy: gold
    X-Container-Bytes-Used: 22722
    Content-Type: application/json; charset=utf-8
    X-Trans-Id: tx58a0543297074b2797ca7-00576343e6
    Date: Fri, 17 Jun 2016 00:27:19 GMT

    [{"hash": "d2a2a1a1642a45f7a8c225ee0197e566", "last_modified": "2016-06-17T00:00:09.906760", "bytes": 22722, "name": "my-large-image_thumbnail.jpg", "content_type": "image/jpeg"}]
    ```
    The new thumbnail size is: `22722 bytes`

2. Download and view the thumbnail image.
    ```
    wget --header "X-Auth-Token: AUTH_tk7a1ab13a03ff4d2c9e07b202a7f8b846" \
    http://swift.api.server:8080/v1/AUTH_test/images_thumbnails/my-large-image_thumbnail.jpg
    ```

    View the image with your preferred program. The image width should be 300 px.
