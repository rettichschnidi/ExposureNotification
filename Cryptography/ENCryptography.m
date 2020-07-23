/*
 *      Copyright (C) 2020 Apple Inc. All Rights Reserved.
 *
 *      ExposureNotification is licensed under Apple Inc.’s
 *      Sample Code License Agreement, which is contained in
 *      the LICENSE file distributed with ExposureNotification,
 *      and only to those who accept that license.
 *
 */

#import <CommonCrypto/CommonRandom.h>

#import <corecrypto/ccaes.h>
#import <corecrypto/ccmode.h>
#import <corecrypto/cchkdf.h>

#import "ENCryptography.h"
#import "ENShims.h"

NS_ASSUME_NONNULL_BEGIN

BTResult ENGenerateTEK(uint8_t *tekBytes, size_t tekLen)
{
    if (tekBytes == NULL || tekLen != EN_TEK_LEN) {
        return BT_ERROR_INVALID_ARGUMENT;
    }
    CCRNGStatus status = CCRandomGenerateBytes(tekBytes, EN_TEK_LEN);
    return (status == kCCSuccess) ? BT_SUCCESS : BT_ERROR;
}

BTResult ENGenerateRPIK(uint8_t *tekBytes, size_t tekLen, uint8_t *outRPIK, size_t outRPIKLen)
{
    if (tekBytes == NULL || tekLen != EN_TEK_LEN || outRPIK == NULL || outRPIKLen != EN_RPIK_LEN) {
        return BT_ERROR_INVALID_ARGUMENT;
    }

    memset(outRPIK, 0, outRPIKLen);
    uint8_t rpikData[] = {'E', 'N', '-', 'R', 'P', 'I', 'K'};
    int error = cchkdf(ccsha256_di(), tekLen, tekBytes, 0, NULL, sizeof(rpikData), rpikData, outRPIKLen, outRPIK);
    if (error) {
        EN_ERROR_PRINTF("cchkdf failed with error %d", error);
        return BT_ERROR_CRYPTO_HKDF_FAILED;
    }
    return BT_SUCCESS;
}

BTResult ENGenerateRollingProximityIdentifier(uint8_t *tekBytes, uint8_t tekBytesLen,
                                              uint8_t *rpik, size_t rpikLen,
                                              uint32_t intervalNumber, uint8_t *outBuffer, size_t outBufferSize)
{
    if (outBuffer == NULL || outBufferSize != EN_RPI_LEN) {
        return BT_ERROR_INVALID_ARGUMENT;
    }

    uint8_t _rpik[EN_RPIK_LEN] = {0};
    char paddedData[] = {'E', 'N', '-', 'R', 'P', 'I' , 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00};
    memcpy((void*) (paddedData + (sizeof(paddedData) - sizeof(intervalNumber))), &intervalNumber, sizeof(intervalNumber));

    if (rpik == NULL) {
        BTResult result = ENGenerateRPIK(tekBytes, tekBytesLen, _rpik, sizeof(_rpik));
        if (result != BT_SUCCESS) {
            EN_ERROR_PRINTF("ENGenerateRPIK failed %d", result);
            return result;
        }
    }

    int error = ccecb_one_shot(ccaes_ecb_encrypt_mode(), 16, (rpik ? rpik : _rpik), 1, paddedData, outBuffer);
    if (error) {
        EN_ERROR_PRINTF("ccecb_one_shot failed with error %d", error);
        return BT_ERROR_CRYPTO_AES_FAILED;
    }

    return BT_SUCCESS;

}

BTResult ENGenerate144RollingProximityIdentifiers(uint8_t *tekBytes, uint8_t tekBytesLen, uint32_t intervalNumber, uint8_t *outBuffer, size_t outBufferSize)
{
    if (outBuffer == NULL || outBufferSize < (EN_RPI_LEN * 144)) {
        return BT_ERROR_INVALID_ARGUMENT;
    }
    uint8_t rpik[EN_RPIK_LEN] = {0};
    BTResult result = BT_SUCCESS;

    result = ENGenerateRPIK(tekBytes, tekBytesLen, rpik, sizeof(rpik));
    if (result != BT_SUCCESS) {
        EN_ERROR_PRINTF("ENGenerateRPIK failed %d", result);
        return result;
    }

    uint8_t paddedDataBuffer[144 * 16] = {0};
    char paddedData[] = {'E', 'N', '-', 'R', 'P', 'I' , 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00};

    for (uint8_t i = 0; i < 144; i++) {
        uint8_t *p = paddedDataBuffer + (i * 16);
        memcpy(p, paddedData, 16);
        p += 16 - sizeof(intervalNumber);
        uint32_t rpiIntervalNumber = intervalNumber + i;
        memcpy((void *) p, &rpiIntervalNumber, sizeof(rpiIntervalNumber));
    }

    int error = ccecb_one_shot(ccaes_ecb_encrypt_mode(), 16, rpik, 144, paddedDataBuffer, outBuffer);
    if (error) {
        EN_ERROR_PRINTF("ccecb_one_shot failed with error %d", error);
        result = BT_ERROR_CRYPTO_AES_FAILED;
    }
    return result;
}

