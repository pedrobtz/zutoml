/* The grammar and the table model (design sections 4, 9 and 12; roadmap
 * Stage 3). R-free.
 *
 * Iterative: arrays and inline tables nest on an explicit frame stack, so
 * depth is a counter (max_depth), never the C stack. The table model is a
 * tree of nodes (ztm_check.h) with a hash of (parent, key) for lookup, so a
 * million distinct keys cost linear time and a duplicate is found at its
 * second definition. Every rule of the spec's "Table", "Inline Table" and
 * "Array of Tables" sections is a state check below, marked GUARD and
 * backed by a toml-test invalid case (tools/run-mutation-check). */
#include <string.h>

#include "ztm_check.h"

/* ---- the parser state --------------------------------------------------- */

typedef struct {
    const char *s;
    size_t n;
    uint8_t has_nul;
    size_t line, column, offset;
} key_part;

enum { FRAME_ARRAY, FRAME_ITAB };
enum { EXPECT_VALUE, EXPECT_SEP, EXPECT_KEY, EXPECT_KEY_OR_CLOSE };

typedef struct {
    uint32_t node;
    uint8_t kind, state;
} frame;

typedef struct {
    ztm_lexer lx;
    const ztm_opts *opt;
    ztm_fault *fault;
    ztm_token tok;
    /* the document */
    ztm_node *nodes;
    uint32_t n, cap;
    uint32_t *slots;          /* the key hash: node indices, ZTM_NONE empty */
    size_t nslots, nkeys;
    /* a dotted key being read */
    key_part *keys;
    size_t nk, kcap;
    /* open arrays and inline tables */
    frame *frames;
    size_t nf, fcap;
} parser;

static ztm_status fail_at(parser *P, ztm_status s, size_t line, size_t column, size_t offset)
{
    P->fault->status = s;
    P->fault->line = line;
    P->fault->column = column;
    P->fault->offset = offset;
    P->fault->limit = NULL;
    P->fault->limit_value = 0;
    return s;
}

static ztm_status fail_tok(parser *P, ztm_status s, const ztm_token *t)
{
    return fail_at(P, s, t->line, t->column, t->offset);
}

static ztm_status fail_key(parser *P, ztm_status s, const key_part *k)
{
    return fail_at(P, s, k->line, k->column, k->offset);
}

static ztm_status fail_limit(parser *P, ztm_status s, const char *limit, uint64_t value)
{
    fail_tok(P, s, &P->tok);
    P->fault->limit = limit;
    P->fault->limit_value = value;
    return s;
}

static ztm_status next(parser *P, ztm_mode mode)
{
    return ztm_lex_next(&P->lx, mode, &P->tok, P->fault);
}

/* The next token other than a newline. */
static ztm_status next_skip_nl(parser *P, ztm_mode mode)
{
    ztm_status s;
    do {
        s = next(P, mode);
    } while (s == ZTM_OK && P->tok.type == ZTM_TOK_NEWLINE);
    return s;
}

static int is_key_token(ztm_tok_type t)
{
    return t == ZTM_TOK_BARE_KEY || t == ZTM_TOK_BASIC_STRING || t == ZTM_TOK_LITERAL_STRING;
}

/* ---- the key hash ------------------------------------------------------- */

static uint64_t key_hash(uint32_t parent, const char *s, size_t n)
{
    uint64_t h = UINT64_C(14695981039346656037) ^ parent;
    for (size_t i = 0; i < n; i++) {
        h ^= (unsigned char) s[i];
        h *= UINT64_C(1099511628211);
    }
    return h ^ (h >> 29);
}

static void hash_insert(parser *P, uint32_t idx)
{
    const ztm_node *nd = &P->nodes[idx];
    size_t mask = P->nslots - 1;
    size_t i = (size_t) key_hash(nd->parent, nd->key, nd->keylen) & mask;
    while (P->slots[i] != ZTM_NONE)
        i = (i + 1) & mask;
    P->slots[i] = idx;
}

static void hash_grow(parser *P)
{
    size_t nslots = P->nslots ? P->nslots * 2 : 64;
    P->slots = ztm_scratch(nslots, sizeof *P->slots);
    P->nslots = nslots;
    memset(P->slots, 0xFF, nslots * sizeof *P->slots);
    for (uint32_t i = 1; i < P->n; i++)
        if (P->nodes[i].key)
            hash_insert(P, i);
}

