/*
 *      Copyright (C) 2020 Apple Inc. All Rights Reserved.
 *
 *      ExposureNotification is licensed under Apple Inc.’s
 *      Sample Code License Agreement, which is contained in
 *      the LICENSE file distributed with ExposureNotification,
 *      and only to those who accept that license.
 *
 */

#import "ENAdvertisementDatabaseQuerySession_Private.h"
#import "ENAdvertisement_Private.h"
#import "ENCryptography.h"
#import "ENShims.h"

#define DEFAULT_EXPOSURE_INFO_BUFFER_SIZE  (915000) // estimated pathological case user
#define DEFAULT_FILTER_BUFFER_SIZE  ((1024 + 512 + 64) * 1024)
#define DEFAULT_FILTER_HASH_COUNT   (3)

#define DEFAULT_EXPOSURE_INFO_BATCH_SIZE (1024)

#define ATTENUATION_DURATION_THRESHOLD_COUNT_MIN (2)
#define ATTENUATION_DURATION_BUCKET_COUNT (4)
#define ATTENUATION_VALUE_BUCKET_COUNT (8)

#define ADVERTISEMENT_MERGE_INTERVAL (4.0) // merge advertisements less than 4 seconds apart

#define EXPOSURE_DURATION_MAX UINT16_MAX

#define VALID_TX_POWER_MIN (-60)
#define VALID_TX_POWER_MAX (20)

#define VALID_ATTENUATION_MIN (1)
#define VALID_ATTENUATION_MAX (UINT8_MAX)

#define DEFAULT_ALLOWABLE_RPI_BROADCAST_DURATION (20 * 60.0f)

typedef char rpi_t[ENRPILength];
typedef char daily_tracing_key_t[ENTEKLength];

typedef struct __attribute__((packed)) {
    CFAbsoluteTime timestamp;
    uint16_t attenuation_durations[ATTENUATION_DURATION_BUCKET_COUNT];
    uint16_t total_duration;
    uint8_t attenuation;
    ENRiskLevel transmission_risk;
} en_exposure_info_t;

ENExposureInfo *exposureInfoFromStructRepresentation(en_exposure_info_t structRepresentation)
{
    ENExposureInfo *exposureInfo = [[ENExposureInfo alloc] init];
    [exposureInfo setDate:[NSDate dateWithTimeIntervalSince1970:structRepresentation.timestamp]];
    [exposureInfo setTransmissionRiskLevel:structRepresentation.transmission_risk];
    [exposureInfo setAttenuationValue:structRepresentation.attenuation];
    [exposureInfo setDuration:structRepresentation.total_duration];

    // sum all durations together for total duration
    NSMutableArray<NSNumber *> *attenuationDurations = [[NSMutableArray alloc] init];
    for (int i = 0; i < ATTENUATION_DURATION_BUCKET_COUNT; i++) {
        [attenuationDurations addObject:@(structRepresentation.attenuation_durations[i])];
    }
    [exposureInfo setAttenuationDurations:attenuationDurations];

    return exposureInfo;
}

void structRepresentationOfExposureInfo(ENExposureInfo *exposureInfo, en_exposure_info_t *structRepresentation)
{
    structRepresentation->timestamp = [[exposureInfo date] timeIntervalSince1970];
    structRepresentation->attenuation = [exposureInfo attenuationValue];
    structRepresentation->transmission_risk = [exposureInfo transmissionRiskLevel];
    structRepresentation->total_duration = [exposureInfo duration];
    for (int i = 0; i < ATTENUATION_DURATION_BUCKET_COUNT; i++) {
        structRepresentation->attenuation_durations[i] = [[[exposureInfo attenuationDurations] objectAtIndex:i] unsignedIntValue];
    }
}

static NSArray<ENAdvertisement *> *timeOrderedAdvertisements(NSArray<ENAdvertisement *> *advertisements)
{
    return [advertisements sortedArrayUsingComparator:^NSComparisonResult(ENAdvertisement *a1, ENAdvertisement *a2) {
        if ([a1 timestamp] < [a2 timestamp]) {
            return NSOrderedAscending;
        } else if ([a1 timestamp] > [a2 timestamp]) {
            return NSOrderedDescending;
        }
        return NSOrderedSame;
    }];
}

