# Read a TOML document from a file or connection

Reads the input and parses it as
[`toml_parse()`](https://pedrobtz.github.io/zutoml/reference/toml_parse.md)
would. At most `max_size + 1` bytes are ever read, so an oversized file
or an endless connection fails with `zutoml_size_limit` rather than
exhausting memory.

## Usage

``` r
toml_read(file, ..., max_size = 64 * 1024^2)
```

## Arguments

- file:

  A file path, a URL, or a connection.

- ...:

  Arguments passed on to
  [`toml_parse()`](https://pedrobtz.github.io/zutoml/reference/toml_parse.md).

- max_size:

  The largest document accepted, in bytes, or `Inf`.

## Value

As
[`toml_parse()`](https://pedrobtz.github.io/zutoml/reference/toml_parse.md).

## Details

A string with an `http`, `https`, `ftp`, `ftps` or `file` scheme is read
with [`url()`](https://rdrr.io/r/base/connections.html), any other
string as a file path. A connection that is not open is opened in `"rb"`
mode and closed afterwards; an open one must be binary, is read from its
current position, and is left open.

## Examples

``` r
path <- tempfile(fileext = ".toml")
writeLines(c("[package]", 'name = "zutoml"', "version = 1"), path)
toml_read(path)
#> $package
#> $package$name
#> [1] "zutoml"
#> 
#> $package$version
#> [1] 1
#> 
#> 
unlink(path)
```
