# The Julia package registry

Julia’s [General registry](https://github.com/JuliaRegistries/General)
is a git repository of TOML files: an index of every registered package,
and four small files per package. This article reads all of them with
zutoml and asks what they say, in particular which packages carry code
compiled from C, C++ or Fortran.

``` r

library(zutoml)
```

## Fetch the registry

The registry is downloaded once, as a tarball of a pinned commit (about
12 MB), and unpacked into a temporary directory.

``` r

commit <- "19314165a0b3aaf26cba8eb458327ec2f90dce4d"
url <- paste0("https://codeload.github.com/JuliaRegistries/General/tar.gz/", commit)
tarball <- tempfile(fileext = ".tar.gz")
withr::with_options(list(timeout = 300), download.file(url, tarball, quiet = TRUE, mode = "wb"))
dir <- tempfile("General")
untar(tarball, exdir = dir)
root <- list.files(dir, full.names = TRUE)
```

## The index

`Registry.toml` names the registry and lists every package by UUID, each
an inline table with its name and the directory holding its files:

``` r

toml_read(file.path(root, "Registry.toml"), select = "repo")
#> [1] "https://github.com/JuliaRegistries/General.git"
index <- toml_read(file.path(root, "Registry.toml"), select = "packages")
length(index)
#> [1] 14524
index[1:2]
#> $`00000000-0000-4000-b000-202512210000`
#> $`00000000-0000-4000-b000-202512210000`$name
#> [1] "Swizzling"
#> 
#> $`00000000-0000-4000-b000-202512210000`$path
#> [1] "S/Swizzling"
#> 
#> 
#> $`00000000-1111-2222-3333-444444444444`
#> $`00000000-1111-2222-3333-444444444444`$name
#> [1] "REPLTreeViews"
#> 
#> $`00000000-1111-2222-3333-444444444444`$path
#> [1] "R/REPLTreeViews"
```

A data frame is easier to work with:

``` r

pkgs <- data.frame(
  uuid = names(index),
  name = vapply(index, `[[`, "", "name"),
  path = vapply(index, `[[`, "", "path"),
  row.names = NULL
)
pkgs$jll <- endsWith(pkgs$name, "_jll")
table(pkgs$jll)
#> 
#> FALSE  TRUE 
#> 12662  1862
```

Packages whose names end in `_jll` are binary wrappers. Each is built by
[BinaryBuilder](https://docs.binarybuilder.org) from a recipe in
[Yggdrasil](https://github.com/JuliaPackaging/Yggdrasil) and ships a
compiled library or program, usually written in C, C++ or Fortran.

## One package: Xsum

[Xsum.jl](https://github.com/JuliaMath/Xsum.jl) gives exactly rounded
sums through Radford Neal’s xsum library, which is written in C. Its
directory has four files:

``` r

xsum <- file.path(root, pkgs$path[pkgs$name == "Xsum"])
list.files(xsum)
#> [1] "Compat.toml"   "Deps.toml"     "Package.toml"  "Versions.toml"
```

`Package.toml` says where the source lives:

``` r

str(toml_read(file.path(xsum, "Package.toml")))
#> List of 3
#>  $ name: chr "Xsum"
#>  $ uuid: chr "1fd64df0-a4d2-11e9-360d-2f03868f4cf5"
#>  $ repo: chr "https://github.com/JuliaMath/Xsum.jl.git"
```

`Versions.toml` has one table per release, keyed by version number and
holding the git tree hash of that release:

``` r

names(toml_read(file.path(xsum, "Versions.toml")))
#> [1] "0.1.0" "1.0.0" "1.1.0" "1.2.0" "1.3.0"
```

`Deps.toml` and `Compat.toml` are keyed by version *ranges*: `[0]`
covers every 0.x release, `[1]` every 1.x release, `["1.3-1"]` releases
from 1.3 up to the end of 1.x.

``` r

str(toml_read(file.path(xsum, "Deps.toml")))
#> List of 2
#>  $ 0:List of 2
#>   ..$ BinaryProvider: chr "b99e7846-7c00-51b0-8f62-c81ae34c0232"
#>   ..$ Libdl         : chr "8f399da3-3557-5675-b5ff-fb832c97cbdb"
#>  $ 1:List of 1
#>   ..$ xsum_jll: chr "e979a739-315a-50ee-b437-b496a9503be1"
```

This is as far as the registry goes. Xsum 0.x downloaded its binary with
`BinaryProvider`; Xsum 1.x depends on `xsum_jll`, the compiled xsum
library. So the registry shows that Xsum calls compiled code. It cannot
say the code is C: `xsum_jll`’s own files name only its wrapper
repository.

``` r

str(toml_read(file.path(root, pkgs$path[pkgs$name == "xsum_jll"], "Package.toml")))
#> List of 3
#>  $ name: chr "xsum_jll"
#>  $ uuid: chr "e979a739-315a-50ee-b437-b496a9503be1"
#>  $ repo: chr "https://github.com/JuliaBinaryWrappers/xsum_jll.jl.git"
```

The binary itself can say more: see [Inside the
binaries](#inside-the-binaries).

## Every package

Reading `Package.toml`, `Versions.toml` and `Deps.toml` for every
package parses some 44,000 small documents.

``` r

read_all <- function(file) {
  lapply(file.path(root, pkgs$path, file), function(f) {
    if (file.exists(f)) toml_read(f) else list()
  })
}
info <- read_all("Package.toml")
versions <- read_all("Versions.toml")
deps <- read_all("Deps.toml")
```

Almost every package is on GitHub. `subdir` marks a package that lives
in a subdirectory of a larger repository:

``` r

pkgs$repo <- vapply(info, `[[`, "", "repo")
pkgs$subdir <- vapply(info, function(x) !is.null(x$subdir), NA)
sort(table(sub("^https?://([^/]+)/.*$", "\\1", pkgs$repo)), decreasing = TRUE)
#> 
#>     github.com     gitlab.com   codeberg.org gitlab.gwdg.de      git.sr.ht 
#>          14435             73              9              4              2 
#> gitlab.emse.fr 
#>              1
sum(pkgs$subdir)
#> [1] 619
```

The most released packages, and how many releases were later yanked:

``` r

pkgs$n_versions <- lengths(versions)
yanked <- function(v) sum(vapply(v, function(e) isTRUE(e$yanked), NA))
pkgs$n_yanked <- vapply(versions, yanked, 0L)
head(pkgs[order(-pkgs$n_versions), c("name", "n_versions", "n_yanked")], 10)
#>                  name n_versions n_yanked
#> 2466       DiffEqBase        631        3
#> 666         SciMLBase        578        3
#> 8572  ModelingToolkit        550        1
#> 94       Reactant_jll        443        0
#> 13455          Meshes        428        0
#> 9030     Oceananigans        424        0
#> 1723   OrdinaryDiffEq        414        4
#> 9580            Trixi        353        0
#> 7303      LinearSolve        332        1
#> 7217           Enzyme        327        0
sum(pkgs$n_yanked)
#> [1] 359
```

### Dependencies of the latest release

To ask what a package depends on *now*, take its latest release and keep
the `Deps.toml` sections whose range contains it. A range is one version
or two joined by `-`; a short bound such as `1` stands for every
`1.x.y`. Pre-releases (`1.0.0-rc1`) are skipped and build numbers (`+0`)
ignored.

``` r

version_parts <- function(v) {
  as.integer(strsplit(sub("[-+].*$", "", v), ".", fixed = TRUE)[[1]])
}

latest <- function(v) {
  v <- names(v)[!grepl("-", names(v))]
  if (!length(v)) return(NA_character_)
  v[order(numeric_version(sub("\\+.*$", "", v)), decreasing = TRUE)][1]
}

# -1, 0 or 1 as version v is below, within or above a (possibly short) bound
compare <- function(v, bound) {
  b <- version_parts(bound)
  d <- which(v[seq_along(b)] != b)
  if (length(d)) sign(v[d[1]] - b[d[1]]) else 0
}

in_range <- function(v, range) {
  bounds <- trimws(strsplit(range, "-", fixed = TRUE)[[1]])
  lo <- bounds[1]
  hi <- bounds[length(bounds)]
  (lo == "*" || compare(v, lo) >= 0) && (hi == "*" || compare(v, hi) <= 0)
}

deps_at <- function(d, v) {
  if (is.na(v)) return(character())
  v <- version_parts(v)
  hit <- Filter(function(r) in_range(v, r), names(d))
  sort(unique(as.character(unlist(lapply(d[hit], names)))))
}

pkgs$latest <- vapply(versions, latest, "")
pkgs$deps <- Map(deps_at, deps, pkgs$latest)
pkgs$deps[[which(pkgs$name == "Xsum")]]
#> [1] "xsum_jll"
```

The most depended-on packages at their latest releases. Standard
libraries such as `LinearAlgebra` are not registered, so they are left
out:

``` r

used <- table(unlist(pkgs$deps))
head(sort(used[names(used) %in% pkgs$name], decreasing = TRUE), 15)
#> 
#>          Statistics           Artifacts         JLLWrappers        StaticArrays 
#>                2086                1910                1795                1373 
#>       Distributions          DataFrames            Reexport           StatsBase 
#>                1277                1272                1157                1155 
#>     PrecompileTools                JSON DocStringExtensions    SpecialFunctions 
#>                 822                 821                 791                 697 
#>      DataStructures                 CSV       ProgressMeter 
#>                 685                 680                 617
```

## Packages with compiled code

The registry records metadata, not source, so it cannot say which
language a package is written in. Dependencies come close: a `_jll`
package *is* compiled code, a package that depends on one calls compiled
code, and a package that depends on `CxxWrap` wraps C++.

``` r

pkgs$calls_jll <- vapply(pkgs$deps, function(d) any(endsWith(d, "_jll")), NA)
pkgs$cxxwrap <- vapply(pkgs$deps, function(d) "CxxWrap" %in% d, NA)
callers <- pkgs[!pkgs$jll & pkgs$calls_jll, ]
c(packages = sum(!pkgs$jll), call_a_jll = nrow(callers), cxxwrap = sum(callers$cxxwrap))
#>   packages call_a_jll    cxxwrap 
#>      12662        856         50
```

### Inside the binaries

Each `_jll` package has an `Artifacts.toml`, one entry per platform it
was built for. BinaryBuilder adds two tags to that platform when the
binary needs them, and both name a language:

- `libgfortran_version`: the binary links GCC’s Fortran runtime, because
  it has Fortran code or Fortran bindings;
- `cxxstring_abi`: the binary passes C++ `std::string`s across its
  interface, so it is C++.

`xsum_jll` has neither; `Arpack_jll` links `libgfortran`:

    [[Arpack]]
    arch = "aarch64"
    git-tree-sha1 = "d626d3e001367ad1c01b8c5580939702be031ee1"
    libgfortran_version = "5.0.0"
    os = "macos"

`Artifacts.toml` is in the package, not in the registry. Julia’s package
server hands out any registered version as a tarball, named by the
package’s UUID and the `git-tree-sha1` that `Versions.toml` records, so
the files read are exactly those of the pinned registry.
[`download.file()`](https://rdrr.io/r/utils/download.file.html) fetches
the tarballs of every `_jll` the callers use, about 8 kB each, in
parallel.

``` r

jlls <- pkgs[pkgs$jll & pkgs$name %in% unlist(callers$deps), ]
nrow(jlls)
#> [1] 780
jlls$tree <- mapply(
  function(v, latest) v[[latest]][["git-tree-sha1"]],
  versions[match(jlls$name, pkgs$name)], jlls$latest
)
jll_dir <- tempfile("jll")
dir.create(jll_dir)
tarballs <- file.path(jll_dir, paste0(jlls$name, ".tar.gz"))
withr::with_options(list(timeout = 600), download.file(
  sprintf("https://pkg.julialang.org/package/%s/%s", jlls$uuid, jlls$tree),
  tarballs,
  method = "libcurl", quiet = TRUE, mode = "wb"
))
```

Every platform entry carries the same tags, so the first one is enough,
and `select` reads only that. An artifact is usually named after its
package (`xsum` in `xsum_jll`); when it is not, `select` raises
`zutoml_missing_key` and the whole file is read instead.

``` r

first_artifact <- function(name, tarball) {
  exdir <- file.path(jll_dir, name)
  untar(tarball, files = "Artifacts.toml", exdir = exdir)
  file <- file.path(exdir, "Artifacts.toml")
  tryCatch(
    toml_read(file, select = paste0(sub("_jll$", "", name), "[1]")),
    zutoml_missing_key = function(e) {
      artifact <- toml_read(file)[[1]]
      if (is.null(names(artifact))) artifact[[1]] else artifact
    }
  )
}
artifacts <- Map(first_artifact, jlls$name, tarballs)
jlls$fortran <- vapply(artifacts, function(a) !is.null(a$libgfortran_version), NA)
jlls$cxx <- vapply(artifacts, function(a) !is.null(a$cxxstring_abi), NA)
table(fortran = jlls$fortran, cxx = jlls$cxx)
#>        cxx
#> fortran FALSE TRUE
#>   FALSE   640   60
#>   TRUE     80    0
```

A package is marked with every language its binaries show.
`CompilerSupportLibraries_jll` is left out: it *is* GCC’s runtime, for
Fortran, C++ and OpenMP together, so depending on it does not say which.

``` r

any_of <- function(flag) {
  tagged <- setdiff(jlls$name[flag], "CompilerSupportLibraries_jll")
  vapply(callers$deps, function(d) any(d %in% tagged), NA)
}
callers$fortran <- any_of(jlls$fortran)
callers$cxx <- any_of(jlls$cxx) | callers$cxxwrap
c(fortran = sum(callers$fortran), cxx = sum(callers$cxx), neither = sum(!callers$fortran & !callers$cxx))
#> fortran     cxx neither 
#>     106      94     660
```

The packages that call Fortran, with the binaries that show it:

``` r

fortran_jlls <- setdiff(jlls$name[jlls$fortran], "CompilerSupportLibraries_jll")
via <- vapply(callers$deps[callers$fortran], function(d) {
  paste(intersect(d, fortran_jlls), collapse = ", ")
}, "")
head(data.frame(package = callers$name[callers$fortran], via), 20)
#>                package                           via
#> 1       FormationTemps                      HDF5_jll
#> 2          TDEPWrapper                      TDEP_jll
#> 3    NLPModelsAlgencan  Algencan_jll, OpenBLAS32_jll
#> 4        MolSimToolkit                 MDLovoFit_jll
#> 5          PETScDiffEq                     PETSc_jll
#> 6                PRIMA                     PRIMA_jll
#> 7            cuNumeric                OpenBLAS32_jll
#> 8            PetscCall                     PETSc_jll
#> 9           Population               OpenSpecFun_jll
#> 10 FastPolynomialRoots                   LibAMVW_jll
#> 11               DASKR                     DASKR_jll
#> 12               Xfoil               xfoil_light_jll
#> 13              MAiNGO                    MAiNGO_jll
#> 14              CUTEst     CUTEst_jll, SIFDecode_jll
#> 15           UnoSolver       OpenBLAS32_jll, Uno_jll
#> 16               FMM3D                     FMM3D_jll
#> 17           StaticMPI                     MPICH_jll
#> 18       QRupdatesFast               QRupdate_ng_jll
#> 19            PinCFlow           HDF5_jll, MPICH_jll
#> 20              MadNLP MUMPS_seq_jll, OpenBLAS32_jll
```

The tags show what a binary *needs*, which is a lower bound. Much C++
passes no strings across its interface and is not tagged, and a binary
with neither tag may be C, C++, Rust or Go. `MPICH_jll` and `HDF5_jll`
are tagged for their Fortran bindings, though they are mostly C. The
build recipes in
[Yggdrasil](https://github.com/JuliaPackaging/Yggdrasil) are the full
answer; the TOML has taken us a long way towards it.
