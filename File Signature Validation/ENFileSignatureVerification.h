/*
 *      Copyright (C) 2020 Apple Inc. All Rights Reserved.
 *
 *      ExposureNotification is licensed under Apple Inc.’s
 *      Sample Code License Agreement, which is contained in
 *      the LICENSE file distributed with ExposureNotification,
 *      and only to those who accept that license.
 *
 */

#pragma once

#import <Foundation/Foundation.h>

#import "ENFile.h"

NS_ASSUME_NONNULL_BEGIN

/*
 *  A sample Temporary Exposure Key file signature verification class. This class
 *  performs the specified signature checks given a public key. The public key provided
 *  is region specific and is fetched from Apple servers.
 */

@interface ENFileSignatureVerification : NSObject

/*
 *  Iniitalize a ENFileSignatureVerification with the provided App ID and a base64 encoded
 *  public key. The public key will be used according to the server guidelines as outlined
 *  on the Apple developer website:
 *  https://developer.apple.com/documentation/exposurenotification/setting_up_an_exposure_notification_server
 */
- (instancetype)initWithAppID:(NSString *)appID publicKey:(NSString *)publicKey;

/*
 *  Validate the provided ENFile with the corresponding ENSignatureFile.
 *  Returns YES the the signature could be validated with the public key provided
 *  during initialization of the ENFileSignatureVerification object.
 */
- (BOOL)validateFile:(ENFile *)mainFile withSignatureFile:(ENSignatureFile *)sigFile;

@end

NS_ASSUME_NONNULL_END
