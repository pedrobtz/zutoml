/* The emitter (design sections 7 and 8; roadmap Stage 5): one pass over an
 * R value into a buffer that doubles, then one CHARSXP.
 *
 * Deterministic: key order is the list's, scalars before sub-tables (TOML
 * requires a table's own keys before its sub-tables' headers); floats by
 * zufast's shortest round-trip digits; date-times by zuf_format_datetime();
 * no locale; '\n' line endings. The emitter charges max_depth as the parser
 * does, so it never writes what toml_parse() at the same depth refuses.
 *
 * Nothing here raises: a value that cannot be written sets e->status and
 * unwinds by return; R raises (R/emit.R). The buffer and the path are
 * R_alloc()ed, so R's own longjmps leak nothing. Local POSIXct values arrive
 * as wall-clock text of class ztm_wallclock (R/emit.R), since R has no C
 * API for the session's time zone. */
#include <limits.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>

#include <zufast/datetime.h>
#include <zufast/number.h>
#include <zufast/utf8.h>

#include "ztm_emit.h"

typedef struct {
    const char *key;   /* NULL for an array index */
    R_xlen_t index;
} path_part;

typedef struct {
    char *buf;
    size_t len, cap;
    size_t line_start;
    int indent, inline_max, width, na_omit, literal;
    int max_depth;
    path_part *path;
    int npath, path_cap;
    ztm_emit_status status;
    const char *detail;
    int dropped;       /* an array element was dropped under na = "omit" */
} emitter;

/* ---- the buffer --------------------------------------------------------- */

static void reserve(emitter *e, size_t extra)
{
    if (e->len + extra <= e->cap)
        return;
    size_t cap = e->cap ? e->cap : 256;
    while (cap < e->len + extra)
        cap *= 2;
    char *grown = R_alloc(cap, 1);
    if (e->len)
        memcpy(grown, e->buf, e->len);
    e->buf = grown;
    e->cap = cap;
}

static void put(emitter *e, const char *s, size_t n)
{
    reserve(e, n);
    memcpy(e->buf + e->len, s, n);
    e->len += n;
}

static void puts_(emitter *e, const char *s) { put(e, s, strlen(s)); }

static void putc_(emitter *e, char c) { put(e, &c, 1); }

static void newline(emitter *e)
{
    putc_(e, '\n');
    e->line_start = e->len;
}

/* ---- the path, for errors ------------------------------------------------ */

static void push_key(emitter *e, const char *key)
{
    if (e->npath == e->path_cap) {
        int cap = e->path_cap ? e->path_cap * 2 : 16;
        path_part *grown = (path_part *) R_alloc((size_t) cap, sizeof *grown);
        if (e->npath)
            memcpy(grown, e->path, (size_t) e->npath * sizeof *grown);
        e->path = grown;
        e->path_cap = cap;
    }
    e->path[e->npath].key = key;
    e->path[e->npath].index = 0;
    e->npath++;
}

static void push_index(emitter *e, R_xlen_t i)
{
    push_key(e, NULL);
    e->path[e->npath - 1].index = i;
}

static void pop(emitter *e) { e->npath--; }

static int fail(emitter *e, ztm_emit_status s, const char *detail)
{
    if (e->status == ZTM_EMIT_OK) {
        e->status = s;
        e->detail = detail;
    }
    return 0;
}

/* ---- classes ------------------------------------------------------------- */

static int has_class(SEXP x, const char *cls) { return Rf_inherits(x, cls); }

/* The classes an atomic value may carry; anything else has no TOML form
 * that zutoml can be sure of (bit64's integer64 is a double with a class,
 * for example), and is refused rather than written by its storage. */
static int known_atomic_classes(SEXP x)
{
    static const char *known[] = {"AsIs", "factor", "Date", "POSIXct", "POSIXt", "difftime",
                                  "toml_bigint", "ztm_wallclock", NULL};
    SEXP cls = Rf_getAttrib(x, R_ClassSymbol);
    for (R_xlen_t i = 0; i < Rf_xlength(cls); i++) {
        const char *c = CHAR(STRING_ELT(cls, i));
        int ok = 0;
        for (int k = 0; known[k]; k++)
            if (strcmp(c, known[k]) == 0)
                ok = 1;
        if (!ok)
            return 0;
    }
    return 1;
}

