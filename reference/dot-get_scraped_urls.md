# Retrieve Scraped URLs from a DuckDB Database

This function reads previously scraped URLs from a DuckDB database file.
It returns a data frame containing the original URLs and any
corresponding redirect URLs stored in the `results` table.

## Usage

``` r
.get_scraped_urls(db_file)
```

## Arguments

- db_file:

  Character string specifying the path to the DuckDB database file. If
  the file does not exist, `NULL` is returned.

## Value

- `NULL` if the database file does not exist.

- An empty character vector if the table `results` is not available.

- A data frame with the columns `url` and `url_redirect` otherwise.

## Details

The function safely opens the DuckDB database in read‑only mode and
ensures that the connection is properly closed upon exit. Only the table
`results` is queried. If the table is missing, no error is thrown.

## Examples

``` r
if (FALSE) { # \dontrun{
# Load previously scraped URLs
scraped <- .get_scraped_urls("my_scraper_db.duckdb")
} # }
```