static uint32_t lookup(parser *P, uint32_t parent, const key_part *k)
{
    if (!P->nslots)
        return ZTM_NONE;
    size_t mask = P->nslots - 1;
    size_t i = (size_t) key_hash(parent, k->s, k->n) & mask;
    for (; P->slots[i] != ZTM_NONE; i = (i + 1) & mask) {
        const ztm_node *nd = &P->nodes[P->slots[i]];
        if (nd->parent == parent && nd->keylen == k->n && memcmp(nd->key, k->s, k->n) == 0)
            return P->slots[i];
    }
    return ZTM_NONE;
}

/* ---- nodes -------------------------------------------------------------- */

/* A new node under `parent`, keyed by k (NULL for an array element), defined
 * at the current token. Charges max_items and max_depth. */
static ztm_status new_node(parser *P, uint32_t parent, ztm_node_kind kind, const key_part *k,
                           uint32_t *out)
{
    uint32_t depth = P->nodes[parent].depth + 1;
    if ((uint64_t) P->n > P->opt->max_items) /* GUARD: max_items */
        return fail_limit(P, ZTM_ERR_ITEM_LIMIT, "max_items", P->opt->max_items);
    if (depth > P->opt->max_depth) /* GUARD: max_depth */
        return fail_limit(P, ZTM_ERR_DEPTH_LIMIT, "max_depth", P->opt->max_depth);
    if (P->n == UINT32_MAX - 1)
        return fail_limit(P, ZTM_ERR_ITEM_LIMIT, "max_items", P->opt->max_items);
    if (P->n == P->cap) {
        ztm_node *grown = ztm_scratch((size_t) P->cap * 2, sizeof *grown);
        memcpy(grown, P->nodes, (size_t) P->cap * sizeof *grown);
        P->nodes = grown;
        P->cap *= 2;
    }
    uint32_t idx = P->n++;
    ztm_node *nd = &P->nodes[idx];
    memset(nd, 0, sizeof *nd);
    nd->kind = (uint8_t) kind;
    nd->depth = depth;
    nd->parent = parent;
    nd->first = nd->last = nd->next = ZTM_NONE;
    if (k) {
        nd->key = k->s;
        nd->keylen = k->n;
        nd->key_has_nul = k->has_nul;
        nd->line = k->line;
        nd->column = k->column;
        nd->offset = k->offset;
    } else {
        nd->line = P->tok.line;
        nd->column = P->tok.column;
        nd->offset = P->tok.offset;
    }
    ztm_node *pa = &P->nodes[parent];
    if (pa->last == ZTM_NONE)
        pa->first = idx;
    else
        P->nodes[pa->last].next = idx;
    pa->last = idx;
    pa->nchildren++;
    if (k) {
        if ((P->nkeys + 1) * 2 > P->nslots)
            hash_grow(P);
        hash_insert(P, idx);
        P->nkeys++;
    }
    *out = idx;
    return ZTM_OK;
}

/* ---- keys --------------------------------------------------------------- */

/* Reads a key, simple or dotted, whose first token is in P->tok. On return
 * P->keys holds its parts and P->tok the token after it. */
static ztm_status read_key(parser *P)
{
    P->nk = 0;
    for (;;) {
        if (!is_key_token((ztm_tok_type) P->tok.type))
            return fail_tok(P, ZTM_ERR_UNEXPECTED_TOKEN, &P->tok);
        if (P->nk == P->kcap) {
            size_t cap = P->kcap ? P->kcap * 2 : 8;
            key_part *grown = ztm_scratch(cap, sizeof *grown);
            if (P->nk)
                memcpy(grown, P->keys, P->nk * sizeof *grown);
            P->keys = grown;
            P->kcap = cap;
        }
        key_part *k = &P->keys[P->nk++];
        ztm_key_of(&P->lx, &P->tok, &k->s, &k->n, &k->has_nul);
        k->line = P->tok.line;
        k->column = P->tok.column;
        k->offset = P->tok.offset;
        ztm_status s = next(P, ZTM_MODE_KEY);
        if (s) return s;
        if (P->tok.type != ZTM_TOK_DOT)
            return ZTM_OK;
        s = next(P, ZTM_MODE_KEY);
        if (s) return s;
    }
}

/* Walks the dotted key in P->keys (all but its last part) from `base`,
 * creating tables as dotted, and creates the last part as a new node of
 * `kind`. The spec: a dotted key may not reach into a table defined by a
 * [header], an inline table, an array, or a value. */
