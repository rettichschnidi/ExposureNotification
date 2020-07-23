/*
 *      Copyright (C) 2020 Apple Inc. All Rights Reserved.
 *
 *      ExposureNotification is licensed under Apple Inc.’s
 *      Sample Code License Agreement, which is contained in
 *      the LICENSE file distributed with ExposureNotification,
 *      and only to those who accept that license.
 *
 */

#import "ENAdvertisementDatabase.h"
#import "ENAdvertisement_Private.h"
#import "ENQueryFilter.h"
#import "ENAdvertisementSQLiteStore.h"
#import "ENAdvertisementDatabaseQuerySession_Private.h"
#import "ENCryptography.h"

#import "ExposureNotificationManager.h"

#pragma mark - Definitions

#define ADVERTISEMENT_TOLERANCE_CTIN (12)   // 2 hours (2 * 60 * 60 / (10 * 60))
#define ADVERTISEMENT_AGE_THRESHOLD (14 * 24 * 60 * 60) // 2 weeks

/// Number of seconds in 1 ENIntervalNumber.
#define ENSecondsPerENIntervalNumber        ( 60 * 10 )

/// Converts CFAbsoluteTime to ENIntervalNumber for generating RPIs.
static inline ENIntervalNumber CFAbsoluteTimeToENIntervalNumber(CFAbsoluteTime inCFTime)
{
    return ((ENIntervalNumber) ((inCFTime + kCFAbsoluteTimeIntervalSince1970) / ENSecondsPerENIntervalNumber));
}

#pragma mark - Database

@implementation ENAdvertisementDatabase {
    // On disk advertisement store, a temporary store may be needed as the
    // backing SQLite database is Class B, meaning we cannot grab a handle
    // to the database if the device is locked
    NSString *_databaseFolderPath;
    ENAdvertisementSQLiteStore *_centralStore;
}

- (instancetype)initWithDatabaseFolderPath:(NSString *)folderPath cacheCount:(NSUInteger)cacheCount
{
    EN_NOTICE_PRINTF("initializing exposure notification database in %s", [_databaseFolderPath UTF8String]);

    if (self = [super init]) {
        _databaseFolderPath = folderPath;
        [self openStore];
    }
    return self;
}

#pragma mark - Backing Store Management

- (BOOL)openStore
{
    BOOL success = YES;

    if (![self openCentralStore]) {
        EN_CRITICAL_PRINTF("failed to open all store types in database folder: %s", [_databaseFolderPath UTF8String]);
        success = NO;
    }

    return success;
}

- (BOOL)openCentralStore
{
    // nothing to do if the central store is already open
    if (_centralStore) {
        return YES;
    }
    _centralStore = [ENAdvertisementSQLiteStore centralStoreInFolderPath:_databaseFolderPath];

    if (_centralStore) {
        return YES;
    }
    return NO;
}

#pragma mark - Querying

- (NSNumber *)storedAdvertisementCount
{
    if (!_centralStore) {
        return nil;
    }

    return [_centralStore storedAdvertisementCount];
}

- (nullable ENQueryFilter *)queryFilterWithBufferSize:(NSUInteger)bufferSize
                                            hashCount:(NSUInteger)hashCount
                                 attenuationThreshold:(uint8_t)attenuationThreshold
{
    EN_NOTICE_PRINTF("creating exposure notification query filter bufferSize:%lu hashCount:%lu", (unsigned long) bufferSize, (unsigned long) hashCount);

    if (!_centralStore) {
        return nil; // do not provide query filters if there is no access to the central store as the filter will be wrong
    }

    return [_centralStore queryFilterWithBufferSize:bufferSize hashCount:hashCount attenuationThreshold:attenuationThreshold];
}

