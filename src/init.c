#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>
#include <R_ext/Visibility.h>

#include "ztm_r.h"

/* Every .Call entry point is listed here; R_useDynamicSymbols(dll, FALSE)
   makes anything missing from the table unreachable by name. */
static const R_CallMethodDef CallEntries[] = {
    {"zutoml_status_names", (DL_FUNC) &zutoml_status_names, 0},
    {"zutoml_tokens",       (DL_FUNC) &zutoml_tokens,       4},
    {NULL, NULL, 0}
};

void R_init_zutoml(DllInfo *dll);

/* The one exported symbol: $(C_VISIBILITY) in Makevars hides the rest. */
void attribute_visible R_init_zutoml(DllInfo *dll)
{
    R_registerRoutines(dll, NULL, CallEntries, NULL, NULL);
    R_useDynamicSymbols(dll, FALSE);
    R_forceSymbols(dll, TRUE);
}
