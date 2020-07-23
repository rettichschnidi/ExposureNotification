/*
 *      Copyright (C) 2020 Apple Inc. All Rights Reserved.
 *
 *      ExposureNotification is licensed under Apple Inc.’s
 *      Sample Code License Agreement, which is contained in
 *      the LICENSE file distributed with ExposureNotification,
 *      and only to those who accept that license.
 *
 */

#import <sqlite3.h>

#import "ENAdvertisement_Private.h"
#import "ENAdvertisementSQLiteStore.h"
#import "en_sqlite_rpi_buffer.h"
#import "ENShims.h"

#pragma mark - Definitions

#define MAX_TEMPORARY_STORES (10)
#define CENTRAL_STORE_FILENAME "en_advertisements.db"
#define ADVERTISEMENT_TABLE_NAME "en_advertisements"

NSString *const ENAdvertisementStoreErrorDomain = @"ENAdvertisementStoreErrorDomain";

typedef NS_ENUM(NSUInteger, ENAdvertisementDatabaseColumn) {
    ENAdvertisementDatabaseColumnRPI,
    ENAdvertisementDatabaseColumnEncryptedAEM,
    ENAdvertisementDatabaseColumnTimestamp,
    ENAdvertisementDatabaseColumnScanInterval,
    ENAdvertisementDatabaseColumnRSSI,
    ENAdvertisementDatabaseColumnSaturated,
    ENAdvertisementDatabaseColumnCounter,
    ENAdvertisementDatabaseColumnDailyTracingKeyIndex,
    ENAdvertisementDatabaseColumnRPIIndex,
    ENAdvertisementDatabaseColumnCount
};

typedef NS_ENUM(NSUInteger, ENAdvertisementDatabaseStatementType) {
    ENAdvertisementDatabaseStatementTypeRowCount,
    ENAdvertisementDatabaseStatementTypeList,
    ENAdvertisementDatabaseStatementTypeQuery,
    ENAdvertisementDatabaseStatementTypeCount
};

typedef void (^ENPreparedStatementEnumerationCallback)(sqlite3_stmt *statement, ENAdvertisementDatabaseStatementType type);
typedef BOOL (^ENAdvertisementEnumerationCallback)(en_advertisement_t advertisement);

@interface ENAdvertisementSQLiteStore ()

@property (nonatomic, strong) NSString *databasePath;

@end

@implementation ENAdvertisementSQLiteStore {
    sqlite3 *_database;
    sqlite3_stmt **_preparedStatements;
}

#pragma mark - Initialization

+ (instancetype)centralStoreInFolderPath:(NSString *)folderPath
{
    NSString *databasePath = [folderPath stringByAppendingPathComponent:@CENTRAL_STORE_FILENAME];
    return [[ENAdvertisementSQLiteStore alloc] initWithPath:databasePath];
}

- (instancetype)initWithPath:(NSString *)path
{
    if (self = [super init]) {
        _databasePath = path;
        if (![self connectToDatabase]) {
            return nil;
        }
    }
    return self;
}

- (void)dealloc
{
    if (_database) {
        [self disconnectFromDatabase];
    }
}

#pragma mark - Database Initialization

+ (NSString *)statementStringForStatementType:(ENAdvertisementDatabaseStatementType)statement
{
    switch (statement) {
        case ENAdvertisementDatabaseStatementTypeRowCount:
            return @"SELECT COUNT(*) FROM " ADVERTISEMENT_TABLE_NAME ";";

        case ENAdvertisementDatabaseStatementTypeList:
            return @"SELECT * FROM " ADVERTISEMENT_TABLE_NAME ";";

        case ENAdvertisementDatabaseStatementTypeQuery:
            return @"SELECT " ADVERTISEMENT_TABLE_NAME ".*, rpi_buffer.daily_tracing_key_index, rpi_buffer.rpi_index "
            "FROM " ADVERTISEMENT_TABLE_NAME ", en_sqlite_rpi_buffer(?1, ?2, ?3, ?4) AS rpi_buffer "
            "WHERE " ADVERTISEMENT_TABLE_NAME ".rpi=rpi_buffer.rpi;";

        default:
            return nil;
    }
}