static int is_df(SEXP x) { return TYPEOF(x) == VECSXP && has_class(x, "data.frame"); }

/* A data frame's rows, from its row names (which R expands from the compact
 * form), so a frame with no columns still has its rows. */
static R_xlen_t df_nrow(SEXP df)
{
    return XLENGTH(Rf_getAttrib(df, R_RowNamesSymbol));
}

/* A list zutoml knows how to write: no class, or only AsIs. A list with
 * another class (POSIXlt, lm, ...) is an object, not a table, and has no
 * TOML form zutoml can be sure of. Data frames are handled on their own. */
static int is_plain_list(SEXP x)
{
    if (TYPEOF(x) != VECSXP)
        return 0;
    SEXP cls = Rf_getAttrib(x, R_ClassSymbol);
    for (R_xlen_t i = 0; i < Rf_xlength(cls); i++)
        if (strcmp(CHAR(STRING_ELT(cls, i)), "AsIs") != 0)
            return 0;
    return 1;
}

static int is_table(SEXP x)
{
    return is_plain_list(x) && !Rf_isNull(Rf_getAttrib(x, R_NamesSymbol));
}

/* An array of tables: a data frame with rows, or an unnamed list of one or
 * more tables, unless I() marks it as a plain array. A data frame with no
 * rows has no tables to write, so it is an empty array: `key = []`. */
static int is_aot(SEXP x)
{
    if (is_df(x))
        return df_nrow(x) > 0;
    if (!is_plain_list(x) || is_table(x) || XLENGTH(x) == 0 || has_class(x, "AsIs"))
        return 0;
    for (R_xlen_t i = 0; i < XLENGTH(x); i++)
        if (!is_table(VECTOR_ELT(x, i)))
            return 0;
    return 1;
}

/* NA, or NULL: a value TOML has no form for (design section 7.1). */
static int is_na_elt(SEXP x, R_xlen_t i)
{
    switch (TYPEOF(x)) {
    case LGLSXP: return LOGICAL(x)[i] == NA_LOGICAL;
    case INTSXP: return INTEGER(x)[i] == NA_INTEGER;
    case REALSXP:
        /* NA_real_ always; NaN too for the classes whose NA it is. */
        return ISNA(REAL(x)[i]) ||
               (ISNAN(REAL(x)[i]) && (has_class(x, "Date") || has_class(x, "POSIXct") ||
                                      has_class(x, "difftime")));
    case STRSXP: return STRING_ELT(x, i) == NA_STRING;
    default: return 0;
    }
}

/* A missing value: NULL, or an NA scalar that is not an array of one. */
static int is_missing(SEXP x)
{
    if (Rf_isNull(x))
        return 1;
    return Rf_isVectorAtomic(x) && XLENGTH(x) == 1 && !has_class(x, "AsIs") && is_na_elt(x, 0);
}

/* ---- scalars -------------------------------------------------------------- */

static void put_i64(emitter *e, int64_t v)
{
    char tmp[24];
    size_t n = 0;
    uint64_t u = v < 0 ? 0u - (uint64_t) v : (uint64_t) v;
    do {
        tmp[n++] = (char) ('0' + u % 10u);
        u /= 10u;
    } while (u);
    if (v < 0)
        putc_(e, '-');
    while (n)
        putc_(e, tmp[--n]);
}

/* A whole double within 64-bit signed range, not -0, is a TOML integer:
 * R has no integer literal, so list(port = 8080) is a double, and a TOML
 * reader expects 8080 (design D4). Anything else is a float, in zufast's
 * shortest round-trip digits with ".0" when it has no point or exponent. */
static void put_double(emitter *e, double v)
{
    if (isfinite(v) && v == floor(v) && !(v == 0 && signbit(v)) &&
        v >= -9223372036854775808.0 && v < 9223372036854775808.0) {
        put_i64(e, (int64_t) v);
        return;
    }
    if (isnan(v)) {
        puts_(e, "nan");
        return;
    }
    if (isinf(v)) {
        puts_(e, v > 0 ? "inf" : "-inf");
        return;
    }
    char tmp[40];
    size_t n = zuf_format_f64(tmp, sizeof tmp, v);
    put(e, tmp, n);
    if (!memchr(tmp, '.', n) && !memchr(tmp, 'e', n) && !memchr(tmp, 'E', n))
        puts_(e, ".0");
}