static NSArray<ENAdvertisement *> *temporalyCombineAdvertisements(NSArray<ENAdvertisement *> *advertisements)
{
    // first ensure the advertisements are in order
    NSArray<ENAdvertisement *> *sortedAdvertisements = timeOrderedAdvertisements(advertisements);

    // combine advertisements within 4s of each other
    NSMutableArray<ENAdvertisement *> *combinedAdvertisements = [[NSMutableArray alloc] init];
    ENAdvertisement *previousAdvertisement = nil;
    for (ENAdvertisement *advertisement in sortedAdvertisements) {

        BOOL insert = NO;
        if (!previousAdvertisement) {
            // always insert the first advertisement
            insert = YES;

        } else if ([advertisement timestamp] - [previousAdvertisement timestamp] <= ADVERTISEMENT_MERGE_INTERVAL) {
            // if the advertisements are within ADVERTISEMENT_MERGE_INTERVAL, combine instead of inserting
            [previousAdvertisement combineWithAdvertisement:advertisement];

        } else {
            // the advertisements are more than ADVERTISEMENT_MERGE_INTERVAL seconds apart
            insert = YES;
        }

        if (insert) {
            [combinedAdvertisements addObject:advertisement];
            previousAdvertisement = advertisement;
        }
    }

    // ensure there is no overlap in the scan intervals
    for (NSUInteger i = 0; i < ([combinedAdvertisements count] - 1); i++) {
        ENAdvertisement *currentAdvertisement = [combinedAdvertisements objectAtIndex:i];
        ENAdvertisement *nextAdvertisement = [combinedAdvertisements objectAtIndex:(i + 1)];

        if ([currentAdvertisement timestamp] > ([nextAdvertisement timestamp] - [nextAdvertisement scanInterval])) {
            uint16_t truncatedScanInterval = (uint16_t)([nextAdvertisement timestamp] - [currentAdvertisement timestamp]);
            [nextAdvertisement setScanInterval:truncatedScanInterval];
        }
    }

    return combinedAdvertisements;
}

@implementation ENAdvertisementDatabaseQuerySession {
    ENAdvertisementDatabase *_database;
    NSUInteger _filterBufferSize;
    NSUInteger _filterHashCount;

    en_exposure_info_t *_exposureInfoBuffer;
    uint32_t _exposureInfoBufferSize;

    // debug stats counters
    uint32_t _tekCount;
}

- (instancetype)initWithDatabase:(ENAdvertisementDatabase *)database attenuationThreshold:(uint8_t)attenuationThreshold
{
    if (self = [super init]) {
        _database = database;

        _exposureInfoBufferSize = DEFAULT_EXPOSURE_INFO_BUFFER_SIZE;
        NSNumber *rowCount = [database storedAdvertisementCount];
        if (rowCount && [rowCount unsignedIntValue] < _exposureInfoBufferSize) {
            _exposureInfoBufferSize = [rowCount unsignedIntValue];
        }

        _exposureInfoBuffer = (en_exposure_info_t *) calloc(_exposureInfoBufferSize, sizeof(en_exposure_info_t));
        if (!_exposureInfoBuffer) {
            EN_ERROR_PRINTF("Failed to allocate exposure info buffer");
            return nil;
        }

        _cachedExposureInfoCount = 0;
        _tekCount = 0;

        [_database setInlineQueryFilter:[_database queryFilterWithBufferSize:DEFAULT_FILTER_BUFFER_SIZE
                                                                   hashCount:DEFAULT_FILTER_HASH_COUNT
                                                        attenuationThreshold:attenuationThreshold]];
    }
    return self;
}

- (void)dealloc
{
    EN_NOTICE_PRINTF("query session complete. tekCount:%d exposureInfoCount:%d",
                     _tekCount, (int) _cachedExposureInfoCount);

    [_database setInlineQueryFilter:nil];
    free(_exposureInfoBuffer);
}

- (uint8_t)weightedAttenuationValueForDurations:(uint32_t *)attenuationDurations
{
    // ensure we have levelValues
    NSArray<NSNumber *> *levelValues = [_configuration attenuationLevelValues];
    if ([levelValues count] != ATTENUATION_VALUE_BUCKET_COUNT) {
        EN_ERROR_PRINTF("incorrect attenuation level values, using all 1.0 count: %d", (int) [levelValues count]);
        NSMutableArray *defaultLevelValues = [[NSMutableArray alloc] init];
        for (int i = 0; i < ATTENUATION_VALUE_BUCKET_COUNT; i++) {
            [defaultLevelValues addObject:@(1.0)];
        }
        levelValues = defaultLevelValues;
    }

    // compute the weighted attenuation value
    uint32_t totalDuration = 0;
    double weightedAttenuationValue = 0.0f;
    for (int i = 0; i < ATTENUATION_VALUE_BUCKET_COUNT; i++) {
        uint32_t bucketDuration = attenuationDurations[i];
        double bucketValue = bucketDuration * [[levelValues objectAtIndex:i] doubleValue];
        if (bucketValue) {
            totalDuration += bucketDuration;
            weightedAttenuationValue += bucketValue;
        }
    }

    if (totalDuration) {
        weightedAttenuationValue = round(weightedAttenuationValue / totalDuration);
    }

    return MIN(UINT8_MAX, weightedAttenuationValue);
}

