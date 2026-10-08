#ifndef ZTM_CHECK_H
#define ZTM_CHECK_H

/* The check phase's interface (design sections 4 and 12), with no SEXP in
 * sight, so it builds without R for fuzzing: compile with -DZTM_STANDALONE
 * and link a harness that provides ztm_scratch() (fuzz/arena.c). Nothing
 * declared here raises: every failure is a status in a ztm_fault. */

#include <stddef.h>
#include <stdint.h>

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
    /* limits (design section 12) */
    ZTM_ERR_SIZE_LIMIT,
    ZTM_ERR_STRING_LIMIT,
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

/* Tokenises the whole document, tracking key and value mode by the bracket
 * structure alone (no grammar checks): the Stage 1 driver behind
 * zutoml_tokens() and the fuzz target. *out receives a scratch array of
 * *n tokens, the last of type ZTM_TOK_EOF. */
ztm_status ztm_tokenize(const unsigned char *buf, size_t len, const ztm_opts *opt,
                        ztm_token **out, size_t *n, ztm_fault *fault);

#endif
