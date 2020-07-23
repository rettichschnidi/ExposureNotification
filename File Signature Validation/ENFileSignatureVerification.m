/*
 *      Copyright (C) 2020 Apple Inc. All Rights Reserved.
 *
 *      ExposureNotification is licensed under Apple Inc.’s
 *      Sample Code License Agreement, which is contained in
 *      the LICENSE file distributed with ExposureNotification,
 *      and only to those who accept that license.
 *
 */

#include <Security/Security.h>

#import "ENFileSignatureVerification.h"
#import "ENShims.h"

NS_ASSUME_NONNULL_BEGIN

@implementation ENFileSignatureVerification {
    NSString *_appID;
    NSString *_publicKey;
}

- (instancetype)initWithAppID:(NSString *)appID publicKey:(NSString *)publicKey;
{
    if (self = [super init]) {
        _appID = appID;
        _publicKey = publicKey;
    }
    return self;
}

- (BOOL)validateFile:(ENFile *)mainFile withSignatureFile:(ENSignatureFile *)sigFile
{

    // Retrieve the signature paramaters from the signature file.

    ENSignature *signatureObj = sigFile.signatures.firstObject;
    NSData *signatureData = signatureObj.signatureData;
    NSData *hashData = mainFile.sha256Data;
    NSString *keyID = signatureObj.keyID;
    NSString *keyVersion = signatureObj.keyVersion;

    // Verify signature.

    __block BOOL verified = NO;

    if( signatureData && hashData && keyVersion )
    {
        [self verifyFileSignature:signatureData hashData:hashData withRegionID:keyID usingPublicVersion:keyVersion withCompletion:
        ^( BOOL inSignatureVerified, NSError *inErrror )
        {
            if (inErrror)
            {
                verified = NO;
            }
            else
            {
                verified = inSignatureVerified;
            }
        }];
    }

    return verified;
}

- (void)verifyFileSignature:(NSData *)signatureData
                   hashData:(NSData *)fileData
               withRegionID:(NSString *)regionID
         usingPublicVersion:(NSString *)publicKeyVersion
             withCompletion:(void(^)(BOOL signatureVerified, NSError * _Nullable error))completion
{
    if (_publicKey) {

        EN_NOTICE_PRINTF("Validating App Public Key for bundle ID: %@", _appID);

        NSString *appPublicKeyString = _publicKey;

        BOOL isVerified = NO;

        if (appPublicKeyString.length > 65) {
            @autoreleasepool {

                // Convert the base64 encoded public key into a binary representation

                NSData *publicKeyECData = [[NSData alloc] initWithBase64EncodedString:appPublicKeyString options:NSDataBase64DecodingIgnoreUnknownCharacters];
                NSData *publicKey = [publicKeyECData subdataWithRange:NSMakeRange(publicKeyECData.length - 65, 65)];

                // Convert the binary represnation into a SecKeyRef

                CFErrorRef cfError = NULL;
                NSDictionary *attributes = @{(id)kSecAttrKeyType  : (id)kSecAttrKeyTypeEC,
                                             (id)kSecAttrKeyClass : (id)kSecAttrKeyClassPublic,
                                             (id)kSecAttrKeySizeInBits : @(256)};
                SecKeyRef applicationPublicKey = SecKeyCreateWithData((__bridge CFDataRef)publicKey, (__bridge CFDictionaryRef)attributes, &cfError);

                if (cfError == NULL) {

                    EN_NOTICE_PRINTF("Validated App Public Key From App Configuration");

                    // Validate the signature

                    Boolean success = SecKeyVerifySignature(applicationPublicKey, kSecKeyAlgorithmECDSASignatureDigestX962SHA256, (__bridge CFDataRef)fileData, (__bridge CFDataRef)signatureData, &cfError);

                    if (success) {
                        // File Data is Valid
                        isVerified = YES;
                        EN_NOTICE_PRINTF("File Signature Verified and Valid");
                    } else {
                        // Invalid File Data
                        isVerified = NO;
                        EN_ERROR_PRINTF( "File Signature Verification Failed: %@", cfError);
                    }
                } else {
                    EN_ERROR_PRINTF( "Unable to Validate App Public Key From App Configuration: %@", cfError);
                }

                if (cfError) {
                    CFRelease(cfError);
                }

                if (applicationPublicKey) {
                    CFAutorelease(applicationPublicKey);
                }
            }
        } else {
            EN_ERROR_PRINTF( "Bad Public Key Size from Server: %lu", appPublicKeyString.length);
            isVerified = NO;
        }

        if (completion) completion(isVerified, nil);

    } else {
        EN_ERROR_PRINTF( "No Public Key");
        if (completion) completion(NO, nil);
    }
}

@end

NS_ASSUME_NONNULL_END