static ztm_status define_dotted(parser *P, uint32_t base, ztm_node_kind kind, uint32_t *out)
{
    uint32_t cur = base;
    ztm_status s;
    for (size_t i = 0; i + 1 < P->nk; i++) {
        const key_part *k = &P->keys[i];
        uint32_t c = lookup(P, cur, k);
        if (c == ZTM_NONE) {
            s = new_node(P, cur, ZTM_NODE_TABLE, k, &c);
            if (s) return s;
            P->nodes[c].state = ZTM_TABLE_DOTTED;
            cur = c;
            continue;
        }
        ztm_node *nd = &P->nodes[c];
        if (nd->kind != ZTM_NODE_TABLE) /* GUARD: dotted_through_value */
            return fail_key(P, nd->kind == ZTM_NODE_VALUE ? ZTM_ERR_DUPLICATE_KEY
                                                          : ZTM_ERR_TABLE_REDEFINED, k);
        if (nd->state == ZTM_TABLE_INLINE) /* GUARD: dotted_into_inline */
            return fail_key(P, ZTM_ERR_INLINE_TABLE_EXTENDED, k);
        if (nd->state == ZTM_TABLE_EXPLICIT) /* GUARD: dotted_into_header_table */
            return fail_key(P, ZTM_ERR_TABLE_REDEFINED, k);
        /* An implicit table, created on the way to a deeper [header], is
         * defined by the dotted key that reaches through it. */
        nd->state = ZTM_TABLE_DOTTED;
        cur = c;
    }
    const key_part *last = &P->keys[P->nk - 1];
    if (lookup(P, cur, last) != ZTM_NONE) /* GUARD: duplicate_key */
        return fail_key(P, ZTM_ERR_DUPLICATE_KEY, last);
    return new_node(P, cur, kind, last, out);
}

/* Resolves the header key in P->keys from the root: [a.b] (aot == 0) or
 * [[a.b]] (aot == 1). On success *base is the table that keys below the
 * header go into. */
static ztm_status define_header(parser *P, int aot, uint32_t *base)
{
    uint32_t cur = 0;
    ztm_status s;
    for (size_t i = 0; i + 1 < P->nk; i++) {
        const key_part *k = &P->keys[i];
        uint32_t c = lookup(P, cur, k);
        if (c == ZTM_NONE) {
            s = new_node(P, cur, ZTM_NODE_TABLE, k, &c);
            if (s) return s;
            P->nodes[c].state = ZTM_TABLE_IMPLICIT;
            cur = c;
            continue;
        }
        ztm_node *nd = &P->nodes[c];
        if (nd->kind == ZTM_NODE_AOT) {
            cur = nd->last;   /* the array's last table */
            continue;
        }
        if (nd->kind != ZTM_NODE_TABLE) /* GUARD: header_through_value */
            return fail_key(P, nd->kind == ZTM_NODE_VALUE ? ZTM_ERR_DUPLICATE_KEY
                                                          : ZTM_ERR_TABLE_REDEFINED, k);
        if (nd->state == ZTM_TABLE_INLINE) /* GUARD: header_into_inline */
            return fail_key(P, ZTM_ERR_INLINE_TABLE_EXTENDED, k);
        cur = c;
    }
    const key_part *last = &P->keys[P->nk - 1];
    uint32_t c = lookup(P, cur, last);
    if (!aot) {
        if (c == ZTM_NONE) {
            s = new_node(P, cur, ZTM_NODE_TABLE, last, &c);
            if (s) return s;
        } else {
            ztm_node *nd = &P->nodes[c];
            if (nd->kind == ZTM_NODE_VALUE) /* GUARD: header_over_value */
                return fail_key(P, ZTM_ERR_DUPLICATE_KEY, last);
            if (nd->kind != ZTM_NODE_TABLE || nd->state != ZTM_TABLE_IMPLICIT) /* GUARD: table_redefined */
                return fail_key(P, nd->state == ZTM_TABLE_INLINE && nd->kind == ZTM_NODE_TABLE
                                       ? ZTM_ERR_INLINE_TABLE_EXTENDED : ZTM_ERR_TABLE_REDEFINED,
                                last);
        }
        P->nodes[c].state = ZTM_TABLE_EXPLICIT;
        *base = c;
        return ZTM_OK;
    }
    if (c == ZTM_NONE) {
        s = new_node(P, cur, ZTM_NODE_AOT, last, &c);
        if (s) return s;
    } else if (P->nodes[c].kind != ZTM_NODE_AOT) { /* GUARD: array_table_redefined */
        return fail_key(P, P->nodes[c].kind == ZTM_NODE_VALUE ? ZTM_ERR_DUPLICATE_KEY
                                                              : ZTM_ERR_TABLE_REDEFINED, last);
    }
    uint32_t t;
    s = new_node(P, c, ZTM_NODE_TABLE, NULL, &t);
    if (s) return s;
    P->nodes[t].state = ZTM_TABLE_EXPLICIT;
    *base = t;
    return ZTM_OK;
}

