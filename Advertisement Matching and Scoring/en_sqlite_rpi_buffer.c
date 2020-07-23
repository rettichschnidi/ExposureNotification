/*
 *      Copyright (C) 2020 Apple Inc. All Rights Reserved.
 *
 *      ExposureNotification is licensed under Apple Inc.’s
 *      Sample Code License Agreement, which is contained in
 *      the LICENSE file distributed with ExposureNotification,
 *      and only to those who accept that license.
 *
 */

#include <assert.h>
#include <string.h>

#include "en_sqlite_rpi_buffer.h"

#define ENRPILength         (16)
#define ENTEKRollingPeriod  (144)

/* Column numbers */
#define EN_SQLITE_RPI_BUFFER_COLUMN_RPI                 (0)
#define EN_SQLITE_RPI_BUFFER_COLUMN_RPI_POINTER         (1)
#define EN_SQLITE_RPI_BUFFER_COLUMN_VALIDITY_POINTER    (2)
#define EN_SQLITE_RPI_BUFFER_COLUMN_BUFFER_COUNT        (3)
#define EN_SQLITE_RPI_BUFFER_COLUMN_VALID_COUNT         (4)
#define EN_SQLITE_RPI_BUFFER_COLUMN_DAILY_KEY_INDEX     (5)
#define EN_SQLITE_RPI_BUFFER_COLUMN_RPI_INDEX           (6)

typedef struct {
    sqlite3_vtab_cursor base;                   /* Base class - must be first */
    sqlite3_int64 current_rpi_index;            /* The current row */
    sqlite3_int64 current_rpi_count;            /* The current count of returned RPI values */
    const void *rpi_buffer;                     /* Pointer to the raw RPI buffer */
    const bool *validity_buffer;                /* Pointer to the validity buffer */
    sqlite3_int64 rpi_buffer_count;             /* Number of RPIs in the buffer */
    sqlite3_int64 rpi_valid_count;              /* Number of valid RPIs in the buffer */
} en_sqlite_rpi_buffer_cursor;

static int en_sqlite_rpi_buffer_connect(sqlite3 *db, void *pAux, int argc, const char * const *argv, sqlite3_vtab **ppVtab, char **pzErr)
{
    int rc = sqlite3_declare_vtab(db, "CREATE TABLE x(rpi, rpi_pointer hidden, validity_pointer hidden, buffer_count hidden, valid_count hidden, daily_tracing_key_index, rpi_index)");
    if (rc == SQLITE_OK) {
        sqlite3_vtab *buffer_virtual_table = (sqlite3_vtab *) sqlite3_malloc(sizeof(sqlite3_vtab));
        if (!buffer_virtual_table) {
            return SQLITE_NOMEM;
        }
        memset(buffer_virtual_table, 0, sizeof(sqlite3_vtab));
        *ppVtab = buffer_virtual_table;
    }
    return rc;
}

static int en_sqlite_rpi_buffer_disconnect(sqlite3_vtab *pVtab){
    sqlite3_free(pVtab);
    return SQLITE_OK;
}

static int en_sqlite_rpi_buffer_open(sqlite3_vtab *p, sqlite3_vtab_cursor **ppCursor)
{
    en_sqlite_rpi_buffer_cursor *buffer_cursor = (en_sqlite_rpi_buffer_cursor *) sqlite3_malloc(sizeof(en_sqlite_rpi_buffer_cursor));
    if (!buffer_cursor) {
        return SQLITE_NOMEM;
    }
    memset(buffer_cursor, 0, sizeof(en_sqlite_rpi_buffer_cursor));
    *ppCursor = &buffer_cursor->base;
    return SQLITE_OK;
}

static int en_sqlite_rpi_buffer_close(sqlite3_vtab_cursor *cur)
{
    sqlite3_free(cur);
    return SQLITE_OK;
}

static int en_sqlite_rpi_buffer_next(sqlite3_vtab_cursor *cur)
{
    en_sqlite_rpi_buffer_cursor *buffer_cursor = (en_sqlite_rpi_buffer_cursor *)cur;

    do {
        buffer_cursor->current_rpi_index++;
    } while (buffer_cursor->current_rpi_index < buffer_cursor->rpi_buffer_count
             && !buffer_cursor->validity_buffer[buffer_cursor->current_rpi_index]);

    return SQLITE_OK;
}

static int en_sqlite_rpi_buffer_column(sqlite3_vtab_cursor *cur, sqlite3_context *ctx, int column_index)
{
    en_sqlite_rpi_buffer_cursor *buffer_cursor = (en_sqlite_rpi_buffer_cursor *)cur;
    switch (column_index) {
        case EN_SQLITE_RPI_BUFFER_COLUMN_RPI: {
            char *rpi_buffer = (char *) buffer_cursor->rpi_buffer;
            char *rpi = &rpi_buffer[buffer_cursor->current_rpi_index * ENRPILength];
            sqlite3_result_blob(ctx, rpi, ENRPILength, NULL);
            break;
        }

        case EN_SQLITE_RPI_BUFFER_COLUMN_DAILY_KEY_INDEX: {
            int64_t daily_key_index = buffer_cursor->current_rpi_index / ENTEKRollingPeriod;
            sqlite3_result_int64(ctx, daily_key_index);
            break;
        }

        case EN_SQLITE_RPI_BUFFER_COLUMN_RPI_INDEX: {
            int64_t rpi_index = buffer_cursor->current_rpi_index % ENTEKRollingPeriod;
            sqlite3_result_int64(ctx, rpi_index);
            break;
        }

        case EN_SQLITE_RPI_BUFFER_COLUMN_BUFFER_COUNT:
            sqlite3_result_int64(ctx, buffer_cursor->rpi_buffer_count);
            break;

        case EN_SQLITE_RPI_BUFFER_COLUMN_VALID_COUNT:
            sqlite3_result_int64(ctx, buffer_cursor->rpi_valid_count);
            break;

        case EN_SQLITE_RPI_BUFFER_COLUMN_RPI_POINTER:
        case EN_SQLITE_RPI_BUFFER_COLUMN_VALIDITY_POINTER:
        default:
            // pointer and any other unknown column index should not return anything
            break;
    }
    return SQLITE_OK;
}

