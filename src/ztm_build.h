#ifndef ZTM_BUILD_H
#define ZTM_BUILD_H

/* The build phase (design section 4): R values from the check phase's
 * document tree. R side: includes R's headers through ztm_build.c only. */
#include <Rinternals.h>

#include "ztm_check.h"

/* toml_parse()'s mapping arguments, as R passes them (R/parse.R). */
enum { ZTM_BIG_BIGINT = 0, ZTM_BIG_DOUBLE = 1, ZTM_BIG_ERROR = 2 };
enum { ZTM_DATETIMES_CONVERT = 0, ZTM_DATETIMES_KEEP = 1 };
enum { ZTM_LOCAL_TIME_CHARACTER = 0, ZTM_LOCAL_TIME_DIFFTIME = 1 };

typedef struct {
    const ztm_doc *doc;
    int simplify;          /* nonzero: the lattice; zero: every array a list */
    int big_integers, datetimes, local_time;
    ztm_fault fault;       /* set when a value cannot be held (section 6.4) */
    int has_local;         /* a local date-time was built: R moves it into the
                              session's zone */
} ztm_builder;

/* The R value of the whole document, or R_NilValue with b->fault set. */
SEXP ztm_build(ztm_builder *b);

#endif
