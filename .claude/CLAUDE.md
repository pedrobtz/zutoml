# CLAUDE.md

<!-- markdownlint-disable-next-line MD013 -->
This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`zutoml` is an R package that parses TOML 1.0 documents into ordinary R values and emits R values as TOML, with a C99 parser and emitter of its own (no vendored library) over the scalar primitives of `zufast` (`LinkingTo`, header-only). It passes the `toml-test` conformance suite in both directions, types every value by the document's syntax (never by sniffing strings), and emits deterministic, readable text. Zero hard runtime dependencies: `zufast` is needed at build time only. It deliberately does not preserve comments or formatting (that is `tomledit`'s and `toml`'s job), validate against a schema, or offer a C API.

Two documents outrank this file. [.agents/design.md](../.agents/design.md) is the specification, numbered §1–§20: every statement in it is a decision, and open questions live only in its §18. [.agents/roadmap.md](../.agents/roadmap.md) sequences it into Stages 0–8, each with a **Status:** line under its heading. Both were adopted on 2026-10-08 from [RFC 0004](https://github.com/pedrobtz/packages/blob/main/rfcs/0004-zutoml-toml-documents.md) in `pedrobtz/packages`. `CLAUDE.md` orients, the design decides, the roadmap sequences.

It is a member of the `zu*` family (sibling checkouts in `../`). `zuyaml` is the model for the R API shape and the bigint class, `zujson` for the array lattice, `zucbor` for limits, conditions, the conformance runner and the mutation check, `zuxml` for `R/zu_source.R`. When a question is not answered here or in the design, look at how those packages settle it before inventing something new.

## Current state

**2026-10-08: Stage 0 merged (#11); Stage 1 (the lexer) in review on `stage-1-lexer`.** `src/ztm_lex.c` tokenises every valid toml-test document for TOML 1.0.0 and 1.1.0 (D17: 1.1.0 is the default) with positioned faults; `ztm_tokens()` is the internal entry the tests use. Gates: `tools/run-conformance`, `tools/run-lint`, `tools/check-symbols`, `tools/run-fuzz` (needs a clang with libFuzzer; on macOS, Homebrew's: `FUZZ_CC=/opt/homebrew/opt/llvm/bin/clang`), in `conformance.yaml` and `hardening.yaml`. Next: Stage 2, values through zufast.

Update this paragraph at the end of every stage: what exists, what is next, and the date.

## Stage tracking

Progress toward the next version is tracked as GitHub sub-issues, so the parent issue shows a progress bar such as "6 of 7".

- **One parent issue per target version**, titled with the bare version, `v0.1.0`: #1, opened 2026-10-08 with sub-issues #2 (Stage 0) to #10 (Stage 8). It is not yet on the board: that needs zutoml added to `.github/scripts/stage-cards.sh` in `pedrobtz/packages`.
- **One sub-issue per roadmap stage**, titled as the roadmap titles it, for example `Stage 3 — The table model and the grammar`, and linking to that section's anchor. The roadmap has nine stages, 0 to 8.
- **Every tracking issue carries the `stage` label**, so it can be told apart from bug and feature issues and left out of open-issue counts.
- **Close a stage by merging its pull request.** Put `Closes #<n>` in the body. Never close a stage whose exit criteria are not met; record a deviation in the stage's **Status:** line first.
- **The roadmap stays authoritative.** Adding, removing or renaming a stage means editing the roadmap and the sub-issues in the same change. Status never goes in a heading: it would change the anchor every issue links to.
- Close the parent issue when CRAN accepts the version and it is tagged.

## Versioning

The package develops at `0.0.0.9000` and targets `0.1.0` for its first CRAN release. Set `Version: 0.1.0` and the matching `NEWS.md` heading when the package enters `Pre-flight` (Stage 8). Bump to `0.1.0.9000` only after CRAN accepts it, never before.

Until the first release the R API may change freely. zutoml depends on a sibling before CRAN does: `LinkingTo: zufast (>= 0.1.0)`, resolved from `Remotes: pedrobtz/zufast@main` during development. **zufast must be on CRAN before zutoml is submitted**, the `Remotes:` line goes at Stage 8, and the release build is checked against zufast's CRAN tarball, because header-only is source-compatible, not ABI-compatible. No package depends on zutoml.

## Commands

Run from the package root.

```sh
Rscript -e 'devtools::load_all()'                # compile src/ and load
Rscript -e 'devtools::document()'                # roxygen -> NAMESPACE, man/
Rscript -e 'devtools::test()'                    # full testthat suite
Rscript -e 'devtools::test(filter = "<name>")'   # one test file
Rscript -e 'devtools::test(shuffle = TRUE)'      # order independence
_R_CHECK_SYSTEM_CLOCK_=0 Rscript -e 'devtools::check(cran = TRUE)'
air format .                                     # format R sources
```

zufast is not on CRAN: install it from the sibling checkout (`R CMD INSTALL ../zufast`) or `pak::pak("pedrobtz/zufast")`. roxygen2 must be 8.1.0 or newer (`Config/roxygen2/version`); an older one rewrites `man/`.

Gate scripts, each arriving at the roadmap stage named and run from the package root:

```sh
tools/update-fixtures          # Stage 0: fetch toml-test at the pinned tag, write the manifest
tools/run-conformance          # Stage 1: every toml-test case through the check phase (CI: conformance)
tools/run-fuzz [secs]          # Stage 1: canary first, then fuzz_parse under ASan+UBSan (CI: hardening)
tools/run-lint                 # Stage 1: -Wall -Wextra -Wpedantic -Wshadow -Werror on project C
tools/check-symbols <so>       # Stage 1: only R_init_zutoml exported; no stdio/abort/exit/assert
tools/run-mutation-check       # Stage 3: every /* GUARD */ seen to be load-bearing
tools/check-no-network         # Stage 6: no test opens a URL or socket
tools/run-benchmarks           # Stage 7: parse vs RcppTOML, emit vs zuyaml; not a CI gate
```

Run `tools/check-symbols` on an `R CMD INSTALL` build, not a `load_all()` one (`load_all()` compiles with `-UNDEBUG`).

## Architecture

Planned layout, from design §4 and §13. Nothing under `src/` beyond the template exists yet.

```text
R/            parse.R, read.R, validate.R, emit.R, write.R, classes.R (toml_bigint),
              conditions.R, args.R, info.R, zu_source.R (copied verbatim from zuxml;
              edit there), zutoml-package.R
src/          init.c                      registration only
              ztm_check.h                 the check phase's R-free interface
              ztm_lex.c, ztm_parse.c      check phase: lexer, grammar, table model, limits
              ztm_status.c                enumerator names (R-free)
              ztm_build.c                 build phase: §6 mapping; ztm_mkchar() the one CHARSXP site
              ztm_emit.c                  §7, §8
              ztm_time.c                  local time; calendar glue over zufast
              Makevars                    hand-listed OBJECTS, $(C_VISIBILITY)
fuzz/         fuzz_parse.c, fuzz_canary.c (not in the tarball)
tools/        gate scripts above
tests/testthat/toml-test/   the suite at a pinned tag, with manifest.tsv (not under fixtures/:
              the 100-byte tarball path limit)
.agents/      design.md, roadmap.md
```

The pipeline is: validate and decode the input in R → **check phase** (`ztm_lex.c`, `ztm_parse.c`: pure C, R-free behind `ztm_check.h`; UTF-8, tokens with positions, the table model, scalars through zufast, the limits; produces an event list) → **build phase** (`ztm_build.c`: R values from the event list, sizes from the check's counts) → R value. `toml_validate()` is the check phase alone. The emitter is a separate one-pass path into an `R_alloc()` buffer.

## Invariants that are easy to break

- **The check phase contains no R.** `ztm_lex.c`, `ztm_parse.c` and `ztm_status.c` never include `R.h`; scratch, interrupts and "no offset" go through the hooks in `ztm_check.h`. The fuzz build (`-DZTM_STANDALONE`) compiles them standalone, and that is the only reason the fuzz gate works.
- **No R object is allocated before the check has passed over the whole document**, and container sizes come from the check's counts, never from the input (design §4, rule 1).
- **`toml_validate()` is exactly `toml_parse()`'s check phase**: same code, same limits. The only disagreements are the §6.4 unrepresentable cases, and a test enumerates them.
- **C never calls `Rf_error()`.** Entry points return a status by enumerator name; `R/conditions.R` maps names to classes. R maps by name, never by matching English.
- **Everything the C holds is `R_alloc()`ed or `PROTECT`ed**, so there are no finalizers and no cleanup paths; any hook may longjmp from anywhere. Do not introduce `malloc()` without reading design §13.
- **zufast parses digits, not TOML.** The lexer checks TOML's shape (underscores between digits, no sign before a prefix, seconds present, `±hh:mm` only), strips prefixes and underscores, then calls `zuf_parse_i64_opt()` with `base`, `zuf_parse_f64()` or `zuf_parse_datetime()`, and checks `r.ptr == last`. zufast's grammars are wider than TOML's in every case; skipping the shape check makes zutoml accept documents `toml-test` says are invalid.
- **Security guards carry a `/* GUARD: name */` marker** on their `if` line and have a `toml-test` invalid case or a hostile input; `tools/run-mutation-check` proves each is load-bearing. Add both for any new guard.
- **The emitter charges `max_depth` as the parser does**, so it never writes what the parser refuses (design §8).
- **Three decoder rules make `toml_emit(toml_parse(d))` reproduce `d`** and are pinned by the round-trip tests: a one-element array decodes as an `I()` value, booleans do not join the numbers, and whole doubles emit as integers.
- **`ztm_mkchar()` is the only place a CHARSXP is made**, so the U+0000 and length guards cannot drift between values, names and keys.
- **Portable make only** in `src/Makevars`: `OBJECTS` hand-listed, no `$(wildcard)`, no `$(shell)`, no `-W*` overrides, no `Makevars.win`.
- **Status never goes in a roadmap heading** (it changes the anchor the stage issues link to).

## Naming

| Layer | Prefix | Examples |
|---|---|---|
| R exports | `toml_` plus `zutoml_info()` | `toml_parse()`, `toml_emit()`, `toml_bigint()` |
| R condition classes | `zutoml_` | `zutoml_error`, `zutoml_parse_error` |
| User-facing value class | `toml_` | `toml_bigint` |
| R and C internals | `ztm_` / `ZTM_` | `ztm_mkchar()`, `ZTM_STANDALONE` |
| `.Call` entry points | `zutoml_` | `zutoml_parse` |
| Test-switching variables | `ZUTOML_` | `ZUTOML_SKIP_HEAVY`, `ZUTOML_SLOW_TESTS` |

`zu_`/`ZU_` is zukomp's family-wide C prefix; `zuf_`, `zb_`, `zuc_`, `zux_`, `zuh_` are taken. Stage 0 re-verifies `ztm_` is free.

## Testing conventions

- **Self-sufficient.** Every test builds its own inputs inside the `test_that()` block. No file-scope objects: `shuffle = TRUE` reorders a file's top-level code too, so anything two tests share goes in `helper-*.R`.
- **Self-contained.** Global state through `withr::local_*()`, randomised input through `withr::local_seed()`. Tests write only under `tempdir()`.
- **Assert on condition classes and fields, never message text.** `expect_error(..., class = "zutoml_parse_error")` plus `kind`, `line`, `column`, `offset` or `path`. Wording belongs in snapshot tests.
- **Order independence.** `devtools::test(shuffle = TRUE)` is part of the definition of done. Serial: no `Config/testthat/parallel`, so gctorture and valgrind see the C.
- **The conformance suite is `toml-test`** (MIT; v2.2.0 on 2026-10-08), fetched only by `tools/update-fixtures` into `tests/testthat/toml-test/` with a manifest, never hand-edited. Its tagged JSON expectations are compared type by type against `toml_parse(d, simplify = "none")` twice: with `datetimes = "keep"`, and with `datetimes = "convert", local_time = "difftime"` (only the second tells a date from a string). `test-conformance.R` skips until `toml_validate()` (Stage 3) and `toml_parse()` (Stage 4) are exported, then every case must pass. It does not cover the lattice, `data_frame =`, the limits or the hostile inputs, which are the package's own tests.
- **Helpers live in `tests/testthat/helper-*.R`**: `helper-expect.R` (`expect_toml()`, `expect_roundtrip()`, `expect_zutoml_error()`), `helper-fixtures.R` (`toml_test_cases()`, `tagged_json_to_r()`, `toml_test_diff()`, tested in `test-helper-fixtures.R`), `helper-skip.R` (`skip_heavy()` on `ZUTOML_SKIP_HEAVY`, set by the gctorture and valgrind legs; `skip_if_no_slow_tests()` on `ZUTOML_SLOW_TESTS`; `skip_until_exported()`).
- **Never write an expected double as a long decimal literal**: R's parser on macOS arm64 rounds some to a neighbouring double. Use exact forms (`2^53`, `-2^63`) or bits.
- **Keep the suite inside the CRAN time budget:** under 15 s; the 10^6-element hostile inputs call `skip_heavy()`.
- Design §6–§7, the roxygen tables and the tests are the same table three times.

## Definition of done

`devtools::document()` and `devtools::check()` clean, meaning 0 errors, 0 warnings and 0 notes. The one allowed note is "New submission" before the first release. `devtools::test(shuffle = TRUE)` green. `gctorture(TRUE)` clean when C changed. CI green on every leg. A user-facing change also needs a test, roxygen documentation and a `NEWS.md` entry. A change to a contract (the exports, the mapping tables, the limits, the condition fields) amends the design in the same commit. A stage is done when its exit criteria pass in CI on all three platforms, not when the code is written; a gate counts once it has been seen to fail.

## Releasing to CRAN

- **CI is the pre-submission check.** The `pedrobtz/r-actions` R CMD check runs `--as-cran` on the CRAN-like runners and containers, and it replaces win-builder, the macOS builder and R-hub. None of them is a release step, and `cran-comments.md` lists the CI legs as its test environments.
- **Entering `Pre-flight`.** Stages 0–7 done, `Version: 0.1.0` set with the `NEWS.md` heading, `cran-comments.md` written, CI green, zufast on CRAN and `Remotes:` removed.
- **Before submitting,** run the `cran-extrachecks` and `review-cran-submission` skills, and resolve every finding.
- **The pretest is automated and does not read `cran-comments.md`.** A NOTE that is explained but not fixed gets the upload archived. Fix the NOTE.
- **After acceptance,** tag `v0.1.0`, publish the GitHub release, bump to `0.1.0.9000`, and close the version's parent issue.

## Editing rules

- roxygen comments are the source. Never edit `man/` or `NAMESPACE` by hand.
- There is no `README.Rmd`; edit `README.md` directly and keep its example output in step with the code by running it.
- Keep prose simple and short, en-GB (`Language: en-GB`; domain terms in `inst/WORDLIST`). One idea per sentence.
- Wrap roxygen text at 80 characters and run `air format .` on R sources.
- `lower_snake_case`; the naming table above.
- Keep hard runtime dependencies at zero. `Suggests` only: `jsonlite` for the suite's expectation files, `withr`, `testthat`, `knitr`, `rmarkdown`.
- Export and document public functions, each with `@return` and runnable `@examples`. No roxygen topics for internals.
- `R/zu_source.R` is copied verbatim from `../zuxml`; fix it there and re-copy.
- `NEWS.md` keeps a versioned heading (`# zutoml 0.0.0.9000`): a bare "development version" heading is a check NOTE once it is the only one.

## Continuous integration

Workflows come from `pedrobtz/r-actions`. The scaffold's `R-CMD-check.yaml` (quick profile on pull requests, full on `main` and under the `full-ci` label), `coverage.yaml` (writes the badge under `.github/badges/`) and `pkgdown.yaml` exist at `@v1`; Stage 0 pins `coverage.yaml` by commit (it holds a write token) and adds Dependabot for `github-actions`. The roadmap's CI table says which stage adds `conformance.yaml`, `hardening.yaml` (fuzz, lint, mutation check, no-network, symbols) and `native-checks.yaml` (UBSan, ASan with `-UNDEBUG`, valgrind, LTO, gctorture, blocking rchk). `_pkgdown.yml` gets `development: mode: auto`. Stage pull requests carry `full-ci`.

Nothing is vendored, so there is no `vendor.yaml`.

This file lives in `.claude/`, not the package root, because pkgdown renders every root-level `*.md` as a site page (alignment rule R8 in `pedrobtz/packages`); keep it here.

## Commits and pull requests

Short, imperative, sentence-case commit subjects, optionally scoped. Keep each commit focused and do not sweep in unrelated files. A pull request explains the user-visible outcome and the rationale, links related issues, lists the checks that were run and the tests that were skipped, and flags platform-sensitive changes. Performance claims need evidence.

Never commit or push to the default branch. Work on a branch (`stage-N-<slug>` for a stage), open a pull request, and leave it for review. Do not merge a pull request unless you are told to.

When you find a defect, in this package, in `zufast` or in an upstream tool, open an issue for it rather than only working around it.
