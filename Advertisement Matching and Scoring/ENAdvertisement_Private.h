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

#import "ENAdvertisement.h"
#import "ENCommonPrivate.h"
#import <stdint.h>

#define AEM_LENGTH (4)
#define DAILY_KEY_INDEX_INVALID UINT32_MAX

typedef struct __attribute__((packed)) {
    char rpi[ENRPILength];
    char encrypted_aem[AEM_LENGTH];
    CFAbsoluteTime timestamp;
    uint32_t daily_key_index;
    uint16_t rpi_index;
    uint16_t scan_interval;
    int8_t rssi;
    bool saturated;
	uint8_t count;
} en_advertisement_t;

NS_ASSUME_NONNULL_BEGIN

@interface ENAdvertisement (PrivateMethods)

- (instancetype)initWithStructRepresentation:(en_advertisement_t)structRepresentation;

- (en_advertisement_t)structRepresentation;

- (void)combineWithAdvertisement:(ENAdvertisement *)otherAdvertisement;

@end

NS_ASSUME_NONNULL_END
