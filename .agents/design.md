# zutoml — Design

**Status:** Draft, 2026-10-08. Adopted from [RFC 0004](https://github.com/pedrobtz/packages/blob/main/rfcs/0004-zutoml-toml-documents.md) (2026-10-07) as the package's own specification. Nothing here is implemented: the repository is the `usethis` skeleton plus these documents. Every statement here is a decision; things not yet decided live in §18 and nowhere else. Amend this file in the same commit as the code that changes it. [roadmap.md](roadmap.md) sequences the work; its section references (§) point here.
**Package:** `zutoml`
**One line:** TOML 1.0 documents parsed into ordinary R values and emitted from them, by a C99 parser and emitter of the package's own over `zufast`'s scalars, with `toml-test` as the conformance gate in both directions.

What changed between the RFC and this document: the RFC said nothing in it had been checked against a running implementation. On 2026-10-08 the sibling checkouts (`../zufast`, `../zuyaml`, `../zujson`, `../zucbor`, `../zuxml`) and the upstream sites were read, and the places where the RFC's assumptions did not hold are corrected and marked *verified 2026-10-08* (§3, §9, §15, §17, §18). The RFC's roadmap table (its §19) became [roadmap.md](roadmap.md).

---

## 1. What zutoml is

`zutoml` parses TOML documents into ordinary R values and emits R values as TOML. TOML is the configuration format of Cargo, `pyproject.toml`, Hugo and many tools' settings; R has it only through C++, Rust or JavaScript runtimes (§3). zutoml is a small C99 parser and emitter with no vendored library: TOML's grammar is two hundred lines of ABNF, its scalars are the primitives `zufast` provides (integers in any base, correctly rounded floats, RFC 3339 date-times), and no C library emits TOML well enough to be worth carrying.

It is a *format* package, like `zuyaml` and `zujson`: an R API over a text format, with no C API of its own.

The one-line statement that governs every decision below:

> **Read any valid TOML 1.0 document exactly, refuse any invalid one with a line and column, and write TOML that TOML readers everywhere accept.**

Three properties shape the design:

- **Strictness is the spec's.** TOML is unusual among configuration formats in being fully specified and having a conformance suite with invalid cases. zutoml passes every `toml-test` case, valid and invalid, and adds no leniency: a document another parser accepts and zutoml refuses is a bug in one of them, and the suite decides which.
- **Types are the document's, not guessed.** Unlike YAML's core schema, TOML types every value by its syntax, so `2024-01-01` is a date and `"2024-01-01"` is a string. zutoml converts each TOML type to one R type and never sniffs strings.
- **Emission is deterministic and readable.** A config file is read by people; the emitter keeps the R object's key order, writes one table per nested list, and chooses string and number forms by fixed rules.

---

## 2. Scope

| | v0.1.0 | Later, when asked | Never |
|---|---|---|---|
| TOML v1.0.0 in full: every string form; integers in decimal, hex, octal and binary with underscores; floats with `inf` and `nan`; booleans; the four date-time types; arrays (heterogeneous, as 1.0 allows); inline tables; tables; dotted keys; arrays of tables | yes | | |
| Parsing from a string, a raw vector, a path, a URL or a connection, bounded | yes | | |
| Emitting a named list, nested lists, data frames as arrays of tables, vectors as arrays | yes | | |
| `toml_validate()`: the parser with the build phase off | yes | | |
| `toml-test` as a conformance gate, both directions | yes | | |
| TOML v1.1.0 forms (seconds optional in times, `\e` and `\x` escapes, newlines and trailing commas in inline tables), read by default; `version = "1.0.0"` strict (D17) | yes | | |
| Format-preserving edits (comments and whitespace kept) | | | yes: a different data model (`tomledit`'s) and a different package |
| A schema language, or validation beyond the grammar | | | yes |
| Type sniffing of strings | | | yes |
| Comments in the parsed value | | | yes: a config reader returns values |

---

## 3. Position in the `zu*` family

These are zutoml's cells for the family table that alignment rule R1 of [`zu-family-alignment.md`](https://github.com/pedrobtz/packages/blob/main/zu-family-alignment.md) places in `pedrobtz/packages` as `zu-family.md`. That file did not exist on 2026-10-08; until it does, the rows live here.

| | zutoml |
|---|---|
| Role | format |
| R prefix | `toml_` |
| Info function | `zutoml_info()` (the package name, as R1 recommends for new packages) |
| Root condition class | `zutoml_error` |
| Public C prefix | none; internal `ztm_` / `ZTM_` |
| From C | no C API; `LinkingTo` consumer only |
| Hides symbols (`$(C_VISIBILITY)`) | yes, from Stage 0 (R3) |
| Vendored code | none |
| `LinkingTo` | `zufast (>= 0.1.0)` |
| `Depends: R` | 4.1 (R2) |
| Language | en-GB (R2) |

The `ztm_` prefix was checked against every sibling's prefix on 2026-10-07 by the RFC, and again on 2026-10-08 (Stage 0) by grepping every sibling's `src/` and `inst/include/` for `ztm_` and `ZTM_`: no match.

### 3.1 Relationships, as decided rather than as hoped

- **`zufast`** owns the scalars (*verified 2026-10-08* against `../zufast/inst/include/zufast/`): `zuf_parse_i64_opt()` with `zuf_num_options.base` set to 16, 8 or 2 for prefixed integers, `zuf_parse_f64()` for floats, `zuf_parse_datetime()` and `zuf_parse_date()` for three of the four date-time types, `zuf_format_f64()` (Ryu, shortest round-trip) and `zuf_format_datetime()` for emission, and `zuf_utf8_valid()` for the document. Two things the RFC assumed zufast does, it does not: it parses **no base prefix** ("digits in the base, no prefix", `number.h`) and has **no underscore option**, so stripping `0x`/`0o`/`0b` and the `_` separators, after checking each `_` sits between two digits, is zutoml's (§9). The fourth date-time type, local time (`07:32:00`), is twenty lines in zutoml, since zufast parses no bare time (zufast §25 lists it among the deferred forms; zutoml is the consumer that would admit it).
- **`zuyaml`** is the template for the R API shape (*verified 2026-10-08*: it exports `yaml_parse()`, `yaml_read()`, `yaml_emit()`, `yaml_write()`, their `_all` forms and `zuyaml_bigint()`), the bigint class and the unwind-safety rules. It is not a dependency: TOML and YAML share no code.
- **`zujson`** is the template for the array lattice and `data_frame =`.
- **`zucbor`** is the template for the limits, the condition fields, the `/* GUARD */` mutation check and the conformance runner over a third-party corpus.
- **`zuxml`** supplies `R/zu_source.R`, copied verbatim with its origin header, for paths, URLs and connections (§10).
- No `zubin`: TOML is text, and the emitter's buffer is `R_alloc()` growth as `zuyaml`'s is.

**Consumers.** None named. The users are R projects reading `pyproject.toml`, `Cargo.toml`, Hugo and tool configuration, lock files in other ecosystems, and anyone writing configuration for tools that read TOML. zutoml is useful on its own; nothing in the API is shaped around a sibling.

### 3.2 What exists elsewhere (*verified 2026-10-08* against CRAN)

| Package | Version, date | Engine | Parses | Emits | Build needs |
|---|---|---|---|---|---|
| `RcppTOML` | 0.2.3, 2025-03-08 | `toml++` (C++17) through Rcpp | yes | no | a C++17 compiler |
| `tomledit` | 0.1.1, 2025-04-10 | Rust `toml_edit` | yes, format-preserving | yes | cargo and rustc |
| `toml` | 1.1.0, 2026-04-13 | a JavaScript TOML library in V8, "based on tomledit", with jsonlite | yes, format-preserving | yes | the V8 package |

The RFC listed the first two and `configr` (which wraps `RcppTOML`); `toml` is newer. The gap zutoml fills is unchanged: a parser *and* emitter in C99 with no runtime beyond R, every TOML type mapped to an R type, the conformance suite as a gate in both directions, and this family's limits and classed conditions.

---

## 4. Architecture

Two phases, as in `zucbor`, for the same reason and one more: a TOML document is a sequence of key definitions whose validity depends on every earlier one (a table defined twice, a dotted key extending an inline table), and the build phase should see only documents the check phase has already accepted whole.

```text
string / raw / file / connection
      │
      ▼
  CHECK  (src/ztm_parse.c, R-free behind ztm_check.h)
      - UTF-8 validity (zuf_utf8_valid); no control characters outside tab and newlines
      - the lexer: tokens with line, column and byte offset
      - the grammar: keys, values, tables, arrays of tables
      - the table model: every definition recorded; every rule of the spec's
        "Table" and "Array of Tables" sections enforced
      - every scalar parsed through zufast, so a bad number or date is refused
        here, with its position
      - limits: max_size, max_depth, max_items, max_string
      │
      ▼   an event list: open table, key, scalar, open array, close ...
  BUILD  (src/ztm_build.c, R)
      - R values from the event list; container sizes from the check's counts
      - arrays simplified by the lattice (§6.3)
      - tables as named lists in definition order
      │
      ▼
  R value
```

The check phase builds without R: `ztm_check.h` declares it with no `SEXP`, scratch memory and interrupt checks are hooks (`R_alloc()` and `R_CheckUserInterrupt()` in the package, an arena and a no-op under `-DZTM_STANDALONE`), and `toml_validate()` runs it alone. The table model is a hash table of canonical key paths with a state per node (`undefined`, `implicit`, `explicit`, `inline`, `array`), which is what the TOML rules are about.

The emitter (`src/ztm_emit.c`) is one pass over the R value into an `R_alloc()` buffer that doubles, then one `mkCharLenCE()`.

Three rules follow and are non-negotiable:

1. **No R object is allocated until the check phase has passed over the whole document.** Container sizes come from counts the check observed, never from the input.
2. **`toml_validate(x)` is exactly the check phase of `toml_parse(x)`.** Same code, same limits. The two disagree only where R cannot hold a valid value (§6.4), never about the text.
3. **The emitter never writes what the parser refuses** (§8), including at the same `max_depth`.

---

## 5. Public R API (complete v0.1.0 surface)

```r
# parse
toml_parse(x, ...)             # string or raw vector -> named list
toml_read(file, ...)           # path, URL or connection -> named list
toml_validate(x, ..., error = FALSE)   # TRUE/FALSE, or the condition

# emit
toml_emit(x, ...)              # named list -> string
toml_write(x, file, ...)       # named list -> file

# values
toml_bigint(x)                 # an integer outside what a double holds exactly,
                               # as a character vector of class toml_bigint
zutoml_info()                  # version, zufast version compiled against,
                               # toml-test version pinned, build flags
```

Six functions, one value class and the info function. The `parse`/`read` and `emit`/`write` split is `zuyaml`'s; `toml_validate()` is `zucbor`'s `cbor_validate()`, the check phase alone, with `error = TRUE` raising the classed condition so a caller learns why.

### Parse arguments

```r
toml_parse(
  x,
  version      = c("1.1.0", "1.0.0"),         # D17
  simplify     = c("preserve", "none"),       # §6.3
  data_frame   = FALSE,                       # arrays of tables as frames
  big_integers = c("bigint", "double", "error"),
  datetimes    = c("convert", "keep"),        # §6.1
  local_time   = c("character", "difftime"),
  max_size     = 64 * 1024^2,
  max_depth    = 128L,
  max_items    = 1e6,
  max_string   = 2^31 - 1
)
```

`toml_read()` adds `file` and passes the rest on. `toml_validate()` takes `x`, `version` and the limits only; the mapping arguments have no meaning for it.

### Emit arguments

```r
toml_emit(
  x,
  indent  = 2L,                 # inside arrays spanning lines
  inline  = 0L,                 # nested lists with at most this many keys are
                                # inline tables; 0 means never (§18 Q1)
  width   = 80L,                # arrays wrap past this column; 0 never
  na      = c("error", "omit"),
  strings = c("basic", "literal")
)
```

`toml_write()` adds `file`. Output is UTF-8 with `\n` line endings.

---

## 6. TOML to R

### 6.1 Scalars

| TOML | R |
|---|---|
| string, all four forms | `character`, marked UTF-8 |
| integer | `integer`, `double` or `toml_bigint` by range |
| float | `double`; `inf`, `-inf`, `nan` as R's `Inf`, `-Inf`, `NaN` |
| boolean | `logical` |
| offset date-time | `POSIXct` in UTC |
| local date-time | `POSIXct` with `tzone = ""` |
| local date | `Date` |
| local time | `character` (default) or `difftime` |

Notes, by row:

- **Strings.** Escapes are decoded, a multi-line string's first newline is trimmed and its line-ending backslash joins lines, as the spec says. A string holding U+0000 is `zutoml_unrepresentable`, since R cannot hold it.
- **Integers.** An `integer` when within R's range (`-2147483648` is a `double`, since as an `integer` it would be `NA`: the `zujson` rule), a `double` up to 2^53, then `big_integers` decides: `"bigint"` (the default) gives a `toml_bigint` holding the canonical decimal; `"double"` the nearest double; `"error"` refuses with `zutoml_unrepresentable`. TOML integers are 64-bit signed, so a value outside that range is `zutoml_parse_error` whatever the option. `zuyaml` and `zucbor` make the same choice: never silently lose integer precision.
- **Floats.** `zuf_parse_f64()`, correctly rounded on every platform. `-0.0` is kept.
- **Offset date-time.** The offset is applied and the instant returned in UTC; the written offset is not kept (a documented loss, §7.4). `datetimes = "keep"` returns the text instead, normalised to RFC 3339 with `T`.
- **Local date-time.** A wall-clock time with no zone. R's convention for that is a `POSIXct` with an empty `tzone`, which prints and computes in the session's zone; it is the same instant only within one session's zone, and §7.4 says so. `"keep"` returns the text.
- **Local time.** R has no time-of-day class. The default is the text as written, normalised to `HH:MM:SS[.fraction]`; `"difftime"` gives seconds since midnight in `units = "secs"`.
- **Fractional seconds.** TOML allows any precision and says extra precision "must be truncated, not rounded". zutoml reads nine digits (nanoseconds), truncating the rest, keeps microseconds in a `POSIXct`, and nanoseconds in `"keep"` mode. (The RFC said more than nine digits was a parse error "as `toml-test` expects"; toml-test v2.2.0 has no such case and the spec says otherwise. Corrected at Stage 2.)

### 6.2 Keys and tables

| TOML | R |
|---|---|
| table, inline table | named `list` |
| dotted key `a.b.c = 1` | nested named lists |
| array of tables `[[x]]` | an unnamed `list` of named lists |
| the document | a named `list` |

Keys are strings, always, so every table is a named list, with names marked UTF-8 and in definition order. An empty key (`"" = 1`) is legal TOML and gives a list element named `""`, which R allows. Duplicate keys are a TOML error, so there is no `duplicate_keys =` argument: the document is refused with the position of the second definition. A table defined after its sub-tables (`[a.b]` then `[a]`) is legal and the result is the same nested list, since order is a property of the document, not of the value.

### 6.3 Arrays and the lattice

TOML 1.0 arrays may mix types. zutoml applies `zujson`'s lattice, as `zucbor` does, under `simplify = "preserve"`:

```text
all strings                                   -> character
all booleans                                  -> logical
all integers that fit                         -> integer
integers and floats                           -> double
integer-valued numbers with a toml_bigint     -> toml_bigint
all local dates                               -> Date
all date-times of one kind                    -> POSIXct
anything else (a mixture of kinds, a nested
  array, an inline table among scalars)       -> list
empty                                         -> logical(0)
one element that simplifies                   -> marked I()
```

- Booleans are a kind of their own: `[true, 1]` is a list, never `c(1L, 1L)` (the `zucbor` rule; `zujson` lets them join the numbers).
- An empty array is `logical(0)`, as in the siblings, so an empty TOML array and an empty R vector round-trip.
- A one-element array that simplifies is marked `I()`, so that `toml_emit()` writes it back as an array: the `zucbor` rule that makes `toml_emit(toml_parse(x))` reproduce `x`.

`simplify = "none"` makes every array a `list`. `data_frame = TRUE` turns an array of tables whose elements all parse to named lists into a data frame, columns in first-seen key order, missing keys `NA`, each column through the lattice; `zujson`'s rules, with `zucbor`'s `max_cells` guard against rows that share no keys.

### 6.4 Valid TOML that R cannot hold

A string containing U+0000; a key longer than an R string; an array of more than `2^31 - 1` elements; a float beyond the range of a double (`1e400`), which zufast rounds to infinity and the check phase flags (Stage 2). Each is `zutoml_unrepresentable`, raised in the build phase with its position. These are the only cases where `toml_validate()` says `TRUE` and `toml_parse()` fails (§4, rule 2). The NUL and length guards live in one function, `ztm_mkchar()`, the only place a CHARSXP is made, so string values, names and keys cannot drift apart.

---

## 7. R to TOML

### 7.1 Scalars and vectors

| R | TOML |
|---|---|
| `character` | basic string, or literal with `strings = "literal"` |
| `integer` | integer |
| `double`, whole, within 64-bit signed range, not `-0` | integer |
| any other `double` | float, shortest round-trip digits |
| `logical` | boolean |
| `POSIXct`, `tzone` non-empty | offset date-time in UTC, `Z` |
| `POSIXct`, `tzone` empty or absent | local date-time |
| `Date` | local date |
| `difftime` in `secs`, 0 to 86 399 | local time |
| `toml_bigint` | integer |
| `factor` | its labels, as strings |
| length-one atomic vector | the scalar |
| longer atomic vector | array |
| `I()` of a length-one vector | an array of one |

Notes, by row:

- **Strings.** A basic string escapes `"`, `\` and control characters; a string containing a newline is a multi-line basic string. With `strings = "literal"`, a string that holds no `'` and no control character is a literal string, which needs no escapes; others stay basic. A string that is not valid UTF-8 after `enc2utf8()` is `zutoml_invalid_argument`.
- **Whole doubles.** `zucbor`'s rule, for `zucbor`'s reason: R has no integer literal, so `list(port = 8080)` is a double and a TOML reader expects `port = 8080`, not `8080.0`. `-0.0` stays a float.
- **Floats.** `zuf_format_f64()`, which prints the shortest digits that read back exactly, with `.0` appended when the result has no point or exponent, since TOML requires one. `NaN` is `nan`, infinities `inf` and `-inf`.
- **`POSIXct`.** Written as RFC 3339 with `T`, `Z` for UTC, microseconds when non-zero. A `tzone` other than UTC is converted to UTC; the zone name is not representable (§7.4, §18 Q3).
- **`NA`** of any type is `zutoml_na_error` unless `na = "omit"`, which drops the key, or the element from an array with a warning. TOML has no null.

### 7.2 Lists

| R | TOML |
|---|---|
| named `list`, at the top | the document |
| named `list` inside a named list | a table `[a.b]`, or inline (`inline =`) |
| named `list` inside an array | an inline table |
| unnamed `list` of named lists, under a key | an array of tables `[[a]]` |
| unnamed `list` otherwise | an array |
| `data.frame` | an array of tables, one per row |
| partially named `list`, `NA` or `""` names | `zutoml_invalid_argument` |

The top-level value must be a named list: TOML has no document that is a bare value, so `toml_emit(1:3)` is `zutoml_invalid_argument`. Names are bare keys when they match `[A-Za-z0-9_-]+` and quoted basic keys otherwise; `""` is a quoted empty key. An unnamed list of named lists becomes `[[name]]` tables only under a key, so a top-level unnamed list is also refused. `NULL` elements are omitted with `na = "omit"` and refused otherwise, like `NA`.

The emitter writes, in order: every scalar and array value of the top table; then each nested table as a `[header]` with its own scalars, recursively, depth-first in the list's order; arrays of tables as `[[header]]` blocks. A nested list with at most `inline` keys and no nested list of its own is written inline instead, which is how a short `{ x = 1, y = 2 }` stays on one line.

### 7.3 What cannot be emitted

`zutoml_unsupported_type`: complex numbers, raw vectors (TOML has no bytes; encode them as a string first), functions, environments, external pointers, S4 objects, `POSIXlt`, and matrices and arrays with `dim` (TOML arrays are nested, and a `dim` is a policy the caller should make explicit by converting to a list).

### 7.4 Known lossy conversions

This table is part of the contract and goes into the user documentation as well.

| Construct | Behaviour |
|---|---|
| offset date-time's offset | applied; the value is UTC |
| local date-time | a `POSIXct` in the session's zone |
| local time | text, or seconds since midnight |
| fractional seconds past microseconds | truncated in a `POSIXct`; kept in `"keep"` |
| comments and whitespace | dropped |
| key order on parse | kept; on emit, the list's |
| `1.0` and `1` | both emit as `1` |
| `factor` | its labels |
| `I(x)` of length one | an array of one |
| `NA`, `NULL` | refused, or omitted on request |

What does round-trip is stated as a property and tested as one (§15): for every valid `toml-test` document `d`, `toml_parse(toml_emit(v))` equals `v`, where `v` is `toml_parse(d, datetimes = "keep")`; and for every R value in §7.1 and §7.2 that emits, `toml_parse(toml_emit(x))` is `identical()` to `x` except where a row above applies.

---

## 8. Deterministic emission

Identical R objects give identical text on every platform:

- key order is the list's; no sorting;
- bare keys where allowed, basic-quoted otherwise;
- one space around `=`; arrays `[1, 2, 3]` on one line until `width`, then one element per line with `indent`; inline tables `{ a = 1, b = 2 }`;
- floats by Ryu, date-times by `zuf_format_datetime()`, both fixed functions with no locale;
- `\n` line endings, no trailing whitespace, one blank line before each table header, a final newline.

`toml_emit()` never writes a document that `toml_parse()` refuses: a property test emits 300 generated values and parses each back. The emitter charges `max_depth` identically to the parser.

---

## 9. The grammar, as zutoml reads it

The lexer and parser follow the ABNF in the TOML v1.0.0 specification clause by clause; this document does not restate it. The points a reader of the code needs:

- **Encoding.** The document must be valid UTF-8 (`zuf_utf8_valid()` on the whole input before lexing); a leading byte-order mark is skipped. Control characters other than tab are forbidden outside strings, and inside strings only through escapes; a bare CR is forbidden (`\r\n` is a newline).
- **Keys.** Bare `[A-Za-z0-9_-]+`, basic-quoted, literal-quoted, and dotted combinations with whitespace around the dots. A bare key of digits (`1234 = 1`) is a key, not a number.
- **Integers** (*verified 2026-10-08*). Decimal with an optional sign and underscores between digits; `0x`, `0o`, `0b` without a sign; no leading zeros in decimal. zutoml's lexer checks the TOML shape, including that every `_` sits between two digits and that no sign precedes a prefix, then strips the prefix and the underscores into scratch and calls `zuf_parse_i64_opt()` with `zuf_num_options.base` of 10, 16, 8 or 2 and the span's end checked (`r.ptr == last`). zufast parses "digits in the base, no prefix" and has no underscore option, so this is zutoml's step, not zufast's. A value outside 64-bit signed is `zutoml_parse_error` (`integer_range`), from `ZUF_ERR_RANGE`.
- **Floats.** Decimal with a fraction and/or an exponent, underscores, `inf` and `nan` with an optional sign; a point must have digits on both sides; no leading zeros. zutoml checks those restrictions and strips underscores, then `zuf_parse_f64()` in its default grammar (which accepts a wider set: `1.`, `.5`, `infinity`), with the span's end checked.
- **Date-times** (*verified 2026-10-08* against `datetime.h`). RFC 3339 forms with `T`, `t` or a single space as the separator, `Z`, `z` or `±hh:mm`; local forms without the offset; local date; local time. The first three go to `zuf_parse_datetime()`, whose grammar is wider than TOML's: it also accepts `±hhmm` and `±hh` offsets and a time without seconds, and returns fields with `has_time` and `has_offset`. zutoml checks the TOML shape on the text first (seconds present in 1.0; offset `Z` or `±hh:mm`) and uses zufast for the value and the calendar validation. Local time is zutoml's own twenty lines.
- **Strings.** Basic: `\b \t \n \f \r \" \\ \uXXXX \UXXXXXXXX`; any other escape is an error; `\u` must not produce a surrogate. Multi-line basic: the first newline after `"""` is trimmed, a `\` at line end trims whitespace up to the next non-whitespace. Literal: no escapes. Multi-line literal: first newline trimmed. One or two quotes may end a multi-line string's content (the `""""..."""""` cases from `toml-test`).
- **Arrays.** Values of any type, newlines and comments between elements, a trailing comma.
- **Inline tables.** On one line, no trailing comma, cannot be extended afterwards.
- **Tables and arrays of tables.** `[a.b]` headers; `[[a]]` appends; the rules in the spec's "Table" and "Array of Tables" sections, each one a state transition in the table model with a `/* GUARD: name */` marker and a `toml-test` invalid case behind it.

---

## 10. Input sources

`toml_parse()` takes a string (length one, any encoding R knows, translated to UTF-8 first) or a raw vector of UTF-8 bytes. `toml_read()` takes a path, a URL or a connection through `zuxml`'s `zu_open_input()` in `R/zu_source.R`, copied verbatim with its origin header as `zucbor` and `zuhtml` do, reading at most `max_size + 1` bytes in 64 KiB blocks so an endless source fails with `zutoml_size_limit` one byte past the limit. The read loop is in R, not C (`zucbor` §9 says why: `R_ReadConnection()` is experimental API and costs a NOTE). A TOML document is one value; there is no sequence form.

---

## 11. Errors

Every condition inherits `zutoml_error`, raised in R from a status the C layer returns by enumerator name (the `zucbor` `.Call` convention: C never calls `Rf_error()`); tests assert on class, never on message text.

```text
zutoml_error
├── zutoml_invalid_argument   an argument, or a value that cannot be emitted as given
├── zutoml_parse_error        the document is not TOML
├── zutoml_unrepresentable    valid TOML R cannot hold (§6.4)
├── zutoml_unsupported_type   an R value with no TOML form (§7.3)
├── zutoml_na_error           NA or NULL with na = "error"
├── zutoml_limit_error
│   ├── zutoml_size_limit
│   ├── zutoml_depth_limit
│   ├── zutoml_item_limit
│   └── zutoml_string_limit
└── zutoml_io_error           the file or connection could not be read or written
```

- `zutoml_parse_error` carries `line`, `column` (1-based, in characters, as editors count) and `offset` (0-based, in bytes), plus `kind`, one of the enumerator names the lexer and the table model use (`bad_escape`, `table_redefined`, `integer_range`, ...), so a test can assert the precise rule without matching English.
- `zutoml_limit_error` carries `limit` (the argument's name) and `limit_value`.
- `zutoml_na_error` and `zutoml_unsupported_type` carry `path`, the key path of the offending value, as `a.b[3].c`.
- `zutoml_invalid_argument` carries `arg`.

Users see:

```text
TOML parse error at line 12, column 7: table [a] defined twice
```

---

## 12. Limits and hostile input

Threat model: a configuration file is usually trusted, but `toml_read()` on a URL is not, and a parser that recurses on `[[[[[` is a crash whatever the source.

| Limit | Default | Where |
|---|---|---|
| `max_size` | 64 MiB | before parsing; while reading a connection |
| `max_depth` | 128 | arrays and tables, counting both |
| `max_items` | 1e6 | keys plus array elements |
| `max_string` | `2^31 - 1` | one string's decoded length, in bytes |

- The parser is iterative with an explicit stack for arrays and inline tables, so depth is a counter, not the C stack; the table model is a hash table keyed by path, so a document with a million distinct keys costs linear time, and a document with a million definitions of nearly the same key is refused at the first duplicate.
- Multi-line strings and arrays are scanned once; no backtracking, so parsing is linear in the input.
- The emitter charges `max_depth` identically, so `toml_emit()` cannot write what `toml_parse()` at the same depth refuses.
- A limit is a positive whole number, or `Inf` for `max_size`, `max_items` and `max_string`. Anything else is `zutoml_invalid_argument`: a security limit silently replaced by a default is a limit the caller did not set.
- `R_CheckUserInterrupt()` every 65 536 tokens; everything held is `R_alloc()`ed or `PROTECT`ed, so an interrupt leaks nothing.
- Each guard carries a `/* GUARD: name */` marker, and `tools/run-mutation-check` proves it load-bearing with a `toml-test` invalid case or a hostile input of §15.

---

## 13. Memory model

The family invariant: anything holding heap state across a longjmp must be owned by R. zutoml meets it with no finalizers at all:

- The check phase keeps the token stream and the table model in `R_alloc()` scratch, released when the `.Call` returns or unwinds. It records, per value, its position and its parsed scalar, so the build phase never re-parses text.
- The build phase allocates each container from the count the check phase recorded.
- Strings become `CHARSXP`s once, through `ztm_mkchar()`, which applies the U+0000 and length guards.
- The emitter grows an `R_alloc()` buffer by doubling and copies once into the result string.

So no C function in the package has an error cleanup path. PROTECT discipline is checked by `rchk` and `gctorture` in CI.

---

## 14. Build, portability and CRAN

- Project code is C99 compiling warning-free under `-Wall -Wextra -Wpedantic` (checked as `gnu17`, since R's own headers need C11); no vendored code, so `tools/verify-vendor` has nothing to check and is not carried.
- `DESCRIPTION`: `LinkingTo: zufast (>= 0.1.0)`; `Suggests: testthat (>= 3.0.0), withr, jsonlite, knitr, rmarkdown` (`jsonlite` reads the `toml-test` expectation files; `zujson` would do once it is on CRAN); no `Imports`. During development `Remotes: pedrobtz/zufast@main`, removed before submission (alignment R10.2: a submitted tarball never carries `Remotes:`).
- `src/Makevars`: `PKG_CFLAGS = $(C_VISIBILITY)`, hand-listed `OBJECTS`, portable make only, no `Makevars.win`; the shared object exports `R_init_zutoml` only (`tools/check-symbols`, which must also find no stdio, `abort` or `exit` symbols).
- `src/init.c` registers every entry point; `R_useDynamicSymbols(dll, FALSE)`, `R_forceSymbols(dll, TRUE)`.
- Licence MIT. `Language: en-GB`; domain terms in `inst/WORDLIST`.
- `.Rbuildignore` covers `.agents/`, `.claude/`, `tools/`, `fuzz/` and `cran-comments.md`. The agent instructions live in `.claude/CLAUDE.md`, not at the root (alignment R8: pkgdown renders every root-level Markdown file as a site page).
- CRAN order: after `zufast`, which on 2026-10-08 is tagged 0.1.0 and not yet on CRAN. Nothing else waits on zutoml.
- Workflows (§15 of roadmap.md): the family's standard set from `pedrobtz/r-actions`, with a `conformance` job running the `toml-test` suite.

---

## 15. Testing

### Conventions

The family's: self-sufficient `test_that()` blocks, classes not messages, green under `shuffle = TRUE`, serial (no `Config/testthat/parallel`, so gctorture and valgrind see the C code), a suite under 15 s on CRAN. `expect_toml(x, "text")` asserts exact emitted text; `expect_roundtrip()` uses `identical()`.

### Mapping

Every row of the §6 and §7 tables has a test. The tables in the roxygen docs, this document and the tests are the same table three times; changing one means changing all three.

### Conformance: `toml-test`

`toml-test` is the conformance gate (*verified 2026-10-08*: the latest tag is v2.2.0; the suite holds `valid/*.toml` with `.json` twins and `invalid/*.toml`, selects the TOML version with `-toml 1.0` or `-toml 1.1`, defaulting to 1.0, and tests encoders in reverse from its tagged JSON; the RFC's "1.5 release" is superseded).

- `tools/update-fixtures` fetches the suite at a pinned tag into `tests/testthat/toml-test/` with a manifest (path, the TOML versions whose case lists name it, SHA-256) and a `VERSION` file (tag and commit); not under `fixtures/`, since the suite's longest path would then pass the 100 bytes R CMD check accepts as portable in the tarball, as `zucbor` does with `cbor/test-vectors`; the files are regenerated only by that tool, and `tools/run-conformance` fails if a committed fixture differs from a fresh fetch.
- Every `valid/*.toml` must parse to the value in its `.json` twin. The twin is the suite's tagged JSON (`{"type": "integer", "value": "42"}`, with types `string`, `integer`, `float`, `bool`, `datetime`, `datetime-local`, `date-local`, `time-local`), read with `jsonlite` and compared type by type against `toml_parse(d, datetimes = "keep", simplify = "none")`, since the tagged form has no lattice and keeps date-times as text, and again under `datetimes = "convert", local_time = "difftime"`, since in `"keep"` mode a date-time and a string are both `character` and only the converted pass tells them apart. Doubles are compared to within two ulps, because the expectation is built with `as.numeric()`, which is not correctly rounded on every platform.
- Every `invalid/*.toml` must raise `zutoml_parse_error`, with `kind` checked where the suite's directory names a rule (`invalid/table/` is `table_redefined` and so on).
- The emitter against the suite: every `valid` value emitted and parsed back equals the suite's expectation; in the `conformance` CI job the emitted text is also fed to the suite's reference decoder (`toml-test`'s own Go binary) and must be accepted.
- The suite's pinned version is in `zutoml_info()`.

### Properties

- `toml_emit(x)` is identical across repeated calls, sessions and CI platforms (a checked-in fixture).
- `toml_parse(toml_emit(x))` recovers `x` modulo §7.4, over 300 generated R values covering every row of §7.1 and §7.2, nesting to depth 6, with every string class (escapes, newlines, quotes, non-ASCII, empty), `NaN`, infinities, `-0`, bigints and every date-time form.
- `toml_validate(toml_emit(x))` for every `x` that emits.

### Security (permanent regressions)

- `[` repeated 10^6 times; `a.` repeated to a 10 MB key; a 10^6-element array of empty inline tables; a multi-line string with 10^7 line-ending backslashes; a basic string with 10^6 `\u0000`; a document of 10^6 `[[a]]` headers; every control character in every string form. Each fails through its class with a position, and none crashes, hangs or allocates unbounded.
- `toml_read()` on an endless connection stops one byte past `max_size`.
- Interrupt: `setTimeLimit()` inside the same expression as a large parse unwinds cleanly and the same input then parses.
- `tools/run-mutation-check` removes each guard in turn and requires its hostile input to stop being refused.
- No test performs network I/O; asserted by `tools/check-no-network` in CI.

### Fuzzing and native checks

The check phase builds without R (`-DZTM_STANDALONE`), so libFuzzer runs `fuzz/fuzz_parse.c` over the same `ztm_parse.c` the package uses, seeded from every `toml-test` file; `fuzz/fuzz_canary.c` must crash before any real target is trusted. Invariants: no crash, every proper prefix of every valid file is a parse error or a smaller valid document, and relaxing a limit can only accept more. The build phase and the emitter are fuzzed through R under the ASan and UBSan legs. Valgrind, `rchk`, gctorture and LTO run through `pedrobtz/r-actions`.

---

## 16. Performance targets

Measured by `tools/run-benchmarks` and recorded here when Stage 7 runs them: parsing a 1 MB document of mixed tables within 2× of `RcppTOML`, and emission within 2× of `zuyaml`'s on the same R value. Configuration files are small; the targets exist so a regression is noticed, not because speed is the point. Benchmarks are not in CI.

---

## 17. Decisions

| # | Question | Decision |
|---|---|---|
| D1 | Parser | project code, no vendored library |
| D2 | Scalars | `zufast`, with TOML's restrictions checked first |
| D3 | Spec version | superseded by D17 |
| D4 | Whole doubles | emitted as integers, `zucbor`'s rule |
| D5 | Date-times | converted by default; `"keep"` returns text |
| D6 | Local date-time | `POSIXct` with empty `tzone` |
| D7 | Local time | text by default; `difftime` on request |
| D8 | Big integers | `toml_bigint`, as `zuyaml` and `zucbor` |
| D9 | Mixed arrays | the `zujson` lattice; booleans a kind of their own; `I()` on one-element |
| D10 | Key order on emit | the list's; never sorted |
| D11 | Top-level value | must be a named list |
| D12 | Duplicate keys | always an error; no option |
| D13 | Conformance | `toml-test`, both directions, as a CI gate |
| D14 | Info function | `zutoml_info()`, the package name (R1) |
| D15 | Base prefixes and underscores | stripped by zutoml's lexer before zufast sees the digits (*verified 2026-10-08*) |
| D16 | Where C raises | never; statuses by enumerator name, R raises (`zucbor`'s convention) |
| D17 | TOML 1.1.0 | read by default; `version = c("1.1.0", "1.0.0")` on every reading function, `"1.0.0"` strict; the emitter writes 1.0-compatible text whatever the version (decided at Stage 1, 2026-10-08) |

Reasons where they are not in the section cited:

- **D1.** Two C parsers were weighed. `toml-c` (C99, MIT) parses TOML 1.0 and passes `toml-test`, but has no emitter, reports positions less precisely than this family's conditions need, and its value model would be converted twice. `tomlc17` (*verified 2026-10-08*: MIT, an amalgamated `tomlc17.c` and `.h`, latest release R261003 of 2026-10-03, passes `toml-test` for both 1.0 and 1.1 by its README, with `toml_parse(src, len)` returning a `toml_result_t` of `ok`, `toptab` and `errmsg[200]`, datums carrying `lineno` and `colno`, and an allocator hook) is the stronger alternative and still parse-only. `toml++` is C++17 and excluded for the format packages. The grammar is small enough that a project parser with zufast's scalars is less code than a vendored tree plus its adapter, and it gives the check-then-build shape for free. Three other sources were weighed on 2026-10-08 and rejected. `teptris` (`leptris/teptris`, MIT, C, parses and emits, claims 100% of `toml-test` 1.0 and 1.1) is the first C library with an emitter, but was three weeks old with one author, a CMake multi-file tree, no allocator hook and views into the input buffer; it is a candidate for the Stage 3 fallback alongside `tomlc17`, and its `validate` command a second reader for emitted text. Adapting `yyjson` (which `zujson` vendors) offers only an arena, a writer buffer and string-scanning tricks; the grammar, the table model and the scalars, which are the work, have no JSON counterpart, so its ideas are borrowed and its code is not. `zubin`'s `zb_buf` allocates with `malloc` only, so using it would need finalizers against §13, and would add a second dependency not yet on CRAN. **Fallback:** if the project parser is not passing every `toml-test` case by the end of Stage 3, vendor `tomlc17` for the check and value phases and keep the emitter; §18 Q6.
- **D3.** 1.1.0 was not final on the RFC's source date; it is now (§18 Q5). Adding its forms is additive and the `version =` argument keeps 1.0 documents strict.
- **D17.** Decided at Stage 1 with the runner in hand. Through the lexer, 205 of 205 valid 1.0.0 cases and, once `\e` and `\xHH` were added (about twenty lines), 214 of 214 valid 1.1.0 cases are accepted. The other 1.1 forms are a shape check at Stage 2 (seconds optional) and a grammar rule at Stage 3 (newlines and a trailing comma in inline tables). toml-test v2.2.0 has no Unicode bare keys among its 1.1 cases, so 1.1.0 as the suite tests it keeps keys ASCII. The emitter stays 1.0-compatible because §1 promises output every reader accepts.
- **D6.** The alternative, refusing local date-times or returning text, makes the most common form in config files (a timestamp without a zone) unusable as a time. The session-zone reading is what `as.POSIXct("2024-01-01 10:00")` does, and the loss is documented.
- **D12.** TOML defines duplicate keys as invalid; a lenient option would make zutoml accept documents other parsers refuse, against §1.
- **D15.** zufast's `zuf_num_options` has `base` but no prefix or separator handling; adding them to zufast would widen a primitive every consumer shares for one consumer's grammar.

---

## 18. Open questions

Each stays the maintainer's until recorded above; the recommendation is the RFC's unless marked otherwise.

1. **Inline-table threshold.** `inline = 0` (never) is the safest default for readability of generated files; `inline = 3` makes small points and ranges one-liners. Recommended: 0, since a caller who wants inline tables knows it.
2. **`difftime` on emit.** Only `secs` within a day maps to a local time; other units and values are ambiguous. Refuse them, or emit as a float of seconds? Recommended: refuse, with the message naming `as.numeric()`.
3. **Non-UTC `POSIXct` on emit.** Convert to UTC (as §7.1 says), or write the zone's offset at that instant (`+02:00`)? The offset form is what a person wrote; the UTC form is deterministic across sessions. Recommended: UTC, with an `offset = TRUE` argument deferred.
4. **`toml_bigint` versus `bit64::integer64`.** `zubin` returns `integer64` by class without a dependency. TOML integers are at most 64-bit, so `integer64` would hold every one exactly. Recommended: keep the family's bigint class for consistency with `zuyaml` and `zucbor`, and record `integer64` as an `int64 =` option for later.
5. *Decided at Stage 1: D17.* **TOML 1.1.0 as the default** (*new, verified 2026-10-08*). toml.io now lists v1.1.0 as the current specification, `toml-test` v2.2.0 carries its cases behind `-toml 1.1`, and `tomlc17` passes both. 1.1.0 is a superset of 1.0.0 for a reader. The RFC's D3 (1.0.0 first) was made when 1.1.0 was unfinished. Recommended (this document's, not the RFC's): decide at Stage 1, when the runner exists, by running both suites; if the 1.1 forms cost little, parse `version = c("1.1.0", "1.0.0")` with 1.1.0 the default and `"1.0.0"` strict, and keep the emitter writing 1.0-compatible text always, since §1 promises output every reader accepts.
6. **The D1 fallback trigger.** Stage 3's exit criterion is every `toml-test` case through `toml_validate()`. If that slips, is the answer more time or `tomlc17`? Recommended: `tomlc17` (or `teptris`, if it has matured; see D1), pinned and vendored under the family's rules, with the emitter and the build phase unchanged; the check-then-build shape survives because `tomlc17` returns a whole tree before any R object is made.

---

## 19. Acceptance criteria for v0.1.0

1. Builds from source on Windows, macOS and Linux, R release, devel and oldrel, with `zufast` from CRAN and nothing else installed at run time.
2. Every `toml-test` valid case parses to its expected value and every invalid case is refused, at the pinned suite version, in CI on every platform.
3. Every emitted document is accepted by `toml_parse()` and, in the conformance job, by the suite's reference decoder.
4. Every hostile input of §15 fails through a classed `zutoml_error` with a position; none crashes, hangs or allocates unbounded; the fuzz gate has been seen to fail on its canary.
5. Emission is deterministic: byte-identical across calls, sessions and platforms.
6. The round-trip properties of §7.4 hold over the generated corpus.
7. Every documented mapping row has a test, and the three copies of each table (design, roxygen, tests) agree.
8. `R CMD check --as-cran` is clean on every CI platform; the shared object exports `R_init_zutoml` only; no stdio or exit symbols.

---

## 20. What this design does not decide

- Whether a format-preserving editor belongs in the family. `tomledit` and `toml` exist and do it; the design keeps the data model simple by excluding it.
- Whether zutoml should ship before `zufast` by inlining the primitives it uses. It could, at the cost of a second copy of code the family is consolidating; the recommendation is to wait, since the wait is short.
- The bare-time primitive in `zufast` (§3.1). zutoml carries its own twenty lines until `zufast` admits one.
