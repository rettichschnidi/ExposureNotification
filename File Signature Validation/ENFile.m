/*
 *      Copyright (C) 2020 Apple Inc. All Rights Reserved.
 *
 *      ExposureNotification is licensed under Apple Inc.’s
 *      Sample Code License Agreement, which is contained in
 *      the LICENSE file distributed with ExposureNotification,
 *      and only to those who accept that license.
 *
 */

#import <corecrypto/ccdigest.h>
#import <ExposureNotification/ExposureNotification.h>
#import <sys/clonefile.h>
#import <sys/mman.h>
#import <sys/stat.h>

#import "ENCommonPrivate.h"
#import "ENInternal.h"
#import "ENProtobufUtils.h"
#import "ENFile.h"
#import "ENShims.h"

NS_ASSUME_NONNULL_BEGIN

//===========================================================================================================================

#define ENFileIdentifierStr		"EK Export v1    " // Space-padded to 16 bytes.
#define ENFileIdentifierLen		sizeof_string( ENFileIdentifierStr )
check_compile_time( ENFileIdentifierLen == 16 );

// ENFile protobuf tags.

#define ENFileTagStartTimestamp					1 // Fixed64
#define ENFileTagEndTimestamp					2 // Fixed64
#define ENFileTagRegion							3 // LengthDelimited (string)
#define ENFileTagBatchNumber					4 // Int32
#define ENFileTagBatchSize						5 // Int32
#define ENFileTagSignatureInfo					6 // LengthDelimited (sub-message)
#define ENFileTagKey							7 // LengthDelimited (sub-message)

// Flags for metadata.

typedef uint32_t		ENFileMetadataFlags;
#define ENFileMetadataFlagsStartTimestamp		( 1U << ENFileTagStartTimestamp )
#define ENFileMetadataFlagsEndTimestamp			( 1U << ENFileTagEndTimestamp )
#define ENFileMetadataFlagsRegion				( 1U << ENFileTagRegion )
#define ENFileMetadataFlagsBatchNumber			( 1U << ENFileTagBatchNumber )
#define ENFileMetadataFlagsBatchSize			( 1U << ENFileTagBatchSize )
#define ENFileMetadataFlagsSignatureInfo		( 1U << ENFileTagSignatureInfo )

#define ENFileMetadataFlagsAll ( \
	ENFileMetadataFlagsStartTimestamp | \
	ENFileMetadataFlagsEndTimestamp | \
	ENFileMetadataFlagsRegion | \
	ENFileMetadataFlagsBatchNumber | \
	ENFileMetadataFlagsBatchSize | \
	ENFileMetadataFlagsSignatureInfo | \
	0 )

// ENFile key protobuf tags.

#define ENKeyTagKeyData							1 // LengthDelimited (raw bytes)
#define ENKeyTagTransmissionRisk				2 // Int32
#define ENKeyTagIntervalNumber					3 // Int32
#define ENKeyTagIntervalCount					4 // Int32

// ENSignatureFile protobuf tags.

#define ENSignatureFileTagSignature				1 // LengthDelimited (sub-message)

#define ENSignatureTagSignatureInfo				1 // LengthDelimited (sub-message)
#define ENSignatureTagBatchNumber				2 // Int32
#define ENSignatureTagBatchSize					3 // Int32
#define ENSignatureTagSignatureData				4 // LengthDelimited (raw bytes)

#define ENSignatureInfoTagAppleBundleID			1 // LengthDelimited (string)
#define ENSignatureInfoTagAndroidPackage		2 // LengthDelimited (string)
#define ENSignatureInfoTagKeyVersion			3 // LengthDelimited (string)
#define ENSignatureInfoTagKeyID					4 // LengthDelimited (string)
#define ENSignatureInfoTagSignatureAlgorithm	5 // LengthDelimited (string)

//===========================================================================================================================

@implementation ENFile
{
	FILE *						_fileHandle;
	NSUInteger					_keyIndex;
	BOOL						_reading;
	ENFileMetadataFlags			_metadataFlags;
	NSMutableDictionary *		_mutableMetadata;
	ENProtobufCoder *			_protobufCoder;
	ENProtobufCoder *			_tekProtobufCoder;
}

