/*
 *      Copyright (C) 2020 Apple Inc. All Rights Reserved.
 *
 *      ExposureNotification is licensed under Apple Inc.’s
 *      Sample Code License Agreement, which is contained in
 *      the LICENSE file distributed with ExposureNotification,
 *      and only to those who accept that license.
 *
 */

#import <ExposureNotification/ExposureNotification.h>

#import "ENProtobufUtils.h"
#import "ENCommonPrivate.h"
#import "ENShims.h"

NS_ASSUME_NONNULL_BEGIN

//===========================================================================================================================

#define	BufferMaxSizeDefault			( 128 * 1024 )

#define ProtobufTypeVarInt				0
#define ProtobufType64Bit				1
#define ProtobufTypeLengthDelimited		2
#define ProtobufTypeStartGroup			3 // Deprecated
#define ProtobufTypeEndGroup			4 // Deprecated
#define ProtobufType32Bit				5

//===========================================================================================================================

@implementation ENProtobufCoder
{
	uint8_t		_staticBuffer[ 256 ];
}

//===========================================================================================================================

- (instancetype) init
{
	self = [super init];
	if( !self ) return( nil );
	
	_bufferMaxSize = BufferMaxSizeDefault;
	
	return( self );
}

//===========================================================================================================================

- (void) setReadMemory:(const void *) inPtr length:(size_t) inLen
{
	_readBase	= (const uint8_t *) inPtr;
	_readSrc	= _readBase;
	_readEnd	= _readBase + inLen;
	
	_writeBase	= NULL;
	_writeDst	= NULL;
	_writeLim	= NULL;
	
	_fileHandle	= NULL;
	_bufferData = nil;
	_bufferOffset = 0;
}

//===========================================================================================================================

- (void) setWriteMemory:(void *) inPtr length:(size_t) inLen
{
	_readBase	= NULL;
	_readSrc	= NULL;
	_readEnd	= NULL;
	
	_writeBase	= (uint8_t *) inPtr;
	_writeDst	= _writeBase;
	_writeLim	= _writeBase + inLen;
	
	_fileHandle	= NULL;
	_bufferData = nil;
	_bufferOffset = 0;
}

//===========================================================================================================================

- (void) setWriteMutableData:(NSMutableData *) inData
{
	_readBase	= NULL;
	_readSrc	= NULL;
	_readEnd	= NULL;
	
	_writeBase	= NULL;
	_writeDst	= NULL;
	_writeLim	= NULL;
	
	_fileHandle	= NULL;
	_bufferData = inData;
	_bufferOffset = 0;
}

//===========================================================================================================================

- (void) setFileHandle:(FILE *) inFileHandle
{
	_readBase	= NULL;
	_readSrc	= NULL;
	_readEnd	= NULL;
	
	_writeBase	= NULL;
	_writeDst	= NULL;
	_writeLim	= NULL;
	
	_fileHandle	= inFileHandle;
	_bufferData = nil;
	_bufferOffset = 0;
}

// MARK: -

//===========================================================================================================================

- (BOOL) readType:(uint8_t *) outType tag:(uint64_t *) outTag eofOkay:(BOOL) inEOFOkay error:(ENErrorOutType) outError
{
	uint64_t key;
	BOOL good = [self readVarInt:&key eofOkay:inEOFOkay error:outError];
	require_return_value( good, NO );
	*outTag  = (uint64_t)( key >> 3 );
	*outType = (uint8_t)( key & 0x7 );
	return( YES );
}

//===========================================================================================================================

- (const uint8_t * _Nullable) readLengthDelimited:(size_t *) outLen error:(ENErrorOutType) outError
{
	uint64_t len = 0;
	BOOL good = [self readVarInt:&len eofOkay:NO error:outError];
	require_return_value( good, nil );
	require_return_nil( len <= SIZE_MAX, outError, ENNSErrorF( kRangeErr, "Length > SIZE_MAX: %llu", len ) );
	
    const uint8_t *ptr = [self _readLength:(size_t) len eofOkay:NO error:outError];
	require_return_value( ptr, nil );
	*outLen = (size_t) len;
	return( ptr );
}

//===========================================================================================================================

