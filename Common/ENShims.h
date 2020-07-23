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

// Compilation Verification

#define check_compile_time( X )         static_assert( X, "Compile-time assert failed" )
#define check_compile_time_code( X )    do { switch( 0 ) { case 0: case X:; } } while( 0 )

// Math

#define Max( X, Y )                     ( ( (X) > (Y) ) ? (X) : (Y) )
#define Min( X, Y )                     ( ( (X) < (Y) ) ? (X) : (Y) )
#define Clamp( x, a, b )                Max( (a), Min( (b), (x) ) )
#define RoundUp( VALUE, MULTIPLE )      ( ( ( (VALUE) + ( (MULTIPLE) - 1 ) ) / (MULTIPLE) ) * (MULTIPLE) )

// Sizing

#define countof( X )        ( sizeof( X ) / sizeof( X[ 0 ] ) )
#define sizeof_string( X )  ( sizeof( (X) ) - 1 )

// Error Handling

#define kUnknownErr             -6700    //! Unknown error occurred.
#define kRangeErr               -6710    //! Index is out of range or not valid.
#define kUnsupportedDataErr     -6732    //! Data is unknown or not supported.
#define kSizeErr                -6743    //! Size was too big, too small, or not appropriate.
#define kNotPreparedErr         -6745    //! Device or service is not ready.
#define kReadErr                -6746    //! Could not read.
#define kWriteErr               -6747    //! Could not write.
#define kUnderrunErr            -6750    //! Less data than expected.
#define kOverrunErr             -6751    //! More data than expected.
#define kEndOfDataErr           -6765    //! Reached the end of the data (e.g. recv returned 0).


#define global_value_errno( VALUE )             ( errno ? errno : kUnknownErr )
#define map_global_noerr_errno( ERR )           ( !(ERR) ? 0 : global_value_errno(ERR) )
#define map_global_value_errno( TEST, VALUE )   ( (TEST) ? 0 : global_value_errno(VALUE) )
#define map_noerr_errno( ERR )                  map_global_noerr_errno( (ERR) )

typedef int BTResult;

#define BT_SUCCESS                      (0)
#define BT_ERROR                        (1)
#define BT_ERROR_INVALID_ARGUMENT       (3)
#define BT_ERROR_CRYPTO_HKDF_FAILED     (1260)
#define BT_ERROR_CRYPTO_AES_FAILED      (1261)

// File Management

#define IsValidFD( X )                          ( (X) >= 0 )
#define map_fd_creation_errno( FD )             ( IsValidFD( FD ) ? 0 : global_value_errno( FD ) )
#define ForgetANSIFile( X ) \
    do \
    { \
        if( *(X) ) \
        { \
            OSStatus        ForgetANSIFileErr; \
            \
            ForgetANSIFileErr = fclose( *(X) ); \
            ForgetANSIFileErr = map_noerr_errno( ForgetANSIFileErr ); \
            *(X) = NULL; \
        } \
         \
    }    while( 0 )

// Early Returns

#define require_return_nil( X, OUT_ERROR, MAKE_ERROR )    require_return_with_error( (X), nil, (OUT_ERROR), (MAKE_ERROR) )
#define require_return_no( X, OUT_ERROR, MAKE_ERROR )    require_return_with_error( (X), NO, (OUT_ERROR), (MAKE_ERROR) )
#define unlikely( EXPRESSSION )        __builtin_expect( !!(EXPRESSSION), 0 )

#define require_return_value( TEST, VALUE ) \
    do \
    { \
        if( unlikely( !(TEST) ) ) \
        { \
            return( (VALUE) ); \
        } \
    \
    }    while( 0 )

#define require_return_with_error( X, RETURN_VALUE, OUT_ERROR, MAKE_ERROR ) \
    do \
    { \
        if( unlikely( !(X) ) ) \
        { \
            const __auto_type outError_ = (OUT_ERROR); \
            if( outError_ ) *outError_ = (MAKE_ERROR); \
            return( (RETURN_VALUE) ); \
        } \
    \
    }    while( 0 )

// Swift Patterns

typedef void ( ^ENDeferBlock )( void );
static inline void _ENDeferCallback( ENDeferBlock *inBlock ) { ( *inBlock )(); }
#define _ENDeferMerge( a, b )   a##b
#define _ENDeferNamed( a )      _ENDeferMerge( __ENDeferVar_, a )
#define ENDefer                 __extension__ __attribute__( ( cleanup( _ENDeferCallback ), unused ) ) ENDeferBlock _ENDeferNamed( __COUNTER__ ) = ^

#define ENIfLet( CONSTANT, VALUE ) \
    for( bool CFIfLet_run_ = true; CFIfLet_run_; CFIfLet_run_ = false ) \
        for( const __auto_type CONSTANT = (VALUE); CONSTANT && CFIfLet_run_; CFIfLet_run_ = false )

// Alignment Macros

#define ENAlignedCast( PTR )        ( (void *)(PTR) )
#define WriteLittle32( PTR, X )     do { *( (uint32_t *) ENAlignedCast( PTR ) ) = (uint32_t)(X); } while( 0 )
#define WriteLittle64( PTR, X )     do { *( (uint64_t *) ENAlignedCast( PTR ) ) = (uint64_t)(X); } while( 0 )
#define ReadLittle32( PTR )         ( *( (uint32_t *) ENAlignedCast( PTR ) ) )
#define ReadLittle64( PTR )         ( *( (uint64_t *) ENAlignedCast( PTR ) ) )

// Logging Macros

#include <os/log.h>

#define YesNoStr( X )                   ( (X) ? "yes" : "no" )
#define EN_DEBUG_PRINTF(...)            os_log_debug(OS_LOG_DEFAULT, __VA_ARGS__);
#define EN_INFO_PRINTF(...)             os_log_info(OS_LOG_DEFAULT, __VA_ARGS__);
#define EN_NOTICE_PRINTF(...)           os_log(OS_LOG_DEFAULT, __VA_ARGS__);
#define EN_ERROR_PRINTF(...)            os_log_error(OS_LOG_DEFAULT, __VA_ARGS__);
#define EN_CRITICAL_PRINTF(...)         os_log_fault(OS_LOG_DEFAULT, __VA_ARGS__);
