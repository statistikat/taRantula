# Execute Arbitrary SQL Query on DuckDB

Executes a custom SQL query against the DuckDB database used by the
scraper. This function provides maximum flexibility for advanced users
who need to run specialized SQL statements beyond the standard table
extractors.

## Usage

``` r
.extract_query(db_file, query)
```

## Arguments

- db_file:

  Path to the DuckDB database file.

- query:

  Character scalar containing a valid SQL query.

## Value

A `data.table` containing the retrieved results, or `NULL` invisibly if
the query fails.

## Details

The function:

- Validates that the DuckDB file exists

- Executes the provided SQL in **read‑only** mode

- Converts the result to a `data.table`

- Returns `NULL` invisibly if the query fails

This is a low‑level function intended for power users. Users must ensure
their SQL queries are syntactically valid.

## Examples

``` r
if (FALSE) { # \dontrun{
## List all domains stored in robots table:
.extract_query("results.duckdb", "SELECT domain FROM robots")

## Count pages scraped successfully:
.extract_query("results.duckdb",
               "SELECT COUNT(*) FROM results WHERE status = TRUE")
} # }
```
