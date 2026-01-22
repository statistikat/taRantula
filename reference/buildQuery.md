# Build Encoded Search Queries

Constructs URL‑encoded search queries from selected columns in a data
frame or data table. This function is typically used to prepare query
strings for the Google Custom Search API.

## Usage

``` r
buildQuery(dat, selectCols = NULL)
```

## Arguments

- dat:

  A `data.frame` or `data.table` containing the text variables used to
  assemble the search string.

- selectCols:

  Character vector of column names to include in the query. If `NULL`,
  all columns in `dat` are used.

## Value

A character vector of encoded search queries. The returned object
includes an attribute `"query_attr" = "built_encoded_query"` used for
downstream checks.

## Examples

``` r
## Example usage will be added later
```