//===========================================================================================================================

- (instancetype) init
{
	self = [super init];
	if( !self ) return( nil );

	return( self );
}

//===========================================================================================================================

- (void) dealloc
{
	ForgetANSIFile( &_fileHandle );
}

//===========================================================================================================================

- (BOOL) openWithFD:(int) inFD reading:(BOOL) inReading error:(ENErrorOutType) outError
{
	EN_DEBUG_PRINTF("Open FD %d, reading %s", inFD, YesNoStr( inReading ) );
	
    FILE *fileHandle = fdopen( inFD, inReading ? "rb" : "wb" );
	OSStatus err = map_global_value_errno( fileHandle, fileHandle );
	require_return_no( !err, outError, ENErrorF( ENErrorCodeBadParameter, "Open FD failed: %#m", err ) );
	_fileHandle = fileHandle;
	_reading = inReading;
	
	if( inReading )
	{
		BOOL good = [self _readPrepareAndReturnError:outError];
		require_return_value( good, NO );
	}
	else
	{
		BOOL good = [self _writePrepareAndReturnError:outError];
		require_return_value( good, NO );
	}
	
	return( YES );
}

//===========================================================================================================================

- (BOOL) openWithFileSystemRepresentation:(const char *) inPath reading:(BOOL) inReading error:(ENErrorOutType) outError
{
	EN_DEBUG_PRINTF("Open path '%s', reading %s", inPath, YesNoStr( inReading ) );
	
	int fileFD = open( inPath, inReading ? O_RDONLY : O_CREAT | O_WRONLY | O_TRUNC, S_IRUSR | S_IWUSR );
	OSStatus err = map_fd_creation_errno( fileFD );
	require_return_no( !err, outError, ENErrorF( ENErrorCodeBadParameter, "Open path failed: '%s', %#m", inPath, err ) );
	
	BOOL good = [self openWithFD:fileFD reading:inReading error:outError];
	return( good );
}

//===========================================================================================================================

- (BOOL) closeAndReturnError:(ENErrorOutType) outError
{
	FILE *fileHandle = _fileHandle;
	EN_DEBUG_PRINTF("Close: fileHandle %s", YesNoStr( fileHandle ) );
	require_return_no( fileHandle, outError, ENErrorF( ENErrorCodeAPIMisuse, "File not open" ) );
	
	int err = fclose( fileHandle );
	_fileHandle = NULL;
	require_return_no( !err, outError, ENErrorF( ENErrorCodeUnknown, "fclose failed: %#m", errno ) );
	
	return( YES );
}

// MARK: -

//===========================================================================================================================

- (BOOL) _readPrepareAndReturnError:(ENErrorOutType) outError
{
    FILE *fileHandle = _fileHandle;
	require_return_no( fileHandle, outError, ENErrorF( ENErrorCodeAPIMisuse, "File not open" ) );
	
	// Read and verify the identifier section.
	
	char buf[ ENFileIdentifierLen ];
	size_t n = fread( buf, 1, sizeof( buf ), fileHandle );
	if( n != sizeof( buf ) )
	{
		OSStatus err = feof( fileHandle ) ? kEndOfDataErr : errno ?: kReadErr;
		if( outError ) *outError = ENErrorF( ENErrorCodeBadFormat, "read identifier failed: %#m", err );
		return( NO );
	}
	EN_DEBUG_PRINTF("Read identifier: '%.*s'", (int) sizeof( buf ), buf );
	check_compile_time_code( sizeof( buf ) >= ENFileIdentifierLen );
	require_return_no( memcmp( buf, ENFileIdentifierStr, ENFileIdentifierLen ) == 0, outError, 
		ENErrorF( ENErrorCodeBadFormat, "File identifier mismatch" ) );
	
	BOOL good = [self _readHash:outError];
	require_return_value( good, NO );
	
	// Read metadata.
	
	_protobufCoder = [[ENProtobufCoder alloc] init];
	[_protobufCoder setFileHandle:fileHandle];
	
	_mutableMetadata = [[NSMutableDictionary alloc] init];
	_metadata = _mutableMetadata;
	
	good = [self _readMetadata:outError];
	require_return_value( good, NO );
	
	return( YES );
}

