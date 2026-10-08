/* The .Call entry points (R side). C never raises: a fault comes back as a
 * list R turns into a classed condition (R/conditions.R, design D16). */
#define R_NO_REMAP
#include <math.h>
#include <string.h>
#include <R.h>
#include <Rinternals.h>

#include <zufast/datetime.h>
#include <zufast/number.h>
#include <zufast/version.h>

#include "ztm_build.h"
#include "ztm_emit.h"
#include "ztm_check.h"
#include "ztm_r.h"

/* A limit argument, validated in R (R/args.R): a positive whole double, or
 * Inf, which means no limit. */
static uint64_t limit_arg(SEXP x)
{
    if (Rf_isNull(x))
        return UINT64_MAX;
    double v = Rf_asReal(x);
    if (!R_FINITE(v) || v >= 18446744073709551615.0)
        return UINT64_MAX;
    return (uint64_t) v;
}

void ztm_opts_from_r(ztm_opts *opt, SEXP version, SEXP max_size, SEXP max_depth,
                     SEXP max_items, SEXP max_string)
{
    opt->version = Rf_asInteger(version) == 10 ? ZTM_TOML_1_0 : ZTM_TOML_1_1;
    opt->max_size = limit_arg(max_size);
    opt->max_items = limit_arg(max_items);
    opt->max_string = limit_arg(max_string);
    uint64_t depth = limit_arg(max_depth);
    opt->max_depth = depth >= UINT32_MAX ? UINT32_MAX - 1 : (uint32_t) depth;
}

static SEXP mk_named_list(int n, const char **names)
{
    SEXP out = PROTECT(Rf_allocVector(VECSXP, n));
    SEXP nm = PROTECT(Rf_allocVector(STRSXP, n));
    for (int i = 0; i < n; i++)
        SET_STRING_ELT(nm, i, Rf_mkChar(names[i]));
    Rf_setAttrib(out, R_NamesSymbol, nm);
    UNPROTECT(2);
    return out;
}

/* A position, 0 meaning none (size_limit has no position), becomes NA. */
static SEXP position(size_t v, int one_based)
{
    if (one_based && v == 0)
        return Rf_ScalarReal(NA_REAL);
    return Rf_ScalarReal((double) v);
}

SEXP ztm_fault_to_r(const ztm_fault *fault)
{
    static const char *names[] = {"status", "line", "column", "offset", "limit", "limit_value"};
    SEXP out = PROTECT(mk_named_list(6, names));
    SET_VECTOR_ELT(out, 0, Rf_mkString(ztm_status_name(fault->status)));
    SET_VECTOR_ELT(out, 1, position(fault->line, 1));
    SET_VECTOR_ELT(out, 2, position(fault->column, 1));
    SET_VECTOR_ELT(out, 3, fault->line ? position(fault->offset, 0) : Rf_ScalarReal(NA_REAL));
    SET_VECTOR_ELT(out, 4, fault->limit ? Rf_mkString(fault->limit) : Rf_ScalarString(NA_STRING));
    SET_VECTOR_ELT(out, 5, Rf_ScalarReal(fault->limit
                                         ? (fault->limit_value == UINT64_MAX ? R_PosInf : (double) fault->limit_value)
                                         : NA_REAL));
    UNPROTECT(1);
    return out;
}

SEXP zutoml_status_names(void)
{
    SEXP out = PROTECT(Rf_allocVector(STRSXP, ZTM_STATUS_COUNT - 1));
    for (int i = 1; i < ZTM_STATUS_COUNT; i++)
        SET_STRING_ELT(out, i - 1, Rf_mkChar(ztm_status_name((ztm_status) i)));
    UNPROTECT(1);
    return out;
}

/* The decimal text of v. */
static size_t i64_text(char *out, int64_t v)
{
    char tmp[24];
    size_t n = 0, k = 0;
    uint64_t u = v < 0 ? 0u - (uint64_t) v : (uint64_t) v;
    do {
        tmp[n++] = (char) ('0' + u % 10u);
        u /= 10u;
    } while (u);
    if (v < 0)
        out[k++] = '-';
    while (n)
        out[k++] = tmp[--n];
    return k;
}

/* A value as text, for the token table's `value` column: strings decoded,
 * numbers in canonical decimal, date-times in RFC 3339. NA for a string
 * holding U+0000, which no CHARSXP can. */
