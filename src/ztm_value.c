/* Scalar values (design section 9, roadmap Stage 2). R-free.
 *
 * zufast parses digits, not TOML: its grammars are wider than TOML's in
 * every case (no prefixes or underscores for integers; "1." and "infinity"
 * for floats; "+hhmm" offsets and optional seconds for date-times). So each
 * span's TOML shape is checked here first, prefixes and underscores are
 * stripped into scratch, and only then is zufast asked for the value, with
 * the whole span required to be consumed. */
#include <math.h>
#include <string.h>

#include <zufast/datetime.h>
#include <zufast/number.h>

#include "ztm_check.h"

static ztm_status fail_tok(const ztm_token *tok, ztm_fault *fault, ztm_status s)
{
    fault->status = s;
    fault->line = tok->line;
    fault->column = tok->column;
    fault->offset = tok->offset;
    fault->limit = NULL;
    fault->limit_value = 0;
    return s;
}

static int is_dec(unsigned char c) { return c >= '0' && c <= '9'; }
static int is_hex(unsigned char c)
{
    return is_dec(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
}
static int is_oct(unsigned char c) { return c >= '0' && c <= '7'; }
static int is_bin(unsigned char c) { return c == '0' || c == '1'; }

/* s[0..n) is DIGIT *( DIGIT / "_" DIGIT ) for the digit class: at least one
 * digit, every underscore between two digits. The digits are appended to
 * out (which has room for n bytes); returns how many, or 0 when the shape
 * is wrong. */
static size_t digits_us(const unsigned char *s, size_t n, int (*digit)(unsigned char), char *out)
{
    size_t k = 0;
    if (n == 0 || !digit(s[0]))
        return 0;
    for (size_t i = 0; i < n; i++) {
        if (s[i] == '_') {
            if (i + 1 >= n || !digit(s[i + 1]) || !digit(s[i - 1])) /* GUARD: underscore_between_digits */
                return 0;
            continue;
        }
        if (!digit(s[i]))
            return 0;
        out[k++] = (char) s[i];
    }
    return k;
}

/* ---- integers ----------------------------------------------------------- */

static ztm_int_class int_class_of(int64_t v)
{
    if (v > INT32_MIN && v <= INT32_MAX)
        return ZTM_INT_FITS_INTEGER;
    if (v >= -(INT64_C(1) << 53) && v <= (INT64_C(1) << 53))
        return ZTM_INT_FITS_DOUBLE;
    return ZTM_INT_BIG;
}

static ztm_status parse_integer(const unsigned char *s, size_t n, const ztm_token *tok,
                                ztm_value *v, ztm_fault *fault)
{
    char *buf = ztm_scratch(n + 1, 1);
    size_t k = 0;
    int base = 10;
    if (n >= 2 && s[0] == '0' && (s[1] == 'x' || s[1] == 'o' || s[1] == 'b')) {
        int (*digit)(unsigned char) = s[1] == 'x' ? is_hex : s[1] == 'o' ? is_oct : is_bin;
        base = s[1] == 'x' ? 16 : s[1] == 'o' ? 8 : 2;
        k = digits_us(s + 2, n - 2, digit, buf);
        if (!k) /* GUARD: integer_prefixed_shape */
            return fail_tok(tok, fault, ZTM_ERR_INVALID_INTEGER);
    } else {
        size_t i = 0;
        if (n && (s[0] == '+' || s[0] == '-')) {
            if (s[0] == '-')
                buf[k++] = '-';
            i = 1;
        }
        size_t d = digits_us(s + i, n - i, is_dec, buf + k);
        if (!d) /* GUARD: integer_shape */
            return fail_tok(tok, fault, ZTM_ERR_INVALID_INTEGER);
        if (d > 1 && buf[k] == '0') /* GUARD: integer_leading_zero */
            return fail_tok(tok, fault, ZTM_ERR_INVALID_INTEGER);
        k += d;
    }
    zuf_num_options opt = {0u, base, 0};
    zuf_result r = zuf_parse_i64_opt(buf, buf + k, &v->i, &opt);
    if (r.status == ZUF_ERR_RANGE) /* GUARD: integer_range */
        return fail_tok(tok, fault, ZTM_ERR_INTEGER_RANGE);
    if (r.status != ZUF_OK || r.ptr != buf + k)
        return fail_tok(tok, fault, ZTM_ERR_INVALID_INTEGER);
    v->int_class = int_class_of(v->i);
    return ZTM_OK;
}

/* ---- floats ------------------------------------------------------------- */

static ztm_status parse_float(const unsigned char *s, size_t n, const ztm_token *tok,
                              ztm_value *v, ztm_fault *fault)
{
    size_t i = 0;
    int neg = 0;
    if (n && (s[0] == '+' || s[0] == '-')) {
        neg = s[0] == '-';
        i = 1;
    }
    if (n - i == 3 && (memcmp(s + i, "inf", 3) == 0 || memcmp(s + i, "nan", 3) == 0)) {
        if (s[i] == 'i')
            v->d = neg ? -HUGE_VAL : HUGE_VAL;
        else
            v->d = NAN;
        return ZTM_OK;
    }
    /* float-int-part ( frac [ exp ] / exp ), every part with underscores
     * between digits; the integer part without leading zeros. */
    char *buf = ztm_scratch(n + 2, 1);
    size_t k = 0;
    if (neg)
        buf[k++] = '-';
    size_t end_int = i;
    while (end_int < n && s[end_int] != '.' && s[end_int] != 'e' && s[end_int] != 'E')
        end_int++;
    size_t d = digits_us(s + i, end_int - i, is_dec, buf + k);
    if (!d || (d > 1 && buf[k] == '0')) /* GUARD: float_int_part */
        return fail_tok(tok, fault, ZTM_ERR_INVALID_FLOAT);
    k += d;
    size_t p = end_int;
    int has_frac = 0, has_exp = 0;
    if (p < n && s[p] == '.') {
        size_t q = p + 1;
        while (q < n && s[q] != 'e' && s[q] != 'E')
            q++;
        buf[k++] = '.';
        d = digits_us(s + p + 1, q - p - 1, is_dec, buf + k);
        if (!d) /* GUARD: float_frac */
            return fail_tok(tok, fault, ZTM_ERR_INVALID_FLOAT);
        k += d;
        p = q;
        has_frac = 1;
    }
    if (p < n && (s[p] == 'e' || s[p] == 'E')) {
        buf[k++] = 'e';
        p++;
        if (p < n && (s[p] == '+' || s[p] == '-'))
            buf[k++] = (char) s[p++];
        d = digits_us(s + p, n - p, is_dec, buf + k);
        if (!d) /* GUARD: float_exp */
            return fail_tok(tok, fault, ZTM_ERR_INVALID_FLOAT);
        k += d;
        p = n;
        has_exp = 1;
    }
    if (p != n || (!has_frac && !has_exp))
        return fail_tok(tok, fault, ZTM_ERR_INVALID_FLOAT);
    zuf_result r = zuf_parse_f64(buf, buf + k, &v->d);
    if (r.ptr != buf + k || (r.status != ZUF_OK && r.status != ZUF_ERR_RANGE))
        return fail_tok(tok, fault, ZTM_ERR_INVALID_FLOAT);
    /* Underflow to zero is rounding; overflow to infinity is a value R
     * cannot hold, refused by the build phase. */
    if (r.status == ZUF_ERR_RANGE && (v->d == HUGE_VAL || v->d == -HUGE_VAL))
        v->overflow = 1;
    return ZTM_OK;
}

/* ---- date-times --------------------------------------------------------- */

static int two_digits(const unsigned char *s) { return is_dec(s[0]) && is_dec(s[1]); }

/* The TOML shape of a time at s[0..n): HH:MM[:SS[.F+]] (seconds required
 * under 1.0.0). Returns the bytes it spans, or 0. */
static size_t time_shape(const unsigned char *s, size_t n, ztm_version version)
{
    if (n < 5 || !two_digits(s) || s[2] != ':' || !two_digits(s + 3))
        return 0;
    size_t p = 5;
    if (p < n && s[p] == ':') {
        if (p + 3 > n || !two_digits(s + p + 1))
            return 0;
        p += 3;
        if (p < n && s[p] == '.') {
            size_t q = p + 1;
            while (q < n && is_dec(s[q]))
                q++;
            if (q == p + 1) /* GUARD: fraction_digits */
                return 0;
            p = q;
        }
    } else if (version < ZTM_TOML_1_1) { /* GUARD: seconds_required_1_0 */
        return 0;
    }
    return p;
}

static ztm_status parse_datetime(const unsigned char *s, size_t n, const ztm_token *tok,
                                 ztm_version version, ztm_value *v, ztm_fault *fault)
{
    const char *first = (const char *) s, *last = first + n;
    zuf_result r;
    if (tok->type == ZTM_TOK_LOCAL_TIME) {
        size_t p = time_shape(s, n, version);
        if (p != n)
            return fail_tok(tok, fault, ZTM_ERR_INVALID_DATETIME);
        /* zufast parses no bare time (design section 3.1): a fixed date in
         * front borrows its validation of the fields. */
        char *buf = ztm_scratch(n + 11, 1);
        memcpy(buf, "2000-01-01T", 11);
        memcpy(buf + 11, s, n);
        r = zuf_parse_datetime(buf, buf + n + 11, &v->dt);
        if (r.status != ZUF_OK || r.ptr != buf + n + 11) /* GUARD: time_fields */
            return fail_tok(tok, fault, ZTM_ERR_INVALID_DATETIME);
        return ZTM_OK;
    }
    if (tok->type == ZTM_TOK_LOCAL_DATE) {
        r = zuf_parse_date(first, last, &v->dt);
        if (n != 10 || r.status != ZUF_OK || r.ptr != last) /* GUARD: date_fields */
            return fail_tok(tok, fault, ZTM_ERR_INVALID_DATETIME);
        return ZTM_OK;
    }
    /* A date, a separator, a time, and for an offset date-time Z or +-HH:MM. */
    if (n < 11 || (s[10] != 'T' && s[10] != 't' && s[10] != ' '))
        return fail_tok(tok, fault, ZTM_ERR_INVALID_DATETIME);
    size_t p = 11 + time_shape(s + 11, n - 11, version);
    if (p == 11)
        return fail_tok(tok, fault, ZTM_ERR_INVALID_DATETIME);
    if (tok->type == ZTM_TOK_DATETIME) {
        if (p + 1 == n && (s[p] == 'Z' || s[p] == 'z'))
            p++;
        else if (p + 6 == n && (s[p] == '+' || s[p] == '-') && two_digits(s + p + 1) &&
                 s[p + 3] == ':' && two_digits(s + p + 4))
            p += 6;
        else /* GUARD: offset_shape */
            return fail_tok(tok, fault, ZTM_ERR_INVALID_DATETIME);
    }
    if (p != n)
        return fail_tok(tok, fault, ZTM_ERR_INVALID_DATETIME);
    r = zuf_parse_datetime(first, last, &v->dt);
    if (r.status != ZUF_OK || r.ptr != last || !v->dt.has_time ||
        v->dt.has_offset != (tok->type == ZTM_TOK_DATETIME)) /* GUARD: datetime_fields */
        return fail_tok(tok, fault, ZTM_ERR_INVALID_DATETIME);
    return ZTM_OK;
}

/* ---- strings ------------------------------------------------------------ */

static size_t put_utf8(char *o, uint32_t cp)
{
    if (cp < 0x80) {
        o[0] = (char) cp;
        return 1;
    }
    if (cp < 0x800) {
        o[0] = (char) (0xC0 | (cp >> 6));
        o[1] = (char) (0x80 | (cp & 0x3F));
        return 2;
    }
    if (cp < 0x10000) {
        o[0] = (char) (0xE0 | (cp >> 12));
        o[1] = (char) (0x80 | ((cp >> 6) & 0x3F));
        o[2] = (char) (0x80 | (cp & 0x3F));
        return 3;
    }
    o[0] = (char) (0xF0 | (cp >> 18));
    o[1] = (char) (0x80 | ((cp >> 12) & 0x3F));
    o[2] = (char) (0x80 | ((cp >> 6) & 0x3F));
    o[3] = (char) (0x80 | (cp & 0x3F));
    return 4;
}

static uint32_t hex_run(const unsigned char *s, size_t ndig)
{
    uint32_t cp = 0;
    for (size_t k = 0; k < ndig; k++) {
        unsigned char c = s[k];
        cp = cp * 16 + (uint32_t) (c <= '9' ? c - '0' : (c | 0x20) - 'a' + 10);
    }
    return cp;
}

/* Decodes a string token the lexer has already validated, so no check here
 * can fail: the escapes are known good and the decoded length is known. */
static void decode_string(const ztm_lexer *lx, const ztm_token *tok, const char **out,
                          size_t *outn, int *has_nul)
{
    const unsigned char *b = lx->buf;
    int ml = tok->type == ZTM_TOK_ML_BASIC_STRING || tok->type == ZTM_TOK_ML_LITERAL_STRING;
    int basic = tok->type == ZTM_TOK_BASIC_STRING || tok->type == ZTM_TOK_ML_BASIC_STRING;
    size_t delim = ml ? 3 : 1;
    size_t p = tok->offset + delim, end = tok->offset + tok->len - delim;
    if (ml) {
        if (p < end && b[p] == '\n')
            p++;
        else if (p + 1 < end && b[p] == '\r' && b[p + 1] == '\n')
            p += 2;
    }
    char *o = ztm_scratch(tok->decoded + 1, 1);
    size_t k = 0;
    *has_nul = 0;
    while (p < end) {
        unsigned char c = b[p];
        if (c == '\r' && p + 1 < end && b[p + 1] == '\n') {
            o[k++] = '\n';
            p += 2;
            continue;
        }
        if (c != '\\' || !basic) {
            o[k++] = (char) c;
            p++;
            continue;
        }
        unsigned char e = b[p + 1];
        uint32_t cp;
        switch (e) {
        case 'b': o[k++] = '\b'; p += 2; continue;
        case 't': o[k++] = '\t'; p += 2; continue;
        case 'n': o[k++] = '\n'; p += 2; continue;
        case 'f': o[k++] = '\f'; p += 2; continue;
        case 'r': o[k++] = '\r'; p += 2; continue;
        case 'e': o[k++] = '\x1B'; p += 2; continue;
        case '"': o[k++] = '"'; p += 2; continue;
        case '\\': o[k++] = '\\'; p += 2; continue;
        case 'x': cp = hex_run(b + p + 2, 2); p += 4; break;
        case 'u': cp = hex_run(b + p + 2, 4); p += 6; break;
        case 'U': cp = hex_run(b + p + 2, 8); p += 10; break;
        default:
            /* A line-ending backslash: skip whitespace and newlines. */
            p++;
            while (p < end && (b[p] == ' ' || b[p] == '\t' || b[p] == '\n' || b[p] == '\r'))
                p++;
            continue;
        }
        if (cp == 0)
            *has_nul = 1;
        k += put_utf8(o + k, cp);
    }
    *out = o;
    *outn = k;
}

void ztm_key_of(ztm_lexer *lx, const ztm_token *tok, const char **s, size_t *n, int *has_nul)
{
    if (tok->type == ZTM_TOK_BARE_KEY) {
        *s = (const char *) lx->buf + tok->offset;
        *n = tok->len;
        *has_nul = 0;
        return;
    }
    decode_string(lx, tok, s, n, has_nul);
}

ztm_status ztm_value_of(ztm_lexer *lx, const ztm_token *tok, ztm_value *v, ztm_fault *fault)
{
    const unsigned char *s = lx->buf + tok->offset;
    memset(v, 0, sizeof *v);
    v->type = tok->type;
    switch (tok->type) {
    case ZTM_TOK_BASIC_STRING:
    case ZTM_TOK_LITERAL_STRING:
    case ZTM_TOK_ML_BASIC_STRING:
    case ZTM_TOK_ML_LITERAL_STRING:
        decode_string(lx, tok, &v->s, &v->n, &v->has_nul);
        return ZTM_OK;
    case ZTM_TOK_BOOL:
        v->b = s[0] == 't';
        return ZTM_OK;
    case ZTM_TOK_INTEGER:
        return parse_integer(s, tok->len, tok, v, fault);
    case ZTM_TOK_FLOAT:
        return parse_float(s, tok->len, tok, v, fault);
    case ZTM_TOK_DATETIME:
    case ZTM_TOK_LOCAL_DATETIME:
    case ZTM_TOK_LOCAL_DATE:
    case ZTM_TOK_LOCAL_TIME:
        return parse_datetime(s, tok->len, tok, lx->version, v, fault);
    default:
        return ZTM_OK;
    }
}
