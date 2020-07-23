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
#import <array>
#import <vector>
#import <map>

#import "ENShims.h"
#import "ENCryptography.h"

typedef uint64_t BTAddress;

typedef struct LE_UUID
{
    uint8_t         length;
    union {
        uint16_t    uuid16;
        uint32_t    uuid32;
        uint8_t     uuid128[16];
    };

    bool operator==(const LE_UUID other) const
    {
        if (length == other.length) {
            return !memcmp(uuid128, other.uuid128, length);
        }
        return false;
    }

    bool operator<(const LE_UUID other) const
    {
        if (length != other.length) {
            return length < other.length;
        }
        return (memcmp(uuid128, other.uuid128, length) < 0);
    }

} LE_UUID;

namespace BT
{

#pragma mark - Class Stubs

class ByteBuffer
{
public:
    size_t getSize() const { return 0; };
    const uint8_t* getData() const { return NULL; };
};

class LeAdvertisementData
{
public:
    typedef LeAdvertisementData *AutoPtr;
    typedef std::map<LE_UUID, ByteBuffer> ServiceDataMap;
    ServiceDataMap fServiceData;
    ServiceDataMap getServiceData() { return fServiceData; };
    BTAddress getDeviceAddress() { return 0; };
    int8_t getRSSI() { return 0; };
    bool getIsSaturated() { return false; };
    double getTimestamp() { return 0.0f; };
};

#pragma mark - ExposureNotificationManager Interface

typedef struct {
    int8_t avgRSSI;
    int8_t maxRSSI;
} RSSIValues;

class ExposureNotificationManager
{

public:
    ExposureNotificationManager();
    virtual ~ExposureNotificationManager() { };

#pragma mark - Exposure Notification Scanning

public:
    BTResult startScanning();
    BTResult stopScanning();

private:
    typedef std::vector<LeAdvertisementData::AutoPtr> ReportsSet;
    typedef std::array<uint8_t, (EN_RPI_LEN + EN_AEM_LEN)> rpiData;
    typedef std::map<rpiData, ReportsSet> ExposureNotificationReportsMap;
    ExposureNotificationReportsMap fReports;

    double previousExposureNotificationScanCompleteTime();
    void bluetoothDeviceFoundCallback(NSUUID *device, const LeAdvertisementData::AutoPtr& advData);
    void scanDidStop();

#pragma mark - Exposure Notification Advertising

public:
    BTResult generateAdvertisingPayload(uint8_t *payloadBytes, uint8_t payloadBytesLen, BTAddress &advertisingAddress);

private:
    // Exposure Notification advertisement generation related methods
    BTResult retrieveCurrentRollingProximityIdentifier(uint8_t *outBuffer, size_t outBufferSize);
    BTResult retrieveCurrentTemporaryExposureKey(uint8_t *outBuffer, size_t outBufferSize);
    uint8_t getPlatformRadiatedLeTxPower();
    
};

}