- (NSArray<ENAdvertisement *> *)filterAdvertisements:(NSArray<ENAdvertisement *> *)advertisements fromKey:(ENTemporaryExposureKey *)key
{
    NSMutableArray<ENAdvertisement *> *validAttenuationAdvertisements = [[NSMutableArray alloc] init];

    // 1. Filter out any advertisements that have attenuation or transmission power that looks suspicious.

    for (ENAdvertisement *advertisement in advertisements) {

        // Any advertisement with a transmission power outside of what is used on iOS and Android devices will be dropped.

        int8_t txPower = 0;
        BTResult result = ENRetrieveTxPowerFromEncryptedAEM((uint8_t *)[[advertisement encryptedAEM] bytes], ENAEMLength,
                                                            (uint8_t *)[[key keyData] bytes], ENTEKLength,
                                                            (uint8_t *)[[advertisement rpi] bytes], ENRPILength, &txPower);
        if (result != BT_SUCCESS) {
            continue;
        }

        if (txPower < VALID_TX_POWER_MIN || txPower > VALID_TX_POWER_MAX) {
            EN_NOTICE_PRINTF("dropping advertisement due to invalid txPower: %d", txPower);
            continue;
        }

        // Any advertisement with 0 attenuation is filtered out as that would mean the rx power was equal to the
        // tx power (zero signal loss). A zero signal loss reading would only be possible if the tx power of within
        // the AEM is not the tx power actually used.

        uint8_t advertisementAttenuation = ENCalculateAttnForDiscoveredRPI((uint8_t *)[[key keyData] bytes], ENTEKLength,
                                                                           (uint8_t *)[[advertisement rpi] bytes], ENRPILength,
                                                                           (uint8_t *)[[advertisement encryptedAEM] bytes], [[advertisement encryptedAEM] length],
                                                                           [advertisement rssi], [advertisement saturated]);

        if (advertisementAttenuation < VALID_ATTENUATION_MIN || advertisementAttenuation > VALID_ATTENUATION_MAX) {
            EN_NOTICE_PRINTF("dropping advertisement due to invalid attenuation: %u", advertisementAttenuation);
            continue;
        }

        [validAttenuationAdvertisements addObject:advertisement];
    }

    // 2. Filter out any advertisements that are from the same RPI > allowedRPIBroadcastDuration after the intial observation
    // of this RPI

    NSMutableDictionary<NSData *, NSDate *> *initialRPIObservationMap = [[NSMutableDictionary alloc] init];
    NSMutableArray<ENAdvertisement *> *validBroadcastDurationAdvertisements = [[NSMutableArray alloc] init];

    // enumerate the advertisements in time order
    NSArray<ENAdvertisement *> *timeOrderedValidAdvertisements = timeOrderedAdvertisements(validAttenuationAdvertisements);
    for (ENAdvertisement *advertisement in timeOrderedValidAdvertisements) {

        // retrieve the first known broadcast of this RPI
        NSDate *initialBroadcastDate = [initialRPIObservationMap objectForKey:[advertisement rpi]];
        if (!initialBroadcastDate) {
            initialBroadcastDate = [NSDate dateWithTimeIntervalSince1970:[advertisement timestamp]];
            [initialRPIObservationMap setObject:initialBroadcastDate forKey:[advertisement rpi]];
        }

        // compare to current broadcast, dropping if > allowedRPIBroadcastDuration
        NSDate *currentBroadcastDate = [NSDate dateWithTimeIntervalSince1970:[advertisement timestamp]];
        NSTimeInterval broadcastDuration = [currentBroadcastDate timeIntervalSinceDate:initialBroadcastDate];
        if (broadcastDuration > DEFAULT_ALLOWABLE_RPI_BROADCAST_DURATION) {
            EN_NOTICE_PRINTF("dropping advertisement due to invalid broadcast duration: %0.3f", broadcastDuration);
            continue;
        }

        [validBroadcastDurationAdvertisements addObject:advertisement];
    }

    return validBroadcastDurationAdvertisements;
}

