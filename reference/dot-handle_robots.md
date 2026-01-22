# Retrieve and Store robots.txt Information in a DuckDB Database

Retrieves **robots.txt** files for a set of domains, parses their
permissions, and stores them in a DuckDB table named `"robots"`.
Existing entries are not overwritten. Domains for which no valid
`robots.txt` can be retrieved are stored with empty permissions,
implying fully permissive access.

## Usage

``` r
.handle_robots(db_file, snapshot_every, workers, urls, user_agent = NULL)
```

## Arguments

- db_file:

  `character(1)` Path to the DuckDB database file.

- snapshot_every:

  `integer(1)` Number of domains to process per chunk.

- workers:

  `integer(1)` Number of worker processes used for parallel retrieval.

- urls:

  `character` Vector of URLs from which the corresponding domains will
  be extracted.

- user_agent:

  `character(1)` Optional user agent string passed to
  [`robotstxt::robotstxt()`](https://docs.ropensci.org/robotstxt/reference/robotstxt.html).

## Value

Invisibly returns `NULL`. Side effect: updates (or creates) table
`"robots"` in the supplied DuckDB file.

## Details

The function processes domains in parallel, retrieves their `robots.txt`
rules, and stores them in chunks to improve efficiency. It automatically
detects which domains are already present in the database and only
processes the missing ones.

The stored permissions can later be queried using
[`query_robotsdata()`](https://statistikat.github.io/taRantula/reference/query_robotsdata.md).

## See also

- [`query_robotsdata()`](https://statistikat.github.io/taRantula/reference/query_robotsdata.md)

- [`check_robotsdata()`](https://statistikat.github.io/taRantula/reference/check_robotsdata.md)

## Examples

``` r
if (FALSE) { # \dontrun{
db <- "robots.duckdb"
urls <- c("https://example.com", "https://r-project.org")
.handle_robots(db_file = db, snapshot_every = 10, workers = 2, urls = urls)
} # }
```
