# Extract Domain from URLs

Extracts the domain portion of URLs and optionally includes the scheme
(`http://` or `https://`). The function removes common subdomains such
as `www.` for consistency.

## Usage

``` r
get_domain(x, include_scheme = FALSE)
```

## Arguments

- x:

  Character vector of URLs.

- include_scheme:

  Logical; if `TRUE`, prepend the detected scheme to the returned
  domain.

## Value

A character vector containing domain names. URLs that cannot be parsed
return the original input value.
