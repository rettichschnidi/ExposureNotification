/*
 *      Copyright (C) 2020 Apple Inc. All Rights Reserved.
 *
 *      ExposureNotification is licensed under Apple Inc.’s
 *      Sample Code License Agreement, which is contained in
 *      the LICENSE file distributed with ExposureNotification,
 *      and only to those who accept that license.
 *
 */

#import <stdint.h>

#import "ExposureNotificationManager.h"
#import "ENCryptography.h"
#import "ENShims.h"

#pragma mark - Constant Values

#define LE_ATT_UUID_16BIT_SIZE      (2)
const LE_UUID LE_ExposureNotification_Service_UUID = {LE_ATT_UUID_16BIT_SIZE, {0xFD6F}};

#pragma mark - Configurable Values

#define EXPOSURE_NOTIFICATION_SCAN_DELTA_TIME_SECONDS           (150)
#define EXPOSURE_NOTIFICATION_SCAN_DURATION_TIME_SECONDS        (4)
#define EXPOSURE_NOTIFICATION_SCAN_AP_WAKE_DELTA_TIME_SECONDS   (300)

const uint8_t EN_VERSION_MAJOR = 0x01;
const uint8_t EN_VERSION_MINOR = 0x00;

namespace BT
{

ExposureNotificationManager::ExposureNotificationManager()
{

}

#pragma mark - Exposure Notification Scanning

BTResult ExposureNotificationManager::startScanning()
{
    // Validate the device is currently capable of performing an ExposureNotification scan

    /*
     * Configure the ExposureNotification scan. The Bluetooth scan should be configured according to the advice in:
     *     https://covid19-static.cdn-apple.com/applications/covid19/current/static/contact-tracing/pdf/ExposureNotification-BluetoothSpecificationv1.2.pdf
     *
     * The scan should be configured to look for Service UUID 0xFD6F and should be configured to capture the RSSI of observed advertisements. In addition,
     * it is recomended to scan with a high duty cycle for a short amount of time to minimize the power impact of ExposureNotification.
     */

    __block BTResult result = BT_SUCCESS;

    // Initiate the configured scan:
    // result = bluetoothStack->scan();

    EN_INFO_PRINTF("startScanning returning %d", result);

    return result;
}

BTResult ExposureNotificationManager::stopScanning()
{
    // After a sufficient amount of time has been spent scanning at the configured duty cycle, stop scanning.

    __block BTResult result = BT_SUCCESS;
    // result = bluetoothStack->stopScanning();

    EN_INFO_PRINTF("stopScanning returning %d", result);

    return result;
}

void ExposureNotificationManager::bluetoothDeviceFoundCallback(NSUUID *device,
                                                               const LeAdvertisementData::AutoPtr& advData)
{
    const LeAdvertisementData::ServiceDataMap svcData = advData->getServiceData();
    if (svcData.size() > 0) {

        // Validate the observed ExposureNotification payload size
        const ByteBuffer svcDataBuffer = svcData.at(LE_ExposureNotification_Service_UUID);
        if (svcDataBuffer.getSize() != (EN_RPI_LEN + EN_AEM_LEN)) {
            EN_ERROR_PRINTF("Invalid service data received from device %@", device);
        } else {

            // Store the observations grouped by RPI of the ExposureNotification payload
            rpiData mapKey;
            memcpy(mapKey.data(), svcDataBuffer.getData(), svcDataBuffer.getSize());
            fReports[mapKey].push_back(advData);

            EN_INFO_PRINTF("device %@ address:%llx rpi:%.16P aem:%.4P rssi:%d saturated:%d timestamp:%f totalReports:%lu",
                           device, advData->getDeviceAddress(), svcDataBuffer.getData(),
                           svcDataBuffer.getData()+EN_RPI_LEN, advData->getRSSI(), advData->getIsSaturated(),
                           advData->getTimestamp() + kCFAbsoluteTimeIntervalSince1970, fReports[mapKey].size());
        }
    }
}

double ExposureNotificationManager::previousExposureNotificationScanCompleteTime()
{
    // Retrieve the previous ExposureNotification scan complete timestamp from the
    // Bluetooth stack.
    return 0;
}

void ExposureNotificationManager::scanDidStop()
{
    EN_NOTICE_PRINTF("scanDidStop, report the results for %lu total devices found", fReports.size());

    // Compute the time delta since the previous ExposureNotification scan, defaulting to 150 seconds
    // (delta lower bound) when a delta is unable to be calculated.
    double lastStopped = 0; this->previousExposureNotificationScanCompleteTime();
    uint32_t delta = EXPOSURE_NOTIFICATION_SCAN_DELTA_TIME_SECONDS;

    if (lastStopped != 0) {
        delta = CFAbsoluteTimeGetCurrent() - lastStopped;

        // If BT was off for a while, and the delta is greater than expected, set it to default 150
        if (delta > (EXPOSURE_NOTIFICATION_SCAN_AP_WAKE_DELTA_TIME_SECONDS + EXPOSURE_NOTIFICATION_SCAN_DURATION_TIME_SECONDS)) {
            delta = EXPOSURE_NOTIFICATION_SCAN_DELTA_TIME_SECONDS;
        }
    }

    for (ExposureNotificationReportsMap::iterator it = fReports.begin(); it != fReports.end(); it++) {
        ReportsSet reports = it->second;
        RSSIValues rssiVals;
        int16_t totalRSSI = 0;
        bool saturated = true;

        if (reports.size() == 0) {
            continue;
        }

        memset(&rssiVals, 127, sizeof(RSSIValues));

        // Use the first report for the service data.
        const LeAdvertisementData::ServiceDataMap &svcData = (*reports.begin())->getServiceData();

        double timestamp = (*reports.begin())->getTimestamp() + kCFAbsoluteTimeIntervalSince1970;
        uint8_t validRSSICount = 0;

        rssiVals.maxRSSI = -127;
        for (const LeAdvertisementData::AutoPtr &aReport : reports) {
            int8_t rssi = aReport->getRSSI();
            if (rssi != 127) {
                saturated &= aReport->getIsSaturated();
                validRSSICount++;
                totalRSSI += rssi;
                rssiVals.maxRSSI = MAX(rssiVals.maxRSSI, rssi);
                EN_DEBUG_PRINTF("%d) rssi:%d saturated:%d", validRSSICount, rssi, aReport->getIsSaturated());
            } else {
                EN_ERROR_PRINTF("Report with invalid RSSI found (127)");
            }
        }

        // If all of the reports are saturated, reflect that in our callback.
        if (validRSSICount == 0) {
            saturated = true;
            rssiVals.maxRSSI = 127;
        } else {
            rssiVals.avgRSSI = totalRSSI / validRSSICount;
        }

        const ByteBuffer svcDataBuffer = svcData.at(LE_ExposureNotification_Service_UUID);
        NSData *rpi = [NSData dataWithBytes:svcDataBuffer.getData() length:EN_RPI_LEN];
        NSData *encryptedAEM = [NSData dataWithBytes:svcDataBuffer.getData() + EN_RPI_LEN length:EN_AEM_LEN];

        EN_INFO_PRINTF("rpi:%@ aem:%@ avgRSSI:%d maxRSSI:%d saturated:%d timestamp:%f deltaSinceLastStop:%d reports:%lu validReports:%d", rpi, encryptedAEM, rssiVals.avgRSSI, rssiVals.maxRSSI, saturated, timestamp, delta, reports.size(), validRSSICount);

        uint8_t reportCounter = reports.size() > 255 ? 255 : reports.size(); // report up to 255 reports, make sure we dont overflow;

        // Save observation to database
        (void) rpi;
        (void) encryptedAEM;
        (void) reportCounter;
        (void) timestamp;
        // database->saveObservation(rpi, encryptedAEM, rssiVals, reportCounter, saturated, timestamp, delta);
    }

    fReports.clear();
}

#pragma mark - Exposure Notification Advertising

BTResult ExposureNotificationManager::retrieveCurrentRollingProximityIdentifier(uint8_t *outBuffer, size_t outBufferSize)
{
    if (outBufferSize != EN_RPI_LEN) {
        return BT_ERROR_INVALID_ARGUMENT;
    }

    // Populate outBuffer with the current rolling proximity identifier

    return BT_SUCCESS;
}

BTResult ExposureNotificationManager::retrieveCurrentTemporaryExposureKey(uint8_t *outBuffer, size_t outBufferSize)
{
    if (outBufferSize != EN_TEK_LEN) {
        return BT_ERROR_INVALID_ARGUMENT;
    }

    // Populate outBuffer with the current temporary exposure key

    return BT_SUCCESS;
}

uint8_t ExposureNotificationManager::getPlatformRadiatedLeTxPower()
{
    // Retrieve the Tx Power of the current platform from the Bluetooth Stack
    return 0;
}

BTResult ExposureNotificationManager::generateAdvertisingPayload(uint8_t *payloadBytes, uint8_t payloadBytesLen, BTAddress &advertisingAddress)
{
    if (payloadBytesLen != (EN_AEM_LEN + EN_RPI_LEN) || payloadBytes == NULL) {
        EN_ERROR_PRINTF("generateAdvertisingPayload payloadBytesLen:%d or payloadBytes is NULL", payloadBytesLen);
        return BT_ERROR_INVALID_ARGUMENT;
    }

    uint8_t currentRPI[EN_RPI_LEN] = {0};
    BTResult result = retrieveCurrentRollingProximityIdentifier(currentRPI, EN_RPI_LEN);
    if (result != BT_SUCCESS) {
        return result;
    }

    uint8_t currentTEK[EN_TEK_LEN] = {0};
    result = retrieveCurrentTemporaryExposureKey(currentTEK, EN_TEK_LEN);
    if (result != BT_SUCCESS) {
        return result;
    }

    /*
     AEM[0] Byte: 1-byte Version and Flags
     Bit 7:6 Major Version: 01
     Bit 5:4 Minor Version: 00
     Bit 3: RFU
     Bit 2: RFU
     Bit 1: RFU
     Bit 0: RFU
     AEM[1] Byte: 1-byte Tx Power
     AEM[2] Byte: RFU
     AEM[3] Byte: RFU
     */
    uint8_t aem[4] = {0};
    aem[0] = (EN_VERSION_MAJOR << 6) | (EN_VERSION_MINOR << 4);
    aem[1] = getPlatformRadiatedLeTxPower();
    result = ENEncryptAEM(aem, EN_AEM_LEN, currentTEK, EN_TEK_LEN, payloadBytes, EN_RPI_LEN, payloadBytes + EN_RPI_LEN, EN_AEM_LEN);
    EN_NOTICE_PRINTF("Payload is now %{private}.20P TXPower:%d version:0x%x", payloadBytes, aem[1], aem[0]);

    return result;
}

}