- (BOOL)
	writeLengthDelimitedPtr:	(const void *)		inPtr
	length:						(size_t)			inLen
	tag:						(uint64_t)			inTag
	error:						(ENErrorOutType)	outError
{
	uint64_t key = ( inTag << 3 ) | ProtobufTypeLengthDelimited;
	BOOL good = [self writeVarInt:key error:outError];
	require_return_value( good, NO );
	
	good = [self writeVarInt:inLen error:outError];
	require_return_value( good, NO );
	
	good = [self _writeBytes:inPtr length:inLen error:outError];
	return( good );
}

//===========================================================================================================================

- (BOOL) skipType:(uint8_t) inType error:(ENErrorOutType) outError
{
	BOOL good;
	switch( inType )
	{
		case ProtobufTypeVarInt:
		{
			uint64_t value = 0;
			good = [self readVarInt:&value eofOkay:NO error:outError];
			require_return_value( good, NO );
			break;
		}
		
		case ProtobufType64Bit:
		{
			good = [self _skipLength:8 error:outError];
			require_return_value( good, NO );
			break;
		}
		
		case ProtobufTypeLengthDelimited:
		{
			uint64_t length = 0;
			good = [self readVarInt:&length eofOkay:NO error:outError];
			require_return_value( good, NO );
			require_return_no( length <= SIZE_MAX, outError,
				ENNSErrorF( kSizeErr, "Length-delimited too big: %llu bytes", length ) );
			
			good = [self _skipLength:(size_t) length error:outError];
			require_return_value( good, NO );
			break;
		}
		
		case ProtobufType32Bit:
		{
			good = [self _skipLength:4 error:outError];
			require_return_value( good, NO );
			break;
		}
		
		default:
			if( outError ) *outError = ENNSErrorF( kUnsupportedDataErr, "Unsupported protobuf type: %d", inType );
			return( NO );
	}
	return( YES );
}

// MARK: -

//===========================================================================================================================

- (NSData * _Nullable) readNSDataAndReturnError:(ENErrorOutType) outError
{
	uint64_t len = 0;
	BOOL good = [self readVarInt:&len eofOkay:NO error:outError];
	require_return_value( good, nil );
	require_return_nil( len < SIZE_MAX, outError, ENNSErrorF( kSizeErr, "Data too big: %llu bytes", len ) );
	
    const uint8_t * ptr = [self _readLength:(size_t) len eofOkay:NO error:outError];
	require_return_value( ptr, nil );
	
    NSData *data = [[NSData alloc] initWithBytes:ptr length:(size_t) len];
	require_return_nil( data, outError, ENNSErrorF( kSizeErr, "Create NSData failed: %llu", len ) );
	return( data );
}

//===========================================================================================================================

- (BOOL) writeNSData:(NSData *) inData tag:(uint64_t) inTag error:(ENErrorOutType) outError
{
	BOOL good = [self writeLengthDelimitedPtr:inData.bytes length:inData.length tag:inTag error:outError];
	return( good );
}

//===========================================================================================================================

- (NSString * _Nullable) readNSStringAndReturnError:(ENErrorOutType) outError
{
	uint64_t length = 0;
	BOOL good = [self readVarInt:&length eofOkay:NO error:outError];
	require_return_value( good, nil );
	require_return_nil( length < SIZE_MAX, outError, ENNSErrorF( kSizeErr, "String too big: %llu bytes", length ) );
	
    const uint8_t *ptr = [self _readLength:(size_t) length eofOkay:NO error:outError];
	require_return_value( ptr, nil );
	
    NSString *str = [[NSString alloc] initWithBytes:ptr length:(size_t) length encoding:NSUTF8StringEncoding];
	require_return_nil( str, outError, ENNSErrorF( kSizeErr, "Bad UTF-8 string" ) );
	return( str );
}

//===========================================================================================================================

- (BOOL) writeNSString:(NSString *) inString tag:(uint64_t) inTag error:(ENErrorOutType) outError
{
    const char *utf8 = inString.UTF8String;
    size_t len = strlen( utf8 );
	BOOL good = [self writeLengthDelimitedPtr:utf8 length:len tag:inTag error:outError];
	return( good );
}

// MARK: -

//===========================================================================================================================

