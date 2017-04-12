# OpenWhisk & OpenStack Swift

## Overview
This project demonstrates how a user can create [AWS Lambda](http://docs.aws.amazon.com/lambda/latest/dg/welcome.html)-like functionality using [OpenStack's Object Store (Swift)](http://docs.openstack.org/developer/swift/) and [OpenWhisk](https://developer.ibm.com/openwhisk/).

This is the code that was used during our [presentation](https://www.openstack.org/summit/barcelona-2016/summit-schedule/events/15090/enabling-aws-s3-lambda-like-functionality-with-openstack-swift-and-openwhisk) at the OpenStack Summit in Barcelona (Oct 2016). The presentation can also be viewd [here](https://www.youtube.com/watch?v=gv4M3vqHrGU)

The following folders provide code for:
- **[OpenStackSwift/](./OpenStackSwift/)**
    - Creating a [WebHook](https://en.wikipedia.org/wiki/Webhook) in OpenStack Swift middleware which can be used to trigger an OpenWhisk Trigger or Action.

- **[OpenWhisk/](./OpenWhisk/)**
    - Creating a custom [OpenWhisk Action](https://github.com/openwhisk/openwhisk/blob/master/docs/reference.md#action-semantics) that will create a thumbnail image and upload it to an OpenStack Swift container.

- **[Test/](./Test/)**
    - Test script to validate the OpenStack Swift and OpenWhisk integration

- **[UI/]()**
    - Simple UI for browsing the Swift Object storage *(coming soon)*

*NOTE: If you are deploying all the components from this project, you should have a server with at least 8GB memory available*

## [License](./license.txt)
All code provided under the [Apache 2 license](./license.txt)