/* ---- values ------------------------------------------------------------- */

static ztm_status push_frame(parser *P, uint32_t node, uint8_t kind, uint8_t state)
{
    if (P->nf == P->fcap) {
        size_t cap = P->fcap ? P->fcap * 2 : 16;
        frame *grown = ztm_scratch(cap, sizeof *grown);
        if (P->nf)
            memcpy(grown, P->frames, P->nf * sizeof *grown);
        P->frames = grown;
        P->fcap = cap;
    }
    frame *f = &P->frames[P->nf++];
    f->node = node;
    f->kind = kind;
    f->state = state;
    return ZTM_OK;
}

/* Gives `node` the value whose first token is in P->tok: a scalar, or an
 * array or inline table, which opens a frame. */
static ztm_status start_value(parser *P, uint32_t node)
{
    ztm_node *nd = &P->nodes[node];
    switch ((ztm_tok_type) P->tok.type) {
    case ZTM_TOK_LBRACKET:
        nd->kind = ZTM_NODE_ARRAY;
        return push_frame(P, node, FRAME_ARRAY, EXPECT_VALUE);
    case ZTM_TOK_LBRACE:
        nd->kind = ZTM_NODE_TABLE;
        nd->state = ZTM_TABLE_INLINE;
        return push_frame(P, node, FRAME_ITAB, EXPECT_KEY_OR_CLOSE);
    case ZTM_TOK_BASIC_STRING:
    case ZTM_TOK_LITERAL_STRING:
    case ZTM_TOK_ML_BASIC_STRING:
    case ZTM_TOK_ML_LITERAL_STRING:
    case ZTM_TOK_INTEGER:
    case ZTM_TOK_FLOAT:
    case ZTM_TOK_BOOL:
    case ZTM_TOK_DATETIME:
    case ZTM_TOK_LOCAL_DATETIME:
    case ZTM_TOK_LOCAL_DATE:
    case ZTM_TOK_LOCAL_TIME:
        nd->kind = ZTM_NODE_VALUE;
        return ztm_value_of(&P->lx, &P->tok, &P->nodes[node].value, P->fault);
    default:
        return fail_tok(P, ZTM_ERR_UNEXPECTED_TOKEN, &P->tok);
    }
}

/* In an inline table: newlines are allowed between key/value pairs under
 * TOML 1.1, never under 1.0. */
static ztm_status next_in_itab(parser *P, ztm_mode mode)
{
    if (P->opt->version >= ZTM_TOML_1_1)
        return next_skip_nl(P, mode);
    return next(P, mode);
}

/* Parses the value after `key =`, already pointed at `node`, with the
 * token after '=' still to be read. Runs the frame stack until every array
 * and inline table it opened is closed. */
static ztm_status parse_value(parser *P, uint32_t node)
{
    ztm_status s = next(P, ZTM_MODE_VALUE);
    if (s) return s;
    size_t floor = P->nf;
    s = start_value(P, node);
    if (s) return s;
    while (P->nf > floor) {
        frame *f = &P->frames[P->nf - 1];
        uint32_t c;
        if (f->kind == FRAME_ARRAY) {
            s = next_skip_nl(P, ZTM_MODE_VALUE);
            if (s) return s;
            if (P->tok.type == ZTM_TOK_RBRACKET) {
                P->nf--;
                continue;
            }
            if (f->state == EXPECT_SEP) {
                if (P->tok.type != ZTM_TOK_COMMA) /* GUARD: array_separator */
                    return fail_tok(P, ZTM_ERR_UNEXPECTED_TOKEN, &P->tok);
                f->state = EXPECT_VALUE;
                continue;
            }
            uint32_t arr = f->node;
            f->state = EXPECT_SEP;
            s = new_node(P, arr, ZTM_NODE_VALUE, NULL, &c);
            if (s) return s;
            s = start_value(P, c);
            if (s) return s;
            continue;
        }
        /* an inline table */
        s = next_in_itab(P, ZTM_MODE_KEY);
        if (s) return s;
        if (f->state == EXPECT_SEP) {
            if (P->tok.type == ZTM_TOK_RBRACE) {
                P->nf--;
                continue;
            }
            if (P->tok.type != ZTM_TOK_COMMA) /* GUARD: inline_table_separator */
                return fail_tok(P, ZTM_ERR_UNEXPECTED_TOKEN, &P->tok);
            f->state = P->opt->version >= ZTM_TOML_1_1 ? EXPECT_KEY_OR_CLOSE : EXPECT_KEY;
            continue;
        }
        if (P->tok.type == ZTM_TOK_RBRACE && f->state == EXPECT_KEY_OR_CLOSE) {
            P->nf--;
            continue;
        }
        /* key = value */
        uint32_t tbl = f->node;
        f->state = EXPECT_SEP;
        s = read_key(P);
        if (s) return s;
        if (P->tok.type != ZTM_TOK_EQUALS)
            return fail_tok(P, ZTM_ERR_UNEXPECTED_TOKEN, &P->tok);
        s = define_dotted(P, tbl, ZTM_NODE_VALUE, &c);
        if (s) return s;
        s = next(P, ZTM_MODE_VALUE);
        if (s) return s;
        s = start_value(P, c);
        if (s) return s;
    }
    return ZTM_OK;
}

