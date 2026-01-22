# Helper: JSON Reader with Retry Logic

Internal helper that reads JSON from a URL, automatically retrying with
exponential backoff when errors or warnings occur.

## Usage

``` r
read_json_wrapper(path, count = 1)
```

## Arguments

- path:

  URL from which JSON should be read.

- count:

  Integer specifying the current retry interval. Used internally.

## Value

Parsed JSON content or an error/warning object when all retries fail.
