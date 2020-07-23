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

#import <ExposureNotification/ExposureNotification.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

@class ENSignature;
@class ENProtobufCoder;
@class ENTemporaryExposureKey;

//===========================================================================================================================
/*!	@brief	Constants
*/

#define ENFileExtensionMainProto				@"bin"
#define ENFileExtensionMainProtoFull			".bin"
#define ENFileExtensionSignatureProto			@"sig"
#define ENFileExtensionSignatureProtoFull		".sig"

#define ENFileSignatureMaxSize					( 64 * 1024 )

//===========================================================================================================================
/*!	@brief	File Metadata Keys
*/

/// [Number] Batch number (the 2 in 2 of 10).
#define ENFileMetadataKeyBatchNumber			@"batchNum"

/// [Number] Number of items in the batch.
#define ENFileMetadataKeyBatchSize				@"batchSize"

/// [String] Version of the public key used to verify the file signature (e.g. "v1").
#define ENFileMetadataKeyPublicKeyVersion		@"pkVers"

/// [String] Region the keys came from (i.e. country).
#define ENFileMetadataKeyRegion					@"region"

/// [Number:UnixEpochTime] Start timestamp for keys.
#define ENFileMetadataKeyStartTimestamp			@"startTS"

/// [Number:UnixEpochTime] Start timestamp for keys.
#define ENFileMetadataKeyEndTimestamp			@"endTS"

//===========================================================================================================================
/*!	@brief	Reads and writes ExposureNotification files.
*/
EN_API_AVAILABLE_EXPORT
@interface ENFile : NSObject

/// Metadata for the file.
@property (readwrite, copy, nullable, nonatomic) NSDictionary *		metadata;

/// SHA-256 hash of the file contents. Readable after open returns successfully.
@property (readonly, copy, nullable, nonatomic) NSData *			sha256Data;

/// Opens a file from an open file descriptor. This takes ownership of the file descriptor and will handle closing it.
- (BOOL) openWithFD:(int) inFD reading:(BOOL) inReading error:(ENErrorOutType) outError;

/// Open a file from a path.
- (BOOL) openWithFileSystemRepresentation:(const char *) inPath reading:(BOOL) inReading error:(ENErrorOutType) outError;

/// Closes the file.
- (BOOL) closeAndReturnError:(ENErrorOutType) outError;

/// Reads the next TEK from the file.
- (ENTemporaryExposureKey * _Nullable) readTEKAndReturnError:(ENErrorOutType) outError;

/// Writes a TEK to the end of the file.
- (BOOL) writeTEK:(ENTemporaryExposureKey*) inKey error:(ENErrorOutType) outError;

@end

//===========================================================================================================================
/*!	@brief	Reads and writes ExposureNotification signature files.
*/
EN_API_AVAILABLE_EXPORT
@interface ENSignatureFile : NSObject

/// Array of signatures parsed from the file.
@property (readwrite, copy, nullable, nonatomic) NSArray <ENSignature *> *		signatures;

/// Decodes a signature file protobuf into an object.
+ (ENSignatureFile * _Nullable)
	signatureFileWithBytes:	(const uint8_t *)	inPtr
	length:					(size_t)			inLen
	error:					(ENErrorOutType)	outError;

/// Open a file from a path.
- (BOOL) openWithFileSystemRepresentation:(const char *) inPath reading:(BOOL) inReading error:(ENErrorOutType) outError;

/// Closes the file.
- (BOOL) closeAndReturnError:(ENErrorOutType) outError;

// Writes all the signatures.
- (BOOL) writeAndReturnError:(ENErrorOutType) outError;

@end

//===========================================================================================================================
/*!	@brief	Reads and writes ExposureNotification signature files.
*/
EN_API_AVAILABLE_EXPORT
@interface ENSignature : NSObject

/// Apple App Bundle ID.
@property (readwrite, copy, nullable, nonatomic) NSString *		appleBundleID;

/// Android App Package.
@property (readwrite, copy, nullable, nonatomic) NSString *		androidBundleID;

/// Batch number (e.g. 1 of 5).
@property (readwrite, assign, nonatomic) uint32_t				batchNumber;

/// Batch count (e.g. 5 in batch).
@property (readwrite, assign, nonatomic) uint32_t				batchCount;

/// Version for key ID.
@property (readwrite, copy, nullable, nonatomic) NSString *		keyID;

/// Version for key rotations.
@property (readwrite, copy, nullable, nonatomic) NSString *		keyVersion;

/// E.g. ECDSA using a P-256 curve and SHA-256 as a hash function.
@property (readwrite, copy, nullable, nonatomic) NSString *		signatureAlgorithm;

/// Signature in X9.62 format (ASN.1 SEQUENCE of two INTEGER fields).
@property (readwrite, copy, nullable, nonatomic) NSData *		signatureData;

/// Initializes with protobuf data.
- (instancetype _Nullable) initWithBytes:(const uint8_t *) inPtr length:(size_t) inLen error:(ENErrorOutType) outError;

/// Encodes to protobuf format.
- (BOOL) encodeWithProtobufCoder:(ENProtobufCoder *) inCoder error:(ENErrorOutType) outError;

@end

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