static void put_escaped_byte(emitter *e, unsigned char c)
{
    static const char hex[] = "0123456789ABCDEF";
    switch (c) {
    case '"': puts_(e, "\\\""); return;
    case '\\': puts_(e, "\\\\"); return;
    case '\b': puts_(e, "\\b"); return;
    case '\t': puts_(e, "\\t"); return;
    case '\n': puts_(e, "\\n"); return;
    case '\f': puts_(e, "\\f"); return;
    case '\r': puts_(e, "\\r"); return;
    default:
        if (c < 0x20 || c == 0x7F) {
            char u[6] = {'\\', 'u', '0', '0', hex[c >> 4], hex[c & 15]};
            put(e, u, 6);
        } else {
            putc_(e, (char) c);
        }
    }
}

static void put_basic(emitter *e, const char *s, size_t n)
{
    putc_(e, '"');
    for (size_t i = 0; i < n; i++)
        put_escaped_byte(e, (unsigned char) s[i]);
    putc_(e, '"');
}

/* A multi-line basic string: newlines as they are, everything else escaped
 * as in a basic string, except that a quote is escaped only where it could
 * help close the string (beside another quote, or last). The newline after
 * the opening delimiter is trimmed by readers, so the content is exact. */
static void put_ml_basic(emitter *e, const char *s, size_t n)
{
    puts_(e, "\"\"\"\n");
    for (size_t i = 0; i < n; i++) {
        unsigned char c = (unsigned char) s[i];
        if (c == '\n') {
            putc_(e, '\n');
        } else if (c == '"' && !(i + 1 < n && s[i + 1] == '"') && i + 1 < n) {
            putc_(e, '"');
        } else {
            put_escaped_byte(e, c);
        }
    }
    puts_(e, "\"\"\"");
}

