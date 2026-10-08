/* Enumerator names for statuses and tokens (R-free). R maps a status name
 * to a condition class (R/conditions.R) and reports it as the condition's
 * `kind`; test-status.R checks every name below is mapped. */
#include "ztm_check.h"

static const char *const status_names[ZTM_STATUS_COUNT] = {
    "ok",
    "invalid_utf8",
    "control_character",
    "bad_escape",
    "bad_unicode_escape",
    "unterminated_string",
    "multiline_key",
    "unexpected_character",
    "invalid_value",
    "invalid_integer",
    "integer_range",
    "invalid_float",
    "invalid_datetime",
    "unexpected_token",
    "duplicate_key",
    "table_redefined",
    "inline_table_extended",
    "size_limit",
    "string_limit",
    "depth_limit",
    "item_limit",
    "nul_in_string",
    "string_too_long",
    "big_integer",
    "float_overflow",
};

const char *ztm_status_name(ztm_status s)
{
    return (unsigned) s < ZTM_STATUS_COUNT ? status_names[s] : "unknown";
}

static const char *const tok_names[ZTM_TOK_COUNT] = {
    "eof",
    "newline",
    "equals",
    "dot",
    "comma",
    "lbracket",
    "rbracket",
    "lbracket2",
    "rbracket2",
    "lbrace",
    "rbrace",
    "bare_key",
    "basic_string",
    "literal_string",
    "ml_basic_string",
    "ml_literal_string",
    "integer",
    "float",
    "bool",
    "datetime",
    "local_datetime",
    "local_date",
    "local_time",
};

const char *ztm_tok_name(ztm_tok_type t)
{
    return (unsigned) t < ZTM_TOK_COUNT ? tok_names[t] : "unknown";
}