BTResult ENGenerateAEMK(uint8_t *tek, size_t tekLen, uint8_t *outAEMK, size_t outAEMKLen)
{
    if (outAEMK == NULL || outAEMKLen != EN_AEMK_LEN || tek == NULL || tekLen != EN_TEK_LEN) {
        return BT_ERROR_INVALID_ARGUMENT;
    }
    memset(outAEMK, 0, outAEMKLen);

    char info[EN_AEMK_INFO_LEN] = {'E', 'N', '-', 'A', 'E', 'M', 'K'};
    int error = cchkdf(ccsha256_di(), tekLen, tek, 0, NULL, sizeof(info), info, outAEMKLen, outAEMK);

    if (error) {
        EN_ERROR_PRINTF("cchkdf failed with error %d", error);
        return BT_ERROR_CRYPTO_HKDF_FAILED;
    }

    return BT_SUCCESS;
}

#pragma mark - AEM Encryption / Decryption

BTResult ENEncryptAEM(uint8_t *metaData, size_t metaDataLen, uint8_t *tek, size_t tekSize,
                      uint8_t *rpi, uint8_t rpiLen, uint8_t *outEncryptedMetaData, size_t outEncryptedMetaDataLen)
{
    uint8_t aemk[EN_AEMK_LEN] = {0};

    if (metaData == NULL || rpi == NULL || outEncryptedMetaData == NULL || outEncryptedMetaDataLen != EN_AEM_LEN ||
        rpiLen != EN_RPI_LEN || metaDataLen != outEncryptedMetaDataLen || !tek) {
        return BT_ERROR_INVALID_ARGUMENT;
    }

    BTResult result = ENGenerateAEMK(tek, EN_TEK_LEN, aemk, EN_AEMK_LEN);
    if (result != BT_SUCCESS) {
        EN_ERROR_PRINTF("encryptAEM ENGenerateAEMK failed %d", result);
        return result;
    }

    const struct ccmode_ctr *ctrMode = ccaes_ctr_crypt_mode();
    int error = ccctr_one_shot(ctrMode, EN_AEMK_LEN, aemk, rpi, metaDataLen, metaData, outEncryptedMetaData);
    if (error) {
        EN_ERROR_PRINTF("encryptAEM ccctr_one_shot failed with error: %d", error);
        return BT_ERROR_CRYPTO_AES_FAILED;
    }

    return BT_SUCCESS;
}

BTResult ENDecryptAEM(uint8_t *encryptedData, size_t dataLen, uint8_t *tek, size_t tekLen, uint8_t *rpi, uint8_t rpiLen, uint8_t *outMetaData, size_t outMedataDataLen)
{
    uint8_t aemk[EN_AEMK_LEN] = {0};

    if (encryptedData == NULL || rpi == NULL || outMetaData == NULL || rpiLen != EN_RPI_LEN ||
        outMedataDataLen != EN_AEM_LEN || dataLen != EN_AEM_LEN) {
        return BT_ERROR_INVALID_ARGUMENT;
    }

    BTResult result = ENGenerateAEMK(tek, tekLen, aemk, EN_AEMK_LEN);
    if (result != BT_SUCCESS) {
        EN_ERROR_PRINTF("decryptAEM ENGenerateAEMK failed %d", result);
        return result;
    }

    const struct ccmode_ctr *ctrMode = ccaes_ctr_crypt_mode();
    int error = ccctr_one_shot(ctrMode, EN_AEMK_LEN, aemk, rpi, dataLen, encryptedData, outMetaData);
    if (error) {
        EN_ERROR_PRINTF("decryptAEM ccctr_one_shot failed with error:%d", error);
        return BT_ERROR_CRYPTO_AES_FAILED;
    }

    return BT_SUCCESS;
}

BTResult ENRetrieveTxPowerFromEncryptedAEM(uint8_t *encryptedAEM, size_t encryptedAEMLen, uint8_t *tek, size_t tekLen, uint8_t *rpi, uint8_t rpiLen, int8_t *outTxPower)
{
    uint8_t aem[EN_AEM_LEN] = {0};
    BTResult result = ENDecryptAEM(encryptedAEM, encryptedAEMLen, tek, tekLen, rpi, rpiLen, aem, EN_AEM_LEN);
    if (result == BT_SUCCESS) {
         *outTxPower = aem[1];
    }
    return result;
}

uint8_t ENCalculateAttnForDiscoveredRPI(uint8_t *tek, size_t tekLen, uint8_t *rpi, uint8_t rpiLen, uint8_t *aem, uint8_t aemLen, int8_t rssi, bool saturated)
{
    int8_t txPower;
    BTResult result = ENRetrieveTxPowerFromEncryptedAEM(aem, aemLen, tek, tekLen, rpi, rpiLen, &txPower);
    EN_INFO_PRINTF("calculateAttnForDiscoveredRPI Decrypted payload TXPower:%d rssi:%d saturated:%d tek:%{private}.16P rpi:%{private}.16P result:%d", txPower, rssi, saturated, tek, rpi, result);

    if (result != BT_SUCCESS) {
        EN_ERROR_PRINTF("calculateAttnForDiscoveredRPI retrieveTxPowerFromEncryptedEAM failed with error:%d returning attn=0xFF", result);
        return 0xFF;
    }

    if (rssi == 127 && saturated) {
        EN_ERROR_PRINTF("calculateAttnForDiscoveredRPI saturated RSSI level");
        return 0;
    }

    int16_t attn = txPower - rssi;
    EN_INFO_PRINTF("calculateAttnForDiscoveredRPI attn:%d", attn);
    if (attn < 0) {
        EN_ERROR_PRINTF("calculateAttnForDiscoveredRPI returning 0 txPower:%d rssi:%d attn:%d AEM:%.4P", txPower, rssi, attn, aem);
        return 0;
    }

    return attn;
}

NS_ASSUME_NONNULL_END
