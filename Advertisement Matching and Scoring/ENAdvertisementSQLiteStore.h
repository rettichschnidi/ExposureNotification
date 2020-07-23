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

#import "ENAdvertisement_Private.h"
#import "ENQueryFilter.h"

NS_ASSUME_NONNULL_BEGIN

extern NSErrorDomain const ENAdvertisementStoreErrorDomain;

typedef NS_ERROR_ENUM(ENAdvertisementStoreErrorDomain, ENAdvertisementStoreErrorCode)
{
    ENAdvertisementStoreErrorCodeUnknown = 1,   /// Underlying failure with an unknown cause.
    ENAdvertisementStoreErrorCodeFull = 2,      /// Device storage is full
    ENAdvertisementStoreErrorCodeCorrupt = 3,   /// Underlying store is corrupt
    ENAdvertisementStoreErrorCodeReopen = 4,    /// Underlying store must be closed and reopened
    ENAdvertisementStoreErrorCodeBusy = 5       /// Underlying store is busy
};

@interface ENAdvertisementSQLiteStore : NSObject

/*
 *  Allocate a central store in the specified folder. A central
 *  store is intended to be the permanent on disk storage for all
 *  observed exposure notification advertisements. It should not be erased
 *  for any reason other than exposure notification being disabled.
 */
+ (nullable instancetype)centralStoreInFolderPath:(NSString *)folderPath;

/*
 *  Open a store backed by the SQLite database at the specified path.
 *  If no database exists at the path, one will be created. If the
 *  database stored at the path is unable to be opened, this method
 *  will return nil;
 */
- (nullable instancetype)initWithPath:(NSString *)path;

/*
 *  Current count of advertisements stored in SQLite database. This class does
 *  no in-memory caching of advertisements, so this represents the actual count
 *  persisted on disk;
 */
@property (nonatomic, nullable, readonly) NSNumber *storedAdvertisementCount;

/*
 *  Generate a query filter for this backing store. A query filter can be used eliminate RPIs that
 *  cannot possibly be in the database.
 */
- (nullable ENQueryFilter *)queryFilterWithBufferSize:(NSUInteger)bufferSize
                                            hashCount:(NSUInteger)hashCount
                                 attenuationThreshold:(uint8_t)attenuationThreshold;
/*
 *  Get a list of en_advertisement_t with RPIs contained in the input RPI buffer.
 *
 *  Returns the count of matching advertisements;
 */
- (NSUInteger)getAdvertisementsMatchingRPIBuffer:(const void *)buffer
                                           count:(NSUInteger)bufferRPICount
                                  validityBuffer:(const void *)validityBuffer
                                   validRPICount:(NSUInteger)validRPICount
                     matchingAdvertisementBuffer:(en_advertisement_t *_Nonnull *_Nullable)matchBufferOut
                                           error:(NSError * _Nullable __autoreleasing * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