//===========================================================================================================================

- (BOOL) _readHash:(ENErrorOutType) outError
{
    FILE *fileHandle = _fileHandle;
	require_return_no( fileHandle, outError, ENErrorF( ENErrorCodeAPIMisuse, "File not open" ) );
	int fileFD = fileno( fileHandle );
	
	struct stat st;
	OSStatus err = fstat( fileFD, &st );
	err = map_global_noerr_errno( err );
	require_return_no( !err, outError, ENNSErrorF( err, "fstat failed" ) );
	require_return_no( ( (uint64_t) st.st_size ) < SIZE_MAX, outError, 
		ENNSErrorF( err, "File too big: %lld", (long long) st.st_size ) );
	
    size_t mapLen = (size_t) st.st_size;
	void *mapMem = mmap( 0, mapLen, PROT_READ, MAP_PRIVATE, fileFD, 0 );
	err = map_global_value_errno( mapMem != MAP_FAILED, mapMem );
	require_return_no( !err, outError, ENNSErrorF( err, "mmap failed" ) );

    uint8_t hashBytes[ CCSHA256_OUTPUT_SIZE ];
	ccdigest( ccsha256_di(), mapLen, mapMem, hashBytes );
	_sha256Data = [[NSData alloc] initWithBytes:hashBytes length:sizeof( hashBytes )];
    munmap( mapMem, mapLen );
	return( YES );
}

//===========================================================================================================================

- (BOOL) _readMetadata:(ENErrorOutType) outError
{
	// Save off the original file position and restore on before existing in case there are any keys before metadata.
	
    FILE *fileHandle = _fileHandle;
	require_return_no( fileHandle, outError, ENErrorF( ENErrorCodeAPIMisuse, "File not open" ) );
	
	fpos_t originalFilePosition;
	int err = fgetpos( fileHandle, &originalFilePosition );
	err = map_global_noerr_errno( err );
	require_return_no( !err, outError, ENNSErrorF( err, "fgetpos failed" ) );
	ENDefer { fsetpos( fileHandle, &originalFilePosition ); };
	
	// Read each protobuf message until we've found all the metadata or reach the end.
	
    ENProtobufCoder *protobufCoder = _protobufCoder;
	require_return_no( protobufCoder, outError, ENErrorF( ENErrorCodeAPIMisuse, "ProtobufCoder not prepared" ) );
	
	while( ( _metadataFlags & ENFileMetadataFlagsAll ) != ENFileMetadataFlagsAll )
	@autoreleasepool {
		uint8_t type = 0;
		uint64_t tag = 0;
		NSError *error = nil;
		BOOL good = [protobufCoder readType:&type tag:&tag eofOkay:YES error:&error];
		if( !good && !error ) break;
		require_return_no( good, outError, error );
		
		switch( tag )
		{
			case ENFileTagStartTimestamp:
			{
				uint64_t u64 = 0;
				good = [protobufCoder readFixedUInt64:&u64 error:outError];
				require_return_value( good, NO );
				_mutableMetadata[ ENFileMetadataKeyStartTimestamp ] = @(u64);
				_metadataFlags |= ENFileMetadataFlagsStartTimestamp;
				break;
			}
			
			case ENFileTagEndTimestamp:
			{
				uint64_t u64 = 0;
				good = [protobufCoder readFixedUInt64:&u64 error:outError];
				require_return_value( good, NO );
				_mutableMetadata[ ENFileMetadataKeyEndTimestamp ] = @(u64);
				_metadataFlags |= ENFileMetadataFlagsEndTimestamp;
				break;
			}
			
			case ENFileTagRegion:
			{
				NSString *str = [protobufCoder readNSStringAndReturnError:outError];
				require_return_value( str, NO );
				_mutableMetadata[ ENFileMetadataKeyRegion ] = str;
				_metadataFlags |= ENFileMetadataFlagsRegion;
				break;
			}
			
			case ENFileTagBatchNumber:
			{
				uint32_t u32 = 0;
				good = [protobufCoder readVarIntUInt32:&u32 error:outError];
				require_return_value( good, NO );
				_mutableMetadata[ ENFileMetadataKeyBatchNumber ] = @(u32);
				_metadataFlags |= ENFileMetadataFlagsBatchNumber;
				break;
			}
			
			case ENFileTagBatchSize:
			{
				uint32_t u32 = 0;
				good = [protobufCoder readVarIntUInt32:&u32 error:outError];
				require_return_value( good, NO );
				_mutableMetadata[ ENFileMetadataKeyBatchSize ] = @(u32);
				_metadataFlags |= ENFileMetadataFlagsBatchSize;
				break;
			}
			
			default:
				good = [protobufCoder skipType:type error:outError];
				require_return_value( good, NO );
				break;
		}
	}
	return( YES );
}