- (ENExposureInfo *)exposureInfoForAdvertisements:(NSArray<ENAdvertisement *> *)advertisements
{
    // Filter advertisements to discard any suspicious behaviors
    ENTemporaryExposureKey *key = [[advertisements firstObject] temporaryExposureKey];
    NSArray<ENAdvertisement *> *filteredAdvertisements = [self filterAdvertisements:advertisements fromKey:key];
    if ([filteredAdvertisements count] == 0) {
        return nil;
    }

    // Combine advertisements to compensate for RPI rotation during a scan
    NSArray<ENAdvertisement *> *combinedAdvertisements = temporalyCombineAdvertisements(filteredAdvertisements);
    if ([combinedAdvertisements count] == 0) {
        return nil;
    }
    ENRiskLevel transmissionRisk = [[[combinedAdvertisements firstObject] temporaryExposureKey] transmissionRiskLevel];

    // setup the buckets for the vended attenuation durations
    const uint8_t minimumThresholdCount = ATTENUATION_DURATION_THRESHOLD_COUNT_MIN;
    const uint8_t maximumThresholdCount = ATTENUATION_DURATION_BUCKET_COUNT - 1;
    const uint8_t providedThresholdCount = (uint8_t)[_attenuationDurationThresholds count];

    uint8_t attenuationDurationThresholds[ATTENUATION_DURATION_BUCKET_COUNT] = {50, 70, UINT8_MAX, UINT8_MAX};
    uint32_t attenuationDurations[ATTENUATION_DURATION_BUCKET_COUNT] = {0};
    uint32_t totalDuration = 0;

    if (providedThresholdCount >= minimumThresholdCount && providedThresholdCount <= maximumThresholdCount) {
        for (NSUInteger i = 0; i < providedThresholdCount; i++) {
            uint8_t threshold = (uint8_t) [[_attenuationDurationThresholds objectAtIndex:i] unsignedIntValue];
            EN_NOTICE_PRINTF("using non-default attenutation duration threshold[%lu]:%d", (unsigned long)i, threshold);
            attenuationDurationThresholds[i] = threshold;
        }
    } else {
        EN_ERROR_PRINTF("incorrect count of non-default attenuation duration thresholds count:%d", providedThresholdCount);
    }

    // setup the buckets for the high level attenuation value
    uint8_t attenuationValueThresholds[ATTENUATION_VALUE_BUCKET_COUNT] = {10, 15, 27, 33, 51, 63, 73, UINT8_MAX};
    uint32_t attenationValueDurations[ATTENUATION_VALUE_BUCKET_COUNT] = {0};

    // compute the aggregate duration, aggregate attenuation value and earliest timestamp seen
    CFTimeInterval earliestTimestamp = [[NSDate distantFuture] timeIntervalSince1970];
    for (ENAdvertisement *advertisement in combinedAdvertisements) {

        // keep track of the earliest seen advertisement for this TEK
        CFTimeInterval advertisementTimestamp = [advertisement timestamp];
        if (advertisementTimestamp && (advertisementTimestamp < earliestTimestamp)) {
            earliestTimestamp = advertisementTimestamp;
        }

        // count towards total duration regardless of saturation
        uint16_t advertisementDuration = [advertisement scanInterval];
        totalDuration += advertisementDuration;

        // compute the attenuation duration values if not saturated
        if ([advertisement rssi] != INT8_MAX) {
            NSData *tek = [[advertisement temporaryExposureKey] keyData];
            uint8_t advertisementAttenuation = ENCalculateAttnForDiscoveredRPI((uint8_t *)[tek bytes], ENTEKLength,
                                                                               (uint8_t *)[[advertisement rpi] bytes], ENRPILength,
                                                                               (uint8_t *)[[advertisement encryptedAEM] bytes], [[advertisement encryptedAEM] length],
                                                                               [advertisement rssi], [advertisement saturated]);

            // bucket duration by attenuation thresholds for API
            for (int i = 0; i < ATTENUATION_DURATION_BUCKET_COUNT; i++) {
                if (advertisementAttenuation <= attenuationDurationThresholds[i]) {
                    attenuationDurations[i] += advertisementDuration;
                    break;
                }
            }

            // bucket duration by attenuation thresholds for aggregate attenuation value
            for (int i = 0; i < ATTENUATION_VALUE_BUCKET_COUNT; i++) {
                if (advertisementAttenuation <= attenuationValueThresholds[i]) {

                    // these buckets are opposite of the attenuation duration API buckets
                    uint8_t bucketIndex = (ATTENUATION_VALUE_BUCKET_COUNT - 1) - i;
                    attenationValueDurations[bucketIndex] += advertisementDuration;
                    break;
                }
            }
        }
    }

    // compute the duration weighted attenuation value
    uint8_t weightedAttenuationValue = [self weightedAttenuationValueForDurations:attenationValueDurations];

    // cap all durations EXPOSURE_DURATION_MAX
    NSMutableArray<NSNumber *> *cappedAttenuationDurations = [[NSMutableArray alloc] init];
    for (int i = 0; i < ATTENUATION_DURATION_BUCKET_COUNT; i++) {
        attenuationDurations[i] = MIN(attenuationDurations[i], EXPOSURE_DURATION_MAX);
        [cappedAttenuationDurations addObject:@(attenuationDurations[i])];
    }
    totalDuration = MIN(totalDuration, EXPOSURE_DURATION_MAX);

    // floor the observation date to the start of the UTC day in which the exposure began
    NSCalendar *calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
    NSTimeZone *timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    [calendar setTimeZone:timeZone];
    NSDate *observationDate = [NSDate dateWithTimeIntervalSince1970:earliestTimestamp];
    NSDate *coarseDate = [calendar startOfDayForDate:observationDate];

    // construct the exposure info
    ENExposureInfo *exposureInfo = [[ENExposureInfo alloc] init];
    [exposureInfo setDate:coarseDate];
    [exposureInfo setAttenuationValue:weightedAttenuationValue];
    [exposureInfo setTransmissionRiskLevel:transmissionRisk];
    [exposureInfo setDuration:totalDuration];
    [exposureInfo setAttenuationDurations:cappedAttenuationDurations];

    return exposureInfo;
}

