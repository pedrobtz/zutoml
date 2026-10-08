/* The build phase (design sections 4, 6 and 13; roadmap Stage 4): R values
 * from the document tree the check phase produced. Runs only after the
 * check has accepted the whole document, and sizes every container from
 * the tree's counts, never from the input.
 *
 * Nothing here raises: a value R cannot hold (design section 6.4) sets
 * b->fault and unwinds by return. Everything allocated is an R object
 * protected by its parent, so R's own longjmps (allocation failure, an
 * interrupt) leak nothing. Recursion is bounded by max_depth, which R caps
 * at ZTM_MAX_DEPTH_CAP. */
#include <limits.h>
#include <string.h>

#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>

#include <zufast/datetime.h>

#include "ztm_build.h"

/* ---- strings ------------------------------------------------------------ */

static int build_failed(const ztm_builder *b) { return b->fault.status != ZTM_OK; }

static void fail_node(ztm_builder *b, const ztm_node *nd, ztm_status s)
{
    b->fault.status = s;
    b->fault.line = nd->line;
    b->fault.column = nd->column;
    b->fault.offset = nd->offset;
    b->fault.limit = NULL;
    b->fault.limit_value = 0;
}

/* The one place a CHARSXP is made from document text (design section 6.4),
 * so the U+0000 and length guards cannot drift between values and keys.
 * NULL, with the fault set, for what no CHARSXP can hold. */
static SEXP ztm_mkchar(ztm_builder *b, const ztm_node *nd, const char *s, size_t n, int has_nul)
{
    if (has_nul) { /* GUARD: nul_in_string */
        fail_node(b, nd, ZTM_ERR_UNREPRESENTABLE_NUL);
        return NULL;
    }
    /* Not mutation-checked: no test can build a 2 GiB string cheaply. */
    if (n > INT_MAX) {
        fail_node(b, nd, ZTM_ERR_UNREPRESENTABLE_LENGTH);
        return NULL;
    }
    return Rf_mkCharLenCE(s, (int) n, CE_UTF8);
}

/* ---- scalars ------------------------------------------------------------ */

/* The lattice kinds (design section 6.3). Integers that fit an R integer,
 * fit a double exactly, or need a toml_bigint are three kinds, so the
 * lattice can tell `[1, 2]` from `[1, 2^40]`. */
typedef enum {
    K_STRING, K_BOOL, K_INT, K_INT_DOUBLE, K_INT_BIG, K_FLOAT,
    K_DATETIME, K_LOCAL_DATETIME, K_LOCAL_DATE, K_LOCAL_TIME, K_OTHER
} kind;

static kind kind_of(const ztm_node *nd)
{
    if (nd->kind != ZTM_NODE_VALUE)
        return K_OTHER;
    const ztm_value *v = &nd->value;
    switch ((ztm_tok_type) v->type) {
    case ZTM_TOK_BASIC_STRING:
    case ZTM_TOK_LITERAL_STRING:
    case ZTM_TOK_ML_BASIC_STRING:
    case ZTM_TOK_ML_LITERAL_STRING:
        return K_STRING;
    case ZTM_TOK_BOOL:
        return K_BOOL;
    case ZTM_TOK_INTEGER:
        return v->int_class == ZTM_INT_FITS_INTEGER ? K_INT
               : v->int_class == ZTM_INT_FITS_DOUBLE ? K_INT_DOUBLE : K_INT_BIG;
    case ZTM_TOK_FLOAT:
        return K_FLOAT;
    case ZTM_TOK_DATETIME:
        return K_DATETIME;
    case ZTM_TOK_LOCAL_DATETIME:
        return K_LOCAL_DATETIME;
    case ZTM_TOK_LOCAL_DATE:
        return K_LOCAL_DATE;
    case ZTM_TOK_LOCAL_TIME:
        return K_LOCAL_TIME;
    default:
        return K_OTHER;
    }
}

/* Seconds since the epoch, as a POSIXct double, with the fraction truncated
 * to microseconds (design section 6.1). A local date-time is read as if UTC
 * here; R moves it into the session's zone (R/parse.R), since R has no C API
 * for the local time zone. */
static double posix_seconds(const zuf_datetime *dt)
{
    zuf_timestamp t = zuf_datetime_timestamp(dt);
    return (double) t.seconds + (double) (t.nanoseconds / 1000u) / 1e6;
}

