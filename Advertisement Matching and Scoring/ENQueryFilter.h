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

NS_ASSUME_NONNULL_BEGIN

@interface ENQueryFilter : NSObject

/*
 *  The size in bytes of the underlying filter buffer. The
 *  buffer is bitmapped, so there will be 8 * bufferSize slots.
 */
@property (nonatomic, readonly) NSUInteger bufferSize;

/*
 *  The number of hashes (and therefore number of bits to be
 *  set in the filter buffer) for each provided RPI.
 */
@property (nonatomic, readonly) NSUInteger hashCount;

/*
 *  This filter is a bloom filter implementation designed to first pass
 *  filter the RPI payloads checked against the EN SQLite database. For
 *  each possible RPI added, a set of hashes will be computed (count is
 *  dictated by hashCount). Each of these hashes will then be modulo mapped
 *  to a bit in the buffer. For an RPI to be possible, it must have all bits
 *  set upon querying the buffer using the same hash function.
 *
 *  Arguments:
 *     size: Size of the internal bitmap buffer in bytes
 *     hashCount: Number of hashes / bits set per RPI
 */
- (instancetype)initWithBufferSize:(NSUInteger)size hashCount:(NSUInteger)hashCount;

/*
 *  Add an RPI contained in the local database to the filter. This will set
 *  one or more bits in the RPI buffer. RPI is assumed to be 16 bytes.
 */
- (void)addPossibleRPI:(const void *)rpi;

/*
 *  Is the provided RPI NOT in the local RPI database. RPI is
 *  assumed to be 16 bytes.
 */
- (BOOL)shouldIgnoreRPI:(const void *)rpi;

@end

NS_ASSUME_NONNULL_END