static SEXP value_text(const ztm_value *v)
{
    char buf[64];
    size_t n = 0;
    switch ((ztm_tok_type) v->type) {
    case ZTM_TOK_BASIC_STRING:
    case ZTM_TOK_LITERAL_STRING:
    case ZTM_TOK_ML_BASIC_STRING:
    case ZTM_TOK_ML_LITERAL_STRING:
        if (v->has_nul)
            return NA_STRING;
        return Rf_mkCharLenCE(v->u.str.s, (int) v->u.str.n, CE_UTF8);
    case ZTM_TOK_BOOL:
        return Rf_mkChar(v->u.b ? "true" : "false");
    case ZTM_TOK_INTEGER:
        n = i64_text(buf, v->u.i);
        break;
    case ZTM_TOK_FLOAT:
        n = zuf_format_f64(buf, sizeof buf, v->u.d);
        break;
    case ZTM_TOK_DATETIME:
    case ZTM_TOK_LOCAL_DATETIME:
    case ZTM_TOK_LOCAL_DATE:
        n = zuf_format_datetime(buf, sizeof buf, &v->u.dt);
        break;
    case ZTM_TOK_LOCAL_TIME:
        /* Formatted on the borrowed date (ztm_value.c), date dropped. */
        n = zuf_format_datetime(buf, sizeof buf, &v->u.dt);
        return Rf_mkCharLen(buf + 11, (int) n - 11);
    default:
        return NA_STRING;
    }
    return Rf_mkCharLen(buf, (int) n);
}

static const char *value_class(const ztm_value *v)
{
    switch ((ztm_tok_type) v->type) {
    case ZTM_TOK_INTEGER:
        return v->int_class == ZTM_INT_FITS_INTEGER ? "integer"
               : v->int_class == ZTM_INT_FITS_DOUBLE ? "double" : "bigint";
    case ZTM_TOK_FLOAT:
        return v->overflow ? "overflow" : "";
    case ZTM_TOK_BASIC_STRING:
    case ZTM_TOK_LITERAL_STRING:
    case ZTM_TOK_ML_BASIC_STRING:
    case ZTM_TOK_ML_LITERAL_STRING:
        return v->has_nul ? "nul" : "";
    default:
        return "";
    }
}

/* zutoml_tokens(x, version, max_size, max_string): the token table of a raw vector,
 * or list(fault = <fault>). Internal (roadmap Stage 1): the lexer's tests
 * and tools/run-conformance read it. */
SEXP zutoml_tokens(SEXP x, SEXP version, SEXP max_size, SEXP max_string)
{
    ztm_opts opt;
    ztm_fault fault;
    ztm_token *toks = NULL;
    ztm_value *vals = NULL;
    size_t n = 0;
    ztm_opts_from_r(&opt, version, max_size, R_NilValue, R_NilValue, max_string);
    ztm_status s = ztm_tokenize(RAW(x), (size_t) XLENGTH(x), &opt, &toks, &vals, &n, &fault);
    if (s != ZTM_OK) {
        static const char *names[] = {"fault"};
        SEXP out = PROTECT(mk_named_list(1, names));
        SET_VECTOR_ELT(out, 0, ztm_fault_to_r(&fault));
        UNPROTECT(1);
        return out;
    }
    static const char *names[] = {"type", "offset", "len", "line", "column", "decoded",
                                  "value", "class"};
    SEXP out = PROTECT(mk_named_list(8, names));
    SEXP value = Rf_allocVector(STRSXP, (R_xlen_t) n);
    SET_VECTOR_ELT(out, 6, value);
    SEXP klass = Rf_allocVector(STRSXP, (R_xlen_t) n);
    SET_VECTOR_ELT(out, 7, klass);
    SEXP type = Rf_allocVector(STRSXP, (R_xlen_t) n);
    SET_VECTOR_ELT(out, 0, type);
    double *col[5];
    for (int k = 0; k < 5; k++) {
        SEXP v = Rf_allocVector(REALSXP, (R_xlen_t) n);
        SET_VECTOR_ELT(out, k + 1, v);
        col[k] = REAL(v);
    }
    for (size_t i = 0; i < n; i++) {
        SET_STRING_ELT(type, (R_xlen_t) i, Rf_mkChar(ztm_tok_name(toks[i].type)));
        col[0][i] = (double) toks[i].offset;
        col[1][i] = (double) toks[i].len;
        col[2][i] = (double) toks[i].line;
        col[3][i] = (double) toks[i].column;
        col[4][i] = (double) toks[i].decoded;
        SET_STRING_ELT(value, (R_xlen_t) i, value_text(&vals[i]));
        SET_STRING_ELT(klass, (R_xlen_t) i, Rf_mkChar(value_class(&vals[i])));
    }
    UNPROTECT(1);
    return out;
}

/* zutoml_check(x, version, max_size, max_depth, max_items, max_string): the
 * whole check phase (toml_validate()). NULL when the document is TOML, or
 * the fault. */
SEXP zutoml_check(SEXP x, SEXP version, SEXP max_size, SEXP max_depth, SEXP max_items,
                  SEXP max_string)
{
    ztm_opts opt;
    ztm_fault fault;
    ztm_doc doc;
    ztm_opts_from_r(&opt, version, max_size, max_depth, max_items, max_string);
    if (ztm_parse(RAW(x), (size_t) XLENGTH(x), &opt, &doc, &fault) != ZTM_OK)
        return ztm_fault_to_r(&fault);
    return R_NilValue;
}