/* ---- the document ------------------------------------------------------- */

/* After a header or a key/value pair: the line must end. */
static ztm_status end_of_line(parser *P)
{
    ztm_status s = next(P, ZTM_MODE_KEY);
    if (s) return s;
    if (P->tok.type != ZTM_TOK_NEWLINE && P->tok.type != ZTM_TOK_EOF) /* GUARD: end_of_line */
        return fail_tok(P, ZTM_ERR_UNEXPECTED_TOKEN, &P->tok);
    return ZTM_OK;
}

ztm_status ztm_parse(const unsigned char *buf, size_t len, const ztm_opts *opt,
                     ztm_doc *doc, ztm_fault *fault)
{
    parser P;
    memset(&P, 0, sizeof P);
    P.opt = opt;
    P.fault = fault;
    ztm_status s = ztm_lex_init(&P.lx, buf, len, opt, fault);
    if (s) return s;

    P.cap = 64;
    P.nodes = ztm_scratch(P.cap, sizeof *P.nodes);
    memset(&P.nodes[0], 0, sizeof P.nodes[0]);
    P.nodes[0].kind = ZTM_NODE_TABLE;
    P.nodes[0].state = ZTM_TABLE_EXPLICIT;
    P.nodes[0].parent = P.nodes[0].first = P.nodes[0].last = P.nodes[0].next = ZTM_NONE;
    P.nodes[0].line = P.nodes[0].column = 1;
    P.n = 1;

    uint32_t base = 0;
    for (;;) {
        s = next(&P, ZTM_MODE_KEY);
        if (s) return s;
        ztm_tok_type t = (ztm_tok_type) P.tok.type;
        if (t == ZTM_TOK_EOF)
            break;
        if (t == ZTM_TOK_NEWLINE)
            continue;
        if (t == ZTM_TOK_LBRACKET || t == ZTM_TOK_LBRACKET2) {
            int aot = t == ZTM_TOK_LBRACKET2;
            s = next(&P, ZTM_MODE_KEY);
            if (s) return s;
            s = read_key(&P);
            if (s) return s;
            if (P.tok.type != (aot ? ZTM_TOK_RBRACKET2 : ZTM_TOK_RBRACKET)) /* GUARD: header_close */
                return fail_tok(&P, ZTM_ERR_UNEXPECTED_TOKEN, &P.tok);
            s = define_header(&P, aot, &base);
            if (s) return s;
        } else if (is_key_token(t)) {
            uint32_t node;
            s = read_key(&P);
            if (s) return s;
            if (P.tok.type != ZTM_TOK_EQUALS) /* GUARD: key_value_equals */
                return fail_tok(&P, ZTM_ERR_UNEXPECTED_TOKEN, &P.tok);
            s = define_dotted(&P, base, ZTM_NODE_VALUE, &node);
            if (s) return s;
            s = parse_value(&P, node);
            if (s) return s;
        } else {
            return fail_tok(&P, ZTM_ERR_UNEXPECTED_TOKEN, &P.tok);
        }
        s = end_of_line(&P);
        if (s) return s;
        if (P.tok.type == ZTM_TOK_EOF)
            break;
    }
    doc->nodes = P.nodes;
    doc->n = P.n;
    return ZTM_OK;
}
