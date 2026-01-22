# Default User‑Agent String

Provides a default desktop Safari‑style user‑agent string for both
Selenium and `httr` requests when no custom value is supplied.

## Usage

``` r
.default_useragent()
```

## Value

A character scalar representing a valid browser user‑agent.

## Details

The user‑agent string is chosen to mimic a typical macOS Safari browser
environment to reduce the likelihood of being blocked by websites for
using automated scraping tools.
