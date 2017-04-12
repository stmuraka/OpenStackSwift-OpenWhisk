const fs = require('fs');
const path = require('path');
const swiftclient = require('./osSwift');

exports.main = ThumbnailAction;

// expects the payload to contain a swiftObject;
// e.g. { "swiftObj": { "method": "PUT", "container": "images", "object": "600_0985.jpg" } }
// console.log('payload: '+JSON.stringify(payload));
function ThumbnailAction(payload) {
    var result = {};
    var swiftObj = payload.swiftObj;
    return new Promise(function(resolve, reject) {
        // If the OpenStack Swift's method was 'PUT', the action was an upload of a new image.
        // The new image should be transformed into a thumbnail
        if ( swiftObj.method == 'PUT' ) {
            swiftclient.transformImage(swiftObj,
                function onSuccess(params){
                    console.log('Image thumbnail created successfully');
                    imagePath = params.container+'/'+params.object;
                    thumbnailPath = params.thumbnailContainer+'/'+path.basename(thumbnail);

                    // Specify the output of the Whisk action
                    result = {
                        result: {
                            success: 'Thumbnail created successfully',
                            source: imagePath,
                            thumbnail: thumbnailPath
                        }
                    };
                    resolve(result);
                },
                function onFailure(error) {
                    console.error(error);
                    reject(error);
                }
            );
        } else if ( swiftObj.method == 'DELETE') {
            // This action will not be called on 'GET'. The only other method supported by OpenStack is DELETE, we assume this and take no action on the object
            // image deleted don't take any action
            result = {
                result: { success: 'No action taken, image was deleted' }
            }
            resolve(result);
        }
        else {
            result = {
                result: { error: 'Should not get this result' }
            }
            reject(result);
        }
    });
}
