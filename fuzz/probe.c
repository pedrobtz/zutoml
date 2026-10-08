/* The R-free check phase as a command, for tools/run-mutation-check:
 *
 *   probe FILE VERSION MAX_SIZE MAX_DEPTH MAX_ITEMS MAX_STRING
 *
 * prints the status name ztm_parse() returns for the document in FILE
 * ("ok" when it is valid). VERSION is 10 or 11. */
#include <stdio.h>
#include <stdlib.h>

#include "ztm_check.h"

void ztm_arena_reset(void);

int main(int argc, char **argv)
{
    if (argc != 7)
        return 2;
    FILE *f = fopen(argv[1], "rb");
    if (!f)
        return 2;
    static unsigned char buf[1 << 24];
    size_t n = fread(buf, 1, sizeof buf, f);
    fclose(f);
    ztm_opts opt;
    opt.version = atoi(argv[2]) == 10 ? ZTM_TOML_1_0 : ZTM_TOML_1_1;
    opt.max_size = strtoull(argv[3], NULL, 10);
    opt.max_depth = (uint32_t) strtoul(argv[4], NULL, 10);
    opt.max_items = strtoull(argv[5], NULL, 10);
    opt.max_string = strtoull(argv[6], NULL, 10);
    ztm_doc doc;
    ztm_fault fault;
    ztm_status s = ztm_parse(buf, n, &opt, &doc, &fault);
    printf("%s\n", ztm_status_name(s));
    ztm_arena_reset();
    return 0;
}
