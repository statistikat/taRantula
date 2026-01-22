# Parse HTML and Remove Non‑Text Elements

Converts an HTML document into a cleaned representation where scripts,
styles, and similar elements are removed. If `keep_only_text = TRUE`,
the function returns only the visible text of the page.

## Usage

``` r
parse_HTML(doc, keep_only_text = FALSE)
```

## Arguments

- doc:

  Either HTML content as a character string or an `xml_document`. `NA`
  inputs are returned unchanged.

- keep_only_text:

  Logical; if `TRUE`, returns only human‑readable text.

## Value

A cleaned XML node set or a character string (if
`keep_only_text = TRUE`).

## Details

This helper is used to prepare HTML content for downstream text
extraction. It:

- Removes `<script>`, `<style>`, and `<noscript>` nodes

- Optionally extracts only visible text

- Supports both raw HTML input and already parsed XML documents
