# Search Google for Business URLs

Sends search queries to the Google Custom Search API to identify URLs
associated with businesses. The function processes queries provided in a
data frame and returns link results together with positional
information.

## Usage

``` r
searchURL(cfg, dat, file = file, query_col = query_col)
```

## Arguments

- cfg:

  A
  [`cfg_googlesearch()`](https://statistikat.github.io/taRantula/reference/paramsGoogleSearch.md)
  configuration object containing API credentials and query-related
  settings.

- dat:

  A `data.frame` or `data.table` containing variables from which search
  queries were constructed.

- file:

  Optional CSV filename to which results will be written. If the file
  exists and `overwrite = FALSE` is set in `cfg`, previously saved
  results will be loaded and skipped.

- query_col:

  Character scalar; the name of the column in `dat` that contains
  encoded search queries created via
  [`buildQuery()`](https://statistikat.github.io/taRantula/reference/buildQuery.md).

## Value

A `data.table` containing the following columns:

- `idcol` – Identifier for the business

- `attributes` – Fields extracted from Google results (e.g., link,
  title)

- `position` – Search result ranking position

## Details

To use this function, you must provide a valid Google Custom Search API
key via the environment variable `SCRAPING_APIKEY_GOOGLE`, for example
by adding it to your `~/.Renviron` file. In addition, the Custom Search
Engine (CSE) identifier must be available via the environment variable
`SCRAPING_ENGINE_GOOGLE`.

## Examples

``` r
## Example usage will be added in future versions
```