- (NSArray<ENExposureInfo *> *)aggregateExposureInfoForAdvertisementBuffer:(NSData *)advertisementBuffer
                                                              exposureKeys:(NSArray<ENTemporaryExposureKey *> *)exposureKeys
{
    // aggregate advertisements per TEK
    NSMutableArray<ENExposureInfo *> *aggregateExposureInfo = [[NSMutableArray alloc] init];
    en_advertisement_t *matchingAdvertisementStructs = (en_advertisement_t *) [advertisementBuffer bytes];
    NSUInteger matchingAdvertisementCount = [advertisementBuffer length] / sizeof(en_advertisement_t);
    NSUInteger advertisementIndex = 0;

    while (advertisementIndex < matchingAdvertisementCount) @autoreleasepool {

        // skip over advertisements until we find a valid advertisement to start the batch
        if (matchingAdvertisementStructs[advertisementIndex].daily_key_index == DAILY_KEY_INDEX_INVALID) {
            advertisementIndex++;
            continue;
        }

        // hydrate advertisements for this batch
        NSMutableArray<ENAdvertisement *> *advertisementBatch = [[NSMutableArray alloc] init];
        const uint32_t currentTEKIndex = matchingAdvertisementStructs[advertisementIndex].daily_key_index;
        const NSUInteger tekStartIndex = advertisementIndex;
        NSUInteger invalidAdvertisementCount = 0;

        for (; advertisementIndex < matchingAdvertisementCount; advertisementIndex++) {
            en_advertisement_t advertisementStruct = matchingAdvertisementStructs[advertisementIndex];

            if (advertisementStruct.daily_key_index == DAILY_KEY_INDEX_INVALID) {
                invalidAdvertisementCount++;
                continue;
            } else if (advertisementStruct.daily_key_index != currentTEKIndex) {
                break;
            } else {
                ENAdvertisement *advertisement = [[ENAdvertisement alloc] initWithStructRepresentation:advertisementStruct];
                ENTemporaryExposureKey *tek = [exposureKeys objectAtIndex:advertisementStruct.daily_key_index];
                [advertisement setTemporaryExposureKey:tek];
                [advertisementBatch addObject:advertisement];
            }
        }

        EN_NOTICE_PRINTF("Converting matching advertisement batch to ExposureInfo tekStartIndex:%d count:%d invalidAdvertisementCount:%d",
                         (int) tekStartIndex, (int) (advertisementIndex - tekStartIndex), (int) invalidAdvertisementCount);
        [aggregateExposureInfo addObject:[self exposureInfoForAdvertisements:advertisementBatch]];
    }

    return aggregateExposureInfo;
}

