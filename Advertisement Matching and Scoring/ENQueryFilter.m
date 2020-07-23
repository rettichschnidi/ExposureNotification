/*
 *      Copyright (C) 2020 Apple Inc. All Rights Reserved.
 *
 *      ExposureNotification is licensed under Apple Inc.’s
 *      Sample Code License Agreement, which is contained in
 *      the LICENSE file distributed with ExposureNotification,
 *      and only to those who accept that license.
 *
 */

#import <ExposureNotification/ExposureNotification.h>
#import "ENQueryFilter.h"
#import "ENShims.h"

#define DEFAULT_QUERY_FILTER_BUFFER_SIZE (1 * 1024 * 1024)
#define DEFAULT_QUERY_FILTER_HASH_COUNT (3)

uint64_t indexForRPI(const void *rpi, uint64_t salt, uint64_t bufferSize)
{
    uint64_t *rpiHalf = (uint64_t *) rpi;
    uint64_t hash = rpiHalf[0] ^ rpiHalf[1] ^ salt;
    uint64_t index = hash % (bufferSize);
    return index;
}

@implementation ENQueryFilter {
    char *_filterBuffer;
    uint64_t *_hashSalts;
}

- (instancetype)init
{
    return [self initWithBufferSize:DEFAULT_QUERY_FILTER_BUFFER_SIZE hashCount:DEFAULT_QUERY_FILTER_HASH_COUNT];
}

- (instancetype)initWithBufferSize:(NSUInteger)size hashCount:(NSUInteger)hashCount
{
    EN_NOTICE_PRINTF("Initializing ENQueryFilter bufferSize:%d hashCount:%d", (int) size, (int) hashCount);

    if (self = [super init]) {
        _bufferSize = size;
        _filterBuffer = (char *) calloc(_bufferSize, 1);
        if (!_filterBuffer) {
            EN_ERROR_PRINTF("Failed to allocate query filter buffer");
            return nil;
        }

        _hashCount = hashCount;
        _hashSalts = (uint64_t *) malloc(_hashCount * sizeof(uint64_t));
        if (!_hashSalts) {
            EN_ERROR_PRINTF("Failed to allocate query filter salt buffer");
            return nil;
        }

        for (int i = 0; i < _hashCount; i++) {
            _hashSalts[i] = random();
        }
    }
    return self;
}

- (void)dealloc
{
    free(_filterBuffer);
    free(_hashSalts);
}

- (void)addPossibleRPI:(const void *)rpi
{
    for (int i = 0; i < _hashCount; i++) {
        uint64_t index = indexForRPI(rpi, _hashSalts[i], _bufferSize * 8);
        uint64_t byteIndex = index / 8;
        uint8_t bitIndex = index % 8;

        _filterBuffer[byteIndex] |= (0x01 << bitIndex);
    }
}

- (BOOL)shouldIgnoreRPI:(const void *)rpi
{
    for (int i = 0; i < _hashCount; i++) {
        uint64_t index = indexForRPI(rpi, _hashSalts[i], _bufferSize * 8);
        uint64_t byteIndex = index / 8;
        uint8_t bitIndex = index % 8;

        if (!(_filterBuffer[byteIndex] & (0x01 << bitIndex))) {
            return YES;
        }
    }
    return NO;
}

@end
