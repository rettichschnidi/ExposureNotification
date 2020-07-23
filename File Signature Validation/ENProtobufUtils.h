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
#import <stdio.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

//===========================================================================================================================
/*!	@brief		Encodes objects to or decodes objects in protobuf format.
*/
EN_API_AVAILABLE_EXPORT
@interface ENProtobufCoder : NSObject

/// Configures for decoding from memory.
- (void) setReadMemory:(const void *) inPtr length:(size_t) inLen;

/// Configures for encoding to memory.
- (void) setWriteMemory:(void *) inPtr length:(size_t) inLen;

/// Configures for encoding to dynamically sized buffer.
- (void) setWriteMutableData:(NSMutableData *) inData;

/// Configures for encoding/decoding from a file.
- (void) setFileHandle:(FILE *) inFileHandle;

/// Reads a key (tag + type).
- (BOOL) readType:(uint8_t *) outType tag:(uint64_t *) outTag eofOkay:(BOOL) inEOFOkay error:(ENErrorOutType) outError;

/// Skip a type.
- (BOOL) skipType:(uint8_t) inType error:(ENErrorOutType) outError;

/// Length-delimited data.
- (const uint8_t * _Nullable) readLengthDelimited:(size_t *) outLen error:(ENErrorOutType) outError
NS_RETURNS_INNER_POINTER;
- (BOOL)
	writeLengthDelimitedPtr:	(const void *)		inPtr
	length:						(size_t)			inLen
	tag:						(uint64_t)			inTag
	error:						(ENErrorOutType)	outError;

/// NSData as length-delimited data
- (NSData * _Nullable) readNSDataAndReturnError:(ENErrorOutType) outError;
- (BOOL) writeNSData:(NSData *) inData tag:(uint64_t) inTag error:(ENErrorOutType) outError;

/// NSString as length-delimited data
- (NSString * _Nullable) readNSStringAndReturnError:(ENErrorOutType) outError;
- (BOOL) writeNSString:(NSString *) inString tag:(uint64_t) inTag error:(ENErrorOutType) outError;

/// VarInt-based integers.
- (BOOL) readVarInt:(uint64_t *) outValue eofOkay:(BOOL) inEOFOkay error:(ENErrorOutType) outError;
- (BOOL) writeVarInt:(uint64_t) inValue error:(ENErrorOutType) outError;

- (BOOL) readVarIntSInt32:(int32_t *) outValue error:(ENErrorOutType) outError;
- (BOOL) writeVarIntSInt32:(int32_t) inValue tag:(uint64_t) inTag error:(ENErrorOutType) outError;

- (BOOL) readVarIntUInt32:(uint32_t *) outValue error:(ENErrorOutType) outError;
- (BOOL) writeVarIntUInt32:(uint32_t) inValue tag:(uint64_t) inTag error:(ENErrorOutType) outError;

- (BOOL) readVarIntSInt64:(int64_t *) outValue error:(ENErrorOutType) outError;
- (BOOL) writeVarIntSInt64:(int64_t) inValue tag:(uint64_t) inTag error:(ENErrorOutType) outError;

- (BOOL) readVarIntUInt64:(uint64_t *) outValue error:(ENErrorOutType) outError;
- (BOOL) writeVarIntUInt64:(uint64_t) inValue tag:(uint64_t) inTag error:(ENErrorOutType) outError;

/// Fixed-sized integers.
- (BOOL) readFixedSInt32:(int32_t *) outValue error:(ENErrorOutType) outError;
- (BOOL) writeFixedSInt32:(int32_t) inValue tag:(uint64_t) inTag error:(ENErrorOutType) outError;

- (BOOL) readFixedUInt32:(uint32_t *) outValue error:(ENErrorOutType) outError;
- (BOOL) writeFixedUInt32:(uint32_t) inValue tag:(uint64_t) inTag error:(ENErrorOutType) outError;

- (BOOL) readFixedSInt64:(int64_t *) outValue error:(ENErrorOutType) outError;
- (BOOL) writeFixedSInt64:(int64_t) inValue tag:(uint64_t) inTag error:(ENErrorOutType) outError;

- (BOOL) readFixedUInt64:(uint64_t *) outValue error:(ENErrorOutType) outError;
- (BOOL) writeFixedUInt64:(uint64_t) inValue tag:(uint64_t) inTag error:(ENErrorOutType) outError;

/// Raw access for debugging.
@property (readonly, assign, nullable, nonatomic) const uint8_t *		readBase;
@property (readonly, assign, nullable, nonatomic) const uint8_t *		readSrc;
@property (readonly, assign, nullable, nonatomic) const uint8_t *		readEnd;

@property (readonly, assign, nullable, nonatomic) uint8_t *				writeBase;
@property (readonly, assign, nullable, nonatomic) uint8_t *				writeDst;
@property (readonly, assign, nullable, nonatomic) uint8_t *				writeLim;

@property (readonly, assign, nullable, nonatomic) FILE *				fileHandle;

@property (readonly, strong, nullable, nonatomic) NSMutableData *		bufferData;
@property (readwrite, assign, nonatomic) size_t							bufferOffset;
@property (readwrite, assign, nonatomic) size_t							bufferMaxSize;

@end

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
