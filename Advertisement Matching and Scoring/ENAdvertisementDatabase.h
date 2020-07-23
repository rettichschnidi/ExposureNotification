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

#import <Foundation/Foundation.h>

#import "ENQueryFilter.h"
#import "ENAdvertisement.h"
#import "ENAdvertisementDatabaseQuerySession.h"

NS_ASSUME_NONNULL_BEGIN

@interface ENAdvertisementDatabase : NSObject

/*
 *  If a large data amount of queries are going to take place
 *  (i.e. periodic processing of the Daily Keys), a query filter will be
 *  cached to prevent unneeded queries on the backing store
 */
@property (nonatomic, strong, nullable) ENQueryFilter *inlineQueryFilter;

/*
 *  Total count of advertisements in the database, this will include advertisements
 *  persisted on disk + advertisements in the cache. This will return nil if the
 *  central database is currently unable to be read.
 */
@property (nonatomic, readonly, nullable) NSNumber *storedAdvertisementCount;

/*
 *  Total count of advertisements dropped due to ENIN filtering.
 */
@property (nonatomic, readonly) NSUInteger droppedAdvertisementCount;

/*
 *  Initialize a ENAdvertisementDatabase with the specified folder.
 *  A ENAdvertisementDatabase needs a path to a folder as it will
 *  create temporary backing stores to persist data when central store is unavailable.
 */
- (instancetype)initWithDatabaseFolderPath:(NSString *)folderPath cacheCount:(NSUInteger)cacheCount;

/*
 *  Generate a query filter with the specified configuration. If many queries are going
 *  to be sent to database in rapid succession, generate a filter with this command and
 *  assign it to the inlineQueryFilter property.
 */
- (nullable ENQueryFilter *)queryFilterWithBufferSize:(NSUInteger)bufferSize
                                            hashCount:(NSUInteger)hashCount
                                 attenuationThreshold:(uint8_t)attenuationThreshold;

/*
 *  Collect all advertisements from the database that were derived from the provided daily
 *  key buffer with RSSI values above the provided threshold. These results will be returned
 *  as the raw underlying struct data, with invalid advertisements having daily_key_index
 *  set to DAILY_KEY_INDEX_INVALID.
 */
- (nullable NSData *)advertisementsBufferMatchingDailyKeys:(NSArray<ENTemporaryExposureKey *> *)dailyKeys
                                      attenuationThreshold:(uint8_t)attenuationThreshold;

/*
 *  For easy query access to the database, create a query session. A query session will manager
 *  the inline filter of the database.
 */
- (nullable ENAdvertisementDatabaseQuerySession *)createQuerySessionWithAttenuationThreshold:(uint8_t)attenuationThreshold;

@end

NS_ASSUME_NONNULL_END