- (BOOL)connectToDatabase
{
    const char *path = [_databasePath UTF8String];
    EN_NOTICE_PRINTF("Initializing. exposureNotificationDatabasePath: %s", path);

    // attempt to open the database
    int result = [self openDatabase];
    if (result != SQLITE_OK) {
        EN_ERROR_PRINTF("Failed to open. exposureNotificationDatabasePath: %s", path);
    }

    // attempt to intialize the advertisement table
    if (result == SQLITE_OK) {
        result = [self initializeAdvertisementTable];
        if (result != SQLITE_OK) {
            EN_ERROR_PRINTF("Failed to initialize advertisement table. exposureNotificationDatabasePath: %s", path);
        }
    }

    // attempt to intialize the ct_sqlite_rpi_buffer module
    if (result == SQLITE_OK) {
        result = [self initializeRPIBufferModule];
        if (result != SQLITE_OK) {
            EN_ERROR_PRINTF("Failed to initializeRPIBufferModule. exposureNotificationDatabasePath: %s", path);
        }
    }

    // attempt to intialize the prepared statements
    if (result == SQLITE_OK) {
        result = [self initializePreparedStatements];
        if (result != SQLITE_OK) {
            EN_ERROR_PRINTF("Failed to initializePreparedStatements. exposureNotificationDatabasePath: %s", path);
        }
    }

    // query the initial row count
    if (result == SQLITE_OK) {
        NSError *countQueryError = nil;
        if (![self refreshStoredAdvertisementCountWithError:&countQueryError]) {
            result = SQLITE_ERROR;
            EN_ERROR_PRINTF("Failed to refresh stored advertisement count. exposureNotificationDatabasePath: %s", path);
        }
    }

    // clean up if anything failed
    if (result != SQLITE_OK) {
        // Failed to open database
        EN_ERROR_PRINTF("Failed to initialize exposureNotificationDatabasePath: %s", path);
        return NO;
    }

    return YES;
}

- (int)openDatabase
{
    // Configure our database connection
    int flags = SQLITE_OPEN_CREATE
                | SQLITE_OPEN_READWRITE
                | SQLITE_OPEN_FILEPROTECTION_COMPLETEUNLESSOPEN;
    return sqlite3_open_v2([_databasePath UTF8String], &_database, flags, NULL);
}

- (int)closeDatabase
{
    int result = SQLITE_ERROR;
    if (_database) {
        result = sqlite3_close(_database);
        if (result == SQLITE_OK) {
            _database = NULL;
        } else {
            EN_ERROR_PRINTF("Failed to close exposure notification database path: %s", [_databasePath UTF8String]);
        }
    } else {
        EN_ERROR_PRINTF("Attempt to close null exposure notification database handle");
    }

    return result;
}

- (void)disconnectFromDatabase
{
    [self enumeratePreparedStatements:^(sqlite3_stmt *statement, ENAdvertisementDatabaseStatementType __unused type) {
        sqlite3_finalize(statement);
    }];
    free(_preparedStatements);
    _preparedStatements = NULL;
    [self closeDatabase];
}

- (int)initializeAdvertisementTable
{
    NSString *createTableStatement = @"CREATE TABLE IF NOT EXISTS " ADVERTISEMENT_TABLE_NAME
                                      "(rpi BLOB, "
                                      "encrypted_aem BLOB, "
                                      "timestamp INTEGER, "
                                      "scan_interval INTEGER, "
                                      "rssi INTEGER, "
                                      "saturated BOOLEAN, "
                                      "counter INTEGER, "
                                      "PRIMARY KEY(rpi, timestamp)) "
                                      "WITHOUT ROWID;";
    int result = sqlite3_exec(_database, [createTableStatement UTF8String], NULL, NULL, NULL);
    if (result != SQLITE_OK) {
        EN_ERROR_PRINTF("Failed to create tables with error %d (%s, %d)", result, sqlite3_errmsg(_database), sqlite3_extended_errcode(_database));
    }

    if (result == SQLITE_OK) {
        NSString *createIndexStatement = @"CREATE INDEX IF NOT EXISTS timestamp ON " ADVERTISEMENT_TABLE_NAME "(timestamp);";
        result = sqlite3_exec(_database, [createIndexStatement UTF8String], NULL, NULL, NULL);
        if (result != SQLITE_OK) {
            EN_ERROR_PRINTF("Failed to create timestamp index with error %d (%s, %d)", result, sqlite3_errmsg(_database), sqlite3_extended_errcode(_database));
        }
    }
    return result;
}

- (int)initializeRPIBufferModule
{
    int result = en_sqlite_rpi_buffer_init(_database);
    if (result != SQLITE_OK) {
        EN_ERROR_PRINTF("Failed to initialize en_sqlite_rpi_buffer module with error %d (%s, %d)", result, sqlite3_errmsg(_database), sqlite3_extended_errcode(_database));
    }
    return result;
}

