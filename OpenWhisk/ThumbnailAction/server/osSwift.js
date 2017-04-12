/*
    NodeJS Wisk Action to resize an image and re-upload to a new container.
    Current Swift authentication is for a standalone server (i.e. no Keystone auth)
*/

// Node packages
const request = require('request');
const url  = require('url');
const fs = require('fs');
const sharp = require('sharp');
const path = require('path');
const q = require('q');

// Remove caching if running in alpine container
sharp.cache(false)

// Storage location for temp images
var tempFilePath = '/tmp';

exports.transformImage = transformImage;

/*
    Function: getSwiftObject(swiftUser)
    Description: Downloads image from OpenStack Swift
*/
function getSwiftObject(swiftUser) {

    var defer = q.defer();
    var userToken = swiftUser.token;       // OpenStack Swift user's token
    var userPath = swiftUser.url;          // OpenStack Swift's user's URL namespace
    var container = swiftUser.container;   // OpenStack Swift container name
    var object = swiftUser.object;         // OpenStack Swift object name

    var objectURL = userPath+'/'+container+'/'+object;
    var headers = { 'X-Auth-Token': userToken };
    var options = { url: objectURL, headers: headers };
    var fileDestination = path.join(tempFilePath, object);

    try {
        request.get(options)
            .on('response', downloadObject)
            .on('error', downloadError);
    } catch (err) {
        defer.reject({ getSwiftObject: "request failed" });
    }

    function downloadObject(response) {
        var file = fs.createWriteStream(fileDestination);
        response.pipe(file);
        file.on('finish', function() {
            file.close();
            console.log('Object downloaded successfully to: ' + fileDestination);
            swiftUser.image = fileDestination;
            defer.resolve(swiftUser);
        });
    }

    function downloadError(error) {
        fs.unlink(fileDestination);
        console.error('ERROR: getSwiftObject - '+error);
        defer.reject(error);
    }

    return defer.promise;
}

/*
    Function: createThumbnail(params)
    Description: Transforms an image into a thumbnail
*/
function createThumbnail(params) {

    var defer = q.defer();
    var image = params.image;                   // image location; should be full path to the image
    var filePath = path.dirname(image);         // path of image (e.g. /path/to/)
    var extension = path.extname(image);        // image extension (e.g. extension)
    var name = path.basename(image, extension); // name of the image without the extension
    var size = 300;

    // TODO: check for valid image formats: JPEG, PNG, WebP, GIF, SVG, TIFF
    thumbnail = path.join(filePath, name + '_thumbnail' + extension);

    // resize image to width of 300 px. and write to thumbnail
    try {
        sharp(image)
          .resize(size)
          .withoutEnlargement()
          .toFile(thumbnail, function(err, info) {
              if (!err) {
                  console.log('Image thumbnail created successfully: '+ thumbnail);
                  params.thumbnail = thumbnail;
                  defer.resolve(params);
              } else {
                  console.error('ERROR: createThumbnail - Failed to create thumbnail');
                  console.error(err);
                  defer.reject(err);
              }
          });
    } catch (err) {
        defer.reject({ createThumbnail: "sharp.resize failed" });
    }

    return defer.promise;
}

/*
    Function: createThumbnailContainer(params)
    Description: Creates a new OpenStack Swift Container for the resized image (if it doesn't exist)
*/
function createThumbnailContainer(params) {

    var defer = q.defer();
    var userPath = params.url;                                  // OpenStack Swift's user's URL namespace
    var userToken = params.token;                               // OpenStack Swift user's token
    var thumbnailContainer = params.container+'_thumbnails';    // Thumbnail Container name
    var containerURL = userPath+'/'+thumbnailContainer;         // Path to the Thumbnail Container

    // HTTP request options
    var options = {
        url: containerURL,
        headers: {
            'X-Auth-Token': userToken
        }
    };
    try {
        request.put(options)
            .on('response', createContainer)
            .on('error', containerError);
    } catch (err) {
        defer.reject({ createThumbnailContainer: "failed to create thumbnail conatiner" });
    }

    // Try to create the thumbnail Container
    function createContainer(response) {
        switch(response.statusCode) {
            case 201:
                console.log('Container "' + thumbnailContainer + '" created successfully');
                break;
            case 202:
                console.log('"'+thumbnailContainer + '" container already created');
                break;
            default:
                console.log('WARNING: Container request successful but not sure what happend; Response Code ' + response.statusCode);
                break;
        }
        params.thumbnailContainer = thumbnailContainer;
        defer.resolve(params);
    }

    function containerError(error) {
        console.log('ERROR: createContainer - '+error);
        defer.reject(error);
    }

    return defer.promise;

}

/*
    Function: putSwiftObject(params)
    Description: uploads an object to an OpenStack Swift Container
*/
function putSwiftObject(params){
    var defer = q.defer();
    var thumbnail = params.thumbnail                    // The full path to the thumbnail file
    var object = path.basename(thumbnail);              // The thumbnail file name; The object to upload
    var container = params.thumbnailContainer;          // The OpenStack Swift's Container name for the thumbnail
    var userPath = params.url;                          // OpenStack Swift's user's URL namespace
    var userToken = params.token;                       // OpenStack Swift's user's token
    var objectURL = userPath+'/'+container+'/'+object;  // The OpenStack API path for the thumbnail object
    var obj = fs.statSync(thumbnail);

    // HTTP request options
    var options = {
        url: objectURL,
        headers: {
            'X-Auth-Token': userToken,
            'Content-Length': obj.size
        }
    };

    // Attempt to upload the object
    var file = fs.createReadStream(thumbnail)
                    .pipe(
                        request.put(options)
                               .on('response', uploadObject)
                               .on('error', uploadError)
                    );

    file.on('error', uploadError);

    function uploadObject(response) {
        console.log('Object ['+object+'] upload successful [rc: '+response.statusCode+']');
        defer.resolve(params);
    }

    function uploadError(error) {
        console.log('ERROR: putSwiftObject - '+error);
        defer.reject(error);
    }
    return defer.promise;
}

/*
    Function: cleanup(params)
    Description: delete temp images
*/
function cleanup(params){
    var defer = q.defer();
    console.log('Cleaning up temp images...');

    // delete images
    fs.unlinkSync(params.image);
    console.log('Deleted ' + params.image);

    // delete thumbnail
    fs.unlinkSync(params.thumbnail);
    console.log('Deleted ' + params.thumbnail);
    console.log('');

    defer.resolve(params);
    return defer.promise;
}

/*
    Function: transformImage(payload, successCallback)
    Description: main function to transform an image. Calls functions in succession.
*/
function transformImage(payload, successCallback, errorCallback) {
    function errorHandler(error) {
        var defer = q.defer();
        defer.reject(error);
        return defer.promise;
    }
    return getSwiftObject(payload)
        .then(createThumbnail, errorHandler)
        .then(createThumbnailContainer, errorHandler)
        .then(putSwiftObject, errorHandler)
        .then(cleanup, errorHandler)
        .then(successCallback, errorCallback);
}
