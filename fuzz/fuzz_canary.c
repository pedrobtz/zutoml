/* The fuzz gate's canary (roadmap Stage 1): links the same lexer and traps
 * as soon as it accepts a non-empty input, which the seed corpus (every
 * toml-test document) guarantees. tools/run-fuzz requires this to crash
 * before trusting any real target: a gate is trusted once it has failed. */
#include <stddef.h>
#include <stdint.h>

#include "ztm_check.h"

void ztm_arena_reset(void);

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    ztm_opts opt = {UINT64_MAX, UINT64_MAX, ZTM_TOML_1_1};
    ztm_fault fault;
    ztm_token *toks;
    size_t n;
    int ok = ztm_tokenize(data, size, &opt, &toks, &n, &fault) == ZTM_OK && size > 0;
    ztm_arena_reset();
    if (ok)
        __builtin_trap();
    return 0;
}
