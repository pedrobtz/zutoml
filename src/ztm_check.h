#ifndef ZTM_CHECK_H
#define ZTM_CHECK_H

/* The check phase's interface (design sections 4 and 12), with no SEXP in
 * sight, so it builds without R for fuzzing: compile with -DZTM_STANDALONE
 * and link a harness that provides ztm_scratch() (fuzz/arena.c). Nothing
 * declared here raises: every failure is a status in a ztm_fault. */

#include <stddef.h>
#include <stdint.h>

#include <zufast/datetime.h>

/* Scratch memory, released as a whole: R_alloc() in the package, which R
 * frees when the .Call returns or unwinds (design section 13); an arena the
 * harness resets after each input in the standalone build. Never NULL: R
 * raises on exhaustion, the arena aborts. */
#ifdef ZTM_STANDALONE
void *ztm_scratch(size_t n, size_t size);
#define ztm_interrupt_check() ((void) 0)
#else
#include <R_ext/Memory.h>
#include <R_ext/Utils.h>
#define ztm_scratch(n, size) ((void *) R_alloc((n), (int) (size)))
#define ztm_interrupt_check() R_CheckUserInterrupt()
#endif

/* Interrupts are polled once per this many tokens (design section 12). */
#define ZTM_INTERRUPT_EVERY 65536u

/* The largest max_depth accepted: the build phase recurses once per level
 * (design section 12). zucbor's cap, for the same reason. */
#define ZTM_MAX_DEPTH_CAP 1023

/* ---- statuses ------------------------------------------------------------
 *
 * One enumerator per rule the check phase enforces. R receives the name
 * (ztm_status_name(), lower case: the `kind` field of design section 11)
 * and maps it to a condition class; tests assert on the name, never on
 * English. Keep ztm_status.c's table in step: test-status.R checks that
 * every name maps to a class. */
typedef enum {
    ZTM_OK = 0,
    /* encoding */
    ZTM_ERR_INVALID_UTF8,          /* the document is not UTF-8 */
    ZTM_ERR_CONTROL_CHARACTER,     /* a control character where TOML has none,
                                      including a CR not before an LF */
    /* strings */
    ZTM_ERR_BAD_ESCAPE,            /* an escape TOML does not define */
    ZTM_ERR_BAD_UNICODE_ESCAPE,    /* \u or \U not a Unicode scalar value */
    ZTM_ERR_UNTERMINATED_STRING,   /* a string that ends with the line or file */
    ZTM_ERR_MULTILINE_KEY,         /* a multi-line string used as a key */
    /* lexical */
    ZTM_ERR_UNEXPECTED_CHARACTER,  /* a byte that cannot start a token here */
    ZTM_ERR_INVALID_VALUE,         /* a span that is no TOML value */
    /* scalars (Stage 2) */
    ZTM_ERR_INVALID_INTEGER,       /* not TOML's integer shape */
    ZTM_ERR_INTEGER_RANGE,         /* outside 64-bit signed */
    ZTM_ERR_INVALID_FLOAT,         /* not TOML's float shape */
    ZTM_ERR_INVALID_DATETIME,      /* not TOML's date-time shape, or no such
                                      date or time */
    /* the grammar and the table model (Stage 3) */
    ZTM_ERR_UNEXPECTED_TOKEN,      /* a token the grammar does not allow here */
    ZTM_ERR_DUPLICATE_KEY,         /* a key defined twice, or a dotted key
                                      through a key that holds a value */
    ZTM_ERR_TABLE_REDEFINED,       /* a table or array of tables defined
                                      twice, or extended where TOML forbids */
    ZTM_ERR_INLINE_TABLE_EXTENDED, /* an inline table added to after it closed */
    /* limits (design section 12) */
    ZTM_ERR_SIZE_LIMIT,
    ZTM_ERR_STRING_LIMIT,
    ZTM_ERR_DEPTH_LIMIT,
    ZTM_ERR_ITEM_LIMIT,
    /* valid TOML R cannot hold (design section 6.4): the build phase's */
    ZTM_ERR_UNREPRESENTABLE_NUL,          /* a string or key holding U+0000 */
    ZTM_ERR_UNREPRESENTABLE_LENGTH,       /* longer than an R string */
    ZTM_ERR_UNREPRESENTABLE_BIG_INTEGER,  /* beyond 2^53, big_integers = "error" */
    ZTM_ERR_UNREPRESENTABLE_FLOAT,        /* beyond a double's range */
    ZTM_STATUS_COUNT
} ztm_status;

