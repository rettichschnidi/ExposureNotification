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
#import <ExposureNotification/ExposureNotification.h>

#import "ENAdvertisementDatabase.h"
#import "ENAdvertisementDatabaseQuerySession.h"
#import "ENFile.h"

NS_ASSUME_NONNULL_BEGIN

/*
 *  A sample daemon side Exposure Detection class. This class utilizes the cryptographic
 *  functions included in ENCryptography to generate the RPIs for the TEK in the provided
 *  ENFile. It then checks the on-device ENAdvertisementDatabase for the presence of these
 *  RPIs, generating ENExposureInfos for matching advertisements.
 */

@interface ENExposureDetectionDaemonSession : NSObject

/*
 *  Initialize the ENExposureDetectionDaemonSession with the provided database and configuration.
 *  The database should be fully initialized with a backing ENAdvertisementSQLiteStore, and the
 *  configuration should be initialized with the configuration to be utilized in the generation of
 *  ENExposureInfo and ENExposureDetectionSummary objects.
 */
- (instancetype)initWithDatabase:(ENAdvertisementDatabase *)database configuration:(ENExposureConfiguration *)configuration;

/*
 *  Find matches for an the TEKs contained with the provided ENFile.
 *  Returnes NO if the matching process encounters an error, else returns YES.
 */
- (BOOL)addFile:(ENFile *)mainFile;

/*
 *  Generate an ENExposureDetectionSummary for the advertisements found in the on device database
 *  that originated from one of the TEKs provided via the addFile: method.
 */
- (ENExposureDetectionSummary *)generateSummary;

/*
 *  Return all generated ENExposureInfo objects for the advertisements found in the on device database
 *  that originated from one of the TEKs provided via the addFile: method.
 */
- (NSArray<ENExposureInfo *> *)exposureInfo;

@end

NS_ASSUME_NONNULL_END