- (int)initializePreparedStatements
{
    int result = SQLITE_OK;

    _preparedStatements = (sqlite3_stmt **) malloc(sizeof(sqlite3_stmt*) * ENAdvertisementDatabaseStatementTypeCount);
    if (!_preparedStatements) {
        EN_ERROR_PRINTF("Failed to allocated prepared statements buffer");
        result = SQLITE_NOMEM;
    }

    if (result == SQLITE_OK) {
        for (int statementIndex = 0; statementIndex < ENAdvertisementDatabaseStatementTypeCount; statementIndex++) {
            ENAdvertisementDatabaseStatementType statementType = (ENAdvertisementDatabaseStatementType) statementIndex;
            const char *statement = [[[self class] statementStringForStatementType:statementType] UTF8String];
            result = sqlite3_prepare(_database, statement, -1, &_preparedStatements[statementType], NULL);
            if (result != SQLITE_OK) {
                EN_ERROR_PRINTF("Failed to prepare sqlite statement %d (%s, %d)", result, sqlite3_errmsg(_database), sqlite3_extended_errcode(_database));
                free(_preparedStatements);
                _preparedStatements = NULL;
                break;
            }
        }
    }

    return result;
}

- (void)enumeratePreparedStatements:(ENPreparedStatementEnumerationCallback)callback
{
    if (_preparedStatements) {
        for (NSUInteger statementIndex = 0; statementIndex < ENAdvertisementDatabaseStatementTypeCount; statementIndex++) {
            ENAdvertisementDatabaseStatementType statementType = (ENAdvertisementDatabaseStatementType) statementIndex;
            callback(_preparedStatements[statementType], statementType);
        }
    }
}

#pragma mark - Database Helper Methods

+ (NSError *)errorForSQLiteResult:(int)result
{
    switch (result) {
        case SQLITE_ERROR:
            return [NSError errorWithDomain:ENAdvertisementStoreErrorDomain code:ENAdvertisementStoreErrorCodeUnknown userInfo:nil];

        case SQLITE_FULL:
            return [NSError errorWithDomain:ENAdvertisementStoreErrorDomain code:ENAdvertisementStoreErrorCodeFull userInfo:nil];

        case SQLITE_CORRUPT:
        case SQLITE_NOTADB:
            return [NSError errorWithDomain:ENAdvertisementStoreErrorDomain code:ENAdvertisementStoreErrorCodeCorrupt userInfo:nil];

        case SQLITE_IOERR:
            return [NSError errorWithDomain:ENAdvertisementStoreErrorDomain code:ENAdvertisementStoreErrorCodeReopen userInfo:nil];

        case SQLITE_BUSY:
            return [NSError errorWithDomain:ENAdvertisementStoreErrorDomain code:ENAdvertisementStoreErrorCodeBusy userInfo:nil];

        default:
            return nil;
    }
}

- (int)beginDatabaseTransaction
{
    int result = sqlite3_exec(_database, "BEGIN EXCLUSIVE TRANSACTION;", NULL, NULL, NULL);
    if (result != SQLITE_OK) {
        EN_ERROR_PRINTF("Failed to begin transaction with error %d (%s, %d)", result, sqlite3_errmsg(_database), sqlite3_extended_errcode(_database));
    }
    return result;
}

- (int)endDatabaseTransaction
{
    int result = sqlite3_exec(_database, "COMMIT;", NULL, NULL, NULL);
    if (result != SQLITE_OK) {
        EN_ERROR_PRINTF("Failed to commit transaction with error %d (%s, %d)", result, sqlite3_errmsg(_database), sqlite3_extended_errcode(_database));
    }
    return result;
}

- (sqlite3_stmt *)preparedStatementOfType:(ENAdvertisementDatabaseStatementType)statementType
{
    sqlite3_stmt *statement = _preparedStatements[statementType];
    sqlite3_reset(statement);
    return statement;
}

