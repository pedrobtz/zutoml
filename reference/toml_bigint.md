# Integers beyond what a double holds exactly

TOML integers are 64-bit. Those beyond 2^53 cannot be held exactly by a
double, so
[`toml_parse()`](https://pedrobtz.github.io/zutoml/reference/toml_parse.md)
returns them, by default, as a `toml_bigint` vector: their exact decimal
text, with a class.

## Usage

``` r
toml_bigint(x)
```

## Arguments

- x:

  Decimal strings (`"-9223372036854775808"`), or whole numbers within
  2^53. `NA` is kept.

## Value

A character vector of class `toml_bigint`, holding canonical decimal
text: no leading zeros or plus sign.

## Examples

``` r
x <- toml_bigint(c("9007199254740993", "-42"))
x
#> <toml_bigint[2]>
#> [1] 9007199254740993 -42             
as.numeric(x)   # loses the precision a bigint keeps
#> [1]  9.007199e+15 -4.200000e+01
toml_parse("big = 9223372036854775807")$big
#> <toml_bigint[1]>
#> [1] 9223372036854775807
```