//===========================================================================================================================

- (BOOL) _writePrepareAndReturnError:(ENErrorOutType) outError
{
	FILE *fileHandle = _fileHandle;
	require_return_no( fileHandle, outError, ENErrorF( ENErrorCodeAPIMisuse, "File not open" ) );
	
	size_t n = fwrite( ENFileIdentifierStr, 1, ENFileIdentifierLen, fileHandle );
	OSStatus err = map_global_value_errno( n == ENFileIdentifierLen, fileHandle );
	require_return_no( !err, outError, ENErrorF( ENErrorCodeUnknown, "Write failed: %#m", err ) );
	
	_protobufCoder = [[ENProtobufCoder alloc] init];
	[_protobufCoder setFileHandle:fileHandle];
	
	BOOL good = [self _writeMetadataAndReturnError:outError];
	require_return_value( good, NO );
	
	return( YES );
}

//===========================================================================================================================

- (BOOL) _writeMetadataAndReturnError:(ENErrorOutType) outError
{
	BOOL			good;
	uint64_t		u64;
	uint32_t		u32;
	NSString *		str;
	
	require_return_no( _protobufCoder, outError, ENErrorF( ENErrorCodeInternal, "No ProtobufCoder coder" ) );
	
	// StartTimestamp
	
    NSNumber *startTimestamp = [_metadata objectForKey:ENFileMetadataKeyStartTimestamp];
	if( startTimestamp )
	{
        u64 = [startTimestamp unsignedLongLongValue];
		good = [_protobufCoder writeFixedUInt64:u64 tag:ENFileTagStartTimestamp error:outError];
		require_return_value( good, NO );
	}
	
	// EndTimestamp

    NSNumber *endTimestamp = [_metadata objectForKey:ENFileMetadataKeyEndTimestamp];
	if( endTimestamp )
	{
        u64 = [endTimestamp unsignedLongLongValue];
		good = [_protobufCoder writeFixedUInt64:u64 tag:ENFileTagEndTimestamp error:outError];
		require_return_value( good, NO );
	}
	
	// Region

    str = [_metadata objectForKey:ENFileMetadataKeyRegion];
	if( str )
	{
		good = [_protobufCoder writeNSString:str tag:ENFileTagRegion error:outError];
		require_return_value( good, NO );
	}
	
	// BatchNumber

    NSNumber *batchNumber = [_metadata objectForKey:ENFileMetadataKeyBatchNumber];
	if( batchNumber )
	{
        u32 = [batchNumber unsignedIntValue];
		good = [_protobufCoder writeVarIntUInt32:u32 tag:ENFileTagBatchNumber error:outError];
		require_return_value( good, NO );
	}
	
	// BatchSize

    NSNumber *batchSize = [_metadata objectForKey:ENFileMetadataKeyBatchSize];
	if( batchSize )
	{
        u32 = [batchSize unsignedIntValue];
		good = [_protobufCoder writeVarIntUInt32:u32 tag:ENFileTagBatchSize error:outError];
		require_return_value( good, NO );
	}
	
	return( YES );
}

// MARK: -

//===========================================================================================================================