const char *ztm_status_name(ztm_status s);

/* ---- options and faults --------------------------------------------------
 *
 * Limits are uint64_t, UINT64_MAX meaning Inf; R validates them before the
 * check runs (R/args.R). */
/* The TOML version read (design D17): 1.1.0 by default, 1.0.0 strict. */
typedef enum { ZTM_TOML_1_0 = 10, ZTM_TOML_1_1 = 11 } ztm_version;

typedef struct {
    uint64_t max_size;      /* bytes of input */
    uint64_t max_string;    /* one string's or key's decoded bytes */
    ztm_version version;
    uint32_t max_depth;     /* nested tables and arrays, counting both */
    uint64_t max_items;     /* keys plus array elements */
} ztm_opts;

/* Why the check failed, and where. line and column are 1-based, the column
 * in code points, as editors count; offset is the 0-based byte offset. */
typedef struct {
    ztm_status status;
    size_t line, column, offset;
    const char *limit;      /* the limit argument's name, or NULL */
    uint64_t limit_value;
} ztm_fault;

/* ---- tokens ----------------------------------------------------------- */

typedef enum {
    ZTM_TOK_EOF = 0,
    ZTM_TOK_NEWLINE,
    ZTM_TOK_EQUALS,
    ZTM_TOK_DOT,
    ZTM_TOK_COMMA,
    ZTM_TOK_LBRACKET,          /* [ */
    ZTM_TOK_RBRACKET,          /* ] */
    ZTM_TOK_LBRACKET2,         /* [[ (key mode only: an array-of-tables header) */
    ZTM_TOK_RBRACKET2,         /* ]] (key mode only) */
    ZTM_TOK_LBRACE,
    ZTM_TOK_RBRACE,
    ZTM_TOK_BARE_KEY,          /* key mode */
    ZTM_TOK_BASIC_STRING,
    ZTM_TOK_LITERAL_STRING,
    ZTM_TOK_ML_BASIC_STRING,   /* value mode */
    ZTM_TOK_ML_LITERAL_STRING, /* value mode */
    ZTM_TOK_INTEGER,           /* value mode, classified by shape only; */
    ZTM_TOK_FLOAT,             /* values and full shape checks are Stage 2 */
    ZTM_TOK_BOOL,
    ZTM_TOK_DATETIME,          /* offset date-time */
    ZTM_TOK_LOCAL_DATETIME,
    ZTM_TOK_LOCAL_DATE,
    ZTM_TOK_LOCAL_TIME,
    ZTM_TOK_COUNT
} ztm_tok_type;

const char *ztm_tok_name(ztm_tok_type t);

typedef struct {
    ztm_tok_type type;
    size_t offset, len;        /* the token's bytes, delimiters included */
    size_t line, column;       /* of its first byte */
    size_t decoded;            /* strings and keys: decoded length in bytes */
} ztm_token;

/* What the lexer expects next: TOML's lexical grammar depends on whether a
 * key or a value comes next (`true` and `1234` are keys before `=`), and
 * only the parser knows which. The lexer is pull-based for that reason. */
typedef enum { ZTM_MODE_KEY, ZTM_MODE_VALUE } ztm_mode;

typedef struct {
    const unsigned char *buf;
    size_t len, pos;
    size_t line, line_start;   /* line number and the offset it starts at */
    size_t col_offset, col;    /* column cache: col is the column of col_offset */
    uint64_t max_string;
    ztm_version version;
    unsigned long ntokens;
} ztm_lexer;

/* Validates the whole input (size, UTF-8) and readies the lexer, skipping a
 * byte-order mark. Returns ZTM_OK or fills fault. */
ztm_status ztm_lex_init(ztm_lexer *lx, const unsigned char *buf, size_t len,
                        const ztm_opts *opt, ztm_fault *fault);

/* The next token in `mode`. Whitespace and comments are skipped; newlines
 * are tokens. Returns ZTM_OK or fills fault. */
ztm_status ztm_lex_next(ztm_lexer *lx, ztm_mode mode, ztm_token *tok, ztm_fault *fault);

/* ---- values (Stage 2) ----------------------------------------------------
 *
 * The value of a scalar token, parsed once by the check phase so the build
 * phase never re-reads text (design section 13). Strings are decoded into
 * scratch. */

