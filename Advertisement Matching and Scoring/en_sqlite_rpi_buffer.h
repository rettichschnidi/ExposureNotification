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

#include <stdbool.h>
#include <sqlite3.h>

#define EN_SQLITE_POINTER_NAME_RPI_BUFFER "en_sqlite_rpi_buffer"
#define EN_SQLITE_POINTER_NAME_VALIDITY_BUFFER "en_sqlite_rpi_validity_buffer"

int en_sqlite_rpi_buffer_init(sqlite3 *db);