- (ENTemporaryExposureKey * _Nullable) readTEKAndReturnError:(ENErrorOutType) outError
{
    ENProtobufCoder *protobufCoder = _protobufCoder;
	require_return_nil( protobufCoder, outError, ENErrorF( ENErrorCodeAPIMisuse, "ProtobufCoder not prepared" ) );
	
	for( ;; )
	{
		@autoreleasepool
		{
			uint8_t type = 0;
			uint64_t tag = 0;
			NSError *error = nil;
			BOOL good = [protobufCoder readType:&type tag:&tag eofOkay:YES error:&error];
			if( !good && !error ) break;
			require_return_nil( good, outError, error );
			
			switch( tag )
			{
				case ENFileTagKey:
				{
					size_t len = 0;
                    const uint8_t *ptr = [protobufCoder readLengthDelimited:&len error:outError];
					require_return_value( good, nil );
					
                    ENTemporaryExposureKey *tek = [self _readKeyWithPtr:ptr length:len error:&error];
					require_return_nil( tek, outError, error );
					return( tek );
				}
				
				default:
					good = [protobufCoder skipType:type error:outError];
					require_return_value( good, nil );
					break;
			}
		}
	}
	if( outError ) *outError = nil;
	return( nil );
}

//===========================================================================================================================

- (ENTemporaryExposureKey * _Nullable) _readKeyWithPtr:(const uint8_t *) inPtr length:(size_t) inLen error:(ENErrorOutType) outError
{
    ENProtobufCoder *protobufCoder = _tekProtobufCoder;
	if( !protobufCoder )
	{
		protobufCoder = [[ENProtobufCoder alloc] init];
		_tekProtobufCoder = protobufCoder;
	}
	[protobufCoder setReadMemory:inPtr length:inLen];
	
    ENTemporaryExposureKey *tek = [[ENTemporaryExposureKey alloc] init];
	for( ;; )
	{
		@autoreleasepool
		{
			uint8_t type = 0;
			uint64_t tag = 0;
			NSError *error = nil;
			BOOL good = [protobufCoder readType:&type tag:&tag eofOkay:YES error:&error];
			if( !good && !error ) break;
			require_return_nil( good, outError, error );
			
			switch( tag )
			{
				case ENKeyTagKeyData:
				{
                    NSData *data = [protobufCoder readNSDataAndReturnError:outError];
					require_return_value( data, nil );
					tek.keyData = data;
					break;
				}
				
				case ENKeyTagIntervalNumber:
				{
					uint32_t u32 = 0;
					good = [protobufCoder readVarIntUInt32:&u32 error:outError];
					require_return_value( good, nil );
					tek.rollingStartNumber = u32;
					break;
				}
				
				case ENKeyTagIntervalCount:
				{
					uint32_t u32 = 0;
					good = [protobufCoder readVarIntUInt32:&u32 error:outError];
					require_return_value( good, nil );
					tek.rollingPeriod = u32;
					break;
				}
				
				case ENKeyTagTransmissionRisk:
				{
					uint32_t u32 = 0;
					good = [protobufCoder readVarIntUInt32:&u32 error:outError];
					require_return_value( good, nil );
					tek.transmissionRiskLevel = (uint8_t ) u32;
					break;
				}
				
				default:
					good = [protobufCoder skipType:type error:outError];
					require_return_value( good, nil );
					break;
			}
		}
	}
	require_return_nil( tek.keyData, outError, ENErrorF( ENErrorCodeUnknown, "TEK no key data" ) );
	return( tek );
}

//===========================================================================================================================

