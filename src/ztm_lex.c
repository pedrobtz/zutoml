/* The lexer (design section 9, roadmap Stage 1). R-free: it includes no R
 * header, so the fuzz target compiles it standalone.
 *
 * Every byte of the document becomes part of a token, whitespace or a
 * comment, or the scan stops with a positioned fault. The lexer is
 * iterative and pull-based: the caller says whether a key or a value comes
 * next (ztm_mode), since TOML's lexical grammar depends on it. Strings are
 * validated here, escapes included, and their decoded length is measured
 * for max_string; decoding them is Stage 2's. Number and date-time spans
 * are classified by shape only; their values and full shape checks are
 * Stage 2's too. */
#include <string.h>

#include <zufast/utf8.h>

#include "ztm_check.h"

/* ---- positions ---------------------------------------------------------- */

/* The column, in code points, of `off`, which lies on the current line.
 * Columns are asked for in increasing order within a line, so the count
 * resumes from the last answer: linear in the line, not quadratic. */
static size_t ztm_column(ztm_lexer *lx, size_t off)
{
    if (lx->col_offset < lx->line_start || lx->col_offset > off) {
        lx->col_offset = lx->line_start;
        lx->col = 1;
    }
    for (size_t i = lx->col_offset; i < off; i++)
        if ((lx->buf[i] & 0xC0) != 0x80)
            lx->col++;
    lx->col_offset = off;
    return lx->col;
}

static ztm_status fail(ztm_lexer *lx, ztm_fault *fault, ztm_status s, size_t off)
{
    fault->status = s;
    fault->line = lx->line;
    fault->column = ztm_column(lx, off);
    fault->offset = off;
    fault->limit = NULL;
    fault->limit_value = 0;
    return s;
}

static void newline_at(ztm_lexer *lx, size_t next_line_start)
{
    lx->line++;
    lx->line_start = next_line_start;
}

/* ---- UTF-8 -------------------------------------------------------------- */

/* The offset of the first byte that does not begin a well-formed UTF-8
 * sequence. Only called once zuf_utf8_valid() has said there is one, so its
 * speed does not matter; it rejects what zufast rejects: overlongs,
 * surrogates and code points beyond U+10FFFF. */
static size_t utf8_first_invalid(const unsigned char *s, size_t n)
{
    size_t i = 0;
    while (i < n) {
        unsigned char b = s[i];
        size_t need;
        unsigned char lo = 0x80, hi = 0xBF;
        if (b < 0x80) { i++; continue; }
        else if (b >= 0xC2 && b <= 0xDF) need = 1;
        else if (b == 0xE0) { need = 2; lo = 0xA0; }
        else if (b == 0xED) { need = 2; hi = 0x9F; }
        else if (b >= 0xE1 && b <= 0xEF) need = 2;
        else if (b == 0xF0) { need = 3; lo = 0x90; }
        else if (b == 0xF4) { need = 3; hi = 0x8F; }
        else if (b >= 0xF1 && b <= 0xF3) need = 3;
        else return i;
        if (i + need >= n) return i;   /* the sequence is cut short */
        if (s[i + 1] < lo || s[i + 1] > hi) return i;
        for (size_t k = 2; k <= need; k++)
            if ((s[i + k] & 0xC0) != 0x80) return i;
        i += need + 1;
    }
    return n;
}

ztm_status ztm_lex_init(ztm_lexer *lx, const unsigned char *buf, size_t len,
                        const ztm_opts *opt, ztm_fault *fault)
{
    memset(lx, 0, sizeof *lx);
    memset(fault, 0, sizeof *fault);
    lx->buf = buf;
    lx->len = len;
    lx->line = 1;
    lx->col = 1;
    lx->max_string = opt->max_string;
    lx->version = opt->version;
    if ((uint64_t) len > opt->max_size) { /* GUARD: max_size */
        fault->status = ZTM_ERR_SIZE_LIMIT;
        fault->limit = "max_size";
        fault->limit_value = opt->max_size;
        return fault->status;
    }
    if (!zuf_utf8_valid((const char *) buf, len)) {
        size_t bad = utf8_first_invalid(buf, len);
        for (size_t i = 0; i < bad; i++)
            if (buf[i] == '\n')
                newline_at(lx, i + 1);
        return fail(lx, fault, ZTM_ERR_INVALID_UTF8, bad);
    }
    if (len >= 3 && buf[0] == 0xEF && buf[1] == 0xBB && buf[2] == 0xBF) {
        lx->pos = 3;
        lx->line_start = 3;
        lx->col_offset = 3;
    }
    return ZTM_OK;
}

