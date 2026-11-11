# CLAUDE.md

<!-- markdownlint-disable-next-line MD013 -->
This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Shared conventions

The portfolio's shared rules are synced into `.claude/shared/` from
`pedrobtz/packages:claude/shared/`. Never edit them here. Where this file and
a shared file disagree, this file wins for this package.

@.claude/shared/workflow.md
@.claude/shared/r-package.md
@.claude/shared/ci.md
@.claude/shared/correctness.md
@.claude/shared/assurance.md

## What this is

`zutoml` parses TOML 1.0 and 1.1 documents into ordinary R values and emits
R values as TOML 1.0, with a C99 parser and emitter of its own (no vendored
library) over the scalar primitives of `zufast` (`LinkingTo`, header-only).
It passes the `toml-test` conformance suite in both directions, types every
value by the document's syntax (never by sniffing strings), and emits
deterministic, readable text. Zero hard runtime dependencies: `zufast` is
needed at build time only. It deliberately does not preserve comments or
formatting (that is `tomledit`'s and `toml`'s job), validate against a
schema, or offer a C API.

Two documents outrank this file. [.agents/design.md](.agents/design.md) is
the specification, numbered §1–§20: every statement in it is a decision, and
open questions live only in its §18.
[.agents/roadmap.md](.agents/roadmap.md) sequences it into Stages 0–8, each
with a **Status:** line under its heading. Both were adopted on 2026-10-08
from [RFC 0004](https://github.com/pedrobtz/packages/blob/main/rfcs/0004-zutoml-toml-documents.md)
in `pedrobtz/packages`. `CLAUDE.md` orients, the design decides, the roadmap
sequences.

It is a member of the `zu*` family (sibling checkouts in `../`). `zuyaml` is
the model for the R API shape and the bigint class, `zujson` for the array
lattice, `zucbor` for limits, conditions, the conformance runner and the
mutation check, `zuxml` for `R/zu_source.R`. When a question is not answered
here or in the design, look at how those packages settle it before inventing
something new.

## Current state

**0.1.0 is on CRAN, published 2026-11-07** (crandb, verified 2026-11-11).
Every stage of the roadmap is done. `toml_validate()`, `toml_parse()` (with
`positions =` and `select =`), `toml_read()`, `toml_emit()`, `toml_write()`,
the markers `toml_inline()`, `toml_literal()` and `toml_multiline()`,
`toml_bigint()` and `zutoml_info()` are exported, with a vignette. Every
toml-test case of TOML 1.0.0 and 1.1.0 passes in both directions (D17: 1.1.0
is read by default; the emitter writes 1.0.0). The review in #29 is fixed:
the emitter checks the invariants R does not enforce (data frame shape,
finite dates and times, canonical wall-clock text, a factor's NA level), so
everything it returns is valid TOML 1.0.0, and `data_frame = TRUE` is linear
in the cells.

On 2026-11-11 `DESCRIPTION` on `main` still says `Version: 0.1.0`: the
`0.1.0.9000` bump has not landed, and no `0.1.0` tag exists. There is no
`cran-release.yaml`, so neither happens by itself.

Update this section at the end of every stage: what exists, what is next,
and the date.

## Versions and dependents

The current version's parent issue is #44, `v0.1.1`. The `v0.1.0` parent
was #1, with sub-issues #2 (Stage 0) to #10 (Stage 8), plus #21 (7b) and #24
(7c): the roadmap has eleven stages, 0 to 8 and 7b and 7c, added after
Stage 7. A stage's status goes in its **Status:** line, never in its
heading, because that would change the anchor every issue links to.

zutoml depends on one sibling, `LinkingTo: zufast (>= 0.1.0)`, from CRAN
since 2026-10-21. A release build is checked against zufast's CRAN tarball,
not a newer checkout, because header-only is source-compatible, not
ABI-compatible. No package depends on zutoml.

## Commands

The check this package runs, rather than the plain one:

```sh
_R_CHECK_SYSTEM_CLOCK_=0 Rscript -e 'devtools::check(cran = TRUE)'
```

Install zufast from CRAN, or from the sibling checkout
(`R CMD INSTALL ../zufast`) to try an unreleased change. roxygen2 must be
8.1.0 or newer (`Config/roxygen2/version`); an older one rewrites `man/`.

Gate scripts, run from the package root, each with the roadmap stage that
added it and the workflow that runs it:

<!-- markdownlint-disable MD013 -->
| Script | Stage | What it does |
| --- | --- | --- |
| `tools/update-fixtures` | 0 | fetch toml-test at the pinned tag, write the manifest |
| `tools/run-conformance` | 1 | every toml-test case through the check phase (`conformance`) |
| `tools/run-fuzz [secs]` | 1 | canary first, then `fuzz_parse` under ASan+UBSan (`hardening`) |
| `tools/run-lint` | 1 | `-Wall -Wextra -Wpedantic -Wshadow -Werror` on project C |
| `tools/check-symbols <so>` | 1 | only `R_init_zutoml` exported; no stdio, `abort`, `exit`, `assert` |
| `tools/run-mutation-check` | 3 | every check-phase `/* GUARD */` seen to be load-bearing (40) |
| `tools/run-mutation-check-r` | 6 | the build phase's and emitter's guards, through R (8) |
| `tools/check-no-network` | 6 | no test opens a URL or socket |
| `tools/run-benchmarks` | 7 | parse vs RcppTOML, emit vs zuyaml; not a CI gate |
<!-- markdownlint-enable MD013 -->

`tools/run-fuzz` needs a clang with libFuzzer; on macOS, Homebrew's:
`FUZZ_CC=/opt/homebrew/opt/llvm/bin/clang`. Run `tools/check-symbols` on an
`R CMD INSTALL` build, not a `load_all()` one (`load_all()` compiles with
`-UNDEBUG`).

## Architecture

```text
R/            parse.R, data-frame.R, read.R, select.R, validate.R, emit.R
              (toml_emit, toml_write), markers.R, classes.R (toml_bigint),
              conditions.R, args.R, info.R, tokens.R (the lexer's token
              table, internal), zu_source.R (copied verbatim from zuxml;
              edit there), zutoml-package.R
src/          init.c                      registration only
              ztm_r.c, ztm_r.h            .Call entry points and SEXP glue
              ztm_check.h                 the check phase's R-free interface:
                                          tokens, values, the node tree
              ztm_lex.c, ztm_parse.c      check phase: lexer, grammar, table
                                          model, limits
              ztm_value.c                 scalars: TOML shape checks, then
                                          zufast; string decoding
              ztm_status.c                enumerator names (R-free)
              ztm_build.c, ztm_build.h    build phase: §6 mapping, positions,
                                          select; ztm_mkchar() the one
                                          CHARSXP site
              ztm_emit.c, ztm_emit.h      §7, §8
              Makevars                    hand-listed OBJECTS, $(C_VISIBILITY)
fuzz/         fuzz_parse.c, fuzz_canary.c, probe.c (the mutation check's
              driver), arena.c, toml.dict (not in the tarball)
tools/        the gate scripts above
tests/testthat/toml-test/   the suite at a pinned tag, with manifest.tsv
              (not under fixtures/: the 100-byte path limit; not in the
              tarball, see Testing)
```

The pipeline is: validate and decode the input in R → **check phase**
(`ztm_lex.c`, `ztm_parse.c`, `ztm_value.c`: pure C, R-free behind
`ztm_check.h`; UTF-8, tokens with positions, the table model, scalars
through zufast, the limits; produces the node tree `ztm_doc`) → **build
phase** (`ztm_build.c`: R values and the lattice from the node tree, sizes
from the check's counts) → R value. Local date-times reach the session's
zone in `R/parse.R`; data frames are built in `R/data-frame.R`.
`toml_validate()` is the check phase alone. The emitter, `src/ztm_emit.c`,
is a separate one-pass path into an `R_alloc()` buffer, with `R/emit.R`
turning local `POSIXct` into wall-clock text first.

## Invariants that are easy to break

- **The check phase contains no R.** `ztm_lex.c`, `ztm_parse.c` and
  `ztm_status.c` never include `R.h`; scratch, interrupts and "no offset" go
  through the hooks in `ztm_check.h`. The fuzz build (`-DZTM_STANDALONE`)
  compiles them standalone, and that is the only reason the fuzz gate works.
- **No R object is allocated before the check has passed over the whole
  document**, and container sizes come from the check's counts, never from
  the input (design §4, rule 1).
- **`toml_validate()` is exactly `toml_parse()`'s check phase**: same code,
  same limits. The only disagreements are the §6.4 unrepresentable cases,
  and a test enumerates them.
- **C never calls `Rf_error()`.** Entry points return a status by enumerator
  name; `R/conditions.R` maps names to classes. R maps by name, never by
  matching English.
- **Everything the C holds is `R_alloc()`ed or `PROTECT`ed**, so there are
  no finalizers and no cleanup paths; any hook may longjmp from anywhere. Do
  not introduce `malloc()` without reading design §13.
- **zufast parses digits, not TOML.** The lexer checks TOML's shape
  (underscores between digits, no sign before a prefix, seconds present,
  `±hh:mm` only), strips prefixes and underscores, then calls
  `zuf_parse_i64_opt()` with `base`, `zuf_parse_f64()` or
  `zuf_parse_datetime()`, and checks `r.ptr == last`. zufast's grammars are
  wider than TOML's in every case; skipping the shape check makes zutoml
  accept documents `toml-test` says are invalid.
- **Security guards carry a `/* GUARD: name */` marker** on their `if` line
  and have a `toml-test` invalid case or a hostile input;
  `tools/run-mutation-check` proves each is load-bearing. Add both for any
  new guard.
- **The emitter charges `max_depth` as the parser does**, so it never writes
  what the parser refuses (design §8).
- **Three decoder rules make `toml_emit(toml_parse(d))` reproduce `d`** and
  are pinned by the round-trip tests: a one-element array decodes as an
  `I()` value, booleans do not join the numbers, and whole doubles emit as
  integers.
- **`ztm_mkchar()` is the only place a CHARSXP is made**, so the U+0000 and
  length guards cannot drift between values, names and keys.
- **Portable make only** in `src/Makevars`: `OBJECTS` hand-listed, no
  `$(wildcard)`, no `$(shell)`, no `-W*` overrides, no `Makevars.win`.
- **A change to a contract amends the design in the same commit**: the
  exports, the mapping tables, the limits, the condition fields. Design
  §6–§7, the roxygen tables and the tests are the same table three times.

## Naming

<!-- markdownlint-disable MD013 -->
| Layer | Prefix | Examples |
| --- | --- | --- |
| R exports | `toml_` plus `zutoml_info()` | `toml_parse()`, `toml_emit()`, `toml_bigint()` |
| R condition classes | `zutoml_` | `zutoml_error`, `zutoml_parse_error` |
| User-facing value class | `toml_` | `toml_bigint` |
| R and C internals | `ztm_` / `ZTM_` | `ztm_mkchar()`, `ZTM_STANDALONE` |
| `.Call` entry points | `zutoml_` | `zutoml_parse` |
| Test-switching variables | `ZUTOML_` | `ZUTOML_SKIP_HEAVY`, `ZUTOML_SLOW_TESTS` |
<!-- markdownlint-enable MD013 -->

`zu_`/`ZU_` is zukomp's family-wide C prefix; `zuf_`, `zb_`, `zuc_`, `zux_`,
`zuh_` are taken. Stage 0 verified that `ztm_` was free.

## Editing rules specific to zutoml

- **There is no `README.Rmd`**, a deviation from the shared rule: edit
  `README.md` directly and keep its example output in step with the code by
  running it.
- Prose is en-GB (`Language: en-GB`); domain terms go in `inst/WORDLIST`.
- `Suggests` only: `zujson` for the suite's expectation files, `withr`,
  `testthat`, `knitr`, `rmarkdown`.
- Every exported function has `@return` and runnable `@examples`.
- `R/zu_source.R` is copied verbatim from `../zuxml`; fix it there and
  re-copy. `air.toml` excludes it from `air format`.
- `NEWS.md` keeps a versioned heading (`# zutoml 0.1.0.9000`): a bare
  "development version" heading is a check NOTE once it is the only one.

## Testing

- **No file-scope objects, because `shuffle = TRUE` reorders a file's
  top-level code too.** Anything two tests share goes in `helper-*.R`.
- **Assert on condition classes and fields**:
  `expect_error(..., class = "zutoml_parse_error")` plus `kind`, `line`,
  `column`, `offset` or `path`.
- **Serial.** No `Config/testthat/parallel`, so gctorture and valgrind see
  the C.
- **The conformance suite is `toml-test`** (MIT; v2.2.0 on 2026-10-08),
  fetched only by `tools/update-fixtures` into `tests/testthat/toml-test/`
  with a manifest, never hand-edited. It is in git but `.Rbuildignore`d, so
  no file by another author ships and `Authors@R` names only the maintainer.
  `toml_test_dir()` skips the
  tests that read it where it is absent (R CMD check on a tarball, on CRAN
  and in CI alike); `tools/run-conformance` and `devtools::test()` run them
  from the checkout, and the `conformance` workflow does so in CI. Its
  tagged JSON expectations are compared type by type against
  `toml_parse(d, simplify = "none")` twice: with `datetimes = "keep"`, and
  with `datetimes = "convert", local_time = "difftime"` (only the second
  tells a date from a string). It does not cover the lattice,
  `data_frame =`, the limits or the hostile inputs, which are the package's
  own tests.
- **Helpers** in `tests/testthat/`:
  - `helper-expect.R`: `expect_toml()` (emit gives exactly this text),
    `expect_roundtrip()`, `expect_zutoml_error()` (class plus `kind`).
  - `helper-fixtures.R`: `toml_test_dir()`, `toml_test_cases()`,
    `tagged_json_to_r()`, `toml_test_diff()`, tested in
    `test-helper-fixtures.R`.
  - `helper-generate.R`: random values for the round-trip properties, built
    to avoid exactly the losses design §7.4 lists, so a difference is a bug.
  - `helper-lex.R`: token and lexer-error helpers over the internal
    `ztm_tokens()`.
  - `helper-select.R`: the document `test-select.R` reads.
  - `helper-skip.R`: `skip_heavy()` on `ZUTOML_SKIP_HEAVY`, set by the
    gctorture and valgrind legs; `skip_if_no_slow_tests()` on
    `ZUTOML_SLOW_TESTS`; `skip_until_exported()`.
- **Never write an expected double as a long decimal literal**: R's parser
  on macOS arm64 rounds some to a neighbouring double. Use exact forms
  (`2^53`, `-2^63`) or bits.
- **Time budget: under 15 s.** The 10^6-element hostile inputs call
  `skip_heavy()`.
- **Done, beyond the shared definition:** `gctorture(TRUE)` clean when C
  changed, and a gate counts only once it has been seen to fail.

## Continuous integration

- `R-CMD-check.yaml` calls r-actions' `r-cmd-check.yml@v1`. **A deviation
  from `ci.md`:** it does not pass `profile: auto`. It runs the quick
  profile on a pull request and the full profile on every push to `main`
  and under `full-ci`. It adds a Windows R-devel row to the shared runners
  (CRAN's Windows R-devel flavour) and sets `nosuggests` and `nold` (CRAN's
  NOSUGGESTS and NOLD flavours), both full profile only.
- `coverage.yaml` calls `coverage.yml`, pinned by commit (it holds a write
  token), and writes the badge under `.github/badges/`.
- `pkgdown.yaml` builds the site.
- `native-checks.yaml` calls `sanitizers.yml` (UBSan on clang and gcc, ASan
  with `-UNDEBUG`), `valgrind.yml`, `lto.yml`, `gctorture.yml`,
  `analyzers.yml` and `rchk.yml`, weekly on Wednesday as well as on push.
  It still skips prose with a `paths-ignore` list rather than the
  `changes.yml` gate.
- `conformance.yaml` (own) checks that the committed suite equals a fresh
  fetch at the pinned tag, runs every case for TOML 1.0.0 and 1.1.0 through
  `tools/run-conformance`, and has `toml_emit()`'s text for every valid
  case accepted by toml-test's reference decoder (BurntSushi/toml, pinned)
  and by Python's `tomllib`.
- `hardening.yaml` (own) runs the C-boundary gates: lint, symbols, both
  mutation checks, no network, and libFuzzer over the check phase with the
  corpus cached between runs (2 minutes per pull-request push, 30 minutes
  nightly).

Neither of the package's own workflows calls `changes.yml` yet, so a label
does not skip them. Dependabot updates `github-actions`. Nothing is vendored,
so there is no `vendor.yaml`.