- (BOOL) writeTEK:(ENTemporaryExposureKey*) inKey error:(ENErrorOutType) outError
{
	FILE *fileHandle = _fileHandle;
	require_return_no( fileHandle, outError, ENErrorF( ENErrorCodeAPIMisuse, "File not open" ) );
	
	if( !_tekProtobufCoder ) _tekProtobufCoder = [[ENProtobufCoder alloc] init];
	uint8_t buf[ 128 ];
	[_tekProtobufCoder setWriteMemory:buf length:sizeof( buf )];
	
	BOOL good;
	ENIfLet( keyData, inKey.keyData )
	{
		good = [_tekProtobufCoder writeNSData:keyData tag:ENKeyTagKeyData error:outError];
		require_return_value( good, NO );
	}
	
	good = [_tekProtobufCoder writeVarIntUInt32:inKey.rollingStartNumber tag:ENKeyTagIntervalNumber error:outError];
	require_return_value( good, NO );
	
	ENIfLet( rollingPeriod, inKey.rollingPeriod )
	{
		good = [_tekProtobufCoder writeVarIntUInt32:rollingPeriod tag:ENKeyTagIntervalCount error:outError];
		require_return_value( good, NO );
	}
	
	good = [_tekProtobufCoder writeVarIntUInt32:inKey.transmissionRiskLevel tag:ENKeyTagTransmissionRisk error:outError];
	require_return_value( good, NO );
	
    uint8_t *msgPtr = _tekProtobufCoder.writeBase;
	require_return_no( msgPtr, outError, ENErrorF( ENErrorCodeInternal, "No TEK protobuf msgPtr" ) );
    uint8_t *msgEnd = _tekProtobufCoder.writeDst;
	require_return_no( msgEnd, outError, ENErrorF( ENErrorCodeInternal, "No TEK protobuf endEnd" ) );
	size_t len = (size_t)( msgEnd - msgPtr );
	if( len > 0 )
	{
		good = [_protobufCoder writeLengthDelimitedPtr:msgPtr length:len tag:ENFileTagKey error:outError];
		require_return_value( good, NO );
	}
	
	return( YES );
}

@end

// MARK: -

//===========================================================================================================================

@implementation ENSignatureFile
{
	FILE *		_fileHandle;
}

//===========================================================================================================================

+ (ENSignatureFile * _Nullable)
	signatureFileWithBytes:	(const uint8_t *)	inPtr
	length:					(size_t)			inLen
	error:					(ENErrorOutType)	outError
{
    ENProtobufCoder *protobufCoder = [[ENProtobufCoder alloc] init];
	[protobufCoder setReadMemory:inPtr length:inLen];
	
    NSMutableArray <ENSignature *> *signatureArray = [[NSMutableArray <ENSignature *> alloc] init];
	for( ;; )
	{
		@autoreleasepool
		{
			uint8_t type = 0;
			uint64_t tag = 0;
			NSError *error = nil;
			BOOL good = [protobufCoder readType:&type tag:&tag eofOkay:YES error:&error];
			if( !good && !error ) break;
			require_return_nil( good, outError, error );
			
			switch( tag )
			{
				case ENSignatureFileTagSignature:
				{
					size_t len = 0;
                    const uint8_t * ptr = [protobufCoder readLengthDelimited:&len error:outError];
					require_return_value( ptr, nil );
					
                    ENSignature *signature = [[ENSignature alloc] initWithBytes:ptr length:len error:&error];
					require_return_value( signature, nil );
					[signatureArray addObject:signature];
					break;
				}
				
				default:
					good = [protobufCoder skipType:type error:&error];
					require_return_value( good, nil );
					break;
			}
		}
	}
	
    ENSignatureFile *signatureFile = [[ENSignatureFile alloc] init];
	signatureFile.signatures = signatureArray;
	return( signatureFile );
}

//===========================================================================================================================

- (BOOL) openWithFileSystemRepresentation:(const char *) inPath reading:(BOOL) inReading error:(ENErrorOutType) outError
{
	require_return_no( !inReading, outError, ENErrorF( ENErrorCodeUnsupported, "Reading files not implemented" ) );
	require_return_no( !_fileHandle, outError, ENErrorF( ENErrorCodeAPIMisuse, "File already open" ) );
	
	_fileHandle = fopen( inPath, inReading ? "rb" : "wb" );
	OSStatus err = map_global_value_errno( _fileHandle, _fileHandle );
	require_return_no( !err, outError, ENErrorF( ENErrorCodeBadParameter, "Open path failed: '%s', %#m", inPath, err ) );
	
	return( YES );
}

//===========================================================================================================================