/* ---- character classes -------------------------------------------------- */

/* A control character TOML forbids unescaped: U+0000-U+001F but tab, and
 * U+007F. Newlines are dealt with before this is asked. */
static int is_control(unsigned char c)
{
    return (c < 0x20 && c != '\t') || c == 0x7F;
}

static int is_bare_key_char(unsigned char c)
{
    return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
           (c >= '0' && c <= '9') || c == '_' || c == '-';
}

/* Bytes that may appear in a number, boolean or date-time span. */
static int is_scalar_char(unsigned char c)
{
    return is_bare_key_char(c) || c == '+' || c == '.' || c == ':';
}

static int is_digit(unsigned char c) { return c >= '0' && c <= '9'; }

static int hex_value(unsigned char c)
{
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

static size_t utf8_len(uint32_t cp)
{
    return cp < 0x80 ? 1 : cp < 0x800 ? 2 : cp < 0x10000 ? 3 : 4;
}

/* ---- strings ------------------------------------------------------------ */

/* An escape at lx->buf[p] == '\\' inside a basic string: advances *pp past
 * it and adds its decoded length. The line-ending backslash of multi-line
 * strings is handled by the caller. */
static int is_escape_char(unsigned char e)
{
    switch (e) {
    case 'b': case 't': case 'n': case 'f': case 'r': case '"': case '\\':
    case 'u': case 'U': case 'e': case 'x':
        return 1;
    default:
        return 0;
    }
}

static ztm_status lex_escape(ztm_lexer *lx, size_t *pp, size_t *decoded, ztm_fault *fault)
{
    size_t p = *pp;
    if (p + 1 >= lx->len)
        return fail(lx, fault, ZTM_ERR_UNTERMINATED_STRING, lx->len);
    unsigned char e = lx->buf[p + 1];
    if (!is_escape_char(e)) /* GUARD: bad_escape */
        return fail(lx, fault, ZTM_ERR_BAD_ESCAPE, p);
    switch (e) {
    case 'b': case 't': case 'n': case 'f': case 'r': case '"': case '\\':
        *decoded += 1;
        *pp = p + 2;
        return ZTM_OK;
    case 'e': /* TOML 1.1: escape, U+001B */
        if (lx->version < ZTM_TOML_1_1) /* GUARD: escape_e_1_0 */
            return fail(lx, fault, ZTM_ERR_BAD_ESCAPE, p);
        *decoded += 1;
        *pp = p + 2;
        return ZTM_OK;
    case 'x': case 'u': case 'U': {
        if (e == 'x' && lx->version < ZTM_TOML_1_1) /* GUARD: escape_x_1_0 */
            return fail(lx, fault, ZTM_ERR_BAD_ESCAPE, p);
        size_t ndig = e == 'x' ? 2 : e == 'u' ? 4 : 8;
        uint32_t cp = 0;
        for (size_t k = 0; k < ndig; k++) {
            int h = p + 2 + k < lx->len ? hex_value(lx->buf[p + 2 + k]) : -1;
            if (h < 0) /* GUARD: unicode_escape_digits */
                return fail(lx, fault, ZTM_ERR_BAD_UNICODE_ESCAPE, p);
            cp = cp * 16 + (uint32_t) h;
        }
        if (cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF)) /* GUARD: unicode_scalar */
            return fail(lx, fault, ZTM_ERR_BAD_UNICODE_ESCAPE, p);
        *decoded += utf8_len(cp);
        *pp = p + 2 + ndig;
        return ZTM_OK;
    }
    default:
        /* Unreachable while the bad_escape guard stands; with it removed
         * (tools/run-mutation-check), an unknown escape decodes as itself. */
        *decoded += 1;
        *pp = p + 2;
        return ZTM_OK;
    }
}

