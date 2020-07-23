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

@class ENTemporaryExposureKey;

//===========================================================================================================================
// MARK: -
// MARK: == Extensions ==

//===========================================================================================================================

@interface ENExposureConfiguration ()
- (double) attenuationLevelValueWithAttenuation:(ENAttenuation) inAttenuation;
- (double) daysSinceLastExposureLevelValueWithDays:(NSInteger) inDays;
- (double) durationLevelValueWithDuration:(NSTimeInterval) inDuration;
- (double) transmissionLevelValueWithTransmissionRiskLevel:(ENRiskLevel) inRiskLevel;
@end

//===========================================================================================================================

@interface ENExposureDetectionSummary ()
@property (readwrite, copy, nonatomic) NSArray <NSNumber *> *		attenuationDurations;
@property (readwrite, assign, nonatomic) NSInteger					daysSinceLastExposure;
@property (readwrite, assign, nonatomic) uint64_t					matchedKeyCount;
@property (readwrite, assign, nonatomic) ENRiskScore				maximumRiskScore;
@property (readwrite, assign, nonatomic) double						maximumRiskScoreFullRange;
@property (readwrite, assign, nonatomic) double						riskScoreSumFullRange;
@end

//===========================================================================================================================

@interface ENExposureInfo ()
@property (readwrite, copy, nullable, nonatomic) NSDictionary *		metadata;
@end

NS_ASSUME_NONNULL_END
