#ifndef ZTM_R_H
#define ZTM_R_H

/* The R side of the package: entry points and the glue between ztm_check.h
 * and SEXPs. Not included by the check phase. */
#include <Rinternals.h>

#include "ztm_check.h"

void ztm_opts_from_r(ztm_opts *opt, SEXP version, SEXP max_size, SEXP max_depth,
                     SEXP max_items, SEXP max_string);
SEXP ztm_fault_to_r(const ztm_fault *fault);

SEXP zutoml_status_names(void);
SEXP zutoml_tokens(SEXP x, SEXP version, SEXP max_size, SEXP max_string);
SEXP zutoml_check(SEXP x, SEXP version, SEXP max_size, SEXP max_depth, SEXP max_items,
                  SEXP max_string);

#endif
