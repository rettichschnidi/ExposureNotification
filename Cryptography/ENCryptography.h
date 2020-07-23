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
#import <stdint.h>

#import "ENShims.h"

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

#define EN_TEK_LEN          (16)
#define EN_RPI_LEN          (16)
#define EN_AEMK_LEN         (16)
#define EN_RPIK_LEN         (16)
#define EN_AEM_LEN          (4)
#define EN_AEMK_INFO_LEN    (7)
#define EN_RPIK_INFO_LEN    (7)

/*
 *  Generate a new Temporary Exposure Key. The Temporary Exposure Key
 *  should be 16 bytes of cyrptographically random data.
 */
BTResult ENGenerateTEK(uint8_t *tekBytes, size_t tekLen);

/*
 *  Derive the Rolling Proximity Identifier Key (RPIK) for the provided TEK.
 *  The RPIK is deterministically generated per-TEK, and is used in the diversification
 *  of a given TEK into the corresponding Rolling Proximity Identifiers.
 *
 *  The RPIK is generated as follows:
 *      RPIK(i) ← HKDF(tek(i), NULL, UTF8("EN-RPIK"), 16)
 *
 *  Where:
 *      HKDF designates the HKDF function as defined by IETF RFC 5869, using the SHA-256 hash function.
 */
BTResult ENGenerateRPIK(uint8_t *tekBytes, size_t tekLen, uint8_t *outRPIK, size_t outRPIKLen);

/*
 *  Generate a single Rolling Proximity Identifier for a specificed TEK, RPIK, and Interval Number.
 *  If the provided rpik pointer is NULL, and RPIK will be derived for the provided TEK.
 *
 *  The RPI is generated as follows:
 *      RPI(i,j) ← AES128(RPIK(i), PaddedData(j))
 *
 *  Where:
 *      j is the Unix Epoch Time at the moment the roll occurs
 *      ENIN(j) ← ENIntervalNumber(j)
 *      PaddedData is the following sequence of 16 bytes:
 *          PaddedDataj[0...5] = UTF8("EN-RPI")
 *          PaddedDataj[6...11] = 0x000000000000
 *          PaddedDataj[12...15] = ENIN(j)
 */
BTResult ENGenerateRollingProximityIdentifier(uint8_t *tekBytes, uint8_t tekBytesLen,
                                              uint8_t *rpik, size_t rpikLen,
                                              uint32_t intervalNumber, uint8_t *outBuffer, size_t outBufferSize);

/*
 *  Generate 144 Rolling Proximity Identifiers for the given TEK, starting with the specified
 *  interval number. Generating 144 RPIs at a time is significantly more efficent than 144 calls
 *  to the above function, as the hardware acclerated AES can diversify all 144 keys with a single
 *  call.
 */
BTResult ENGenerate144RollingProximityIdentifiers(uint8_t *tekBytes, uint8_t tekBytesLen, uint32_t intervalNumber,
                                                  uint8_t *outBuffer, size_t outBufferSize);

/*
 *  Generate the Associated Encrypted Metadata Key for a given TEK.
 *  The AMEK is deterministically generated per-TEK, and is used in the encryption
 *  and decryption of the metadata included in the ExposureNotification bluetooth packet.
 *
 *  Where:
 *      AEMK(i) ← HKDF(tek(i), NULL, UTF8("EN-AEMK"), 16)
 */
BTResult ENGenerateAEMK(uint8_t *tek, size_t tekLen, uint8_t *outAEMK, size_t outAEMKLen);

/*
 *  Encrypt the provided metadata with the specified TEK and RPI. The correct AEMK will
 *  be derived for the provided TEK and used in the encryption of the metadata.
 *
 *  Where:
 *      AssociatedEncryptedMetadata(i, j) ← AES128−CTR(AEMK(i), RPI(i, j), Metadata)
 */
BTResult ENEncryptAEM(uint8_t *metaData, size_t metaDataLen, uint8_t *tek, size_t tekSize,
                      uint8_t *rpi, uint8_t rpiLen, uint8_t *outEncryptedMetaData, size_t outEncryptedMetaDataLen);

/*
 *  Dencrypt the provided metadata with the specified TEK and RPI. The correct AEMK will
 *  be derived for the provided TEK and used in the decryption of the metadata.
 */
BTResult ENDecryptAEM(uint8_t *encryptedData, size_t dataLen, uint8_t *tek, size_t tekLen, uint8_t *rpi, uint8_t rpiLen, uint8_t *outMetaData, size_t outMedataDataLen);

/*
 *  Retrieve the Bluetooth transmission power from the provided encrypted AEM. The AEM
 *  will be decrypted with the provided TEK and RPI.
 */
BTResult ENRetrieveTxPowerFromEncryptedAEM(uint8_t *encryptedAEM, size_t encryptedAEMLen,
                                           uint8_t *tek, size_t tekLen, uint8_t *rpi, uint8_t rpiLen,
                                           int8_t *outTxPower);

/*
 *  Calculate the normalized attenuation for an observed ExposureNotification advertisement.
 *  The attenuation value returned will be one of the following values:
 *      0    : saturated RSSI does not allow calculation
 *      >0   : calculated attentuation
 *      0xFF : could not decrypt AEM with given RPI, inalid inputs.
 */
uint8_t ENCalculateAttnForDiscoveredRPI(uint8_t *tek, size_t tekLen, uint8_t *rpi, uint8_t rpiLen,
                                        uint8_t *aem, uint8_t aemLen, int8_t rssi, bool saturated);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
