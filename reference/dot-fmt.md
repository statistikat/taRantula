# Format Numeric Values

Simple wrapper around [`formatC()`](https://rdrr.io/r/base/formatc.html)
used internally for preparing numeric output (e.g., percentages or
durations) in scraper messages.

## Usage

``` r
.fmt(x, format = "f", digits = 3)
```

## Arguments

- x:

  A numeric value.

- format:

  Character string indicating the desired output format; passed to
  [`formatC()`](https://rdrr.io/r/base/formatc.html). Defaults to `"f"`.

- digits:

  Number of digits after the decimal point. Defaults to `3`.

## Value

A character string with formatted numeric output.