static double time_seconds(const zuf_datetime *dt)
{
    return (double) dt->hour * 3600 + (double) dt->minute * 60 + (double) dt->second +
           (double) (dt->nanosecond / 1000u) / 1e6;
}

/* RFC 3339 text: the "keep" form of a date-time, canonical (T, Z for a zero
 * offset, the fraction in 0, 3, 6 or 9 digits). A local time drops the
 * borrowed date (ztm_value.c). */
static SEXP datetime_text(const ztm_value *v)
{
    char buf[64];
    size_t n = zuf_format_datetime(buf, sizeof buf, &v->u.dt);
    if (v->type == ZTM_TOK_LOCAL_TIME)
        return Rf_mkCharLen(buf + 11, (int) n - 11);
    return Rf_mkCharLen(buf, (int) n);
}

static SEXP bigint_text(int64_t i)
{
    char tmp[24], out[24];
    size_t n = 0, k = 0;
    uint64_t u = i < 0 ? 0u - (uint64_t) i : (uint64_t) i;
    do {
        tmp[n++] = (char) ('0' + u % 10u);
        u /= 10u;
    } while (u);
    if (i < 0)
        out[k++] = '-';
    while (n)
        out[k++] = tmp[--n];
    return Rf_mkCharLen(out, (int) k);
}

/* x's attribute `name` set to the string `value`, with the new string
 * protected across Rf_setAttrib(), which may allocate. */
static void set_string_attr(SEXP x, const char *name, const char *value)
{
    SEXP v = PROTECT(Rf_mkString(value));
    Rf_setAttrib(x, Rf_install(name), v);
    UNPROTECT(1);
}

static void set_class2(SEXP x, const char *a, const char *b2)
{
    SEXP cls = PROTECT(Rf_allocVector(STRSXP, b2 ? 2 : 1));
    SET_STRING_ELT(cls, 0, Rf_mkChar(a));
    if (b2)
        SET_STRING_ELT(cls, 1, Rf_mkChar(b2));
    Rf_setAttrib(x, R_ClassSymbol, cls);
    UNPROTECT(1);
}

/* Gives a typed vector of `k` its class and attributes. */
static void dress(ztm_builder *b, SEXP x, kind k)
{
    switch (k) {
    case K_INT_BIG:
        if (b->big_integers == ZTM_BIG_BIGINT)
            set_class2(x, "toml_bigint", NULL);
        break;
    case K_DATETIME:
    case K_LOCAL_DATETIME:
        if (b->datetimes == ZTM_DATETIMES_CONVERT) {
            set_class2(x, "POSIXct", "POSIXt");
            /* "<local>" marks a wall-clock time for R to move into the
             * session's zone; R replaces it with "". */
            set_string_attr(x, "tzone", k == K_DATETIME ? "UTC" : "<local>");
            if (k == K_LOCAL_DATETIME)
                b->has_local = 1;
        }
        break;
    case K_LOCAL_DATE:
        if (b->datetimes == ZTM_DATETIMES_CONVERT)
            set_class2(x, "Date", NULL);
        break;
    case K_LOCAL_TIME:
        if (b->datetimes == ZTM_DATETIMES_CONVERT && b->local_time == ZTM_LOCAL_TIME_DIFFTIME) {
            set_class2(x, "difftime", NULL);
            set_string_attr(x, "units", "secs");
        }
        break;
    default:
        break;
    }
}

/* The SEXPTYPE a vector of kind k is stored as. */
static SEXPTYPE storage_of(ztm_builder *b, kind k)
{
    switch (k) {
    case K_STRING: return STRSXP;
    case K_BOOL: return LGLSXP;
    case K_INT: return INTSXP;
    case K_INT_DOUBLE: case K_FLOAT: return REALSXP;
    case K_INT_BIG: return b->big_integers == ZTM_BIG_BIGINT ? STRSXP : REALSXP;
    case K_DATETIME: case K_LOCAL_DATETIME: case K_LOCAL_DATE:
        return b->datetimes == ZTM_DATETIMES_CONVERT ? REALSXP : STRSXP;
    case K_LOCAL_TIME:
        return b->datetimes == ZTM_DATETIMES_CONVERT && b->local_time == ZTM_LOCAL_TIME_DIFFTIME
                   ? REALSXP : STRSXP;
    default: return VECSXP;
    }
}