static int en_sqlite_rpi_buffer_rowid(sqlite3_vtab_cursor *cur, sqlite_int64 *pRowid){
    en_sqlite_rpi_buffer_cursor *buffer_cursor = (en_sqlite_rpi_buffer_cursor *)cur;
    *pRowid = buffer_cursor->current_rpi_count;
    return SQLITE_OK;
}

static int en_sqlite_rpi_buffer_eof(sqlite3_vtab_cursor *cur){
    en_sqlite_rpi_buffer_cursor *buffer_cursor = (en_sqlite_rpi_buffer_cursor *)cur;
    return buffer_cursor->current_rpi_count >= buffer_cursor->rpi_valid_count || buffer_cursor->current_rpi_index >= buffer_cursor->rpi_buffer_count;
}

static int en_sqlite_rpi_buffer_filter(sqlite3_vtab_cursor *cur, int idxNum, const char *idxStr, int argc, sqlite3_value **argv)
{
    en_sqlite_rpi_buffer_cursor *buffer_cursor = (en_sqlite_rpi_buffer_cursor *)cur;
    if (idxNum) {
        buffer_cursor->rpi_buffer = (const void *) sqlite3_value_pointer(argv[0], EN_SQLITE_POINTER_NAME_RPI_BUFFER);
        buffer_cursor->validity_buffer = (const bool *) sqlite3_value_pointer(argv[1], EN_SQLITE_POINTER_NAME_VALIDITY_BUFFER);
        buffer_cursor->rpi_buffer_count = buffer_cursor->rpi_buffer ? sqlite3_value_int64(argv[2]) : 0;
        buffer_cursor->rpi_valid_count = buffer_cursor->validity_buffer ? sqlite3_value_int64(argv[3]) : 0;
    } else {
        buffer_cursor->rpi_buffer = NULL;
        buffer_cursor->validity_buffer = NULL;
        buffer_cursor->rpi_buffer_count = 0;
        buffer_cursor->rpi_valid_count = 0;
    }
    buffer_cursor->current_rpi_index = 0;
    buffer_cursor->current_rpi_count = 0;
    return SQLITE_OK;
}

static int en_sqlite_rpi_buffer_best_index(sqlite3_vtab *tab, sqlite3_index_info *pIdxInfo)
{
    int indicies[5] = {0};

    struct sqlite3_index_constraint *current_constraint = (struct sqlite3_index_constraint *) pIdxInfo->aConstraint;
    for (int i = 0; i < pIdxInfo->nConstraint; i++, current_constraint++) {
        if (!current_constraint->usable || current_constraint->op != SQLITE_INDEX_CONSTRAINT_EQ) {
            continue;
        }

        switch (current_constraint->iColumn) {
            case EN_SQLITE_RPI_BUFFER_COLUMN_RPI_POINTER:
            case EN_SQLITE_RPI_BUFFER_COLUMN_VALIDITY_POINTER:
            case EN_SQLITE_RPI_BUFFER_COLUMN_BUFFER_COUNT:
            case EN_SQLITE_RPI_BUFFER_COLUMN_VALID_COUNT:
                indicies[current_constraint->iColumn] = i;
                break;
        }
    }

    for (int j = 1; j < 5; j++) {
        pIdxInfo->aConstraintUsage[indicies[j]].argvIndex = j;
        pIdxInfo->aConstraintUsage[indicies[j]].omit = 1;
    }

    pIdxInfo->estimatedCost = (double) 1;
    pIdxInfo->estimatedRows = 100;
    pIdxInfo->idxNum = 4;

    return SQLITE_OK;
}

/*
 ** This following structure defines all the methods for the
 ** en_sqlite_rpi_buffer virtual table.
 */
static sqlite3_module en_sqlite_rpi_buffer_module = {
    0,                                  /* iVersion */
    0,                                  /* xCreate */
    en_sqlite_rpi_buffer_connect,       /* xConnect */
    en_sqlite_rpi_buffer_best_index,    /* xBestIndex */
    en_sqlite_rpi_buffer_disconnect,    /* xDisconnect */
    0,                                  /* xDestroy */
    en_sqlite_rpi_buffer_open,          /* xOpen - open a cursor */
    en_sqlite_rpi_buffer_close,         /* xClose - close a cursor */
    en_sqlite_rpi_buffer_filter,        /* xFilter - configure scan constraints */
    en_sqlite_rpi_buffer_next,          /* xNext - advance a cursor */
    en_sqlite_rpi_buffer_eof,           /* xEof - check for end of scan */
    en_sqlite_rpi_buffer_column,        /* xColumn - read data */
    en_sqlite_rpi_buffer_rowid,         /* xRowid - read data */
    0,                                  /* xUpdate */
    0,                                  /* xBegin */
    0,                                  /* xSync */
    0,                                  /* xCommit */
    0,                                  /* xRollback */
    0,                                  /* xFindMethod */
    0,                                  /* xRename */
};

int en_sqlite_rpi_buffer_init(sqlite3 *db)
{
    return sqlite3_create_module(db, "en_sqlite_rpi_buffer", &en_sqlite_rpi_buffer_module, 0);
}