- (BOOL) readVarInt:(uint64_t *) outValue eofOkay:(BOOL) inEOFOkay error:(ENErrorOutType) outError
{
	uint64_t value = 0;
	uint8_t  shift = 0;
	for( ;; )
	{
		const uint8_t *ptr = [self _readLength:1 eofOkay:inEOFOkay error:outError];
		require_return_value( ptr, NO );
		uint8_t u8 = *ptr;
		uint8_t b = u8 & 0x7F;
		uint64_t u64 = ( (uint64_t) b ) << shift;
		require_return_no( ( u64 >> shift ) == b, outError, ENNSErrorF( kRangeErr, "readVarInt shift overflow" ) );
		value |= u64;
		if( !( u8 & 0x80 ) ) break;
		shift += 7;
		require_return_no( shift <= 63, outError, ENNSErrorF( kOverrunErr, "readVarInt overrun" ) );
	}
	*outValue = value;
	return( YES );
}

//===========================================================================================================================

- (BOOL) writeVarInt:(uint64_t) inValue error:(ENErrorOutType) outError
{
	while( inValue > 0x7F )
	{
		uint8_t u8 = 0x80 | ( (uint8_t)( inValue & 0xFF ) );
		BOOL good = [self _writeBytes:&u8 length:1 error:outError];
		require_return_value( good, NO );
		inValue >>= 7;
	}
	uint8_t u8 = (uint8_t)( inValue & 0xFF );
	BOOL good = [self _writeBytes:&u8 length:1 error:outError];
	require_return_value( good, NO );
	return( YES );
}

//===========================================================================================================================

- (BOOL) readVarIntSInt32:(int32_t *) outValue error:(ENErrorOutType) outError
{
	uint64_t u64 = 0;
	BOOL good = [self readVarInt:&u64 eofOkay:NO error:outError];
	require_return_value( good, NO );
	int32_t s32 = (int32_t) u64;
	s32 = ( s32 >> 1 ) ^ -( s32 & 1 );
	*outValue = s32;
	return( YES );
}

//===========================================================================================================================

- (BOOL) writeVarIntSInt32:(int32_t) inValue tag:(uint64_t) inTag error:(ENErrorOutType) outError
{
	uint64_t key = ( inTag << 3 ) | ProtobufTypeVarInt;
	BOOL good = [self writeVarInt:key error:outError];
	require_return_value( good, NO );
	
	int32_t value = ( (int32_t)( ( (uint32_t) inValue ) << 1 ) ) ^ ( inValue >> 31 );
	good = [self writeVarInt:(uint64_t) value error:outError];
	return( good );
}

//===========================================================================================================================

- (BOOL) readVarIntUInt32:(uint32_t *) outValue error:(ENErrorOutType) outError
{
	uint64_t u64 = 0;
	BOOL good = [self readVarInt:&u64 eofOkay:NO error:outError];
	require_return_value( good, NO );
	require_return_no( u64 <= UINT32_MAX, outError, ENNSErrorF( kRangeErr, "Out-of-range UInt32: %llu", u64 ) );
	*outValue = (uint32_t) u64;
	return( YES );
}

//===========================================================================================================================

- (BOOL) writeVarIntUInt32:(uint32_t) inValue tag:(uint64_t) inTag error:(ENErrorOutType) outError
{
	uint64_t key = ( inTag << 3 ) | ProtobufTypeVarInt;
	BOOL good = [self writeVarInt:key error:outError];
	require_return_value( good, NO );
	
	good = [self writeVarInt:inValue error:outError];
	return( good );
}

//===========================================================================================================================

- (BOOL) readVarIntSInt64:(int64_t *) outValue error:(ENErrorOutType) outError
{
	uint64_t u64 = 0;
	BOOL good = [self readVarInt:&u64 eofOkay:NO error:outError];
	require_return_value( good, NO );
	int64_t s64 = (int64_t) u64;
	s64 = ( s64 >> 1 ) ^ -( s64 & 1 );
	*outValue = s64;
	return( YES );
}

//===========================================================================================================================

- (BOOL) writeVarIntSInt64:(int64_t) inValue tag:(uint64_t) inTag error:(ENErrorOutType) outError
{
	uint64_t key = ( inTag << 3 ) | ProtobufTypeVarInt;
	BOOL good = [self writeVarInt:key error:outError];
	require_return_value( good, NO );
	
	int64_t value = ( (int64_t)( ( (uint64_t) inValue ) << 1 ) ) ^ ( inValue >> 63 );
	good = [self writeVarInt:(uint64_t) value error:outError];
	return( good );
}

//===========================================================================================================================