- (BOOL) closeAndReturnError:(ENErrorOutType) outError
{
	FILE *fileHandle = _fileHandle;
	require_return_no( fileHandle, outError, ENErrorF( ENErrorCodeAPIMisuse, "File not open" ) );
	
	int err = fclose( fileHandle );
	_fileHandle = NULL;
	require_return_no( !err, outError, ENErrorF( ENErrorCodeUnknown, "fclose failed: %#m", errno ) );
	
	return( YES );
}

//===========================================================================================================================

- (BOOL) writeAndReturnError:(ENErrorOutType) outError
{
    FILE *fileHandle = _fileHandle;
	require_return_no( fileHandle, outError, ENErrorF( ENErrorCodeAPIMisuse, "File not open" ) );
	
    ENProtobufCoder *protobufCoder = [[ENProtobufCoder alloc] init];
	[protobufCoder setFileHandle:fileHandle];
	
	for( ENSignature *signature in _signatures )
	{
		@autoreleasepool
		{
            ENProtobufCoder *sigProtobufCoder = [[ENProtobufCoder alloc] init];
            NSMutableData *bufferData = [[NSMutableData alloc] init];
			[sigProtobufCoder setWriteMutableData:bufferData];
			BOOL good = [signature encodeWithProtobufCoder:sigProtobufCoder error:outError];
			require_return_value( good, NO );
			
			size_t len = bufferData.length;
			if( len > 0 )
			{
				good = [protobufCoder writeLengthDelimitedPtr:bufferData.bytes length:len
					tag:ENSignatureFileTagSignature error:outError];
				require_return_value( good, NO );
			}
		}
	}
	return( YES );
}

@end

// MARK: -

@implementation ENSignature

//===========================================================================================================================

- (instancetype _Nullable) initWithBytes:(const uint8_t *) inPtr length:(size_t) inLen error:(ENErrorOutType) outError
{
	self = [self init];
	require_return_nil( self, outError, ENErrorF( ENErrorCodeUnknown, "init failed" ) );
	
    ENProtobufCoder *protobufCoder = [[ENProtobufCoder alloc] init];
	[protobufCoder setReadMemory:inPtr length:inLen];
	
	for( ;; )
	{
		@autoreleasepool
		{
			uint8_t type = 0;
			uint64_t tag = 0;
			NSError *error = nil;
			BOOL good = [protobufCoder readType:&type tag:&tag eofOkay:YES error:&error];
			if( !good && !error ) break;
			require_return_nil( good, outError, error );
			
			switch( tag )
			{
				case ENSignatureTagSignatureInfo:
				{
					size_t len = 0;
                    const uint8_t * ptr = [protobufCoder readLengthDelimited:&len error:outError];
					require_return_value( ptr, nil );
					
					good = [self _readSignatureInfoPtr:ptr length:len error:outError];
					require_return_value( good, nil );
					break;
				}
				
				case ENSignatureTagBatchNumber:
				{
					uint32_t u32 = 0;
					good = [protobufCoder readVarIntUInt32:&u32 error:outError];
					require_return_value( good, nil );
					_batchNumber = u32;
					break;
				}
				
				case ENSignatureTagBatchSize:
				{
					uint32_t u32 = 0;
					good = [protobufCoder readVarIntUInt32:&u32 error:outError];
					require_return_value( good, nil );
					_batchCount = u32;
					break;
				}
				
				case ENSignatureTagSignatureData:
				{
                    NSData *data = [protobufCoder readNSDataAndReturnError:outError];
					require_return_value( data, nil );
					_signatureData = data;
					break;
				}
				
				default:
					good = [protobufCoder skipType:type error:outError];
					require_return_value( good, nil );
					break;
			}
		}
	}
	return( self );
}

//===========================================================================================================================