static int is_bare_key(const char *s, size_t n)
{
    if (n == 0)
        return 0;
    for (size_t i = 0; i < n; i++) {
        unsigned char c = (unsigned char) s[i];
        if (!((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') ||
              c == '_' || c == '-'))
            return 0;
    }
    return 1;
}

/* A CHARSXP's text as valid UTF-8, or NULL with the status set. */
static const char *utf8_of(emitter *e, SEXP ch)
{
    const char *s = Rf_translateCharUTF8(ch);
    if (!zuf_utf8_valid(s, strlen(s))) {
        fail(e, ZTM_EMIT_INVALID, "a string is not valid UTF-8");
        return NULL;
    }
    return s;
}

static int put_key(emitter *e, SEXP ch)
{
    const char *s = utf8_of(e, ch);
    if (!s)
        return 0;
    size_t n = strlen(s);
    if (is_bare_key(s, n))
        put(e, s, n);
    else
        put_basic(e, s, n);
    return 1;
}

/* A string value: literal when asked and possible, multi-line basic for a
 * table's own value that holds a newline, basic otherwise. */
static int put_string(emitter *e, SEXP ch, int ml_ok)
{
    const char *s = utf8_of(e, ch);
    if (!s)
        return 0;
    size_t n = strlen(s);
    int has_nl = memchr(s, '\n', n) != NULL;
    if (e->literal) {
        int ok = 1;
        for (size_t i = 0; i < n && ok; i++) {
            unsigned char c = (unsigned char) s[i];
            if (c == '\'' || (c < 0x20 && c != '\t') || c == 0x7F)
                ok = 0;
        }
        if (ok) {
            putc_(e, '\'');
            put(e, s, n);
            putc_(e, '\'');
            return 1;
        }
    }
    if (ml_ok && has_nl)
        put_ml_basic(e, s, n);
    else
        put_basic(e, s, n);
    return 1;
}

/* Seconds to whole seconds and microseconds, rounding to the nearest
 * microsecond, as R's own printing of a POSIXct does. */
static void split_seconds(double v, double *whole, uint32_t *micro)
{
    double w = floor(v);
    double m = floor((v - w) * 1e6 + 0.5);
    if (m >= 1e6) {
        w += 1;
        m = 0;
    }
    *whole = w;
    *micro = (uint32_t) m;
}

static int put_datetime_utc(emitter *e, double v)
{
    double whole;
    uint32_t micro;
    split_seconds(v, &whole, &micro);
    double days = floor(whole / 86400);
    if (days < -719528 || days > 2932896) /* outside years 0000-9999 */
        return fail(e, ZTM_EMIT_INVALID, "a date-time outside the years 0000 to 9999");
    zuf_datetime dt;
    memset(&dt, 0, sizeof dt);
    int32_t y;
    uint32_t mo, d;
    zuf_civil_from_days((int32_t) days, &y, &mo, &d);
    double sod = whole - days * 86400;
    dt.year = y;
    dt.month = (uint8_t) mo;
    dt.day = (uint8_t) d;
    dt.hour = (uint8_t) (sod / 3600);
    dt.minute = (uint8_t) (fmod(sod, 3600) / 60);
    dt.second = (uint8_t) fmod(sod, 60);
    dt.nanosecond = micro * 1000u;
    dt.has_time = 1;
    dt.has_offset = 1;
    char tmp[64];
    put(e, tmp, zuf_format_datetime(tmp, sizeof tmp, &dt));
    return 1;
}

static int put_date(emitter *e, double v)
{
    double days = floor(v);
    if (days < -719528 || days > 2932896)
        return fail(e, ZTM_EMIT_INVALID, "a date outside the years 0000 to 9999");
    char tmp[24];
    put(e, tmp, zuf_format_date(tmp, sizeof tmp, (int32_t) days));
    return 1;
}

/* A difftime in seconds within a day is a local time (design section 7.1;
 * section 18 Q2: anything else is refused). */
static int put_local_time(emitter *e, SEXP x, double v)
{
    SEXP units = Rf_getAttrib(x, Rf_install("units"));
    if (TYPEOF(units) != STRSXP || XLENGTH(units) != 1 ||
        strcmp(CHAR(STRING_ELT(units, 0)), "secs") != 0)
        return fail(e, ZTM_EMIT_INVALID,
                    "a difftime is a local time only in units \"secs\"; "
                    "convert it with units(x) <- \"secs\", or write as.numeric(x)");
    double whole;
    uint32_t micro;
    split_seconds(v, &whole, &micro);
    if (!(v >= 0) || whole >= 86400)
        return fail(e, ZTM_EMIT_INVALID,
                    "a difftime is a local time only from 0 to 86400 seconds; "
                    "write as.numeric(x) for a duration");
    char tmp[24];
    int h = (int) (whole / 3600), m = (int) (fmod(whole, 3600) / 60), s = (int) fmod(whole, 60);
    tmp[0] = (char) ('0' + h / 10);
    tmp[1] = (char) ('0' + h % 10);
    tmp[2] = ':';
    tmp[3] = (char) ('0' + m / 10);
    tmp[4] = (char) ('0' + m % 10);
    tmp[5] = ':';
    tmp[6] = (char) ('0' + s / 10);
    tmp[7] = (char) ('0' + s % 10);
    size_t n = 8;
    if (micro) {
        uint32_t digits = micro % 1000 == 0 ? 3 : 6;
        uint32_t f = digits == 3 ? micro / 1000 : micro;
        tmp[n++] = '.';
        for (uint32_t k = digits; k > 0; k--) {
            tmp[n + k - 1] = (char) ('0' + f % 10);
            f /= 10;
        }
        n += digits;
    }
    put(e, tmp, n);
    return 1;
}

static int put_bigint(emitter *e, SEXP ch)
{
    const char *s = CHAR(ch);
    size_t n = strlen(s);
    int64_t v;
    zuf_result r = zuf_parse_i64(s, s + n, &v);
    if (r.status != ZUF_OK || r.ptr != s + n)
        return fail(e, ZTM_EMIT_INVALID, "a toml_bigint outside the 64-bit signed range");
    put_i64(e, v);
    return 1;
}

/* Element i of the atomic vector x, which is not NA. */
static int put_scalar(emitter *e, SEXP x, R_xlen_t i, int ml_ok)
{
    switch (TYPEOF(x)) {
    case LGLSXP:
        puts_(e, LOGICAL(x)[i] ? "true" : "false");
        return 1;
    case INTSXP:
        if (has_class(x, "factor")) {
            SEXP levels = Rf_getAttrib(x, R_LevelsSymbol);
            int code = INTEGER(x)[i];
            if (TYPEOF(levels) != STRSXP || code < 1 || code > XLENGTH(levels))
                return fail(e, ZTM_EMIT_INVALID, "a factor with a code outside its levels");
            return put_string(e, STRING_ELT(levels, code - 1), ml_ok);
        }
        put_i64(e, INTEGER(x)[i]);
        return 1;
    case REALSXP: {
        double v = REAL(x)[i];
        if (has_class(x, "POSIXct"))
            return put_datetime_utc(e, v);
        if (has_class(x, "Date"))
            return put_date(e, v);
        if (has_class(x, "difftime"))
            return put_local_time(e, x, v);
        put_double(e, v);
        return 1;
    }
    case STRSXP:
        if (has_class(x, "toml_bigint"))
            return put_bigint(e, STRING_ELT(x, i));
        if (has_class(x, "ztm_wallclock")) {
            puts_(e, CHAR(STRING_ELT(x, i)));
            return 1;
        }
        return put_string(e, STRING_ELT(x, i), ml_ok);
    default:
        return fail(e, ZTM_EMIT_UNSUPPORTED, NULL);
    }
}

/* ---- values -------------------------------------------------------------- */

static int put_value(emitter *e, SEXP x, int depth, int ml_ok);

static int check_depth(emitter *e, int depth)
{
    if (depth > e->max_depth) /* GUARD: emit_max_depth */
        return fail(e, ZTM_EMIT_DEPTH, NULL);
    return 1;
}

/* A value with no TOML form, by type and class (design section 7.3). */
static int writable_atomic(emitter *e, SEXP x)
{
    switch (TYPEOF(x)) {
    case LGLSXP:
    case INTSXP:
    case REALSXP:
    case STRSXP:
        break;
    default:
        return fail(e, ZTM_EMIT_UNSUPPORTED, NULL);
    }
    if (!Rf_isNull(Rf_getAttrib(x, R_DimSymbol)))
        return fail(e, ZTM_EMIT_UNSUPPORTED, "a matrix or array with dim: convert it to a list");
    if (!known_atomic_classes(x))
        return fail(e, ZTM_EMIT_UNSUPPORTED, NULL);
    return 1;
}

/* The elements of an array, compact ("1, 2, 3") or one per line. */
static int put_array_elements(emitter *e, SEXP x, int depth, int multiline)
{
    int first = 1;
    R_xlen_t n = XLENGTH(x);
    int atomic = Rf_isVectorAtomic(x);
    for (R_xlen_t i = 0; i < n; i++) {
        push_index(e, i);
        int missing = atomic ? is_na_elt(x, i) : is_missing(VECTOR_ELT(x, i));
        if (missing) {
            if (!e->na_omit) {
                fail(e, ZTM_EMIT_NA, NULL);
                return 0;
            }
            e->dropped = 1;
            pop(e);
            continue;
        }
        if (multiline) {
            newline(e);
            for (int k = 0; k < e->indent; k++)
                putc_(e, ' ');
        } else if (!first) {
            puts_(e, ", ");
        }
        first = 0;
        if (!check_depth(e, depth + 1))
            return 0;
        if (atomic ? !put_scalar(e, x, i, 0) : !put_value(e, VECTOR_ELT(x, i), depth + 1, 0))
            return 0;
        if (multiline)
            putc_(e, ',');
        pop(e);
    }
    if (multiline && !first)
        newline(e);
    return 1;
}

static int put_array(emitter *e, SEXP x, int depth)
{
    putc_(e, '[');
    if (!put_array_elements(e, x, depth, 0))
        return 0;
    putc_(e, ']');
    return 1;
}

/* One row of a data frame, as an inline table. NA cells are missing keys:
 * that is what toml_parse(data_frame = TRUE) makes of them. */
static int put_df_row(emitter *e, SEXP df, R_xlen_t row, int depth)
{
    SEXP names = Rf_getAttrib(df, R_NamesSymbol);
    int first = 1;
    putc_(e, '{');
    for (R_xlen_t j = 0; j < XLENGTH(df); j++) {
        SEXP col = VECTOR_ELT(df, j);
        int missing = Rf_isVectorAtomic(col) ? is_na_elt(col, row)
                                             : is_missing(VECTOR_ELT(col, row));
        if (missing)
            continue;
        puts_(e, first ? " " : ", ");
        first = 0;
        push_key(e, CHAR(STRING_ELT(names, j)));
        if (!put_key(e, STRING_ELT(names, j)))
            return 0;
        puts_(e, " = ");
        if (!check_depth(e, depth + 1))
            return 0;
        if (Rf_isVectorAtomic(col)) {
            if (!writable_atomic(e, col) || !put_scalar(e, col, row, 0))
                return 0;
        } else if (!put_value(e, VECTOR_ELT(col, row), depth + 1, 0)) {
            return 0;
        }
        pop(e);
    }
    puts_(e, first ? "}" : " }");
    return 1;
}

static int check_names(emitter *e, SEXP x)
{
    SEXP names = Rf_getAttrib(x, R_NamesSymbol);
    for (R_xlen_t i = 0; i < XLENGTH(names); i++)
        if (STRING_ELT(names, i) == NA_STRING)
            return fail(e, ZTM_EMIT_INVALID, "a list with NA names: every key must be a string");
    if (Rf_any_duplicated(names, FALSE))
        return fail(e, ZTM_EMIT_INVALID, "a list with duplicated names: TOML keys are unique");
    return 1;
}

static int put_inline_table(emitter *e, SEXP x, int depth)
{
    if (!check_names(e, x))
        return 0;
    SEXP names = Rf_getAttrib(x, R_NamesSymbol);
    int first = 1;
    putc_(e, '{');
    for (R_xlen_t i = 0; i < XLENGTH(x); i++) {
        SEXP v = VECTOR_ELT(x, i);
        push_key(e, CHAR(STRING_ELT(names, i)));
        if (is_missing(v)) {
            if (!e->na_omit)
                return fail(e, ZTM_EMIT_NA, NULL);
            pop(e);
            continue;
        }
        puts_(e, first ? " " : ", ");
        first = 0;
        if (!put_key(e, STRING_ELT(names, i)))
            return 0;
        puts_(e, " = ");
        if (!check_depth(e, depth + 1) || !put_value(e, v, depth + 1, 0))
            return 0;
        pop(e);
    }
    puts_(e, first ? "}" : " }");
    return 1;
}

/* A value on the right of '=' or in an array: a scalar, an array, an inline
 * table. `depth` is the value's own depth, already checked. */
static int put_value(emitter *e, SEXP x, int depth, int ml_ok)
{
    R_CheckStack();
    if (Rf_isVectorAtomic(x)) {
        if (!writable_atomic(e, x))
            return 0;
        if (XLENGTH(x) == 1 && !has_class(x, "AsIs")) {
            if (is_na_elt(x, 0))
                return fail(e, ZTM_EMIT_NA, NULL);
            return put_scalar(e, x, 0, ml_ok);
        }
        return put_array(e, x, depth);
    }
    if (TYPEOF(x) == VECSXP) {
        if (is_df(x)) {
            putc_(e, '[');
            R_xlen_t nrow = df_nrow(x);
            for (R_xlen_t r = 0; r < nrow; r++) {
                if (r)
                    puts_(e, ", ");
                push_index(e, r);
                if (!check_depth(e, depth + 1) || !put_df_row(e, x, r, depth + 1))
                    return 0;
                pop(e);
            }
            putc_(e, ']');
            return 1;
        }
        if (!is_plain_list(x))
            return fail(e, ZTM_EMIT_UNSUPPORTED, NULL);
        if (is_table(x))
            return put_inline_table(e, x, depth);
        return put_array(e, x, depth);
    }
    if (Rf_isNull(x))
        return fail(e, ZTM_EMIT_NA, NULL);
    return fail(e, ZTM_EMIT_UNSUPPORTED, NULL);
}

/* ---- tables -------------------------------------------------------------- */

/* Whether a table's element is written under a [header] (or [[header]]s)
 * rather than as `key = value`. */
static int is_header_kind(emitter *e, SEXP v)
{
    if (is_aot(v))
        return 1;
    if (!is_table(v))
        return 0;
    if (e->inline_max > 0 && XLENGTH(v) <= e->inline_max) {
        for (R_xlen_t i = 0; i < XLENGTH(v); i++)
            if (TYPEOF(VECTOR_ELT(v, i)) == VECSXP)
                return 1;
        return 0;   /* small and flat: written inline */
    }
    return 1;
}

typedef struct {
    SEXP *keys;   /* the header path's keys, as CHARSXPs */
    int n, cap;
} header_path;

static void header_push(header_path *h, SEXP key)
{
    if (h->n == h->cap) {
        int cap = h->cap ? h->cap * 2 : 16;
        SEXP *grown = (SEXP *) R_alloc((size_t) cap, sizeof *grown);
        if (h->n)
            memcpy(grown, h->keys, (size_t) h->n * sizeof *grown);
        h->keys = grown;
        h->cap = cap;
    }
    h->keys[h->n++] = key;
}

static int put_header(emitter *e, const header_path *h, int aot)
{
    if (e->len)
        newline(e);
    puts_(e, aot ? "[[" : "[");
    for (int i = 0; i < h->n; i++) {
        if (i)
            putc_(e, '.');
        if (!put_key(e, h->keys[i]))
            return 0;
    }
    puts_(e, aot ? "]]" : "]");
    newline(e);
    return 1;
}

static int put_table_body(emitter *e, SEXP x, int depth, header_path *h);

/* `key = value` for the table's own values, then a section per sub-table and
 * array of tables, depth-first in the list's order (design section 7.2). */
static int put_table_body(emitter *e, SEXP x, int depth, header_path *h)
{
    R_CheckStack();
    if (!check_depth(e, depth) || !check_names(e, x))
        return 0;
    SEXP names = Rf_getAttrib(x, R_NamesSymbol);
    R_xlen_t n = XLENGTH(x);
    for (R_xlen_t i = 0; i < n; i++) {
        SEXP v = VECTOR_ELT(x, i);
        if (is_header_kind(e, v))
            continue;
        push_key(e, CHAR(STRING_ELT(names, i)));
        if (is_missing(v)) {
            if (!e->na_omit)
                return fail(e, ZTM_EMIT_NA, NULL);
            pop(e);
            continue;
        }
        if (!put_key(e, STRING_ELT(names, i)))
            return 0;
        puts_(e, " = ");
        size_t start = e->len;
        if (!check_depth(e, depth + 1) || !put_value(e, v, depth + 1, 1))
            return 0;
        /* An array past `width` is rewritten one element per line. */
        int is_array = (Rf_isVectorAtomic(v) && (XLENGTH(v) != 1 || has_class(v, "AsIs"))) ||
                       (TYPEOF(v) == VECSXP && !is_table(v));
        if (is_array && e->width > 0 && e->len - e->line_start > (size_t) e->width &&
            XLENGTH(v) > 0) {
            e->len = start;
            putc_(e, '[');
            if (is_df(v)) {
                R_xlen_t nrow = df_nrow(v);
                for (R_xlen_t r = 0; r < nrow; r++) {
                    newline(e);
                    for (int k = 0; k < e->indent; k++)
                        putc_(e, ' ');
                    push_index(e, r);
                    if (!check_depth(e, depth + 2) || !put_df_row(e, v, r, depth + 2))
                        return 0;
                    pop(e);
                    putc_(e, ',');
                }
                newline(e);
            } else if (!put_array_elements(e, v, depth + 1, 1)) {
                return 0;
            }
            putc_(e, ']');
        }
        newline(e);
        pop(e);
    }
    for (R_xlen_t i = 0; i < n; i++) {
        SEXP v = VECTOR_ELT(x, i);
        if (!is_header_kind(e, v))
            continue;
        push_key(e, CHAR(STRING_ELT(names, i)));
        header_push(h, STRING_ELT(names, i));
        if (is_df(v)) {
            /* An array of tables, one per row: each row's cells are values. */
            if (!check_depth(e, depth + 1))
                return 0;
            R_xlen_t nrow = df_nrow(v);
            SEXP cn = Rf_getAttrib(v, R_NamesSymbol);
            for (R_xlen_t r = 0; r < nrow; r++) {
                push_index(e, r);
                if (!check_depth(e, depth + 2) || !put_header(e, h, 1))
                    return 0;
                for (R_xlen_t j = 0; j < XLENGTH(v); j++) {
                    SEXP col = VECTOR_ELT(v, j);
                    int missing = Rf_isVectorAtomic(col) ? is_na_elt(col, r)
                                                         : is_missing(VECTOR_ELT(col, r));
                    if (missing)
                        continue;
                    push_key(e, CHAR(STRING_ELT(cn, j)));
                    if (!put_key(e, STRING_ELT(cn, j)))
                        return 0;
                    puts_(e, " = ");
                    if (!check_depth(e, depth + 3))
                        return 0;
                    if (Rf_isVectorAtomic(col)) {
                        if (!writable_atomic(e, col) || !put_scalar(e, col, r, 1))
                            return 0;
                    } else if (!put_value(e, VECTOR_ELT(col, r), depth + 3, 1)) {
                        return 0;
                    }
                    newline(e);
                    pop(e);
                }
                pop(e);
            }
        } else if (is_aot(v)) {
            if (!check_depth(e, depth + 1))
                return 0;
            for (R_xlen_t r = 0; r < XLENGTH(v); r++) {
                push_index(e, r);
                if (!check_depth(e, depth + 2) || !put_header(e, h, 1))
                    return 0;
                if (!put_table_body(e, VECTOR_ELT(v, r), depth + 2, h))
                    return 0;
                pop(e);
            }
        } else {
            /* A sub-table: its header is written when it has values of its
             * own or is empty; otherwise its sub-tables' headers imply it. */
            int own = XLENGTH(v) == 0;
            for (R_xlen_t k = 0; k < XLENGTH(v) && !own; k++) {
                SEXP c = VECTOR_ELT(v, k);
                if (!is_header_kind(e, c) && !(e->na_omit && is_missing(c)))
                    own = 1;
            }
            if (own && !put_header(e, h, 0))
                return 0;
            if (!put_table_body(e, v, depth + 1, h))
                return 0;
        }
        h->n--;
        pop(e);
    }
    return 1;
}

SEXP ztm_emit(SEXP x, const ztm_emit_opts *opt, ztm_emit_result *res)
{
    emitter e;
    memset(&e, 0, sizeof e);
    e.indent = opt->indent;
    e.inline_max = opt->inline_max;
    e.width = opt->width;
    e.na_omit = opt->na_omit;
    e.literal = opt->literal;
    e.max_depth = opt->max_depth;
    header_path h = {NULL, 0, 0};
    put_table_body(&e, x, 0, &h);
    res->status = e.status;
    res->detail = e.detail;
    res->dropped = e.dropped;
    res->path = NULL;
    if (e.status != ZTM_EMIT_OK) {
        /* The key path of the offending value, as a.b[3].c. */
        emitter p;
        memset(&p, 0, sizeof p);
        for (int i = 0; i < e.npath; i++) {
            if (e.path[i].key) {
                if (i)
                    putc_(&p, '.');
                puts_(&p, e.path[i].key);
            } else {
                char tmp[32];
                snprintf(tmp, sizeof tmp, "[%.0f]", (double) e.path[i].index + 1);
                puts_(&p, tmp);
            }
        }
        putc_(&p, '\0');
        res->path = p.buf;
        return R_NilValue;
    }
    if (e.len > INT_MAX) {
        res->status = ZTM_EMIT_INVALID;
        res->detail = "the document is longer than an R string can be";
        return R_NilValue;
    }
    return Rf_mkCharLenCE(e.buf ? e.buf : "", (int) e.len, CE_UTF8);
}