- (BOOL) readVarIntUInt64:(uint64_t *) outValue error:(ENErrorOutType) outError
{
	uint64_t u64 = 0;
	BOOL good = [self readVarInt:&u64 eofOkay:NO error:outError];
	require_return_value( good, NO );
	*outValue = u64;
	return( YES );
}

//===========================================================================================================================

- (BOOL) writeVarIntUInt64:(uint64_t) inValue tag:(uint64_t) inTag error:(ENErrorOutType) outError
{
	uint64_t key = ( inTag << 3 ) | ProtobufTypeVarInt;
	BOOL good = [self writeVarInt:key error:outError];
	require_return_value( good, NO );
	
	good = [self writeVarInt:inValue error:outError];
	return( good );
}

// MARK -

//===========================================================================================================================

- (BOOL) readFixedSInt32:(int32_t *) outValue error:(ENErrorOutType) outError
{
	const uint8_t *ptr = [self _readLength:4 eofOkay:NO error:outError];
	require_return_value( ptr, NO );
	*outValue = (int32_t) ReadLittle32( ptr );
	return( YES );
}

//===========================================================================================================================

- (BOOL) writeFixedSInt32:(int32_t) inValue tag:(uint64_t) inTag error:(ENErrorOutType) outError
{
	uint64_t key = ( inTag << 3 ) | ProtobufType32Bit;
	BOOL good = [self writeVarInt:key error:outError];
	require_return_value( good, NO );

	int32_t value = ( (int32_t)( ( (uint32_t) inValue ) << 1 ) ) ^ ( inValue >> 31 );
	uint8_t buf[ 4 ];
	WriteLittle32( buf, value );
	good = [self _writeBytes:buf length:sizeof( buf ) error:outError];
	return( good );
}

//===========================================================================================================================

- (BOOL) readFixedUInt32:(uint32_t *) outValue error:(ENErrorOutType) outError
{
	const uint8_t *ptr = [self _readLength:4 eofOkay:NO error:outError];
	require_return_value( ptr, NO );
	*outValue = ReadLittle32( ptr );
	return( YES );
}

//===========================================================================================================================

- (BOOL) writeFixedUInt32:(uint32_t) inValue tag:(uint64_t) inTag error:(ENErrorOutType) outError
{
	uint64_t key = ( inTag << 3 ) | ProtobufType32Bit;
	BOOL good = [self writeVarInt:key error:outError];
	require_return_value( good, NO );
	
	uint8_t buf[ 4 ];
	WriteLittle32( buf, inValue );
	good = [self _writeBytes:buf length:sizeof( buf ) error:outError];
	return( good );
}

//===========================================================================================================================

- (BOOL) readFixedSInt64:(int64_t *) outValue error:(ENErrorOutType) outError
{
	const uint8_t *ptr = [self _readLength:8 eofOkay:NO error:outError];
	require_return_value( ptr, NO );
	*outValue = (int64_t) ReadLittle64( ptr );
	return( YES );
}

//===========================================================================================================================

- (BOOL) writeFixedSInt64:(int64_t) inValue tag:(uint64_t) inTag error:(ENErrorOutType) outError
{
	uint64_t key = ( inTag << 3 ) | ProtobufType64Bit;
	BOOL good = [self writeVarInt:key error:outError];
	require_return_value( good, NO );
	
	int64_t value = ( (int64_t)( ( (uint64_t) inValue ) << 1 ) ) ^ ( inValue >> 63 );
	uint8_t buf[ 8 ];
	WriteLittle64( buf, value );
	good = [self _writeBytes:buf length:sizeof( buf ) error:outError];
	return( good );
}

//===========================================================================================================================

- (BOOL) readFixedUInt64:(uint64_t *) outValue error:(ENErrorOutType) outError
{
	const uint8_t *ptr = [self _readLength:8 eofOkay:NO error:outError];
	require_return_value( ptr, NO );
	*outValue = ReadLittle64( ptr );
	return( YES );
}

//===========================================================================================================================

- (BOOL) writeFixedUInt64:(uint64_t) inValue tag:(uint64_t) inTag error:(ENErrorOutType) outError
{
	uint64_t key = ( inTag << 3 ) | ProtobufType64Bit;
	BOOL good = [self writeVarInt:key error:outError];
	require_return_value( good, NO );
	
	uint8_t buf[ 8 ];
	WriteLittle64( buf, inValue );
	good = [self _writeBytes:buf length:sizeof( buf ) error:outError];
	return( good );
}

