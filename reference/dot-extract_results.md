# Extract Table Results from DuckDB

Retrieves records from one of the internal DuckDB tables used by the
`UrlScraper` framework. Supported tables include:

- `"results"` – scraped HTML documents

- `"logs"` – worker progress log entries

- `"links"` – extracted hyperlinks

Optional SQL-style filtering is supported (e.g.,
`"url LIKE 'https://example.com/%'"`).

## Usage

``` r
.extract_results(db_file, tab = "results", filter)
```

## Arguments

- db_file:

  Path to the DuckDB file created by the scraper.

- tab:

  Character scalar specifying the table to query. Must be one of
  `"results"`, `"logs"`, or `"links"`.

- filter:

  Optional SQL `WHERE` clause (without the word `WHERE`) used to subset
  the results.

## Value

A `data.table` containing all rows from the selected table, optionally
filtered. Returns `NULL` invisibly if the query fails.

## Details

This helper function:

- Connects to the DuckDB database in **read‑only** mode

- Validates the requested table name

- Constructs a `SELECT * FROM <table>` query, optionally with a `WHERE`
  clause

- Returns results as a `data.table`

If the underlying query fails (often due to malformed filters), an
informative message is printed and `NULL` is returned invisibly.

## Examples

``` r
if (FALSE) { # \dontrun{
## Extract all scraped results:
.extract_results("results.duckdb", tab = "results")

## Extract links from a specific domain:
.extract_results("results.duckdb", tab = "links",
                  filter = "href LIKE 'https://example.com/%'")
} # }
```
