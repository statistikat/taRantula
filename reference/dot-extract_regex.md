# Extract Regular Expression Matches from Scraped HTML

Applies a regular expression to previously scraped HTML documents,
optionally restricted to a specific capture group. Each document is
first cleaned using
[`parse_HTML()`](https://statistikat.github.io/taRantula/reference/parse_HTML.md)
to remove non‑text content, ensuring reliable pattern extraction.

## Usage

``` r
.extract_regex(docs, urls, pattern, group = NULL, ignore_cases = TRUE)
```

## Arguments

- docs:

  Character vector or list of HTML source documents.

- urls:

  Character vector of URLs corresponding to `docs`.

- pattern:

  A regular expression to search for.

- group:

  Optional capture group name or index to extract. If `NULL`, the full
  match is returned.

- ignore_cases:

  Logical; if `TRUE`, performs case‑insensitive matching.

## Value

A `data.table` where each row corresponds to a match and includes:

- `url` – The originating document URL

- `pattern` (or the given group name) – Extracted values

Missing matches are returned as `NA_character_`.

## Details

The function:

- Cleans and normalizes each HTML document

- Converts text to lowercase when `ignore_cases = TRUE`

- Extracts all regex matches using
  [`stringr::str_match_all()`](https://stringr.tidyverse.org/reference/str_match.html)

- Supports named or numbered capture groups

- Returns a unified `data.table` indexed by URL

Named groups allow meaningful column labeling in the result.

## Examples

``` r
if (FALSE) { # \dontrun{
## Extract email-like patterns:
.extract_regex(docs, urls, pattern = "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+")
} # }
```