// MARK: -

//===========================================================================================================================

- (const uint8_t * _Nullable) _readLength:(size_t) inLen eofOkay:(BOOL) inEOFOkay error:(ENErrorOutType) outError
NS_RETURNS_INNER_POINTER
{
    const uint8_t *readSrc = _readSrc;
	if( readSrc )
	{
		require_return_nil( ( (size_t)( _readEnd - readSrc ) ) >= inLen, outError, 
			inEOFOkay ? nil : ENNSErrorF( kUnderrunErr, "read memory underrun" ) );
		_readSrc = readSrc + inLen;
		return( readSrc );
	}
	
	FILE *fileHandle = _fileHandle;
	if( fileHandle )
	{
		require_return_nil( inLen <= _bufferMaxSize, outError, ENNSErrorF( kSizeErr, "read too big: %zu", inLen ) );
		uint8_t *bufferPtr;
		if( inLen <= sizeof( _staticBuffer ) )
		{
			bufferPtr = _staticBuffer;
		}
		else
		{
            NSMutableData *bufferData = _bufferData;
			if( !bufferData )
			{
				bufferData = [[NSMutableData alloc] initWithLength:inLen];
				_bufferData = bufferData;
			}
			else
			{
				bufferData.length = inLen;
			}
			bufferPtr = (uint8_t *) bufferData.mutableBytes;
		}
		
		size_t n = fread( bufferPtr, 1, inLen, fileHandle );
		if( n != inLen )
		{
			if( outError ) *outError = feof( fileHandle ) ? nil : ENNSErrorF( kReadErr, "read failed: %#m", errno );
			return( nil );
		}
		return( bufferPtr );
	}
	
	if( outError ) *outError = ENNSErrorF( kNotPreparedErr, "read, no input sources" );
	return( nil );
}

//===========================================================================================================================

- (BOOL) _skipLength:(size_t) inLen error:(ENErrorOutType) outError
{
    const uint8_t *readSrc = _readSrc;
	if( readSrc )
	{
		require_return_no( ( (size_t)( _readEnd - readSrc ) ) >= inLen, outError, 
			ENNSErrorF( kUnderrunErr, "read memory underrun" ) );
		_readSrc = readSrc + inLen;
		return( YES );
	}
	
	FILE *fileHandle = _fileHandle;
	if( fileHandle )
	{
		int err = fseeko( fileHandle, (off_t) inLen, SEEK_CUR );
		err = map_global_value_errno( !err, fileHandle );
		require_return_no( !err, outError, ENNSErrorF( err, "fseek failed: %zu bytes", inLen ) );
		return( YES );
	}
	
	if( outError ) *outError = ENNSErrorF( kNotPreparedErr, "skip, no input sources" );
	return( NO );
}

//===========================================================================================================================

- (BOOL) _writeBytes:(const void *) inPtr length:(size_t) inLen error:(ENErrorOutType) outError
{
    uint8_t *writeDst = _writeDst;
	if( writeDst )
	{
		require_return_no( ( (size_t)( _writeLim - writeDst ) ) >= inLen, outError, 
			ENNSErrorF( kOverrunErr, "write memory overrun" ) );
		memcpy( writeDst, inPtr, inLen );
		_writeDst = writeDst + inLen;
		return( YES );
	}
	
	FILE *fileHandle = _fileHandle;
	if( fileHandle )
	{
		size_t n = fwrite( inPtr, 1, inLen, fileHandle );
		require_return_no( n == inLen, outError, ENNSErrorF( kWriteErr, "write failed: %#m", errno ) );
		return( YES );
	}
	
    NSMutableData *bufferData = _bufferData;
	if( bufferData )
	{
		require_return_no( ( (size_t)( _bufferMaxSize - _bufferOffset ) ) >= inLen, outError, 
			ENNSErrorF( kOverrunErr, "write buffer overrun" ) );
		[bufferData appendBytes:inPtr length:inLen];
		_bufferOffset += inLen;
		return( YES ); 
	}
	
	if( outError ) *outError = ENNSErrorF( kNotPreparedErr, "write no output sources" );
	return( NO );
}

@end

NS_ASSUME_NONNULL_END
