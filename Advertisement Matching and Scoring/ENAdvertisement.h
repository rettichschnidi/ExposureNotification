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

NS_ASSUME_NONNULL_BEGIN

@interface ENAdvertisement : NSObject

- (instancetype)initWithRPI:(NSData *)rpi
               encryptedAEM:(NSData *)encryptedAEM
                  timestamp:(CFAbsoluteTime)timestamp
               scanInterval:(uint16_t)scanInterval
					avgRSSI:(int8_t)avgRSSI
                  saturated:(BOOL)saturated
                countryCode:(uint16_t)countryCode
					counter:(uint8_t)count;

@property (nonatomic, strong) NSData *rpi;
@property (nonatomic, strong) NSData *encryptedAEM;
@property (nonatomic) CFAbsoluteTime timestamp;
@property (nonatomic) uint16_t scanInterval;
@property (nonatomic) int8_t rssi;
@property (nonatomic) bool saturated;
@property (nonatomic) uint16_t countryCode;
@property (nonatomic) uint8_t counter;

@property (nonatomic, strong, nullable) ENTemporaryExposureKey *temporaryExposureKey;

@end

NS_ASSUME_NONNULL_END

