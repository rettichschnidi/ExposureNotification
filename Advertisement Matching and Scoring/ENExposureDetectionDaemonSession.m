/*
 *      Copyright (C) 2020 Apple Inc. All Rights Reserved.
 *
 *      ExposureNotification is licensed under Apple Inc.’s
 *      Sample Code License Agreement, which is contained in
 *      the LICENSE file distributed with ExposureNotification,
 *      and only to those who accept that license.
 *
 */

#import "ENExposureDetectionDaemonSession.h"
#import "ENCommonPrivate.h"
#import "ENInternal.h"
#import "ENShims.h"

#define TEKBatchSize (256)

@implementation ENExposureDetectionDaemonSession {
    ENAdvertisementDatabase *_database;
    ENAdvertisementDatabaseQuerySession *_databaseQuerySession;
    ENExposureConfiguration * _configuration;
    NSUInteger _matchedKeyCount;
}

- (instancetype)init
{
    return [self initWithDatabase:nil configuration:nil];
}

- (instancetype)initWithDatabase:(ENAdvertisementDatabase *)database configuration:(ENExposureConfiguration *)configuration
{
    if (self = [super init]) {
        _database = database;
        _databaseQuerySession = [_database createQuerySessionWithAttenuationThreshold:0xFF];
        _databaseQuerySession.cacheExposureInfo = YES;

        _configuration = configuration;
        _databaseQuerySession.configuration = _configuration;
        _databaseQuerySession.attenuationDurationThresholds = _configuration.attenuationDurationThresholds;

        _matchedKeyCount = 0;
    }
    return self;
}

- (BOOL)addFile:(ENFile *)mainFile
{
    __block NSError *error = nil;

    uint64_t fileMatchCount = 0;
    for( ;; )
    {
        @autoreleasepool
        {
            NSMutableArray<ENTemporaryExposureKey *> *tekArray = [[NSMutableArray <ENTemporaryExposureKey *> alloc] init];
            check_compile_time_code( TEKBatchSize > 0 );
            uint32_t tekCount = 0;

            // Match the TEKs in batches to reduce the peak memory usage

            for( ; tekCount < TEKBatchSize; ++tekCount )
            {
                ENTemporaryExposureKey *key = [mainFile readTEKAndReturnError:&error];
                if( !key ) break;
                [tekArray addObject:key];
            }
            if( tekCount == 0 ) break;

            fileMatchCount += [_databaseQuerySession matchCountForKeys:tekArray attenuationThreshold:0xFF error:&error];
            if( error ) break;
        }
    }

    _matchedKeyCount += fileMatchCount;

    if( error )
    {
        return NO;
    }
    return YES;
}

- (ENExposureDetectionSummary *)generateSummary
{
    // Process all the cached info to create the summary.

    __block uint32_t attenuationDurationSums[ 3 ] = { 0, 0, 0 };
    __block uint32_t *attenuationDurationSumsPtr = attenuationDurationSums;
    __block uint64_t minimumRiskScoreSkipped = 0;
    ENRiskScore minimumRiskScore = _configuration.minimumRiskScore;
    double minimumRiskScoreFullRange = _configuration.minimumRiskScoreFullRange;
    __block ENRiskScore maximumRiskScore = 0;
    __block double maximumRiskScoreFullRange = 0;
    __block CFAbsoluteTime mostRecentExposureTime = 0;
    __block double riskScoreSumFullRange = 0;

    CFAbsoluteTime nowTime = CFAbsoluteTimeGetCurrent();
    [_databaseQuerySession enumerateCachedExposureInfo:
    ^( NSArray <ENExposureInfo *> * _Nullable inExposureInfoBatch, NSError * _Nullable __unused inError )
    {
        for( ENExposureInfo *exposureInfo in inExposureInfoBatch )
        {

            // Determine if this exposure is the most recent exposure
            NSTimeInterval exposureTime = exposureInfo.date.timeIntervalSinceReferenceDate;
            if( exposureTime > mostRecentExposureTime ) mostRecentExposureTime = exposureTime;

            // Filter out any exposures with a risk score below the configured minimum
            double riskScoreFullRange = [self estimateRiskWithExposureInfo:exposureInfo referenceTime:nowTime
                transmissionRiskLevel:nil];
            ENRiskScore clampedRiskScore = (ENRiskScore) Clamp( riskScoreFullRange, ENRiskScoreMin, ENRiskScoreMax );
            if( ( clampedRiskScore < minimumRiskScore ) || ( riskScoreFullRange < minimumRiskScoreFullRange ) )
            {
                ++minimumRiskScoreSkipped;
                continue;
            }

            // Update the maximum seen risk score
            if( clampedRiskScore > maximumRiskScore ) maximumRiskScore = clampedRiskScore;
            if( riskScoreFullRange > maximumRiskScoreFullRange ) maximumRiskScoreFullRange = riskScoreFullRange;
            riskScoreSumFullRange += riskScoreFullRange;

            // Accumulate the calculated attenuation durations
            NSArray <NSNumber *> *attenuationDurations = exposureInfo.attenuationDurations;
            if( attenuationDurations.count >= countof( attenuationDurationSums ) )
            {
                for( size_t i = 0; i < countof( attenuationDurationSums ); ++i )
                {
                    uint32_t durationSum = attenuationDurationSumsPtr[ i ];
                    if( durationSum >= ENDurationMaxSeconds ) continue;
                    durationSum += attenuationDurations[ i ].unsignedIntValue;
                    if( durationSum > ENDurationMaxSeconds ) durationSum = ENDurationMaxSeconds;
                    attenuationDurationSumsPtr[ i ] = durationSum;
                }
            }
        }
    }];

    // Round the attenuation durations
    NSInteger daysSinceLastExposure = ( mostRecentExposureTime > 0 )
        ? ( (NSInteger)( ( nowTime - mostRecentExposureTime ) / kSecondsPerDay ) )
        : 0;
    attenuationDurationSums[ 0 ] = RoundUp( attenuationDurationSums[ 0 ], ENDurationIncrement );
    attenuationDurationSums[ 1 ] = RoundUp( attenuationDurationSums[ 1 ], ENDurationIncrement );
    attenuationDurationSums[ 2 ] = RoundUp( attenuationDurationSums[ 2 ], ENDurationIncrement );

    // Generate the summary
    ENExposureDetectionSummary *summary = [[ENExposureDetectionSummary alloc] init];
    summary.attenuationDurations =
    @[
        @(attenuationDurationSums[ 0 ]),
        @(attenuationDurationSums[ 1 ]),
        @(attenuationDurationSums[ 2 ])
    ];
    summary.daysSinceLastExposure = daysSinceLastExposure;
    summary.matchedKeyCount = _matchedKeyCount;
    summary.maximumRiskScore = maximumRiskScore;
    summary.maximumRiskScoreFullRange = maximumRiskScoreFullRange;
    summary.riskScoreSumFullRange = riskScoreSumFullRange;

    return summary;
}

