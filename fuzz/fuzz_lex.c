/* libFuzzer target over the lexer (roadmap Stage 1; renamed fuzz_parse.c
 * when the grammar lands at Stage 3). Invariants beyond "no crash, no
 * sanitizer report": tokens tile the input in order, every token's line and
 * column are positive, and TOML 1.1 accepts whatever 1.0 accepts. */
#include <stddef.h>
#include <stdint.h>

#include "ztm_check.h"

void ztm_arena_reset(void);

static void check(int ok)
{
    if (!ok)
        __builtin_trap();
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    ztm_opts opt = {UINT64_MAX, UINT64_MAX, ZTM_TOML_1_0};
    ztm_fault fault;
    ztm_token *toks;
    size_t n;
    ztm_status s10 = ztm_tokenize(data, size, &opt, &toks, &n, &fault);
    if (s10 == ZTM_OK) {
        size_t prev = 0;
        for (size_t i = 0; i < n; i++) {
            check(toks[i].offset >= prev && toks[i].offset + toks[i].len <= size);
            check(toks[i].line >= 1 && toks[i].column >= 1);
            prev = toks[i].offset + toks[i].len;
        }
        check(toks[n - 1].type == ZTM_TOK_EOF);
    } else {
        check(fault.status > ZTM_OK && fault.status < ZTM_STATUS_COUNT);
        check(fault.offset <= size);
    }
    ztm_arena_reset();
    opt.version = ZTM_TOML_1_1;
    ztm_status s11 = ztm_tokenize(data, size, &opt, &toks, &n, &fault);
    check(s10 != ZTM_OK || s11 == ZTM_OK);
    ztm_arena_reset();
    return 0;
}