/* Stores the value of `nd` at x[i], x of the storage storage_of(k). Returns
 * 0 with the fault set for what R cannot hold. */
static int store(ztm_builder *b, SEXP x, R_xlen_t i, const ztm_node *nd, kind k)
{
    const ztm_value *v = &nd->value;
    SEXP ch;
    switch (k) {
    case K_STRING:
        ch = ztm_mkchar(b, nd, v->u.str.s, v->u.str.n, v->has_nul);
        if (!ch) return 0;
        SET_STRING_ELT(x, i, ch);
        return 1;
    case K_BOOL:
        LOGICAL(x)[i] = v->u.b;
        return 1;
    case K_INT:
    case K_INT_DOUBLE:
    case K_INT_BIG:
        /* Stored by the vector's type, which the array's common kind chose:
         * an integer among bigints is written as one. */
        if (k == K_INT_BIG && b->big_integers == ZTM_BIG_ERROR) { /* GUARD: big_integer */
            fail_node(b, nd, ZTM_ERR_UNREPRESENTABLE_BIG_INTEGER);
            return 0;
        }
        if (TYPEOF(x) == STRSXP)
            SET_STRING_ELT(x, i, bigint_text(v->u.i));
        else if (TYPEOF(x) == INTSXP)
            INTEGER(x)[i] = (int) v->u.i;
        else
            REAL(x)[i] = (double) v->u.i;
        return 1;
    case K_FLOAT:
        if (v->overflow) { /* GUARD: float_overflow */
            fail_node(b, nd, ZTM_ERR_UNREPRESENTABLE_FLOAT);
            return 0;
        }
        REAL(x)[i] = v->u.d;
        return 1;
    case K_DATETIME:
    case K_LOCAL_DATETIME:
    case K_LOCAL_DATE:
    case K_LOCAL_TIME:
        if (TYPEOF(x) == STRSXP) {
            SET_STRING_ELT(x, i, datetime_text(v));
        } else if (k == K_LOCAL_DATE) {
            REAL(x)[i] = (double) zuf_datetime_days(&v->u.dt);
        } else if (k == K_LOCAL_TIME) {
            REAL(x)[i] = time_seconds(&v->u.dt);
        } else {
            REAL(x)[i] = posix_seconds(&v->u.dt);
        }
        return 1;
    default:
        return 0;
    }
}

/* ---- containers --------------------------------------------------------- */

static SEXP build_node(ztm_builder *b, uint32_t idx);

static SEXP build_scalar(ztm_builder *b, const ztm_node *nd)
{
    kind k = kind_of(nd);
    SEXP x = PROTECT(Rf_allocVector(storage_of(b, k), 1));
    if (!store(b, x, 0, nd, k)) {
        UNPROTECT(1);
        return R_NilValue;
    }
    dress(b, x, k);
    UNPROTECT(1);
    return x;
}

/* A table: a named list, keys in definition order (design section 6.2). */
static SEXP build_table(ztm_builder *b, uint32_t idx)
{
    const ztm_node *nd = &b->doc->nodes[idx];
    SEXP out = PROTECT(Rf_allocVector(VECSXP, (R_xlen_t) nd->nchildren));
    SEXP names = PROTECT(Rf_allocVector(STRSXP, (R_xlen_t) nd->nchildren));
    R_xlen_t i = 0;
    for (uint32_t c = nd->first; c != ZTM_NONE; c = b->doc->nodes[c].next, i++) {
        const ztm_node *cn = &b->doc->nodes[c];
        SEXP key = ztm_mkchar(b, cn, cn->key, cn->keylen, cn->key_has_nul);
        if (!key) {
            UNPROTECT(2);
            return R_NilValue;
        }
        SET_STRING_ELT(names, i, key);
        SEXP v = build_node(b, c);
        if (build_failed(b)) {
            UNPROTECT(2);
            return R_NilValue;
        }
        SET_VECTOR_ELT(out, i, v);
    }
    Rf_setAttrib(out, R_NamesSymbol, names);
    UNPROTECT(2);
    return out;
}