- (nullable NSData *)matchingAdvertisementBufferForRPIBuffer:(NSData *)buffer exposureKeys:(NSArray<ENTemporaryExposureKey *> *)exposureKeys
{
    // alocate the validity buffer
    uint64_t bufferRPICount = [buffer length] / ENRPILength;
    bool *validityBuffer = (bool *) calloc(bufferRPICount, sizeof(bool));
    if (!validityBuffer) {
        EN_ERROR_PRINTF("failed to allocate validity buffer");
        return nil;
    }
    int possibleRPICount = 0;

    // populate the validity buffer
    const char *rpiBuffer = (const char *) [buffer bytes];
    for (uint32_t exposureKeyIndex = 0; exposureKeyIndex < [exposureKeys count]; exposureKeyIndex++) {

        // determine how many RPI to look at
        ENTemporaryExposureKey *exposureKey = [exposureKeys objectAtIndex:exposureKeyIndex];
        uint32_t rollingPeriod = ENTEKRollingPeriod;
        if ([exposureKey rollingPeriod] && [exposureKey rollingPeriod] < ENTEKRollingPeriod) {
            rollingPeriod = [exposureKey rollingPeriod];
        } else if ([exposureKey rollingPeriod] > ENTEKRollingPeriod) {
            // if the TEK has a rollingPeriod > ENTEKRollingPeriod, log an error and
            // continue as to not consider any of these TEK in the matching process
            EN_ERROR_PRINTF("invalid TEK rollingPeriod: %d", [exposureKey rollingPeriod]);
            continue;
        }

        // check if those RPI are possibly valid
        for (uint32_t rpiIndex = 0; rpiIndex < rollingPeriod; rpiIndex++) {
            uint32_t rpiBufferIndex = (exposureKeyIndex * ENTEKRollingPeriod) + rpiIndex;
            if (![_inlineQueryFilter shouldIgnoreRPI:&rpiBuffer[rpiBufferIndex * ENRPILength]]) {
                validityBuffer[rpiBufferIndex] = true;
                possibleRPICount++;
            }
        }
    }

    EN_INFO_PRINTF("querying sqlite for advertisements count:%d filteredCount:%llu", possibleRPICount, (bufferRPICount - possibleRPICount));

    // retreive raw data of matching advertisements
    en_advertisement_t *matchingAdvertisementsBuffer = NULL;
    NSError *matchError = nil;
    NSUInteger matchingAdvertisementCount = [_centralStore getAdvertisementsMatchingRPIBuffer:rpiBuffer
                                                                                        count:bufferRPICount
                                                                               validityBuffer:validityBuffer
                                                                                validRPICount:possibleRPICount
                                                                  matchingAdvertisementBuffer:&matchingAdvertisementsBuffer
                                                                                        error:&matchError];
    free(validityBuffer);

    if (!matchingAdvertisementsBuffer) {
        EN_ERROR_PRINTF("sqlite matching advertisements returned null results buffer");

        if ([matchError code] == ENAdvertisementStoreErrorCodeReopen) {
            // close the database to recover
        } else if ([matchError code] == ENAdvertisementStoreErrorCodeCorrupt) {
            // delete the corrupt store to recover
        }

        return nil;
    }

    EN_INFO_PRINTF("sqlite matching advertisements count:%lu", (unsigned long) matchingAdvertisementCount);
    return [NSData dataWithBytesNoCopy:matchingAdvertisementsBuffer length:(matchingAdvertisementCount * sizeof(en_advertisement_t))];
}

