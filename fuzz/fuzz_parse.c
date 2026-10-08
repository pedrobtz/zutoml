/* libFuzzer target over the whole check phase (roadmap Stage 3): lexer,
 * values, grammar, table model and limits. Invariants beyond "no crash, no
 * sanitizer report":
 *
 *   - a fault is a known status at an offset within the input;
 *   - TOML 1.1 accepts whatever 1.0 accepts (1.1 only adds forms);
 *   - relaxing a limit can only accept more: a document accepted under
 *     tight limits is accepted under loose ones;
 *   - the document tree is well formed: every child's parent is its
 *     parent, and depths increase by one. */
#include <stddef.h>
#include <stdint.h>

#include "ztm_check.h"

void ztm_arena_reset(void);

static void check(int ok)
{
    if (!ok)
        __builtin_trap();
}

static ztm_status run(const uint8_t *data, size_t size, ztm_version v, uint32_t depth,
                      uint64_t items, uint64_t string)
{
    ztm_opts opt = {UINT64_MAX, string, v, depth, items};
    ztm_doc doc;
    ztm_fault fault;
    ztm_status s = ztm_parse(data, size, &opt, &doc, &fault);
    if (s == ZTM_OK) {
        check(doc.n >= 1 && doc.nodes[0].kind == ZTM_NODE_TABLE);
        for (uint32_t i = 0; i < doc.n; i++) {
            const ztm_node *nd = &doc.nodes[i];
            uint32_t count = 0;
            for (uint32_t c = nd->first; c != ZTM_NONE; c = doc.nodes[c].next) {
                check(c < doc.n && doc.nodes[c].parent == i);
                check(doc.nodes[c].depth == nd->depth + 1);
                count++;
            }
            check(count == nd->nchildren);
        }
    } else {
        check(s > ZTM_OK && s < ZTM_STATUS_COUNT);
        check(fault.offset <= size);
    }
    ztm_arena_reset();
    return s;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    ztm_status tight = run(data, size, ZTM_TOML_1_0, 8, 64, 64);
    ztm_status loose10 = run(data, size, ZTM_TOML_1_0, 128, 1000000, UINT64_MAX);
    ztm_status loose11 = run(data, size, ZTM_TOML_1_1, 128, 1000000, UINT64_MAX);
    check(tight != ZTM_OK || loose10 == ZTM_OK);
    check(loose10 != ZTM_OK || loose11 == ZTM_OK);
    return 0;
}
