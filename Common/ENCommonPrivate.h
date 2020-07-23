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

#import <CoreFoundation/CoreFoundation.h>
#import <ExposureNotification/ExposureNotification.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

//===========================================================================================================================

#define kSecondsPerMinute               ( 60 )
#define kSecondsPerDay                  ( 60 * 60 * 24 )
#define ENDurationIncrement				( 1 * kSecondsPerMinute )
#define ENDurationMaxSeconds			( 30 * kSecondsPerMinute )

//===========================================================================================================================

static inline const char * ENErrorCodeToString( ENErrorCode inValue )
{
	switch( inValue )
	{
		case ENErrorCodeUnknown:				return( "ENErrorCodeUnknown" );
		case ENErrorCodeBadParameter:			return( "ENErrorCodeBadParameter" );
		case ENErrorCodeNotEntitled:			return( "ENErrorCodeNotEntitled" );
		case ENErrorCodeNotAuthorized:			return( "ENErrorCodeNotAuthorized" );
		case ENErrorCodeUnsupported:			return( "ENErrorCodeUnsupported" );
		case ENErrorCodeInvalidated:			return( "ENErrorCodeInvalidated" );
		case ENErrorCodeBluetoothOff:			return( "ENErrorCodeBluetoothOff" );
		case ENErrorCodeInsufficientStorage:	return( "ENErrorCodeInsufficientStorage" );
		case ENErrorCodeNotEnabled:				return( "ENErrorCodeNotEnabled" );
		case ENErrorCodeAPIMisuse:				return( "ENErrorCodeAPIMisuse" );
		case ENErrorCodeInternal:				return( "ENErrorCodeInternal" );
		case ENErrorCodeInsufficientMemory:		return( "ENErrorCodeInsufficientMemory" );
		case ENErrorCodeRateLimited:			return( "ENErrorCodeRateLimited" );
		case ENErrorCodeRestricted:				return( "ENErrorCodeRestricted" );
		case ENErrorCodeBadFormat:				return( "ENErrorCodeBadFormat" );
		default:								return( "?" );
	}
}

//===========================================================================================================================
// MARK: -
// MARK: == Extensions ==

//===========================================================================================================================

@interface ENExposureInfo ()
@property (readwrite, copy, nonatomic) NSArray <NSNumber *> *		attenuationDurations;
@property (readwrite, assign, nonatomic) ENAttenuation				attenuationValue;
@property (readwrite, copy, nonatomic) NSDate *						date;
@property (readwrite, assign, nonatomic) NSTimeInterval				duration;
@property (readwrite, assign, nonatomic) ENRiskScore				totalRiskScore;
@property (readwrite, assign, nonatomic) double						totalRiskScoreFullRange;
@property (readwrite, assign, nonatomic) ENRiskLevel				transmissionRiskLevel;
@end

//===========================================================================================================================
// MARK: -
// MARK: == Utilities ==

/// Creates an NSError with NSOSStatusErrorDomain
NSError * _Nullable ENNSErrorF( OSStatus inStatus, const char *inFormat, ... );

/// Creates an NSError with ENErrorDomain.
EN_API_AVAILABLE_EXPORT
NSError * _Nullable	ENErrorF( ENErrorCode inErrorCode, const char *inFormat, ... );

EN_API_AVAILABLE_EXPORT
NSError * _Nullable	ENNestedErrorF( NSError *inUnderlyingError, ENErrorCode inErrorCode, const char *inFormat, ... );

//===========================================================================================================================
// MARK: -
// MARK: == Temporary Exposure Key (TEK) ==

/*!    @defgroup    Temporary Exposure Key (TEK)

    A Temporary Exposure Key (TEK) is generated at a fixed cadence (EKRollingPeriod) where the protocol is broadcasting.

    TEK = CRNG( 16 )
*/

#define ENTEKRollingPeriod        144 /// Rolls every 10 minutes: (24 * 60 * 60) / (10 * 60).
#define ENTEKLength                16  /// Number of bytes in a TEK.

/// Holds the raw bytes TEK.
typedef struct
{
    uint8_t        bytes[ ENTEKLength ];

}    ENTEKStruct;

//===========================================================================================================================
// MARK: -
// MARK: == Rolling Proximity Identifier (RPI) ==

/*!    @defgroup    Rolling Proximity Identifier (RPI)

    A Rolling Proximity Identifier (RPI) is a privacy-preserving identifier sent in Bluetooth Low Energy (BLE) advertisements.
    Each time the BLE advertising address changes (e.g. every 15 minutes), a new RPI is derived.

    RPI = Truncate( HMAC-SHA-256( TEK, "EN-RPI" || ENIN ), 16 )
*/

/// Info parameter to use with HMAC to generate an RPI.
#define ENRPIInfoPtr        "EN-RPI"
#define ENRPIInfoLen        ( sizeof( ENRPIInfoPtr ) - 1 )

/// Number of bytes in a Rotating Proximity Identifier Key (RPI).
#define ENRPILength            16

/// Number of bytes in Associated Encrypted Metadata (AEM). This contains the following:
///
/// <version/flags:1> <TxPower:1> <RFU:1> <RFU:1>
#define ENAEMLength            4

/// Holds the raw bytes for a Rotating Proximity Identifier Key (RPI).
typedef struct
{
    uint8_t        bytes[ ENRPILength ];

}    ENRPIStruct;

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
