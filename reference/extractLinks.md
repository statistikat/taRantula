# Extract Hyperlinks from an HTML Document

Extracts all valid hyperlinks from an HTML document and returns them as
a cleaned and normalized `data.table`. The function parses `<a>`,
`<area>`, `<base>`, and `<link>` elements, resolves relative URLs,
removes invalid or unwanted links, and enriches the output with metadata
such as the source URL, extraction level, and timestamp.

## Usage

``` r
extractLinks(doc, baseurl)
```

## Arguments

- doc:

  A character string containing HTML or an `xml_document` object.

- baseurl:

  Character string representing the URL from which the document
  originated. Used to resolve relative links and filter domains.

## Value

A `data.table` containing the following columns:

- `href` – Cleaned and validated absolute URLs

- `label` – Link text extracted from the anchor element

- `source_url` – The originating page from which links were extracted

- `level` – Extraction depth (always 0 for this function)

- `scraped_at` – Timestamp of extraction

Duplicate URLs are automatically removed.

## Details

This extractor is designed for web‑scraping pipelines where only
meaningful, navigable hyperlinks are desired. The function:

- Converts inputs to an XML document when necessary

- Extracts link text and normalizes whitespace

- Resolves relative URLs against the provided `baseurl`

- Forces all URLs to use `https://`

- Removes invalid links using
  [`check_links()`](https://statistikat.github.io/taRantula/reference/check_links.md)

- Ensures uniqueness of extracted links

## Examples

``` r
html <- "<html><body><a href='/about'>About</a></body></html>"
extractLinks(html, baseurl = "https://example.com")
#>                         href  label          source_url level
#>                       <char> <char>              <char> <num>
#> 1: https://example.com/about  About https://example.com     0
#>             scraped_at
#>                 <POSc>
#> 1: 2026-01-22 12:41:20
```
