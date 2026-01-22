# Query Stored robots.txt Permissions for a Given URL

Retrieves the stored robots.txt permissions for the domain of the given
URL from a DuckDB database and returns them as a `robotstxt` object.

## Usage

``` r
query_robotsdata(db_file, url)
```

## Arguments

- db_file:

  `character(1)` Path to the DuckDB database file.

- url:

  `character(1)` URL for which the stored robots.txt information should
  be retrieved.

## Value

A `robotstxt` object from the **robotstxt** package.

## Details

If the domain does not exist in the `"robots"` table, the function
returns a `robotstxt` object with empty permissions, implying full
access.

## See also

- [`check_robotsdata()`](https://statistikat.github.io/taRantula/reference/check_robotsdata.md)

## Examples

``` r
if (FALSE) { # \dontrun{
query_robotsdata("robots.duckdb", "https://example.com/page")
} # }
```