+ (en_advertisement_t)advertisementForSQLiteStatement:(sqlite3_stmt *)statement
{
    en_advertisement_t advertisement = {
        .timestamp = (CFAbsoluteTime) sqlite3_column_int64(statement, ENAdvertisementDatabaseColumnTimestamp),
        .daily_key_index = (uint32_t) sqlite3_column_int64(statement, ENAdvertisementDatabaseColumnDailyTracingKeyIndex),
        .rpi_index = (uint16_t) sqlite3_column_int64(statement, ENAdvertisementDatabaseColumnRPIIndex),
        .scan_interval = (uint16_t) sqlite3_column_int(statement, ENAdvertisementDatabaseColumnScanInterval),
        .rssi = (int8_t) sqlite3_column_int(statement, ENAdvertisementDatabaseColumnRSSI),
        .saturated = (bool) sqlite3_column_int(statement, ENAdvertisementDatabaseColumnSaturated),
        .count = (uint8_t) sqlite3_column_int(statement, ENAdvertisementDatabaseColumnCounter),
    };

    const void *rpi = sqlite3_column_blob(statement, ENAdvertisementDatabaseColumnRPI);
    memcpy(advertisement.rpi, rpi, ENRPILength);

    const void *encryptedAEM = sqlite3_column_blob(statement, ENAdvertisementDatabaseColumnEncryptedAEM);
    memcpy(advertisement.encrypted_aem, encryptedAEM, AEM_LENGTH);

    return advertisement;
}

#pragma mark - Store API

- (BOOL)refreshStoredAdvertisementCountWithError:(NSError * _Nullable __autoreleasing * _Nullable)error
{
    sqlite3_stmt *statement = [self preparedStatementOfType:ENAdvertisementDatabaseStatementTypeRowCount];

    int result = [self beginDatabaseTransaction];

    // execute the query
    if (result == SQLITE_OK) {
        result = sqlite3_step(statement);
        if (result != SQLITE_ROW) {
            EN_ERROR_PRINTF("Failed to execute sqlite count statement %d (%s, %d)", result, sqlite3_errmsg(_database), sqlite3_extended_errcode(_database));
        }
    }

    // store the result or the error
    if (result == SQLITE_ROW) {
        NSUInteger count = sqlite3_column_int(statement, 0);
        _storedAdvertisementCount = @(count);
    } else {
        _storedAdvertisementCount = nil;
        if (error) {
            *error = [[self class] errorForSQLiteResult:result];
        }
    }

    // always end the transaction
    [self endDatabaseTransaction];
    sqlite3_reset(statement);

    return (result == SQLITE_ROW);
}

- (int)enumerateAdvertisements:(ENAdvertisementEnumerationCallback)callback
{
    sqlite3_stmt *statement = [self preparedStatementOfType:ENAdvertisementDatabaseStatementTypeList];

    int result = [self beginDatabaseTransaction];

    if (result == SQLITE_OK) {
        do {
            result = sqlite3_step(statement);
            if (result == SQLITE_ROW) {
                en_advertisement_t advertisement = [[self class] advertisementForSQLiteStatement:statement];
                if (!callback(advertisement)) {
                    break;
                }
            } else if (result == SQLITE_DONE) {
                break;
            } else {
                EN_ERROR_PRINTF("Failed to retreive next advertisement %d (%s, %d)", result, sqlite3_errmsg(_database), sqlite3_extended_errcode(_database));
            }
        } while (result == SQLITE_ROW);
    }

    // always end the transaction
    result = [self endDatabaseTransaction];
    sqlite3_reset(statement);

    return result;
}

- (ENQueryFilter *)queryFilterWithBufferSize:(NSUInteger)bufferSize
                                   hashCount:(NSUInteger)hashCount
                        attenuationThreshold:(uint8_t)attenuationThreshold
{
    ENQueryFilter *filter = [[ENQueryFilter alloc] initWithBufferSize:bufferSize
                                                            hashCount:hashCount];
    int result = [self enumerateAdvertisements:^(en_advertisement_t advertisement) {
        [filter addPossibleRPI:advertisement.rpi];
        return YES;
    }];

    if (result != SQLITE_OK) {
        EN_ERROR_PRINTF("Error creating query filter %d (%s, %d)", result, sqlite3_errmsg(_database), sqlite3_extended_errcode(_database));
        filter = nil;
    }

    return filter;
}

