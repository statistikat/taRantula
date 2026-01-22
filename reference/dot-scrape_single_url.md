# Scrape a Single URL

This function retrieves and processes the content of a single URL using
either a Selenium session or an HTTP request. It extracts the HTML
source, identifies potential redirects, parses links on the page, and
returns a structured `data.table` containing the scraping results.

## Usage

``` r
.scrape_single_url(db_file, sid, url, robots_check)
```

## Arguments

- db_file:

  Character string specifying the path to the DuckDB database file used
  for robots.txt rule evaluation.

- sid:

  Either a Selenium session object (`SeleniumSession`) or a named list
  of HTTP headers to be used with
  [`httr::GET()`](https://httr.r-lib.org/reference/GET.html).

- url:

  Character string containing the URL to be scraped.

- robots_check:

  Logical indicating whether robots.txt rules should be validated before
  scraping.

## Value

A `data.table` with the following columns:

- url:

  Final URL after potential redirection.

- url_redirect:

  Original URL, if a redirect occurred; otherwise `NA`.

- status:

  Logical indicating whether scraping succeeded.

- src:

  HTML source (or `NA` if scraping failed or disallowed).

- links:

  A list-column containing extracted link information as a `data.table`.

- scraped_at:

  POSIXct timestamp indicating when the scrape occurred.

## Details

The function first checks robots.txt rules using
[`check_robotsdata()`](https://statistikat.github.io/taRantula/reference/check_robotsdata.md).
If scraping is disallowed, a standardized record is returned. When using
Selenium, the browser is navigated to the URL and the potentially
redirected final URL is captured. For non-Selenium inputs, an HTTP GET
request is performed. Errors during scraping are caught and converted
into structured output.
