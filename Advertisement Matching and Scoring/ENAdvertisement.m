/*
 *      Copyright (C) 2020 Apple Inc. All Rights Reserved.
 *
 *      ExposureNotification is licensed under Apple Inc.’s
 *      Sample Code License Agreement, which is contained in
 *      the LICENSE file distributed with ExposureNotification,
 *      and only to those who accept that license.
 *
 */

#import "ENAdvertisement_Private.h"
#import "ENShims.h"

@implementation ENAdvertisement

- (instancetype)initWithStructRepresentation:(en_advertisement_t)structRepresentation
{
    NSData *rpi = [[NSData alloc] initWithBytes:structRepresentation.rpi length:ENRPILength];
    NSData *encryptedAEM = [[NSData alloc] initWithBytes:structRepresentation.encrypted_aem length:AEM_LENGTH];

    return [self initWithRPI:rpi
                encryptedAEM:encryptedAEM
                   timestamp:structRepresentation.timestamp
                scanInterval:structRepresentation.scan_interval
					 avgRSSI:structRepresentation.rssi
                   saturated:structRepresentation.saturated
                 countryCode:0
                     counter:structRepresentation.count];
}

- (instancetype)initWithRPI:(NSData *)rpi
               encryptedAEM:(NSData *)encryptedAEM
                  timestamp:(CFAbsoluteTime)timestamp
               scanInterval:(uint16_t)scanInterval
					avgRSSI:(int8_t)rssi
                  saturated:(BOOL)saturated
                countryCode:(uint16_t)countryCode
                    counter:(uint8_t)count
{
    if (self = [super init]) {
        _rpi = rpi;
        _encryptedAEM = encryptedAEM;
        _timestamp = timestamp;
        _scanInterval = scanInterval;
        _rssi = rssi;
        _saturated = saturated;
        _countryCode = countryCode;
		_counter = count;
    }
    return self;
}

- (en_advertisement_t)structRepresentation
{
    en_advertisement_t adv = {
        .timestamp = _timestamp,
        .scan_interval = _scanInterval,
        .rssi = _rssi,
        .saturated = _saturated,
		.count = _counter
    };
    [_rpi getBytes:adv.rpi length:ENRPILength];
    [_encryptedAEM getBytes:adv.encrypted_aem length:AEM_LENGTH];
    return adv;
}

- (void)combineWithAdvertisement:(ENAdvertisement *)otherAdvertisement
{
    uint8_t totalCount = _counter + [otherAdvertisement counter];
    if (!totalCount) {
        EN_CRITICAL_PRINTF("Invalid advertisement combine counter:%d otherCounter:%d", _counter, [otherAdvertisement counter]);
        totalCount = 1;
    }

    if ([otherAdvertisement rssi] != INT8_MAX && _rssi != INT8_MAX) {
        // if both advertisements have a valid RSSI reading, combine them using their counters as the weight
        int totalRSSI = (_rssi * _counter) + ([otherAdvertisement rssi] * [otherAdvertisement counter]);
        _rssi = (totalRSSI / totalCount);
    } else {
        // if one of more rssi values is saturated, take the minimum
        _rssi = (_rssi < [otherAdvertisement rssi]) ? _rssi : [otherAdvertisement rssi];
    }

    _saturated = (_rssi == INT8_MAX);
    _counter = totalCount;
}

@end