- (NSArray<ENExposureInfo *> *)exposureInfo
{
    // Get the ENExposureInfo objects from the database.

    __block NSInteger databaseTotal = 0;
    __block ENRiskScore minimumRiskScore = _configuration.minimumRiskScore;
    double minimumRiskScoreFullRange = _configuration.minimumRiskScoreFullRange;
    __block uint64_t minimumRiskScoreSkipped = 0;

    CFAbsoluteTime nowTime = CFAbsoluteTimeGetCurrent();
    NSMutableArray <ENExposureInfo *> *exposureInfoArray = [[NSMutableArray <ENExposureInfo *> alloc] init];

    [_databaseQuerySession enumerateCachedExposureInfo:
    ^( NSArray <ENExposureInfo *> * _Nullable inExposureInfoBatch, NSError * _Nullable __unused inError )
    {
        databaseTotal += inExposureInfoBatch.count;
        for( ENExposureInfo *exposureInfo in inExposureInfoBatch )
        {
            // Filter out any exposures with a risk score below the configured minimum
            ENRiskLevel transmissionRiskLevel = 0;
            double riskScoreFullRange = [self estimateRiskWithExposureInfo:exposureInfo referenceTime:nowTime
                transmissionRiskLevel:&transmissionRiskLevel];
            ENRiskScore clampedRiskScore = (ENRiskScore) Clamp( riskScoreFullRange, ENRiskScoreMin, ENRiskScoreMax );
            if( ( clampedRiskScore < minimumRiskScore ) || ( riskScoreFullRange < minimumRiskScoreFullRange ) )
            {
                ++minimumRiskScoreSkipped;
                continue;
            }

            // Round the attenuation durations
            uint32_t duration = (uint32_t) exposureInfo.duration;
            duration = RoundUp( duration, ENDurationIncrement );
            exposureInfo.duration = Min( duration, ENDurationMaxSeconds );

            NSMutableArray <NSNumber *> *filteredAttenuationDurations = [[NSMutableArray <NSNumber *> alloc] init];
            for( NSNumber *attenuationDuration in exposureInfo.attenuationDurations )
            {
                duration = attenuationDuration.unsignedIntValue;
                duration = RoundUp( duration, ENDurationIncrement );
                duration = Min( duration, ENDurationMaxSeconds );
                [filteredAttenuationDurations addObject:@(duration)];
            }

            // Populate the final ENExposureInfo
            exposureInfo.attenuationDurations = filteredAttenuationDurations;
            exposureInfo.totalRiskScore = clampedRiskScore;
            exposureInfo.totalRiskScoreFullRange = riskScoreFullRange;
            exposureInfo.transmissionRiskLevel = transmissionRiskLevel;

            [exposureInfoArray addObject:exposureInfo];
        }
    }];

    return exposureInfoArray;
}

/*
 *  Calculate the risk score as outlined on the Apple Developer site:
 *  https://developer.apple.com/documentation/exposurenotification/enexposureconfiguration
 */
- (double)estimateRiskWithExposureInfo:(ENExposureInfo *)inInfo
                         referenceTime:(CFAbsoluteTime)inReferenceTime
                 transmissionRiskLevel:(ENRiskLevel * _Nullable)outTransmissionRiskLevel
{
    double attenuationLevelValue = [_configuration attenuationLevelValueWithAttenuation:inInfo.attenuationValue];
    NSInteger days = 0;
    NSDate *date = inInfo.date;
    if( date )
    {
        double seconds = inReferenceTime - date.timeIntervalSinceReferenceDate;
        seconds = Clamp( seconds, 0, NSIntegerMax );
        days = (NSInteger)( seconds / kSecondsPerDay );
    }
    double daysLevelValue = [_configuration daysSinceLastExposureLevelValueWithDays:days];
    double durationLevelValue = [_configuration durationLevelValueWithDuration:inInfo.duration];
    double transmissionLevelValue = [_configuration transmissionLevelValueWithTransmissionRiskLevel:inInfo.transmissionRiskLevel];
    if( outTransmissionRiskLevel ) *outTransmissionRiskLevel = inInfo.transmissionRiskLevel;
    double totalScore = attenuationLevelValue * daysLevelValue * durationLevelValue * transmissionLevelValue;
    return( totalScore );
}

@end
