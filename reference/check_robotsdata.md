# Check Whether a URL Is Allowed According to Stored robots.txt Rules

Determines whether a URL is permitted to be scraped according to the
`robots.txt` rules stored in a DuckDB `"robots"` table.

## Usage

``` r
check_robotsdata(db_file, url)
```

## Arguments

- db_file:

  `character(1)` Path to the DuckDB database file.

- url:

  `character(1)` URL to evaluate.

## Value

`TRUE` if scraping the URL is allowed, `FALSE` otherwise.

## Details

Internally calls
[`query_robotsdata()`](https://statistikat.github.io/taRantula/reference/query_robotsdata.md)
and evaluates permissions via
[`robotstxt::paths_allowed()`](https://docs.ropensci.org/robotstxt/reference/paths_allowed.html).
If no valid robots.txt information is available for the domain, the
function returns `TRUE` (i.e., scraping is allowed).

## See also

- [`query_robotsdata()`](https://statistikat.github.io/taRantula/reference/query_robotsdata.md)

## Examples

``` r
if (FALSE) { # \dontrun{
check_robotsdata("robots.duckdb", "https://example.com/secret")
} # }
```
