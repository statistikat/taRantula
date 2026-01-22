# Filter New URLs by Removing Duplicates and Already-Scraped URLs

This function filters a vector of newly collected URLs by excluding
those that were already scraped or that appear more than once in the new
input. URL parsing is performed using `urltools`, and duplicates are
detected after normalization of URLs.

## Usage

``` r
.filter_new_urls(urls_scraped = NULL, urls_new, return_index = FALSE)
```

## Arguments

- urls_scraped:

  Optional list or vector containing URLs that were already scraped. If
  `NULL`, only internal duplicates in `urls_new` are removed.

- urls_new:

  Character vector of new URLs to be filtered.

- return_index:

  Logical; if `TRUE`, the function returns the indices of duplicates and
  previously scraped URLs instead of filtered URLs.

## Value

- If `return_index = FALSE` (default): a character vector of filtered
  URLs.

- If `return_index = TRUE`: a list with elements

  - `index_old`: indices of URLs found in `urls_scraped`

  - `index_duplicate`: indices of duplicated URLs within `urls_new`

## Details

URL parsing is handled internally via a helper function that extracts
URL components, removes the `scheme` field, and attaches the domain.
Matching between new and previously scraped URLs is done using
data.table's keyed joins to efficiently identify overlaps.

## Examples

``` r
if (FALSE) { # \dontrun{
# Example URLs
new_urls <- c("https://example.com", "https://example.com/page",
              "https://example.com")

old_urls <- c("https://example.com/page")

# Filter new URLs
filtered <- .filter_new_urls(urls_scraped = old_urls, urls_new = new_urls)

# Inspect indices of removed URLs
idx <- .filter_new_urls(urls_scraped = old_urls, urls_new = new_urls,
                        return_index = TRUE)
} # }
```