- (nullable NSData *)advertisementsBufferMatchingDailyKeys:(NSArray<ENTemporaryExposureKey *> *)dailyKeys
                                      attenuationThreshold:(uint8_t)attenuationThreshold
{
    EN_INFO_PRINTF("ExposureNotification: generating RPI data from tracing key count:%lu", (unsigned long) [dailyKeys count]);

    // preallocate the RPI buffer
    uint64_t rpiBufferSize = [dailyKeys count] * ENTEKRollingPeriod * ENRPILength;
    __block ENRPIStruct *rpiBuffer = (ENRPIStruct *) malloc(rpiBufferSize);
    if (!rpiBuffer) {
        EN_ERROR_PRINTF("failed to allocate RPI buffer");
        return nil;
    }

    // generate the RPI data
    __block BOOL success = YES;
    [dailyKeys enumerateObjectsUsingBlock:^(ENTemporaryExposureKey *exposureKey, NSUInteger index, BOOL *stop) {
        BTResult result = ENGenerate144RollingProximityIdentifiers((uint8_t *) [[exposureKey keyData] bytes], [[exposureKey keyData] length],
                                                                   [exposureKey rollingStartNumber],
                                                                   (uint8_t *) &rpiBuffer[index * ENTEKRollingPeriod], ENTEKRollingPeriod * ENRPILength);
        if (result != BT_SUCCESS) {
            EN_CRITICAL_PRINTF("Failed to generate RPI data TEK:%@ rollingStartNumber:%d", [exposureKey keyData], [exposureKey rollingStartNumber]);
            success = NO;
            *stop = YES;
        }
    }];

    // Find the matching advertisements
    NSData *rpiBufferData = [[NSData alloc] initWithBytesNoCopy:rpiBuffer length:rpiBufferSize];
    NSData *matchingAdvertisementStructs = nil;
    if (success) {
        matchingAdvertisementStructs = [self matchingAdvertisementBufferForRPIBuffer:rpiBufferData exposureKeys:dailyKeys];
        if (!matchingAdvertisementStructs) {
            success = NO;
            EN_ERROR_PRINTF("Failed to generate matching advertisements buffer");
        }
    }
    NSUInteger matchingAdvertisementCount = [matchingAdvertisementStructs length] / sizeof(en_advertisement_t);
    en_advertisement_t *matchingAdvertisementsBuffer = (en_advertisement_t *) [matchingAdvertisementStructs bytes];

    // hydrate the buffer data into objects
    CFAbsoluteTime timestampThreshold = (CFAbsoluteTimeGetCurrent() + kCFAbsoluteTimeIntervalSince1970) - ADVERTISEMENT_AGE_THRESHOLD;
    if (success) {
        for (NSUInteger i = 0; i < matchingAdvertisementCount; i++) @autoreleasepool {
            en_advertisement_t *advertisementStruct = &matchingAdvertisementsBuffer[i];
            ENTemporaryExposureKey *tek = [dailyKeys objectAtIndex:advertisementStruct->daily_key_index];

            // verify the duration is within the expiration period (the daily purge may not have run yet)
            if (advertisementStruct->timestamp < timestampThreshold) {
                EN_NOTICE_PRINTF("Dropping outdated advertisement TEK:%@ timestamp:%0.2f threshold:%0.2f", tek, advertisementStruct->timestamp, timestampThreshold);
                advertisementStruct->daily_key_index = DAILY_KEY_INDEX_INVALID;
                _droppedAdvertisementCount++;
                continue;
            }

            uint32_t dailyKeyRPIIndex = advertisementStruct->rpi_index + [tek rollingStartNumber];
            uint32_t minValidCTIN = dailyKeyRPIIndex - ADVERTISEMENT_TOLERANCE_CTIN;
            uint32_t maxValidCTIN = dailyKeyRPIIndex + ADVERTISEMENT_TOLERANCE_CTIN;
            uint32_t observedCTIN = CFAbsoluteTimeToENIntervalNumber(advertisementStruct->timestamp - kCFAbsoluteTimeIntervalSince1970);

            if (minValidCTIN <= observedCTIN && observedCTIN <= maxValidCTIN) {
                NSData *tekData = [tek keyData];
                uint8_t attenuation = ENCalculateAttnForDiscoveredRPI((uint8_t *) [tekData bytes], [tekData length],
                                                                      (uint8_t *) advertisementStruct->rpi, ENRPILength,
                                                                      (uint8_t *) advertisementStruct->encrypted_aem, AEM_LENGTH,
                                                                      advertisementStruct->rssi, advertisementStruct->saturated);
                EN_NOTICE_PRINTF("RPI : %.16P Attenuation : %u", advertisementStruct->rpi, attenuation);

                if (attenuation >= attenuationThreshold) {
                    EN_NOTICE_PRINTF("dropping advertisement due to attenuation threshold");
                    advertisementStruct->daily_key_index = DAILY_KEY_INDEX_INVALID;
                    _droppedAdvertisementCount++;
                }
            } else {
                EN_NOTICE_PRINTF("ExposureNotification: Dropping advertisement %@ with invalid CTIN : %u, rpiIndex : %u",
                                 [[dailyKeys objectAtIndex:advertisementStruct->daily_key_index] keyData], observedCTIN, dailyKeyRPIIndex);
                advertisementStruct->daily_key_index = DAILY_KEY_INDEX_INVALID;
                _droppedAdvertisementCount++;
            }
        }
    }

    return matchingAdvertisementStructs;
}

- (ENAdvertisementDatabaseQuerySession *)createQuerySessionWithAttenuationThreshold:(uint8_t)attenuationThreshold
{
    EN_NOTICE_PRINTF("creating advertisement query session attn:%u", attenuationThreshold);

    ENAdvertisementDatabaseQuerySession *querySession = [[ENAdvertisementDatabaseQuerySession alloc] initWithDatabase:self attenuationThreshold:attenuationThreshold];
    return querySession;
}

@end