- (int)bindRPIBuffer:(const void *)buffer
               count:(NSUInteger)bufferRPICount
      validityBuffer:(const void *)validityBuffer
       validRPICount:(NSUInteger)validRPICount
   toSQLiteStatement:(sqlite3_stmt *)statement
{
    int result = sqlite3_bind_pointer(statement, 1, (void *) buffer, EN_SQLITE_POINTER_NAME_RPI_BUFFER, SQLITE_STATIC);
    if (result != SQLITE_OK) {
        EN_ERROR_PRINTF("Failed to bind RPI buffer to query statement (%s, %d)", sqlite3_errmsg(_database), sqlite3_extended_errcode(_database));
    }

    if (result == SQLITE_OK) {
        result = sqlite3_bind_pointer(statement, 2, (void *) validityBuffer, EN_SQLITE_POINTER_NAME_VALIDITY_BUFFER, SQLITE_STATIC);
        if (result != SQLITE_OK) {
            EN_ERROR_PRINTF("Failed to bind validity buffer to query statement (%s, %d)", sqlite3_errmsg(_database), sqlite3_extended_errcode(_database));
        }
    }

    if (result == SQLITE_OK) {
        result = sqlite3_bind_int(statement, 3, (int) bufferRPICount);
        if (result != SQLITE_OK) {
            EN_ERROR_PRINTF("Failed to bind RPI buffer count to query statement (%s, %d)", sqlite3_errmsg(_database), sqlite3_extended_errcode(_database));
        }
    }

    if (result == SQLITE_OK) {
        result = sqlite3_bind_int(statement, 4, (int) validRPICount);
        if (result != SQLITE_OK) {
            EN_ERROR_PRINTF("Failed to bind valid RPI count to query statement (%s, %d)", sqlite3_errmsg(_database), sqlite3_extended_errcode(_database));
        }
    }

    return result;
}

- (NSUInteger)getAdvertisementsMatchingRPIBuffer:(const void *)buffer
                                           count:(NSUInteger)bufferRPICount
                                  validityBuffer:(const void *)validityBuffer
                                   validRPICount:(NSUInteger)validRPICount
                     matchingAdvertisementBuffer:(en_advertisement_t *_Nonnull *_Nullable)matchBufferOut
                                           error:(NSError * _Nullable __autoreleasing * _Nullable)error;
{
    // Ensure we know the maximum buffer size
    if (![self storedAdvertisementCount] && ![self refreshStoredAdvertisementCountWithError:error]) {
        EN_ERROR_PRINTF("Failed to refresh stored advertisement count");
        return 0;
    }

    NSUInteger matchingAdvertisementCount = 0;
    NSUInteger maxAdvertisementMatches = [[self storedAdvertisementCount] unsignedIntValue];

    en_advertisement_t *matchBuffer = (en_advertisement_t *) calloc(maxAdvertisementMatches, sizeof(en_advertisement_t));
    if (!matchBuffer) {
        EN_ERROR_PRINTF("Failed to allocate matchBuffer");
        return 0;
    }

    // bind the buffer to this query
    sqlite3_stmt *statement = [self preparedStatementOfType:ENAdvertisementDatabaseStatementTypeQuery];
    int result = [self bindRPIBuffer:buffer
                               count:bufferRPICount
                      validityBuffer:validityBuffer
                       validRPICount:validRPICount
                   toSQLiteStatement:statement];

    if (result != SQLITE_OK) {
        EN_ERROR_PRINTF("Failed to bind data to sqlite statement (%s, %d)", sqlite3_errmsg(_database), sqlite3_extended_errcode(_database));
    }

    if (result == SQLITE_OK) {
        result = [self beginDatabaseTransaction];
    }

    if (result == SQLITE_OK) {
        // iterate through results until there are no more rows
        do {
            result = sqlite3_step(statement);
            if (result == SQLITE_ROW) {
                if (matchingAdvertisementCount < maxAdvertisementMatches) {
                    // copy the result into the results buffer
                    matchBuffer[matchingAdvertisementCount++] = [[self class] advertisementForSQLiteStatement:statement];
                } else {
                    EN_INFO_PRINTF("dropping match due to full buffer. bufferSize:%d", (int) maxAdvertisementMatches);
                    _storedAdvertisementCount = nil;
                }
            }
        } while (result == SQLITE_ROW);

        if (result != SQLITE_DONE) {
            EN_ERROR_PRINTF("Failed to query matching advertisements %d (%s, %d)", result, sqlite3_errmsg(_database), sqlite3_extended_errcode(_database));
        }
    }

    if (result == SQLITE_DONE) {
        *matchBufferOut = matchBuffer;
    } else {
        free(matchBuffer);
        *matchBufferOut = NULL;
        matchingAdvertisementCount = 0;

        if (error) {
            *error = [[self class] errorForSQLiteResult:result];
        }
    }

    // clean up
    [self endDatabaseTransaction];
    sqlite3_clear_bindings(statement);
    sqlite3_reset(statement);

    return matchingAdvertisementCount;
}

@end
