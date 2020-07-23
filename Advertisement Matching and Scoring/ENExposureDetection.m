/*
 *      Copyright (C) 2020 Apple Inc. All Rights Reserved.
 *
 *      ExposureNotification is licensed under Apple Inc.’s
 *      Sample Code License Agreement, which is contained in
 *      the LICENSE file distributed with ExposureNotification,
 *      and only to those who accept that license.
 *
 */

#import <CoreFoundation/CoreFoundation.h>
#import <ExposureNotification/ExposureNotification.h>
#import <Foundation/Foundation.h>
#import <math.h>

#import "ENCommonPrivate.h"
#import "ENInternal.h"
#import "ENShims.h"

NS_ASSUME_NONNULL_BEGIN

// MARK: -

//===========================================================================================================================

@implementation ENExposureConfiguration
{
	ENRiskLevelValue		_attenuationLevelValuesMap[ 8 ];
	ENRiskLevelValue		_daysSinceLastExposureLevelValuesMap[ 8 ];
	ENRiskLevelValue		_durationLevelValuesMap[ 8 ];
	ENRiskLevelValue		_transmissionRiskLevelValuesMap[ 8 ];
}

//===========================================================================================================================

- (instancetype _Nullable) init
{
	self = [super init];
	if( !self ) return( nil );
	
	ENRiskLevelValue defaultLevelValues[] = { 1, 2, 3, 4, 5, 6, 7, 8 };
	
	check_compile_time_code( sizeof( _attenuationLevelValuesMap ) == sizeof( defaultLevelValues ) );
	memcpy( _attenuationLevelValuesMap, defaultLevelValues, sizeof( defaultLevelValues ) );
	
	check_compile_time_code( sizeof( _daysSinceLastExposureLevelValuesMap ) == sizeof( defaultLevelValues ) );
	memcpy( _daysSinceLastExposureLevelValuesMap, defaultLevelValues, sizeof( defaultLevelValues ) );
	
	check_compile_time_code( sizeof( _durationLevelValuesMap ) == sizeof( defaultLevelValues ) );
	memcpy( _durationLevelValuesMap, defaultLevelValues, sizeof( defaultLevelValues ) );
	
	check_compile_time_code( sizeof( _transmissionRiskLevelValuesMap ) == sizeof( defaultLevelValues ) );
	memcpy( _transmissionRiskLevelValuesMap, defaultLevelValues, sizeof( defaultLevelValues ) );
	
	_attenuationDurationThresholds		= @[ @50, @70 ];
	_attenuationLevelValues				= @[ @1, @2, @3, @4, @5, @6, @7, @8 ];
	_attenuationWeight					= ENRiskWeightDefault;
	
	_daysSinceLastExposureLevelValues	= @[ @1, @2, @3, @4, @5, @6, @7, @8 ];
	_daysSinceLastExposureWeight		= ENRiskWeightDefault;
	
	_durationLevelValues				= @[ @1, @2, @3, @4, @5, @6, @7, @8 ];
	_durationWeight						= ENRiskWeightDefault;
	
	_transmissionRiskLevelValues		= @[ @1, @2, @3, @4, @5, @6, @7, @8 ];
	_transmissionRiskWeight				= ENRiskWeightDefault;
	
	return( self );
}

//===========================================================================================================================

- (double) attenuationLevelValueWithAttenuation:(ENAttenuation) inAttenuation
{
	return( inAttenuation * _attenuationWeight );
}

//===========================================================================================================================

- (double) daysSinceLastExposureLevelValueWithDays:(NSInteger) inDays
{
	double levelValue;
	if(      inDays >= 14 )	levelValue = _daysSinceLastExposureLevelValuesMap[ 0 ];
	else if( inDays >= 12 )	levelValue = _daysSinceLastExposureLevelValuesMap[ 1 ];
	else if( inDays >= 10 )	levelValue = _daysSinceLastExposureLevelValuesMap[ 2 ];
	else if( inDays >= 8 )	levelValue = _daysSinceLastExposureLevelValuesMap[ 3 ];
	else if( inDays >= 6 )	levelValue = _daysSinceLastExposureLevelValuesMap[ 4 ];
	else if( inDays >= 4 )	levelValue = _daysSinceLastExposureLevelValuesMap[ 5 ];
	else if( inDays >= 2 )	levelValue = _daysSinceLastExposureLevelValuesMap[ 6 ];
	else					levelValue = _daysSinceLastExposureLevelValuesMap[ 7 ];
	return( levelValue * _daysSinceLastExposureWeight );
}

//===========================================================================================================================

- (double) durationLevelValueWithDuration:(NSTimeInterval) inDuration
{
	double   levelValue;
	double   minutes = inDuration / kSecondsPerMinute;
	if(      minutes <= 0 )		levelValue = _durationLevelValuesMap[ 0 ];
	else if( minutes <= 5 )		levelValue = _durationLevelValuesMap[ 1 ];
	else if( minutes <= 10 )	levelValue = _durationLevelValuesMap[ 2 ];
	else if( minutes <= 15 )	levelValue = _durationLevelValuesMap[ 3 ];
	else if( minutes <= 20 )	levelValue = _durationLevelValuesMap[ 4 ];
	else if( minutes <= 25 )	levelValue = _durationLevelValuesMap[ 5 ];
	else if( minutes <= 30 )	levelValue = _durationLevelValuesMap[ 6 ];
	else						levelValue = _durationLevelValuesMap[ 7 ];
	return( levelValue * _durationWeight );
}

//===========================================================================================================================

- (double) transmissionLevelValueWithTransmissionRiskLevel:(ENRiskLevel) inRiskLevel
{
	check_compile_time_code( ( ENRiskLevelMin >= 0 ) && ( ENRiskLevelMax < countof( _transmissionRiskLevelValuesMap ) ) );
	double levelValue = _transmissionRiskLevelValuesMap[ Clamp( inRiskLevel, ENRiskLevelMin, ENRiskLevelMax ) ];
	return( levelValue * _transmissionRiskWeight );
}

@end

NS_ASSUME_NONNULL_END