static ztm_status check_string_limit(ztm_lexer *lx, ztm_token *tok, ztm_fault *fault)
{
    if ((uint64_t) tok->decoded > lx->max_string) { /* GUARD: max_string */
        fail(lx, fault, ZTM_ERR_STRING_LIMIT, tok->offset);
        fault->line = tok->line;
        fault->column = tok->column;
        fault->limit = "max_string";
        fault->limit_value = lx->max_string;
        return fault->status;
    }
    return ZTM_OK;
}

/* A single-line string, basic (q == '"') or literal (q == '\''), whose
 * opening quote is at lx->pos. */
static ztm_status lex_string(ztm_lexer *lx, unsigned char q, ztm_token *tok, ztm_fault *fault)
{
    size_t p = lx->pos + 1, decoded = 0;
    for (;;) {
        if (p >= lx->len)
            return fail(lx, fault, ZTM_ERR_UNTERMINATED_STRING, p);
        unsigned char c = lx->buf[p];
        if (c == q)
            break;
        if (c == '\n' || (c == '\r' && p + 1 < lx->len && lx->buf[p + 1] == '\n'))
            return fail(lx, fault, ZTM_ERR_UNTERMINATED_STRING, p);
        if (is_control(c)) /* GUARD: control_in_string */
            return fail(lx, fault, ZTM_ERR_CONTROL_CHARACTER, p);
        if (c == '\\' && q == '"') {
            ztm_status s = lex_escape(lx, &p, &decoded, fault);
            if (s) return s;
            continue;
        }
        decoded++;
        p++;
    }
    tok->type = q == '"' ? ZTM_TOK_BASIC_STRING : ZTM_TOK_LITERAL_STRING;
    tok->len = p + 1 - lx->pos;
    tok->decoded = decoded;
    lx->pos = p + 1;
    return check_string_limit(lx, tok, fault);
}

/* A multi-line string whose opening triple quote is at lx->pos. A newline
 * right after the delimiter is trimmed; CRLF decodes as LF; up to two quotes
 * may sit against the closing delimiter. */
static ztm_status lex_ml_string(ztm_lexer *lx, unsigned char q, ztm_token *tok, ztm_fault *fault)
{
    size_t p = lx->pos + 3, decoded = 0;
    if (p < lx->len && lx->buf[p] == '\n') {
        newline_at(lx, ++p);
    } else if (p + 1 < lx->len && lx->buf[p] == '\r' && lx->buf[p + 1] == '\n') {
        p += 2;
        newline_at(lx, p);
    }
    for (;;) {
        if (p >= lx->len)
            return fail(lx, fault, ZTM_ERR_UNTERMINATED_STRING, p);
        unsigned char c = lx->buf[p];
        if (c == q) {
            size_t run = 0;
            while (p + run < lx->len && lx->buf[p + run] == q)
                run++;
            if (run >= 3) {
                size_t content = run - 3 > 2 ? 2 : run - 3;
                decoded += content;
                p += content + 3;
                break;
            }
            decoded += run;
            p += run;
            continue;
        }
        if (c == '\n') {
            decoded++;
            newline_at(lx, ++p);
            continue;
        }
        if (c == '\r' && p + 1 < lx->len && lx->buf[p + 1] == '\n') {
            decoded++;
            p += 2;
            newline_at(lx, p);
            continue;
        }
        if (is_control(c)) /* GUARD: control_in_ml_string */
            return fail(lx, fault, ZTM_ERR_CONTROL_CHARACTER, p);
        if (c == '\\' && q == '"') {
            /* A line-ending backslash: whitespace, then a newline, then all
             * whitespace and newlines up to the next other character go. */
            size_t k = p + 1;
            while (k < lx->len && (lx->buf[k] == ' ' || lx->buf[k] == '\t'))
                k++;
            int nl = k < lx->len && (lx->buf[k] == '\n' ||
                     (lx->buf[k] == '\r' && k + 1 < lx->len && lx->buf[k + 1] == '\n'));
            if (nl) {
                while (k < lx->len) {
                    unsigned char w = lx->buf[k];
                    if (w == ' ' || w == '\t') {
                        k++;
                    } else if (w == '\n') {
                        newline_at(lx, ++k);
                    } else if (w == '\r' && k + 1 < lx->len && lx->buf[k + 1] == '\n') {
                        k += 2;
                        newline_at(lx, k);
                    } else {
                        break;
                    }
                }
                p = k;
                continue;
            }
            ztm_status s = lex_escape(lx, &p, &decoded, fault);
            if (s) return s;
            continue;
        }
        decoded++;
        p++;
    }
    tok->type = q == '"' ? ZTM_TOK_ML_BASIC_STRING : ZTM_TOK_ML_LITERAL_STRING;
    tok->len = p - lx->pos;
    tok->decoded = decoded;
    lx->pos = p;
    return check_string_limit(lx, tok, fault);
}

