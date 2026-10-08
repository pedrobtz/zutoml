#ifndef ZTM_EMIT_H
#define ZTM_EMIT_H

/* The emitter (design sections 7 and 8). R side. */
#include <Rinternals.h>

typedef enum {
    ZTM_EMIT_OK = 0,
    ZTM_EMIT_UNSUPPORTED,   /* an R value with no TOML form (section 7.3) */
    ZTM_EMIT_NA,            /* NA or NULL with na = "error" */
    ZTM_EMIT_INVALID,       /* a value that cannot be written as given */
    ZTM_EMIT_DEPTH          /* nested deeper than max_depth */
} ztm_emit_status;

typedef struct {
    int indent, inline_max, width, na_omit, literal, max_depth;
} ztm_emit_opts;

typedef struct {
    ztm_emit_status status;
    const char *detail;     /* why, for ZTM_EMIT_INVALID and some others */
    const char *path;       /* the offending value's key path */
    int dropped;            /* na = "omit" dropped an array element */
} ztm_emit_result;

/* The document for the named list x, as a CHARSXP, or R_NilValue with
 * res->status set. */
SEXP ztm_emit(SEXP x, const ztm_emit_opts *opt, ztm_emit_result *res);

#endif