typedef enum {
    ZTM_INT_FITS_INTEGER,  /* an R integer: within int32, not INT32_MIN */
    ZTM_INT_FITS_DOUBLE,   /* exactly a double: |v| <= 2^53 */
    ZTM_INT_BIG            /* beyond: a toml_bigint, or big_integers decides */
} ztm_int_class;

typedef struct {
    uint8_t type;          /* a ztm_tok_type */
    uint8_t int_class;     /* integers: a ztm_int_class */
    uint8_t overflow;      /* floats: beyond double's range (d is +-Inf),
                              valid TOML R cannot hold (design section 6.4) */
    uint8_t has_nul;       /* strings: holds U+0000 (design section 6.4) */
    union {
        int64_t i;         /* ZTM_TOK_INTEGER */
        double d;          /* ZTM_TOK_FLOAT */
        int b;             /* ZTM_TOK_BOOL */
        zuf_datetime dt;   /* the four date-time types; local time uses the
                              time fields only */
        struct {
            const char *s; /* decoded UTF-8, not NUL-terminated */
            size_t n;
        } str;
    } u;
} ztm_value;

/* The value of a scalar or string token. Faults are positioned at the
 * token's first byte. */
ztm_status ztm_value_of(ztm_lexer *lx, const ztm_token *tok, ztm_value *v, ztm_fault *fault);

/* A key token's text: a bare key as written, a quoted key decoded. */
void ztm_key_of(ztm_lexer *lx, const ztm_token *tok, const char **s, size_t *n, uint8_t *has_nul);

/* Tokenises the whole document, tracking key and value mode by the bracket
 * structure alone (no grammar checks), and parses every value token (Stage
 * 2): the driver behind zutoml_tokens() and the fuzz target until the
 * grammar lands. *out receives a scratch array of *n tokens, the last of
 * type ZTM_TOK_EOF; *vals, when not NULL, the parallel array of values
 * (zeroed for punctuation and keys). */
ztm_status ztm_tokenize(const unsigned char *buf, size_t len, const ztm_opts *opt,
                        ztm_token **out, ztm_value **vals, size_t *n, ztm_fault *fault);

/* ---- the document (Stage 3) ----------------------------------------------
 *
 * The check phase's output: a tree of nodes in definition order, which the
 * build phase walks (design section 4). Children are a linked list, so a
 * table's keys keep the order the document gave them. Node 0 is the root
 * table. Indices, not pointers: the node array grows by copying. */

#define ZTM_NONE UINT32_MAX

typedef enum {
    ZTM_NODE_TABLE,        /* a table or inline table: keyed children */
    ZTM_NODE_AOT,          /* an array of tables: its tables, unkeyed */
    ZTM_NODE_ARRAY,        /* an array value: its elements, unkeyed */
    ZTM_NODE_VALUE         /* a scalar or string, in `value` */
} ztm_node_kind;

/* How a table came to be, which is what TOML's redefinition rules are
 * about (design section 9; the spec's "Table" section). */
typedef enum {
    ZTM_TABLE_IMPLICIT,    /* created on the way to a deeper [header] */
    ZTM_TABLE_EXPLICIT,    /* defined by its own [header], or [[header]] */
    ZTM_TABLE_DOTTED,      /* created by a dotted key */
    ZTM_TABLE_INLINE       /* an inline table, sealed once closed */
} ztm_table_state;

typedef struct {
    uint8_t kind;          /* ztm_node_kind */
    uint8_t state;         /* tables: ztm_table_state */
    uint8_t key_has_nul;   /* the key holds U+0000 (design section 6.4) */
    uint32_t depth;        /* the root is 0 */
    uint32_t parent, first, last, next;
    uint32_t nchildren;
    const char *key;       /* NULL for array elements and the root */
    size_t keylen;
    size_t line, column, offset;   /* where it was defined */
    ztm_value value;       /* ZTM_NODE_VALUE */
} ztm_node;

typedef struct {
    ztm_node *nodes;
    uint32_t n;
} ztm_doc;

/* The whole check phase: lexer, grammar, table model, values and limits.
 * Returns ZTM_OK and fills doc, or fills fault. Never raises; interrupts
 * go through ztm_interrupt_check(). */
ztm_status ztm_parse(const unsigned char *buf, size_t len, const ztm_opts *opt,
                     ztm_doc *doc, ztm_fault *fault);

#endif
