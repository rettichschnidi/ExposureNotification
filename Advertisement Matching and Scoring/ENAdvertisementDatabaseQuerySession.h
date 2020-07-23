/*
 *      Copyright (C) 2020 Apple Inc. All Rights Reserved.
 *
 *      ExposureNotification is licensed under Apple Inc.’s
 *      Sample Code License Agreement, which is contained in
 *      the LICENSE file distributed with ExposureNotification,
 *      and only to those who accept that license.
 *
 */

#import <Foundation/Foundation.h>
#import <ExposureNotification/ExposureNotification.h>

NS_ASSUME_NONNULL_BEGIN

typedef void ( ^ENExposureInfoEnumerationHandler )(NSArray<ENExposureInfo *> * _Nullable exposureInfoBatch,  NSError * _Nullable error);

@interface ENAdvertisementDatabaseQuerySession : NSObject

/// Create ENAdvertisementDatabaseQuerySession via -[ENAdvertisementDatabase createQuerySession]
- (instancetype)init NS_UNAVAILABLE;

/*
 *  This is used as the thresholds for the attenuation durations on the ENExposureInfo.
 *
 *  THIS MUST BE 2 or 3 NUMBERS.
 *     With 2 numbers, the buckets will be (a <= x), (x < a <= y), (y < a)
 *     With 3 numbers, the buckets will be (a <= x), (x < a <= y), (y < a <= z), (z < a)
 */
@property (nonatomic, strong, nullable) NSArray<NSNumber *> *attenuationDurationThresholds;

@property (nonatomic, strong, nullable) ENExposureConfiguration *configuration;

/*
 *  Retrieves the count of matches found in the on-device database for the provided Temporary
 *  Exposure Keys. If the cacheExposureInfo property is set to YES, the generated ENExposureInfo
 *  can be enumerated at a later time via the enumerateCachedExposureInfo methods.
 */
- (uint64_t) matchCountForKeys:(NSArray<ENTemporaryExposureKey *> *)inKeys
          attenuationThreshold:(uint8_t)attenuationThreshold
                         error:(ENErrorOutType)outError;

/*
 *  Retrieves the generated ENExposureInfo for matches found in the on-device database for the
 *  provided Temporary Exposure Keys. If the cacheExposureInfo property is set to YES, the generated
 *  ENExposureInfo can be enumerated at a later time via the enumerateCachedExposureInfo methods.
 */
- (nullable NSArray<ENExposureInfo *> *) exposureInfoForKeys:(NSArray <ENTemporaryExposureKey *> *) inKeys
                                        attenuationThreshold:(uint8_t)attenuationThreshold
                                                       error:(ENErrorOutType)outError;

/*
 *  ENExposureInfo caching
 *  If the cacheExposureInfo property is set to YES, the above matching methods will cache all
 *  generated ENExposureInfo objects to be stored in an in memory cache. When the complete list
 *  of TEKs representing positive matches has been pased in, the enumerateCachedExposureInfo methods
 *  can be used to enumerate the cached ENExposureInfos for scoring / sending to the client app.
 */

@property (nonatomic) BOOL cacheExposureInfo;
@property (nonatomic) NSUInteger cachedExposureInfoCount;

- (void)enumerateCachedExposureInfo:(ENExposureInfoEnumerationHandler)enumerationHandler;
- (void)enumerateCachedExposureInfo:(ENExposureInfoEnumerationHandler)enumerationHandler withBatchSize:(uint32_t)batchSize;
- (void)enumerateCachedExposureInfo:(ENExposureInfoEnumerationHandler)enumerationHandler inRange:(NSRange)range withBatchSize:(uint32_t)batchSize;

@end

NS_ASSUME_NONNULL_END