- (BOOL) _readSignatureInfoPtr:(const uint8_t *) inPtr length:(size_t) inLen error:(ENErrorOutType) outError
{
    ENProtobufCoder *protobufCoder = [[ENProtobufCoder alloc] init];
	[protobufCoder setReadMemory:inPtr length:inLen];
	
	for( ;; )
	{
		@autoreleasepool
		{
			uint8_t type = 0;
			uint64_t tag = 0;
			NSError *error = nil;
			BOOL good = [protobufCoder readType:&type tag:&tag eofOkay:YES error:&error];
			if( !good && !error ) break;
			require_return_no( good, outError, error );
			
			switch( tag )
			{
				case ENSignatureInfoTagAppleBundleID:
				{
                    NSString *str = [protobufCoder readNSStringAndReturnError:outError];
					require_return_value( str, NO );
					_appleBundleID = str;
					break;
				}
				
				case ENSignatureInfoTagAndroidPackage:
				{
                    NSString *str = [protobufCoder readNSStringAndReturnError:outError];
					require_return_value( str, NO );
					_androidBundleID = str;
					break;
				}
				
				case ENSignatureInfoTagKeyVersion:
				{
                    NSString *str = [protobufCoder readNSStringAndReturnError:outError];
					require_return_value( str, NO );
					_keyVersion = str;
					break;
				}
				
				case ENSignatureInfoTagKeyID:
				{
                    NSString *str = [protobufCoder readNSStringAndReturnError:outError];
					require_return_value( str, NO );
					_keyID = str;
					break;
				}
				
				case ENSignatureInfoTagSignatureAlgorithm:
				{
                    NSString *str = [protobufCoder readNSStringAndReturnError:outError];
					require_return_value( str, NO );
					_signatureAlgorithm = str;
					break;
				}
				
				default:
					good = [protobufCoder skipType:type error:outError];
					require_return_value( good, NO );
					break;
			}
		}
	}
	return( YES );
}

//===========================================================================================================================

- (BOOL) encodeWithProtobufCoder:(ENProtobufCoder *) inCoder error:(ENErrorOutType) outError
{
	// SignatureInfo
	
    ENProtobufCoder *sigInfoProtobufCoder = [[ENProtobufCoder alloc] init];
    NSMutableData *bufferData = [[NSMutableData alloc] init];
	[sigInfoProtobufCoder setWriteMutableData:bufferData];
	BOOL good = [self _encodeInfoWithProtobufCoder:sigInfoProtobufCoder error:outError];
	require_return_value( good, NO );
	
	size_t len = bufferData.length;
	if( len > 0 )
	{
		good = [inCoder writeLengthDelimitedPtr:bufferData.bytes length:len tag:ENSignatureTagSignatureInfo error:outError];
		require_return_value( good, NO );
	}
	
	// BatchNum
	
	good = [inCoder writeVarIntUInt32:_batchNumber tag:ENSignatureTagBatchNumber error:outError];
	require_return_value( good, NO );
	
	// BatchSize
	
	good = [inCoder writeVarIntUInt32:_batchCount tag:ENSignatureTagBatchSize error:outError];
	require_return_value( good, NO );
	
	// Signature
	
	ENIfLet( x, _signatureData )
	{
		good = [inCoder writeNSData:x tag:ENSignatureTagSignatureData error:outError];
		require_return_value( good, NO );
	}
	
	return( YES );
}

//===========================================================================================================================

- (BOOL) _encodeInfoWithProtobufCoder:(ENProtobufCoder *) inCoder error:(ENErrorOutType) outError
{
	ENIfLet( x, _appleBundleID )
	{
		BOOL good = [inCoder writeNSString:x tag:ENSignatureInfoTagAppleBundleID error:outError];
		require_return_value( good, NO );
	}
	ENIfLet( x, _androidBundleID )
	{
		BOOL good = [inCoder writeNSString:x tag:ENSignatureInfoTagAndroidPackage error:outError];
		require_return_value( good, NO );
	}
	ENIfLet( x, _keyVersion )
	{
		BOOL good = [inCoder writeNSString:x tag:ENSignatureInfoTagKeyVersion error:outError];
		require_return_value( good, NO );
	}
	ENIfLet( x, _keyID )
	{
		BOOL good = [inCoder writeNSString:x tag:ENSignatureInfoTagKeyID error:outError];
		require_return_value( good, NO );
	}
	ENIfLet( x, _signatureAlgorithm )
	{
		BOOL good = [inCoder writeNSString:x tag:ENSignatureInfoTagSignatureAlgorithm error:outError];
		require_return_value( good, NO );
	}
	return( YES );
}

@end

NS_ASSUME_NONNULL_END