- (NSArray<ENExposureInfo *> *) exposureInfoForKeys:(NSArray<ENTemporaryExposureKey *> *) inKeys
                               attenuationThreshold:(uint8_t)attenuationThreshold
                                              error:(ENErrorOutType) outError
{
    // dedup exposure keys
    _tekCount += [inKeys count];
    NSMutableDictionary<NSData *, ENTemporaryExposureKey *> *exposureKeyMap = [[NSMutableDictionary alloc] init];
    for (ENTemporaryExposureKey *exposureKey in inKeys) {
        [exposureKeyMap setObject:exposureKey forKey:[exposureKey keyData]];
    }
    NSArray<ENTemporaryExposureKey *> *uniqueExposureKeys = [exposureKeyMap allValues];

    NSArray<ENExposureInfo *> *aggregateExposureInfo = nil;
    __block NSData *matchingAdvertisementBuffer = nil;

    @autoreleasepool {
        matchingAdvertisementBuffer = [self->_database advertisementsBufferMatchingDailyKeys:uniqueExposureKeys attenuationThreshold:attenuationThreshold];

        if (matchingAdvertisementBuffer) {
            aggregateExposureInfo = [self aggregateExposureInfoForAdvertisementBuffer:matchingAdvertisementBuffer exposureKeys:uniqueExposureKeys];

            // check bounds on the buffer as records could be added during a query session
            if (_cacheExposureInfo && (_cachedExposureInfoCount < _exposureInfoBufferSize)) {
                for (ENExposureInfo *exposureInfo in aggregateExposureInfo) {
                    structRepresentationOfExposureInfo(exposureInfo, &_exposureInfoBuffer[_cachedExposureInfoCount++]);

                    // quit filling the buffer if it's full
                    if (_cachedExposureInfoCount >= _exposureInfoBufferSize) {
                        break;
                    }
                }
            }
        }
    }

    if (!matchingAdvertisementBuffer) {
        NSDictionary *errorUserInfo = @{
            NSLocalizedDescriptionKey: @"Error encountered querying database"
        };
        *outError = [NSError errorWithDomain:ENErrorDomain code:ENErrorCodeInternal userInfo:errorUserInfo];
        return nil;
    }

    return aggregateExposureInfo;
}

- (uint64_t) matchCountForKeys:(NSArray<ENTemporaryExposureKey *> *)inKeys
          attenuationThreshold:(uint8_t)attenuationThreshold
                         error:(ENErrorOutType) outError
{
    return [[self exposureInfoForKeys:inKeys attenuationThreshold:attenuationThreshold error:outError] count];
}

- (void)enumerateCachedExposureInfo:(ENExposureInfoEnumerationHandler)enumerationHandler
{
    [self enumerateCachedExposureInfo:enumerationHandler withBatchSize:DEFAULT_EXPOSURE_INFO_BATCH_SIZE];
}

- (void)enumerateCachedExposureInfo:(ENExposureInfoEnumerationHandler)enumerationHandler withBatchSize:(uint32_t)batchSize
{
    [self enumerateCachedExposureInfo:enumerationHandler inRange:NSMakeRange(0, _cachedExposureInfoCount) withBatchSize:batchSize];
}

- (void)enumerateCachedExposureInfo:(ENExposureInfoEnumerationHandler)enumerationHandler inRange:(NSRange)range withBatchSize:(uint32_t)batchSize
{
    NSMutableArray<ENExposureInfo *> *exposureInfoBatch = [[NSMutableArray alloc] init];
    for (NSUInteger batchStartIndex = range.location; batchStartIndex < (range.location + range.length); batchStartIndex += batchSize) @autoreleasepool {
        uint64_t batchCount = (batchStartIndex + batchSize) > _cachedExposureInfoCount ? (_cachedExposureInfoCount - batchStartIndex) : batchSize;
        for (NSUInteger i = batchStartIndex; i < (batchStartIndex + batchCount); i++) {
            [exposureInfoBatch addObject:exposureInfoFromStructRepresentation(_exposureInfoBuffer[i])];
        }
        enumerationHandler(exposureInfoBatch, nil);
        [exposureInfoBatch removeAllObjects];
    }
}

@end
