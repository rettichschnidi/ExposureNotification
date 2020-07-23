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

#import "ENAdvertisementDatabaseQuerySession.h"
#import "ENAdvertisementDatabase.h"

NS_ASSUME_NONNULL_BEGIN

@interface ENAdvertisementDatabaseQuerySession (PrivateMethods)

- (instancetype)initWithDatabase:(ENAdvertisementDatabase *)database attenuationThreshold:(uint8_t)attenuationThreshold;

@end

NS_ASSUME_NONNULL_END