/* An unnamed list of the children's values. */
static SEXP build_list(ztm_builder *b, uint32_t idx)
{
    const ztm_node *nd = &b->doc->nodes[idx];
    SEXP out = PROTECT(Rf_allocVector(VECSXP, (R_xlen_t) nd->nchildren));
    R_xlen_t i = 0;
    for (uint32_t c = nd->first; c != ZTM_NONE; c = b->doc->nodes[c].next, i++) {
        SEXP v = build_node(b, c);
        if (build_failed(b)) {
            UNPROTECT(1);
            return R_NilValue;
        }
        SET_VECTOR_ELT(out, i, v);
    }
    UNPROTECT(1);
    return out;
}

static void mark_asis(SEXP x)
{
    SEXP old = PROTECT(Rf_getAttrib(x, R_ClassSymbol));
    R_xlen_t n = Rf_isNull(old) ? 0 : XLENGTH(old);
    SEXP cls = PROTECT(Rf_allocVector(STRSXP, n + 1));
    SET_STRING_ELT(cls, 0, Rf_mkChar("AsIs"));
    for (R_xlen_t i = 0; i < n; i++)
        SET_STRING_ELT(cls, i + 1, STRING_ELT(old, i));
    Rf_setAttrib(x, R_ClassSymbol, cls);
    UNPROTECT(2);
}

/* The kind an array's elements share, by the lattice of design section 6.3,
 * or K_OTHER when they share none. Booleans are a kind of their own;
 * integers widen to double with floats or with integers beyond R's range,
 * and to toml_bigint only among integers. */
static kind common_kind(ztm_builder *b, const ztm_node *arr)
{
    kind acc = K_OTHER;
    int first = 1;
    for (uint32_t c = arr->first; c != ZTM_NONE; c = b->doc->nodes[c].next) {
        kind k = kind_of(&b->doc->nodes[c]);
        if (k == K_OTHER)
            return K_OTHER;
        if (k == K_INT_BIG && b->big_integers == ZTM_BIG_DOUBLE)
            k = K_INT_DOUBLE;
        if (first) {
            acc = k;
            first = 0;
            continue;
        }
        if (k == acc)
            continue;
        int acc_int = acc == K_INT || acc == K_INT_DOUBLE || acc == K_INT_BIG;
        int k_int = k == K_INT || k == K_INT_DOUBLE || k == K_INT_BIG;
        if (acc_int && k_int) {
            acc = (acc == K_INT_BIG || k == K_INT_BIG) ? K_INT_BIG : K_INT_DOUBLE;
        } else if ((acc_int || acc == K_FLOAT) && (k_int || k == K_FLOAT) &&
                   acc != K_INT_BIG && k != K_INT_BIG) {
            acc = K_FLOAT;
        } else {
            return K_OTHER;
        }
    }
    return acc;
}

static SEXP build_array(ztm_builder *b, uint32_t idx)
{
    const ztm_node *nd = &b->doc->nodes[idx];
    if (nd->nchildren == 0) {
        /* An empty array is logical(0) (design section 6.3). */
        return b->simplify ? Rf_allocVector(LGLSXP, 0) : Rf_allocVector(VECSXP, 0);
    }
    kind k = b->simplify ? common_kind(b, nd) : K_OTHER;
    if (k == K_OTHER)
        return build_list(b, idx);
    SEXP out = PROTECT(Rf_allocVector(storage_of(b, k), (R_xlen_t) nd->nchildren));
    R_xlen_t i = 0;
    for (uint32_t c = nd->first; c != ZTM_NONE; c = b->doc->nodes[c].next, i++) {
        const ztm_node *cn = &b->doc->nodes[c];
        if (!store(b, out, i, cn, kind_of(cn))) {
            UNPROTECT(1);
            return R_NilValue;
        }
    }
    dress(b, out, k);
    /* One element that simplifies is marked I(), so that writing it back
     * gives an array again (design section 6.3). */
    if (nd->nchildren == 1)
        mark_asis(out);
    UNPROTECT(1);
    return out;
}

static SEXP build_node(ztm_builder *b, uint32_t idx)
{
    const ztm_node *nd = &b->doc->nodes[idx];
    R_CheckStack();
    switch ((ztm_node_kind) nd->kind) {
    case ZTM_NODE_TABLE:
        return build_table(b, idx);
    case ZTM_NODE_AOT:
        return build_list(b, idx);
    case ZTM_NODE_ARRAY:
        return build_array(b, idx);
    default:
        return build_scalar(b, nd);
    }
}

SEXP ztm_build(ztm_builder *b)
{
    memset(&b->fault, 0, sizeof b->fault);
    b->has_local = 0;
    return build_node(b, 0);
}