/* ---- scalars ------------------------------------------------------------ */

static int is_date_prefix(const unsigned char *s, size_t n)
{
    return n >= 10 && is_digit(s[0]) && is_digit(s[1]) && is_digit(s[2]) &&
           is_digit(s[3]) && s[4] == '-' && is_digit(s[5]) && is_digit(s[6]) &&
           s[7] == '-' && is_digit(s[8]) && is_digit(s[9]);
}

static int span_is(const unsigned char *s, size_t n, const char *lit)
{
    return n == strlen(lit) && memcmp(s, lit, n) == 0;
}

/* The token type of a scalar span, by shape alone (design section 9);
 * ZTM_TOK_EOF when the span is no TOML value. */
static ztm_tok_type classify(const unsigned char *s, size_t n)
{
    if (span_is(s, n, "true") || span_is(s, n, "false"))
        return ZTM_TOK_BOOL;
    const unsigned char *u = s;
    size_t m = n;
    if (m && (u[0] == '+' || u[0] == '-')) { u++; m--; }
    if (span_is(u, m, "inf") || span_is(u, m, "nan"))
        return ZTM_TOK_FLOAT;
    if (is_date_prefix(s, n)) {
        if (n == 10)
            return ZTM_TOK_LOCAL_DATE;
        if (s[10] != 'T' && s[10] != 't' && s[10] != ' ')
            return ZTM_TOK_EOF;
        if (s[n - 1] == 'Z' || s[n - 1] == 'z')
            return ZTM_TOK_DATETIME;
        for (size_t i = 11; i < n; i++)
            if (s[i] == '+' || s[i] == '-')
                return ZTM_TOK_DATETIME;
        return ZTM_TOK_LOCAL_DATETIME;
    }
    if (n >= 5 && is_digit(s[0]) && is_digit(s[1]) && s[2] == ':')
        return ZTM_TOK_LOCAL_TIME;
    if (!m || !is_digit(u[0]))
        return ZTM_TOK_EOF;
    if (n >= 2 && s[0] == '0' && (s[1] == 'x' || s[1] == 'o' || s[1] == 'b'))
        return ZTM_TOK_INTEGER;
    for (size_t i = 0; i < n; i++)
        if (s[i] == '.' || s[i] == 'e' || s[i] == 'E')
            return ZTM_TOK_FLOAT;
    return ZTM_TOK_INTEGER;
}

static ztm_status lex_scalar(ztm_lexer *lx, ztm_token *tok, ztm_fault *fault)
{
    size_t p = lx->pos;
    while (p < lx->len && is_scalar_char(lx->buf[p]))
        p++;
    /* A date and a time separated by one space are one value. */
    if (p - lx->pos == 10 && is_date_prefix(lx->buf + lx->pos, 10) &&
        p + 3 < lx->len && lx->buf[p] == ' ' && is_digit(lx->buf[p + 1]) &&
        is_digit(lx->buf[p + 2]) && lx->buf[p + 3] == ':') {
        p++;
        while (p < lx->len && is_scalar_char(lx->buf[p]))
            p++;
    }
    tok->type = classify(lx->buf + lx->pos, p - lx->pos);
    if (tok->type == ZTM_TOK_EOF) /* GUARD: invalid_value */
        return fail(lx, fault, ZTM_ERR_INVALID_VALUE, lx->pos);
    tok->len = p - lx->pos;
    lx->pos = p;
    return ZTM_OK;
}

/* ---- the lexer ---------------------------------------------------------- */

