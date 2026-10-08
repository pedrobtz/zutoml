# zutoml — Roadmap to 0.1.0 (first CRAN release)

Companion to [design.md](design.md). Section references (§) point there.

**Status:** adopted 2026-10-08 from [RFC 0004](https://github.com/pedrobtz/packages/blob/main/rfcs/0004-zutoml-toml-documents.md). Nothing below is implemented; the repository is the `usethis` skeleton (created 2026-10-08 with `create-pkg.sh -c`) plus these documents.

## Sequencing principles

1. **The conformance runner lands with the lexer, not after the parser.** `toml-test` is the oracle for every later stage (§15); a stage that cannot run the suite cannot show it is done.
2. **The check phase lands before the builder.** The table model and the limits are the security core (§4, §12). Building R objects first means retrofitting limits into code that already assumes they hold.
3. **The emitter lands before hardening.** Round trip is the strongest property available (§7.4); every stage after it gets a better suite for free.
4. **Every stage ends with something runnable and tested.** No stage is "write three files, test later".
5. **A stage is done when its exit criteria pass in CI on all three platforms**, not when the code is written.
6. **Gates need canaries.** A gate is trusted once it has been seen to fail on purpose: a planted symbol, a fuzz canary that crashes, a removed guard whose hostile input is accepted.
7. **Change the design in the same commit as the contract.** A stage that changes a decision in §17 edits design.md in that commit, with the roxygen table and the tests that state it.

Sizes are relative: **S** ≈ a sitting, **M** ≈ a few, **L** ≈ the stage is the week.

**Status never goes in a heading.** A heading is `## Stage N — Title · Size` and nothing else; the state is the **Status:** line under it. Status words in a heading change its GitHub anchor and break every issue that links to it.

**Tracking.** A `v0.1.0` parent issue and one `stage`-labelled sub-issue per stage, each linking to its heading here, as `templates/package-CLAUDE.md` describes. None exists on 2026-10-08; Stage 0 opens them and `.github/scripts/stage-cards.sh` in `pedrobtz/packages` puts the parent on the board. Close a stage's issue when its exit criteria pass and update its **Status:** line in the same pull request. Each stage gains a **What actually happened** block when it closes: what the plan got wrong is the most useful thing this file records.

## The release order, and what it costs

zutoml's C includes `zufast`'s headers, so `LinkingTo: zufast (>= 0.1.0)` is unconditional and **zufast must be on CRAN before zutoml can be submitted** (alignment R10.2: a submitted tarball never carries `Remotes:`). On 2026-10-08 zufast is tagged 0.1.0 and not on CRAN. Until it is, `DESCRIPTION` carries `Remotes: pedrobtz/zufast@main` so that `setup-r-dependencies` and `pak` resolve it in CI, and Stage 8 removes the field and rebuilds against the CRAN tarball (R10.3: header-only is source-compatible, not ABI-compatible). Every stage before 8 can proceed; only the submission waits. If zufast's release slips indefinitely, the fallback is to inline the five primitives zutoml uses (`zuf_parse_i64_opt`, `zuf_parse_f64`, `zuf_parse_datetime`, `zuf_format_f64`, `zuf_format_datetime`, plus `zuf_utf8_valid`) under a documented exception; §20 says why that is not planned.

Nothing waits on zutoml.

## Working rhythm

One pull request per stage (zucrypt's rhythm): branch `stage-N-<slug>` from `main`; `devtools::document()`, `devtools::test()`, `devtools::test(shuffle = TRUE)` and `devtools::check(cran = TRUE)` clean at 0/0/0 locally before pushing; the PR body states the stage and its exit criteria as a checklist, carries `Closes #<n>` for the stage issue, and wears the `full-ci` label so the full R CMD check matrix runs before merge; every CI leg green before merging, not "green except the container ones"; then update `.claude/CLAUDE.md`'s current-state paragraph and the **Status:** line.

Two local traps the siblings hit: roxygen2 must be 8.1.0 or newer (`Config/roxygen2/version: 8.1.0`) or `document()` rewrites `man/`; and `devtools::check()` offline NOTEs on the system clock, silenced with `_R_CHECK_SYSTEM_CLOCK_=0`.

## Testing strategy, fixed once

Inherited from the family and stated in §15; every stage adds its tests under these rules.

- Self-sufficient tests: inputs built inside each `test_that()`; `withr::local_seed()` for anything random; nothing written outside `tempdir()`.
- Assert on condition classes and fields (`kind`, `line`, `column`, `offset`, `path`), never message text; wording is covered by snapshots.
- Serial testthat, no `Config/testthat/parallel`. `devtools::test(shuffle = TRUE)` is in every stage's definition of done. Shuffling reorders a file's top-level code too: anything two tests share goes in a `helper-*.R` file.
- Helpers: `helper-expect.R` (`expect_toml(x, text)`, `expect_roundtrip(x)`, `expect_zutoml_error(expr, class, kind = NULL)`), `helper-fixtures.R` (`toml_test_cases(kind)` reading the manifest, `tagged_json_to_r()` for the suite's expectation files), `helper-skip.R` (`skip_heavy()` on `ZUTOML_SKIP_HEAVY`, set by the gctorture and valgrind legs; `skip_if_no_slow_tests()` on `ZUTOML_SLOW_TESTS`; alignment R7 names).
- Fixtures: `tests/testthat/toml-test/` from `tools/update-fixtures` with a manifest (not under `fixtures/`: design §15); nothing generated at test time; nothing hand-edited.
- CRAN budget: the suite finishes in under 15 s; the `toml-test` corpus runs on CRAN too, since it is under 1 MB; the 10^6-element hostile inputs sit behind `skip_heavy()`.

## CI, and the stage each workflow lands in

Reusable workflows from `pedrobtz/r-actions`. `R-CMD-check.yaml`, `coverage.yaml` and `pkgdown.yaml` exist from the scaffold at `@v1`; alignment R5 recommends commit pins everywhere with the tag in a trailing comment and Dependabot keeping them current, and the template requires a commit pin for `coverage.yml`, which holds a write token. A workflow lands at the stage where it has something to check; a job that is green because it inspected nothing is worse than none.

| Workflow | Stage | What it checks |
|---|---|---|
| `R-CMD-check.yaml` (exists) | 0 | runners and the CRAN-like containers; quick on PRs, full on `main` and with the `full-ci` label; zufast from `Remotes` |
| `coverage.yaml` (exists) | 0 | badge on `main`; pinned by commit |
| `pkgdown.yaml` (exists) | 0 | the site; `development: mode: auto` in `_pkgdown.yml` |
| `conformance.yaml` | 1 | `tools/run-conformance`: fixtures equal a fresh fetch; the `toml-test` reference binary accepts every emitted document (from Stage 5) |
| `hardening.yaml` | 1 | `tools/run-fuzz` through r-actions `fuzz.yml`: canary first, then `fuzz_parse` under ASan and UBSan, 2 minutes per PR and 30 nightly on a cached corpus; `tools/run-lint`; `tools/check-no-network`; `tools/run-mutation-check` from Stage 3 |
| `native-checks.yaml` | 2 | r-actions sanitizers, valgrind, LTO, gctorture (quick step on PRs), blocking rchk, analyzers |
| `symbols` job (in `hardening.yaml`) | 0 | `tools/check-symbols` on an `R CMD INSTALL` build: `R_init_zutoml` only; no stdio, `abort`, `exit` or `assert` |
| `vendor.yaml` | — | not used: zutoml vendors nothing |

CI stands in for win-builder and the macOS builder (the template's "Releasing to CRAN"): the Windows R-devel and macOS release legs are CRAN's own builds under `--as-cran`. Neither builder is a release step.

## Stage map

| Stage | Size | Needs | Delivers |
|---|---|---|---|
| 0 — Package identity and a clean baseline | S | — | a package that checks 0/0/0 with zufast resolved; fixtures and tracking issues |
| 1 — The lexer and the `toml-test` runner | M | 0 | tokens with positions; `tools/run-conformance`; the fuzz target and canary |
| 2 — Values through zufast | M | 1 | every scalar form of §9 parsed, every invalid scalar refused with its `kind` |
| 3 — The table model and the grammar | L | 2 | `toml_validate()`: every `toml-test` case passes; guards and the mutation check |
| 4 — Build phase | M | 3 | `toml_parse()`: the lattice, `toml_bigint`, `data_frame =`; every `valid/` case to its value |
| 5 — The emitter | M | 4 | `toml_emit()`, `toml_write()`; §7 and §8; the emitter against the suite |
| 6 — Round trip, limits, fuzzing, mutation check | M | 5 | the properties and hostile inputs of §15; sanitizers clean |
| 7 — Files, connections, documentation, benchmarks | S | 6 | `toml_read()` bounded; vignette; `cran-comments.md`; benchmarks recorded |
| 8 — Release 0.1.0 | S | 7, and zufast on CRAN | the submission |

---

## Stage 0 — Package identity and a clean baseline · S

**Status:** in progress (branch `stage-0-baseline`). Done locally: metadata, registration, conditions, the test suite (fixtures, helpers, `test-conformance.R` skipping until the parser exports), `tools/update-fixtures`, `tools/run-conformance --fixtures-only`; `devtools::check(cran = TRUE)` 0/0/0. Left: the `coverage.yaml` pin, Dependabot, the tracking issues and labels, CI green.

**Goal:** the `usethis` skeleton becomes a package with the right metadata, registration and build hygiene, so every later stage is measured against a clean 0/0/0.

**Do**

- `DESCRIPTION`: `Title: Read and Write 'TOML' Documents`; a `Description` naming TOML 1.0, the four date-time types, the emitter and `toml-test`; `Authors@R` Pedro Baltazar (`aut`, `cre`, `cph`); `Depends: R (>= 4.1)`; `LinkingTo: zufast (>= 0.1.0)`; `Remotes: pedrobtz/zufast@main` (development only, see above); `Suggests: testthat (>= 3.0.0), withr, jsonlite, knitr, rmarkdown`; `VignetteBuilder: knitr`; `Language: en-GB`; `Config/roxygen2/version: 8.1.0`; `URL` and `BugReports`; `Config/testthat/edition: 3` and **no** `Config/testthat/parallel`. No `Imports`, no `Copyright:`: nothing is vendored.
- `LICENSE` and `LICENSE.md` name the real holder.
- `.Rbuildignore`: `^\.agents$` and `^\.claude$` (added with these documents), `^tools$`, `^fuzz$`, `^cran-comments\.md$`, `^CRAN-SUBMISSION$`, `^vignettes/articles$`, and the `src/` patterns for `*.o`, `*.so`, `*.dll`, `*.dylib`; the same object patterns in `.gitignore`.
- `src/init.c` with `R_registerRoutines()` over an empty table, `R_useDynamicSymbols(dll, FALSE)`, `R_forceSymbols(dll, TRUE)`; delete the template `src/zutoml.c`; `src/Makevars` with `PKG_CFLAGS = $(C_VISIBILITY)`, `OBJECTS = init.o`, and a comment that `OBJECTS` is hand-listed.
- `R/zutoml-package.R` keeps the `@useDynLib zutoml, .registration = TRUE` block; `R/conditions.R` with the §11 hierarchy documented in one `?"zutoml-conditions"` topic and `ztm_abort()` building classed conditions in `zucbor`'s shape.
- `NEWS.md`: `# zutoml 0.0.0.9000` (a bare "development version" heading is a check NOTE once it is the only one).
- Replace the template test with `tests/testthat/test-init.R`: the DLL is loaded and registered. Write it before removing the template test: an empty `tests/testthat/` beside `tests/testthat.R` is a hard check error.
- `coverage.yaml`: pin `coverage.yml` by commit with the tag in a trailing comment; add `.github/dependabot.yml` for `github-actions` (R5).
- `_pkgdown.yml`: `development: mode: auto`.
- **Verify the `ztm_` prefix is free**: grep every sibling's `src/` and `inst/include/` for `ztm_` and `ZTM_`; record the date in design §3.
- `tools/update-fixtures`: fetch `toml-test` at a pinned tag (v2.2.0 on 2026-10-08; re-check) into `tests/testthat/toml-test/` with `manifest.tsv` (path, TOML versions, SHA-256), `VERSION`, `LICENSE` and a `README.md`, all written by the tool.
- `.claude/CLAUDE.md` (exists from 2026-10-08): update its current-state paragraph.
- Open the tracking issues: `v0.1.0` parent, one `stage`-labelled sub-issue per stage linking to its anchor here; create the `stage` and `full-ci` labels.

**Exit**

- `devtools::check(cran = TRUE)` is 0/0/0 locally, with zufast installed from the sibling checkout or `Remotes`.
- `R-CMD-check.yaml` is green on every leg with zufast resolved from `Remotes`.
- `NAMESPACE` carries `useDynLib(zutoml, .registration = TRUE)`.
- The fixtures are committed with their manifest; `tools/run-conformance --fixtures-only` reproduces them.
- The tracking issues exist and the parent is on the board.

**Not this stage:** any lexer code, any `toml_*` export.

---

## Stage 1 — The lexer and the `toml-test` runner · M

**Status:** not started.

**Goal:** every byte of a TOML document becomes a token with a line, column and byte offset, or a positioned refusal; and the conformance suite can be run, even though every case fails.

**Do**

- `src/ztm_check.h`: the R-free interface (hooks for scratch, interrupt, standalone build), status enumerators and the `kind` names of §11.
- `src/ztm_lex.c`: UTF-8 validation of the whole input (`zuf_utf8_valid()`), BOM, newlines (`\n`, `\r\n`; bare CR refused), comments, bare and quoted keys, the four string forms with their escape rules (§9), number and date-time *spans* (classified by shape; values come at Stage 2), punctuation; tokens carry line, column (characters) and offset (bytes). Iterative; no recursion.
- `max_size` and `max_string` enforced here (§12); `R_CheckUserInterrupt()` through the hook every 65 536 tokens.
- `src/ztm_status.c`: the enumerator-name table R maps to classes; a test enumerates every status and asserts it maps.
- A smoke `.Call` entry point that tokenises a buffer and returns the token table (internal, `zutoml_tokens`), used by the tests of this stage.
- `tools/run-conformance`: walks the manifest, runs each `valid/` and `invalid/` case through the current check phase, and reports counts by directory; at this stage it reports lexing results only. `conformance.yaml` runs it.
- `fuzz/fuzz_lex.c` (renamed `fuzz_parse.c` at Stage 3) and `fuzz/fuzz_canary.c` under `-DZTM_STANDALONE`; `tools/run-fuzz` requiring the canary to crash first; `hardening.yaml` with r-actions `fuzz.yml`, seeded from every `toml-test` file.
- `tools/run-lint` (`-Wall -Wextra -Wpedantic -Wshadow -Werror` over project C as `gnu17`), seen to fail on a planted warning; `tools/check-symbols`, seen to fail on a planted `fprintf(stderr, ...)` (zucbor found clang rewrites it to `fwrite`, so the check must list stream symbols, not only function names).
- **Decide §18 Q5** (TOML 1.1.0 as the default) with the runner in hand: run the suite at `-toml 1.0` and `-toml 1.1`, count the forms the lexer would need, record the decision in §17.

**Exit**

- Every `toml-test` file tokenises or fails at the position the suite implies; `tools/run-conformance` prints the table.
- The fuzz canary crashes and `fuzz_lex` runs clean for the PR budget; `tools/run-lint` and `tools/check-symbols` have each been seen to fail.
- Every control character in every string form is refused with `kind = "control_character"` and a position (`test-lex.R`).
- ASan and UBSan clean over the lexer tests (local, `-fsanitize`; the CI legs arrive at Stage 2).

---

## Stage 2 — Values: strings, numbers, date-times through zufast · M

**Status:** not started.

**Goal:** every scalar span becomes a value, through zufast where zufast applies, with TOML's restrictions checked first.

**Do**

- Strings: escape decoding into scratch, `\u`/`\U` with the surrogate rule, multi-line trimming and line-ending backslashes; U+0000 recorded as a flag for the build phase's `zutoml_unrepresentable`.
- Integers: shape check (sign only in decimal, no leading zeros, every `_` between digits), prefix and underscore stripping into scratch, `zuf_parse_i64_opt()` with `base`, `r.ptr == last`, `ZUF_ERR_RANGE` as `integer_range`. Classification for the build phase: fits `integer`, fits `double` exactly, needs `toml_bigint` (the canonical decimal is kept from the digits).
- Floats: shape check (digits both sides of a point, no leading zeros, `inf`/`nan` with optional sign), underscores stripped, `zuf_parse_f64()`.
- Date-times: TOML shape check on the text (`T`, `t` or space; seconds present under 1.0; `Z`, `z` or `±hh:mm` only), then `zuf_parse_datetime()` or `zuf_parse_date()` for the fields; the fraction kept to nine digits, more refused; local time parsed by zutoml with the same validation as zufast's time fields.
- Every value recorded in the event list with its position and classification, so the build phase never re-parses.
- `tests/testthat/test-values.R`: every scalar form of §9, boundary integers (`-9223372036854775808`, `9223372036854775807`, `2^53` ± 1, `-2147483648`), `-0.0`, every `invalid/` scalar case of the suite with its `kind`.
- `native-checks.yaml` lands: sanitizers with `-UNDEBUG`, valgrind, LTO, gctorture, blocking rchk.

**Exit**

- Every scalar form of §9 parses to the classification §6.1 says; every `invalid/` scalar case (`invalid/integer/`, `invalid/float/`, `invalid/datetime/`, `invalid/string/`, `invalid/control/`) is refused with its `kind`, by `tools/run-conformance`.
- `native-checks.yaml` green.

---

## Stage 3 — The table model and the grammar · L

**Status:** not started.

**Goal:** `toml_validate()` is exported, and the whole `toml-test` suite passes through it.

**Do**

- `src/ztm_parse.c`: the grammar over the token stream with an explicit stack for arrays and inline tables (`max_depth` a counter), `max_items` counting keys plus array elements.
- The table model: a hash table of canonical key paths in `R_alloc()` scratch with a state per node (`undefined`, `implicit`, `explicit`, `inline`, `array`); every rule of the spec's "Table" and "Array of Tables" sections a state transition with a `/* GUARD: name */` marker: no redefinition, no extending an inline table or an array of tables through dotted keys, no `[a]` after `[a.b]` defined `a` explicitly, duplicate keys refused at the second definition with its position, and the rest the suite's `invalid/table/`, `invalid/array/`, `invalid/inline-table/` and `invalid/key/` directories enumerate.
- The event list the build phase consumes (§4), with container counts.
- `toml_validate(x, ..., error = FALSE)` exported: the first user-facing function, since by §4 rule 2 it *is* this stage. `R/validate.R`, `R/args.R` for the limits (positive whole numbers or `Inf`; anything else `zutoml_invalid_argument`).
- `tools/run-mutation-check`: for every `/* GUARD */`, a scratch copy without it must accept the guard's `toml-test` invalid case or §15 hostile input; seen to fail on a guard whose case was wrong.
- `fuzz_lex` becomes `fuzz_parse` over the whole check phase; the monotonicity invariant (relaxing a limit only accepts more).
- `?"zutoml-conditions"` completed for every class the check phase raises.

**Exit**

- Every `valid/` case returns `TRUE` and every `invalid/` case raises `zutoml_parse_error` with the expected `kind`, through `toml_validate()`, in `conformance.yaml` on every platform.
- Every guard has a mutation case and `tools/run-mutation-check` passes.
- `[` repeated 10^6 times is `zutoml_depth_limit`; 10^6 `[[a]]` headers is `zutoml_item_limit` or parses, as the limits say; a 10 MB dotted key is `zutoml_string_limit`; no stack overflow under a 1 MB stack in the sanitizer job.
- **If this exit is not met in the stage's time, §18 Q6 is decided** (vendor `tomlc17`), recorded in §17, and Stage 4 proceeds over its tree.

---

## Stage 4 — Build phase: the lattice, bigints, data frames · M

**Status:** not started.

**Goal:** `toml_parse()` returns the §6 value for every valid document.

**Do**

- `src/ztm_build.c`: R values from the event list, containers allocated from the check's counts, tables as named lists in definition order, names and strings through `ztm_mkchar()` (the one CHARSXP site, with the U+0000 and length guards).
- Scalars: `integer`/`double`/`toml_bigint` by classification and `big_integers`; `POSIXct` in UTC from the fields (offset applied; civil-date arithmetic through zufast's calendar helpers); `POSIXct` with `tzone = ""` for local date-times; `Date`; local time as text or `difftime`; `datetimes = "keep"` returning normalised text.
- The lattice of §6.3 with booleans as their own kind and `I()` on one-element arrays; `simplify = "none"`; `data_frame = TRUE` with `max_cells`.
- `R/classes.R`: `toml_bigint()` constructor validating canonical decimal, with `format`, `print`, `as.character`, `as.numeric` and `[` methods.
- `toml_parse()` exported; `R/parse.R`.
- Tests: every row of §6.1 to §6.4; the lattice table; `test-conformance.R` comparing every `valid/` case with its tagged JSON twin (`helper-fixtures.R`'s `tagged_json_to_r()`).

**Exit**

- Every `valid/` case parses to its expected value, type by type, in `conformance.yaml`.
- Every §6 row has a test; `gctorture(TRUE)` clean over the suite locally; rchk clean.
- `toml_validate()` and `toml_parse()` disagree only on the §6.4 cases (a test enumerates them).

---

## Stage 5 — The emitter · M

**Status:** not started.

**Goal:** `toml_emit()` and `toml_write()` write §7's text under §8's rules, and the suite accepts it.

**Do**

- `src/ztm_emit.c`: one pass into a doubling `R_alloc()` buffer; §7.1 scalars (`zuf_format_f64()` with `.0` appended, `zuf_format_datetime()`, local time), §7.2 lists and data frames, bare or quoted keys, `[header]` and `[[header]]` blocks, `inline =`, `width =` wrapping with `indent =`, `strings = "literal"`, `na = "omit"`.
- `zutoml_unsupported_type`, `zutoml_na_error` and `zutoml_invalid_argument` with `path`.
- `max_depth` charged as the parser charges it.
- `toml_write()` through a connection or path; UTF-8, `\n`.
- Tests: every row of §7.1 to §7.3 as exact text (`expect_toml()`); the §7.4 table; `test-emit-conformance.R`: every `valid/` value emitted and parsed back equals the suite's expectation; `conformance.yaml` feeds the emitted text to the `toml-test` reference decoder.
- **Decide §18 Q1 to Q3** (inline threshold, `difftime` on emit, non-UTC `POSIXct`), record in §17.

**Exit**

- Every `valid/` value round-trips through the emitter to its expectation; the reference decoder accepts every emitted document in CI.
- A checked-in fixture of one emitted document is byte-identical on every CI platform.

---

## Stage 6 — Round trip, limits, fuzzing, mutation check · M

**Status:** not started.

**Goal:** the properties and the hostile inputs of §15 hold, under every instrumented build.

**Do**

- `test-roundtrip.R`: 300 generated values over every §7 row to depth 6 (`withr::local_seed()`), each emitted twice (identical) and parsed back (`identical()` modulo §7.4); `toml_validate(toml_emit(x))` for each.
- `test-hostile.R`: the §15 list, each a permanent regression, the large ones behind `skip_heavy()`.
- Interrupt test with `setTimeLimit()`; the endless-connection test for `toml_read()` arrives with Stage 7.
- Fuzz the build phase and the emitter through R under the ASan containers (`tools/sanitizer-exercise.R`); the parse fuzz corpus grows nightly.
- `tools/run-mutation-check` extended to the emitter's depth guard and the build phase's guards.
- `tools/check-no-network` in `hardening.yaml`.

**Exit**

- Every property and hostile input of §15 is a passing test; sanitizers, valgrind, rchk and gctorture clean in CI; 30 minutes of nightly fuzzing clean (met as the nights accrue, and stated as such).

---

## Stage 7 — Files, connections, documentation, benchmarks · S

**Status:** not started.

**Goal:** the package reads from where users keep files, and is documented for CRAN.

**Do**

- `R/zu_source.R` copied verbatim from `../zuxml` with its origin line; `toml_read()` reading at most `max_size + 1` bytes in 64 KiB blocks; `toml_write()` to a path or connection; `zutoml_io_error`.
- Every export documented with `@return` and runnable `@examples`; `?"zutoml-conditions"`; the §6 and §7 tables in `?toml_parse` and `?toml_emit`.
- A vignette, *Configuration files in TOML* (reading `pyproject.toml` and `Cargo.toml`, writing a config); `_pkgdown.yml` listing every export and article; README rewritten with a worked example.
- `inst/WORDLIST`; `cran-comments.md` listing the CI legs as test environments.
- `tools/run-benchmarks` against `RcppTOML` (parse) and `zuyaml` (emit); results recorded in design §16.

**Exit**

- `devtools::check(cran = TRUE)` 0/0/0; `pkgdown::check_pkgdown()` clean; the endless-connection test passes; benchmarks recorded.

---

## Stage 8 — Release 0.1.0 · S

**Status:** not started. Waits for zufast on CRAN.

**Do**

- Remove `Remotes:`; rebuild and check against zufast's CRAN tarball (R10.3).
- Verify each §19 acceptance criterion explicitly, in a table naming the test file, tool or CI job behind it. Writing it out is the check: zuxml found three criteria backed only by gates nothing else mentioned.
- Set `Version: 0.1.0` and the `NEWS.md` heading; `R CMD check --as-cran --run-donttest` 0/0/0; run the `cran-extrachecks` and `review-cran-submission` skills and resolve every finding.
- Submit. After acceptance: tag `v0.1.0`, publish the GitHub release, bump to `0.1.0.9000` with a NEWS heading, close the parent issue.

**Exit:** on CRAN.

---

## Acceptance criteria against stages

| § 19 | Criterion | Stage | Verified by (to be filled at Stage 8) |
|---|---|---|---|
| 1 | builds everywhere with zufast from CRAN | 0, 8 | `R-CMD-check.yaml` full profile |
| 2 | every `toml-test` case, both kinds | 3, 4 | `conformance.yaml`, `test-conformance.R` |
| 3 | every emitted document accepted | 5 | `test-emit-conformance.R`, the reference decoder job |
| 4 | hostile inputs refused with a class; canary seen | 1, 3, 6 | `test-hostile.R`, `tools/run-fuzz`, `tools/run-mutation-check` |
| 5 | deterministic emission | 5 | the cross-platform fixture |
| 6 | round-trip properties | 6 | `test-roundtrip.R` |
| 7 | three copies of each table agree | 4, 5 | review, stated as such |
| 8 | clean check; only `R_init_zutoml` exported | 0, 8 | CI matrix, `tools/check-symbols` |

## Explicitly not in 0.1.0

TOML 1.1.0 forms unless §18 Q5 admits them · format-preserving edits · comments in the value · a schema language · a C API · `bit64::integer64` output.

## Deferred past 0.1.0, with the reason

| Item | Why not now | What would bring it in |
|---|---|---|
| `version = "1.1.0"` forms | decided at Stage 1 (§18 Q5) | the decision, or a user with a 1.1 document |
| `offset = TRUE` on emit (§18 Q3) | UTC is deterministic across sessions | a caller who needs the written offset kept |
| `int64 =` option (§18 Q4) | the family's bigint class keeps three packages alike | a `bit64` user |
| a bare-time primitive in zufast | zutoml's twenty lines suffice | a second consumer |

## Risk register

| Risk | Stage | Mitigation |
|---|---|---|
| zufast's CRAN release slips | 8 | every other stage proceeds; the inlining fallback is written down and not planned |
| zufast's header shape changes under `Remotes: @main` | all | rebuild against the CRAN tarball at Stage 8 (R10.3); the floor `>= 0.1.0` |
| the project parser does not pass `toml-test` in Stage 3's time | 3 | §18 Q6: vendor `tomlc17` for the check phase |
| a table-model rule misread | 3 | every rule has a `toml-test` invalid case and a mutation case |
| non-determinism across platforms (float digits, line endings) | 5 | Ryu and `\n` only; the cross-platform fixture |
| the lattice grows until nobody holds it in their head | 4 | §6.3 is `zujson`'s with two `zucbor` rules; new kinds only for TOML types |
| `toml-test` changes a case between pins | all | the manifest pins the tag; `tools/update-fixtures` is the only writer |
| `shuffle = TRUE` exposes file-scope helpers | all | helpers only in `helper-*.R` |

## After 0.1.0

1. TOML 1.1.0, if not already admitted (§18 Q5).
2. `data_frame` writing options and `offset = TRUE`, as users ask.
3. The first user bug reports, and whatever they show the mapping gets wrong.
