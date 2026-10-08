/* The .Call entry points (R side). C never raises: a fault comes back as a
 * list R turns into a classed condition (R/conditions.R, design D16). */
#define R_NO_REMAP
#include <math.h>
#include <R.h>
#include <Rinternals.h>

#include <zufast/datetime.h>
#include <zufast/number.h>

#include "ztm_check.h"
#include "ztm_r.h"

/* A limit argument, validated in R (R/args.R): a positive whole double, or
 * Inf, which means no limit. */
static uint64_t limit_arg(SEXP x)
{
    double v = Rf_asReal(x);
    if (!R_FINITE(v) || v >= 18446744073709551615.0)
        return UINT64_MAX;
    return (uint64_t) v;
}

void ztm_opts_from_r(ztm_opts *opt, SEXP version, SEXP max_size, SEXP max_string)
{
    opt->version = Rf_asInteger(version) == 10 ? ZTM_TOML_1_0 : ZTM_TOML_1_1;
    opt->max_size = limit_arg(max_size);
    opt->max_string = limit_arg(max_string);
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
    switch (v->type) {
    case ZTM_TOK_BASIC_STRING:
    case ZTM_TOK_LITERAL_STRING:
    case ZTM_TOK_ML_BASIC_STRING:
    case ZTM_TOK_ML_LITERAL_STRING:
        if (v->has_nul)
            return NA_STRING;
        return Rf_mkCharLenCE(v->s, (int) v->n, CE_UTF8);
    case ZTM_TOK_BOOL:
        return Rf_mkChar(v->b ? "true" : "false");
    case ZTM_TOK_INTEGER:
        n = i64_text(buf, v->i);
        break;
    case ZTM_TOK_FLOAT:
        n = zuf_format_f64(buf, sizeof buf, v->d);
        break;
    case ZTM_TOK_DATETIME:
    case ZTM_TOK_LOCAL_DATETIME:
    case ZTM_TOK_LOCAL_DATE:
        n = zuf_format_datetime(buf, sizeof buf, &v->dt);
        break;
    case ZTM_TOK_LOCAL_TIME:
        /* Formatted on the borrowed date (ztm_value.c), date dropped. */
        n = zuf_format_datetime(buf, sizeof buf, &v->dt);
        return Rf_mkCharLen(buf + 11, (int) n - 11);
    default:
        return NA_STRING;
    }
    return Rf_mkCharLen(buf, (int) n);
}

static const char *value_class(const ztm_value *v)
{
    switch (v->type) {
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
    ztm_opts_from_r(&opt, version, max_size, max_string);
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