/* zutoml_parse(x, version, max_size, max_depth, max_items, max_string,
 * simplify, big_integers, datetimes, local_time, positions): toml_parse().
 * A list of `value`, `fault` (NULL or the fault), `has_local` and
 * `positions` (NULL unless asked for). */
SEXP zutoml_parse(SEXP x, SEXP version, SEXP max_size, SEXP max_depth, SEXP max_items,
                  SEXP max_string, SEXP simplify, SEXP big_integers, SEXP datetimes,
                  SEXP local_time, SEXP positions)
{
    ztm_opts opt;
    ztm_fault fault;
    ztm_doc doc;
    static const char *names[] = {"value", "fault", "has_local", "positions"};
    ztm_opts_from_r(&opt, version, max_size, max_depth, max_items, max_string);
    SEXP out = PROTECT(mk_named_list(4, names));
    if (ztm_parse(RAW(x), (size_t) XLENGTH(x), &opt, &doc, &fault) != ZTM_OK) {
        SET_VECTOR_ELT(out, 1, ztm_fault_to_r(&fault));
        UNPROTECT(1);
        return out;
    }
    ztm_builder b;
    memset(&b, 0, sizeof b);
    b.doc = &doc;
    b.simplify = Rf_asLogical(simplify) == TRUE;
    b.big_integers = Rf_asInteger(big_integers);
    b.datetimes = Rf_asInteger(datetimes);
    b.local_time = Rf_asInteger(local_time);
    SEXP value = ztm_build(&b);
    SET_VECTOR_ELT(out, 0, value);
    if (b.fault.status != ZTM_OK)
        SET_VECTOR_ELT(out, 1, ztm_fault_to_r(&b.fault));
    SET_VECTOR_ELT(out, 2, Rf_ScalarLogical(b.has_local));
    if (b.fault.status == ZTM_OK && Rf_asLogical(positions) == TRUE)
        SET_VECTOR_ELT(out, 3, ztm_positions(&doc));
    UNPROTECT(1);
    return out;
}

/* zutoml_emit(x, indent, inline, width, na_omit, literal, max_depth):
 * toml_emit(). A list of `text` (NULL on failure), `status`, `detail`,
 * `path` and `dropped`. */
SEXP zutoml_emit(SEXP x, SEXP indent, SEXP inline_max, SEXP width, SEXP na_omit,
                 SEXP literal, SEXP max_depth)
{
    static const char *names[] = {"text", "status", "detail", "path", "dropped"};
    static const char *statuses[] = {"ok", "unsupported_type", "na", "invalid", "depth_limit"};
    ztm_emit_opts opt;
    ztm_emit_result res;
    opt.indent = Rf_asInteger(indent);
    opt.inline_max = Rf_asInteger(inline_max);
    opt.width = Rf_asInteger(width);
    opt.na_omit = Rf_asLogical(na_omit) == TRUE;
    opt.literal = Rf_asLogical(literal) == TRUE;
    opt.max_depth = Rf_asInteger(max_depth);
    SEXP out = PROTECT(mk_named_list(5, names));
    SEXP text = PROTECT(ztm_emit(x, &opt, &res));
    if (res.status == ZTM_EMIT_OK)
        SET_VECTOR_ELT(out, 0, Rf_ScalarString(text));
    SET_VECTOR_ELT(out, 1, Rf_mkString(statuses[res.status]));
    SET_VECTOR_ELT(out, 2, res.detail ? Rf_mkString(res.detail) : Rf_ScalarString(NA_STRING));
    SET_VECTOR_ELT(out, 3, res.path ? Rf_mkString(res.path) : Rf_ScalarString(NA_STRING));
    SET_VECTOR_ELT(out, 4, Rf_ScalarLogical(res.dropped));
    UNPROTECT(2);
    return out;
}

/* zutoml_build_info(): what zutoml_info() reports from the compiled code. */
SEXP zutoml_build_info(void)
{
    static const char *names[] = {"zufast", "max_depth_cap", "ndebug"};
    SEXP out = PROTECT(mk_named_list(3, names));
    SET_VECTOR_ELT(out, 0, Rf_mkString(ZUFAST_VERSION));
    SET_VECTOR_ELT(out, 1, Rf_ScalarInteger(ZTM_MAX_DEPTH_CAP));
#ifdef NDEBUG
    SET_VECTOR_ELT(out, 2, Rf_ScalarLogical(TRUE));
#else
    SET_VECTOR_ELT(out, 2, Rf_ScalarLogical(FALSE));
#endif
    UNPROTECT(1);
    return out;
}
