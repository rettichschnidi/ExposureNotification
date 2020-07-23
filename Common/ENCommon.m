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
#import <Foundation/Foundation.h>

#import "ENInternal.h"
#import "ENShims.h"
#import "ENCommonPrivate.h"

NS_ASSUME_NONNULL_BEGIN

// MARK: == Constants ==

//===========================================================================================================================

NSString * const		ENErrorDomain = @"ENErrorDomain";

// MARK: -
// MARK: == Utilities ==

//===========================================================================================================================

NSString * NSPrintV( const char *inFormat, va_list inArgs )
{
    NSString *formatString = [[NSString alloc] initWithUTF8String:inFormat];
    NSString *str = [[NSString alloc] initWithFormat:formatString arguments:inArgs];
    return str;
}

//===========================================================================================================================

NSString * NSPrintF( const char *inFormat, ... )
{
    NSString *result;
    va_list args;

    va_start( args, inFormat );
    result = NSPrintV( inFormat, args );
    va_end( args );
    return( result );
}

//===========================================================================================================================

NSError * _Nullable ENNSErrorV( OSStatus inStatus, const char *inFormat, va_list inArgs )
{
    if( !inStatus ) return( nil );
    NSString *extraStr = NSPrintV(inFormat, inArgs);
    NSString *desc = NSPrintF("%d (%@)", (int) inStatus, extraStr);
    NSError *error = [[NSError alloc] initWithDomain:NSOSStatusErrorDomain code:inStatus userInfo:@{
        NSLocalizedDescriptionKey        : desc,
    }];
    return( error );
}

//===========================================================================================================================

NSError * _Nullable ENNSErrorF( OSStatus inStatus, const char *inFormat, ... )
{
    if( !inStatus ) return( nil );
    va_list args;
    va_start( args, inFormat );
    NSError *error = ENNSErrorV( inStatus, inFormat, args );
    va_end( args );
    return( error );
}

//===========================================================================================================================

NSError * _Nullable	ENErrorF( ENErrorCode inErrorCode, const char *inFormat, ... )
{
    va_list args;
    va_start( args, inFormat );
    const char *codeStr = ENErrorCodeToString( inErrorCode );
	NSString *extraStr = NSPrintV( inFormat, args );
	NSString *desc = NSPrintF( "%s (%@)", codeStr, extraStr );
    NSError *error = [[NSError alloc] initWithDomain:ENErrorDomain code:inErrorCode userInfo:@{
		NSLocalizedDescriptionKey	: desc, 
	}];
	va_end( args );
	return( error );
}

//===========================================================================================================================

NSError * _Nullable	ENNestedErrorF( NSError *inUnderlyingError, ENErrorCode inErrorCode, const char *inFormat, ... )
{
	va_list args;
	va_start( args, inFormat );
    const char *codeStr = ENErrorCodeToString( inErrorCode );
    NSString *extraStr = NSPrintV( inFormat, args );
	NSString *desc = NSPrintF( "%s (%@)", codeStr, extraStr );
    NSError *error = [[NSError alloc] initWithDomain:ENErrorDomain code:inErrorCode userInfo:@{
		NSLocalizedDescriptionKey	: desc, 
		NSUnderlyingErrorKey		: inUnderlyingError ?: ENNSErrorF( kUnknownErr, "Unknown" ),
	}];
	va_end( args );
	return( error );
}

NS_ASSUME_NONNULL_END