/* Skips spaces, tabs and comments; stops at a newline or anything else. */
static ztm_status skip_blank(ztm_lexer *lx, ztm_fault *fault)
{
    while (lx->pos < lx->len) {
        unsigned char c = lx->buf[lx->pos];
        if (c == ' ' || c == '\t') {
            lx->pos++;
        } else if (c == '#') {
            size_t p = lx->pos + 1;
            while (p < lx->len && lx->buf[p] != '\n') {
                unsigned char d = lx->buf[p];
                if (d == '\r' && p + 1 < lx->len && lx->buf[p + 1] == '\n')
                    break;
                if (is_control(d)) /* GUARD: control_in_comment */
                    return fail(lx, fault, ZTM_ERR_CONTROL_CHARACTER, p);
                p++;
            }
            lx->pos = p;
        } else {
            break;
        }
    }
    return ZTM_OK;
}

static void punct(ztm_lexer *lx, ztm_token *tok, ztm_tok_type t, size_t len)
{
    tok->type = t;
    tok->len = len;
    lx->pos += len;
}

ztm_status ztm_lex_next(ztm_lexer *lx, ztm_mode mode, ztm_token *tok, ztm_fault *fault)
{
    ztm_status s = skip_blank(lx, fault);
    if (s) return s;
    if (++lx->ntokens % ZTM_INTERRUPT_EVERY == 0)
        ztm_interrupt_check();
    memset(tok, 0, sizeof *tok);
    tok->offset = lx->pos;
    tok->line = lx->line;
    tok->column = ztm_column(lx, lx->pos);
    if (lx->pos >= lx->len) {
        tok->type = ZTM_TOK_EOF;
        return ZTM_OK;
    }
    const unsigned char *b = lx->buf + lx->pos;
    size_t left = lx->len - lx->pos;
    switch (b[0]) {
    case '\n':
        punct(lx, tok, ZTM_TOK_NEWLINE, 1);
        newline_at(lx, lx->pos);
        return ZTM_OK;
    case '\r':
        if (left < 2 || b[1] != '\n') /* GUARD: bare_cr */
            return fail(lx, fault, ZTM_ERR_CONTROL_CHARACTER, lx->pos);
        punct(lx, tok, ZTM_TOK_NEWLINE, left >= 2 ? 2 : 1);
        newline_at(lx, lx->pos);
        return ZTM_OK;
    case '=': punct(lx, tok, ZTM_TOK_EQUALS, 1); return ZTM_OK;
    case ',': punct(lx, tok, ZTM_TOK_COMMA, 1); return ZTM_OK;
    case '{': punct(lx, tok, ZTM_TOK_LBRACE, 1); return ZTM_OK;
    case '}': punct(lx, tok, ZTM_TOK_RBRACE, 1); return ZTM_OK;
    case '[':
        if (mode == ZTM_MODE_KEY && left >= 2 && b[1] == '[')
            punct(lx, tok, ZTM_TOK_LBRACKET2, 2);
        else
            punct(lx, tok, ZTM_TOK_LBRACKET, 1);
        return ZTM_OK;
    case ']':
        if (mode == ZTM_MODE_KEY && left >= 2 && b[1] == ']')
            punct(lx, tok, ZTM_TOK_RBRACKET2, 2);
        else
            punct(lx, tok, ZTM_TOK_RBRACKET, 1);
        return ZTM_OK;
    case '"':
    case '\'':
        if (left >= 3 && b[1] == b[0] && b[2] == b[0]) {
            if (mode == ZTM_MODE_KEY) /* GUARD: multiline_key */
                return fail(lx, fault, ZTM_ERR_MULTILINE_KEY, lx->pos);
            return lex_ml_string(lx, b[0], tok, fault);
        }
        return lex_string(lx, b[0], tok, fault);
    default:
        break;
    }
    if (mode == ZTM_MODE_KEY) {
        if (b[0] == '.') {
            punct(lx, tok, ZTM_TOK_DOT, 1);
            return ZTM_OK;
        }
        if (is_bare_key_char(b[0])) {
            size_t p = lx->pos;
            while (p < lx->len && is_bare_key_char(lx->buf[p]))
                p++;
            tok->type = ZTM_TOK_BARE_KEY;
            tok->len = p - lx->pos;
            tok->decoded = tok->len;
            lx->pos = p;
            return check_string_limit(lx, tok, fault);
        }
    } else if (is_scalar_char(b[0])) {
        return lex_scalar(lx, tok, fault);
    }
    if (is_control(b[0])) /* GUARD: control_outside_string */
        return fail(lx, fault, ZTM_ERR_CONTROL_CHARACTER, lx->pos);
    return fail(lx, fault, ZTM_ERR_UNEXPECTED_CHARACTER, lx->pos);
}

/* ---- the Stage 1 driver ------------------------------------------------- */

enum { CTX_ARRAY = 1, CTX_ITAB = 2 };
enum { ST_KEY, ST_VALUE, ST_AFTER };

ztm_status ztm_tokenize(const unsigned char *buf, size_t len, const ztm_opts *opt,
                        ztm_token **out, ztm_value **vals, size_t *n, ztm_fault *fault)
{
    ztm_lexer lx;
    ztm_status s = ztm_lex_init(&lx, buf, len, opt, fault);
    if (s) return s;

    size_t cap = 64, count = 0, depth = 0, stack_cap = 16;
    ztm_token *toks = ztm_scratch(cap, sizeof *toks);
    ztm_value *values = ztm_scratch(cap, sizeof *values);
    unsigned char *stack = ztm_scratch(stack_cap, 1);
    int state = ST_KEY;

    for (;;) {
        unsigned char top = depth ? stack[depth - 1] : 0;
        ztm_mode mode = (state == ST_VALUE || (state == ST_AFTER && top == CTX_ARRAY))
                            ? ZTM_MODE_VALUE : ZTM_MODE_KEY;
        if (count == cap) {
            ztm_token *grown = ztm_scratch(cap * 2, sizeof *toks);
            ztm_value *vgrown = ztm_scratch(cap * 2, sizeof *values);
            memcpy(grown, toks, cap * sizeof *toks);
            memcpy(vgrown, values, cap * sizeof *values);
            toks = grown;
            values = vgrown;
            cap *= 2;
        }
        ztm_token *t = &toks[count];
        s = ztm_lex_next(&lx, mode, t, fault);
        if (s) return s;
        memset(&values[count], 0, sizeof values[count]);
        if (mode == ZTM_MODE_VALUE && t->type >= ZTM_TOK_BASIC_STRING) {
            s = ztm_value_of(&lx, t, &values[count], fault);
            if (s) return s;
        }
        count++;
        if (t->type == ZTM_TOK_EOF)
            break;
        switch (t->type) {
        case ZTM_TOK_EQUALS:
            state = ST_VALUE;
            break;
        case ZTM_TOK_NEWLINE:
            if (!depth)
                state = ST_KEY;
            break;
        case ZTM_TOK_COMMA:
            state = top == CTX_ITAB ? ST_KEY : ST_VALUE;
            break;
        case ZTM_TOK_LBRACKET:
        case ZTM_TOK_LBRACE:
            if (mode == ZTM_MODE_VALUE) {
                if (depth == stack_cap) {
                    unsigned char *grown = ztm_scratch(stack_cap * 2, 1);
                    memcpy(grown, stack, stack_cap);
                    stack = grown;
                    stack_cap *= 2;
                }
                stack[depth++] = t->type == ZTM_TOK_LBRACKET ? CTX_ARRAY : CTX_ITAB;
                state = t->type == ZTM_TOK_LBRACKET ? ST_VALUE : ST_KEY;
            }
            break;
        case ZTM_TOK_RBRACKET:
            if (top == CTX_ARRAY) {
                depth--;
                state = ST_AFTER;
            }
            break;
        case ZTM_TOK_RBRACE:
            if (top == CTX_ITAB) {
                depth--;
                state = ST_AFTER;
            }
            break;
        case ZTM_TOK_LBRACKET2:
        case ZTM_TOK_RBRACKET2:
        case ZTM_TOK_DOT:
        case ZTM_TOK_BARE_KEY:
            break;
        default:
            /* strings, numbers, booleans, date-times */
            if (mode == ZTM_MODE_VALUE)
                state = ST_AFTER;
            break;
        }
    }
    *out = toks;
    if (vals)
        *vals = values;
    *n = count;
    return ZTM_OK;
}
