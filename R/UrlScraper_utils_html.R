#' Normalize URLs
#'
#' Cleans URLs to ensure consistent formatting for database lookups and crawling.
#'
#' This function performs the following steps:
#' - Ensures HTTPS scheme
#' - Removes trailing slashes
#' - Removes URL anchors
#' - Trims whitespace
#'
#' @param u A vector of URLs (character).
#' @return A vector of cleaned URLs (character).
#' @noRd
clean_url <- function(u) {
  # return empty if input is empty
  if (is.null(u) || length(u) == 0) return(character(0))

  # trim leading and trailing whitespace
  u <- trimws(u)

  # convert http to https for consistency
  u <- gsub("^http://", "https://", u)

  # remove everything from the anchor sign onwards
  u <- sub("#.*$", "", u)

  # remove trailing slashes to treat site.com/ and site.com as identical
  u <- sub("/+$", "", u)

  return(u)
}

#' @title Extract Hyperlinks from an HTML Document
#'
#' @description
#' Extracts all valid hyperlinks from an HTML document and returns them as a
#' cleaned and normalized `data.table`.
#' The function parses `<a>`, `<area>`, `<base>`, and `<link>` elements,
#' resolves relative URLs, removes invalid or unwanted links, and enriches the
#' output with metadata such as the source URL, extraction level, and timestamp.
#'
#' @details
#' This extractor is designed for web‑scraping pipelines where only meaningful,
#' navigable hyperlinks are desired.
#' The function:
#'
#' * Converts inputs to an XML document when necessary
#' * Extracts link text and normalizes whitespace
#' * Resolves relative URLs against the provided `baseurl`
#' * Forces all URLs to use `https://`
#' * Removes invalid links using [`check_links()`]
#' * Ensures uniqueness of extracted links
#'
#' @param doc A character string containing HTML or an `xml_document` object.
#' @param baseurl Character string representing the URL from which the document
#'    originated. Used to resolve relative links and filter domains.
#' @param keep_links Optional character vector. If provided, overrides the
#'    standard boolean filtering by retaining links that match these specific
#'    invalidation categories (e.g., "duplicate" or "anker point").
#'    Defaults to NULL.
#'
#' @return
#' A `data.table` containing the following columns:
#' * `href` – Cleaned and validated absolute URLs
#' * `label` – Link text extracted from the anchor element
#' * `source_url` – The originating page from which links were extracted
#' * `scraped_at` – Timestamp of extraction
#'
#' Duplicate URLs are automatically removed.
#'
#' @export
#'
#' @examples
#' html <- "<html><body><a href='/about'>About</a></body></html>"
#' extractLinks(html, baseurl = "https://example.com")
extractLinks <- function(doc, baseurl, keep_links = NULL) {
  # Ensure the document is in the required format
  if (!inherits(doc, "xml_document")) {
    doc <- rvest::read_html(doc)
  }

  # Identify all relevant link elements
  body_node <- xml2::xml_find_first(doc, "//body")
  links <- rvest::html_elements(doc, "a, area, base, link")
  hrefs <- rvest::html_attr(links, "href")
  
  # make absolute links
  baseurl_slash <- sub("/+$", "/", baseurl)
  hrefs <- xml2::url_absolute(hrefs, baseurl_slash)
  
  # Return an empty data table if no valid links are found
  if (length(hrefs) == 0 || all(is.na(hrefs))) {
    return(data.table::data.table(
      href = character(),
      label = character(),
      source_url = character(),
      scraped_at = as.POSIXct(character())
    ))
  }

  # Normalize link text and remove excessive whitespace
  labels <- rvest::html_text(links, trim = TRUE)
  labels <- gsub("\\s+", " ", labels)

  # Filter out missing URL references
  valid_idx <- !is.na(hrefs)
  labels <- labels[valid_idx]
  hrefs <- hrefs[valid_idx]

  # Resolve relative URLs to absolute paths based on the base URL
  hrefs <- xml2::url_absolute(
    x = sub("^/", "", hrefs),
    base = sub("/$", "", baseurl)
  )

  # Apply URL normalization
  hrefs <- vapply(hrefs, clean_url, FUN.VALUE = character(1))
  baseurl <- clean_url(baseurl)

  # Validate links against defined filtering logic
  # If keep_links is provided, we request descriptive strings instead of booleans
  keep <- check_links(hrefs = hrefs, baseurl = baseurl,
    return_bool = is.null(keep_links))

  # If specific filter exceptions are provided, apply them here
  if (!is.null(keep_links)) {
    keep <- keep %in% c("", keep_links)
  }

  # Construct the result data table and ensure uniqueness
  href <- NULL
  dt_links <- data.table::data.table(
    href = hrefs[keep],
    label = labels[keep],
    stringsAsFactors = FALSE
  )

  dt_links <- unique(dt_links)
  dt_links$source_url <- baseurl
  dt_links$scraped_at <- Sys.time()

  return(dt_links[!duplicated(href)])
}

#' @title Link Validation Helper
#'
#' @description
#' Evaluates extracted URLs and determines which of them should be retained
#' for further processing.
#' The function filters out links that:
#'
#' * Do not belong to the same domain as `baseurl`
#' * Point to files such as images, audio, video, archives, executables, etc.
#' * Refer to fragments or anchor points
#' * Refer back to the same path as the main page
#'
#' @param hrefs Character vector of URLs to check.
#' @param baseurl Character string giving the original page URL for domain and
#'    path comparison.
#'
#' @return
#' A logical vector indicating which entries in `hrefs` should be retained.
#'
#' @export
#'
#' @keywords internal
check_links <- function(hrefs, baseurl, return_bool = TRUE) {
  # Define helper for concatenating paths with missing values
  pasteNA <- function(y, x, sep = "", na.sub = "") {
    x[is.na(x)] <- na.sub
    y[is.na(y)] <- na.sub
    paste(x, y, sep = sep)
  }

  urlParsed <- urltools::url_parse(baseurl)
  urlPathParam <- pasteNA(urlParsed$path, urlParsed$parameter)
  linksParsed <- urltools::url_parse(hrefs)
  linksExtract <- urltools::suffix_extract(linksParsed$domain)

  # Check if the URL shares the same domain as the base URL
  sameDomain <- get_domain(hrefs) == get_domain(baseurl)
  sameDomain[is.na(sameDomain)] <- FALSE

  # Define file extensions to exclude from the crawl
  file_string <- c(
    "\\.ics", "\\.mng", "\\.pct", "\\.bmp", "\\.gif", "\\.jpg", "\\.jpeg", "\\.png", "\\.pst", "\\.psp", "\\.tif", "\\.tiff", "\\.drw", "\\.dxf", "\\.eps",
    "\\.woff2", "\\.svg", "\\.mp3", "\\.wma", "\\.ogg", "\\.wav", "\\.ra", "\\.aac", "\\.mid", "\\.aiff", "\\.3gp", "\\.asf", "\\.asx", "\\.avi", "\\.mp4",
    "\\.woff", "\\.mpg", "\\.qt", "\\.rm", "\\.swf", "\\.wmv", "\\.m4a", "\\.css", "\\.pdf", "\\.doc", "\\.docx", "\\.exe", "\\.bin", "\\.rss", "\\.zip",
    "\\.rar", "\\.msu", "\\.flv", "\\.dmg", "\\.xls", "\\.xlsx", "\\.ico", "\\.mng?download=true", "\\.pct?download=true", "\\.bmp?download=true",
    "\\.gif?download=true", "\\.jpg?download=true", "\\.jpeg?download=true", "\\.png?download=true", "\\.pst?download=true",
    "\\.psp?download=true", "\\.tif?download=true", "\\.tiff?download=true", "\\.ai?download=true", "\\.drw?download=true",
    "\\.dxf?download=true", "\\.eps?download=true", "\\.ps?download=true", "\\.svg?download=true", "\\.mp3?download=true",
    "\\.wma?download=true", "\\.ogg?download=true", "\\.wav?download=true", "\\.ra?download=true", "\\.aac?download=true",
    "\\.mid?download=true", "\\.au?download=true", "\\.aiff?download=true", "\\.3gp?download=true", "\\.asf?download=true",
    "\\.asx?download=true", "\\.avi?download=true", "\\.mov?download=true", "\\.mp4?download=true", "\\.mpg?download=true",
    "\\.qt?download=true", "\\.rm?download=true", "\\.swf?download=true", "\\.wmv?download=true", "\\.m4a?download=true",
    "\\.css?download=true", "\\.pdf?download=true", "\\.doc?download=true", "\\.exe?download=true", "\\.bin?download=true",
    "\\.rss?download=true", "\\.zip?download=true", "\\.rar?download=true", "\\.msu?download=true", "\\.flv?download=true",
    "\\.dmg?download=true"
  )

  # Identify files that match prohibited extensions
  noFile <- !grepl(paste(file_string, collapse = "|"), linksParsed$path)

  # Compare sub-paths and parameters for duplicates
  subPathParam <- pasteNA(linksParsed$path, linksParsed$parameter)
  subPath <- linksParsed$path
  subPath[is.na(subPath)] <- ""
  param <- linksParsed$parameter
  param[is.na(param)] <- ""
  subPathParam <- paste0(subPath, param)

  diffPathParam <- subPathParam != "" & !duplicated(gsub("/$", "", subPathParam)) & subPath != "/"

  # Ensure the path and parameter differ from the main URL
  if (!is.na(urltools::path(baseurl))) {
    diffPathParam <- diffPathParam & urlPathParam != subPathParam
  }

  # Validate fragments
  nofragment <- is.na(linksParsed$fragment) | urlPathParam != subPathParam

  # Determine final set of valid links:
  # - sameDomain: ensure URL resides on the permitted domain
  # - noFile: filter out non-HTML assets and binary files
  # - nofragment: prevent re-crawling anchor points on the current page
  # - diffPathParam: avoid redundant crawls of identical paths and parameters
  linksSelect <- sameDomain & noFile & nofragment & diffPathParam

  if (return_bool == TRUE) {
    return(linksSelect)
  }

  # Return descriptive reason if not returning a boolean
  linksSelect <- fcase(
    sameDomain == FALSE, "different domain",
    noFile == FALSE, "document",
    nofragment == FALSE, "anker point",
    diffPathParam == FALSE, "duplicate",
    default = ""
  )

  return(linksSelect)
}

#' @title Extract Domain from URLs
#'
#' @description
#' Extracts the domain portion of URLs and optionally includes the scheme
#' (`http://` or `https://`).
#' The function removes common subdomains such as `www.` for consistency.
#'
#' @param x Character vector of URLs.
#' @param include_scheme Logical; if `TRUE`, prepend the detected scheme to the
#'    returned domain.
#'
#' @return
#' A character vector containing domain names. URLs that cannot be parsed
#' return the original input value.
#'
#' @keywords internal
get_domain <- function(x, include_scheme = FALSE) {
  # Extract primary domain using urltools
  x_help <- urltools::domain(x)

  # Remove the www subdomain prefix for consistency across datasets
  x_out <- gsub("^www\\.", "", x_help)

  # Prepend the scheme if requested, handling missing values as empty strings
  if (include_scheme == TRUE) {
    x_scheme <- urltools::scheme(x)
    x_scheme <- fifelse(is.na(x_scheme), "", paste0(x_scheme, "://"))
    x_out <- paste0(x_scheme, x_out)
  }

  # Fallback to the original URL if parsing results in NA
  x_out[is.na(x_out)] <- x[is.na(x_out)]

  return(x_out)
}


#' @title Parse HTML and Remove Non‑Text Elements
#'
#' @description
#' Converts an HTML document into a cleaned representation where scripts,
#' styles, and similar elements are removed.
#' If `keep_only_text = TRUE`, the function returns only the visible text of
#' the page.
#'
#' @details
#' This helper is used to prepare HTML content for downstream text extraction.
#' It:
#' * Removes `<script>`, `<style>`, and `<noscript>` nodes
#' * Optionally extracts only visible text
#' * Supports both raw HTML input and already parsed XML documents
#'
#' @param doc Either HTML content as a character string or an
#'    `xml_document`. `NA` inputs are returned unchanged.
#' @param keep_only_text Logical; if `TRUE`, returns only human‑readable text.
#'
#' @return
#' A cleaned XML node set or a character string (if `keep_only_text = TRUE`).
#'
#' @keywords internal
parse_HTML <- function(doc, keep_only_text = FALSE) {
  # Handle NA input by returning it unchanged
  if (is.na(doc)) {
    return(doc)
  }

  # Prepare document
  if (!inherits(doc, "xml_document")) {
    doc <- rvest::read_html(doc)
  }

  # Filter nodes to exclude scripts, styles, and noscript elements
  remove_nodes <- c("script", "style", "noscript")
  xpath_expr <- paste0("ancestor::", remove_nodes, ' or name()="', remove_nodes, '"')
  xpath_expr <- paste(xpath_expr, collapse = " or ")
  xpath_expr <- paste0("//*[not(", xpath_expr, ")]")

  if (keep_only_text == TRUE) {
    xpath_expr <- paste0(xpath_expr, "/text()")
  }

  doc <- rvest::html_elements(doc, xpath = xpath_expr)

  # Extract and normalize visible text if requested
  if (keep_only_text == TRUE) {
    doc <- rvest::html_text(doc, trim = TRUE)
    doc <- doc[doc != ""]
    doc <- paste(doc, collapse = "\n")
    # Clean byte sequence issues
    doc <- iconv(doc, sub = "byte")
  }

  return(doc)
}

#' @title Extract Regular Expression Matches from Scraped HTML
#'
#' @description
#' Applies a regular expression to previously scraped HTML documents, optionally
#' restricted to a specific capture group. Each document is first cleaned using
#' parse_HTML() to remove non-text content, ensuring reliable pattern extraction.
#'
#' @details
#' The function cleans and normalizes each HTML document, converts text to
#' lowercase when ignore_cases is `TRUE`, extracts all regex matches using
#' `stringr::str_match_all()`, supports named or numbered capture groups, and
#' returns a unified `data.table` indexed by URL.
#'
#' Named groups allow meaningful column labeling in the result.
#'
#' @param docs Character vector or list of HTML source documents.
#' @param urls Character vector of URLs corresponding to docs.
#' @param pattern A regular expression to search for.
#' @param group Optional capture group name or index to extract. If `NULL`, the
#' full match is returned.
#' @param ignore_cases Logical; if `TRUE`, performs case-insensitive matching.
#'
#' @return
#' A `data.table` where each row corresponds to a match and includes:
#'
#' - "url": The original document URL
#' - "pattern" (or the given group name): Extracted values
#'
#' Missing matches are returned as `NA_character_`.
#'
#' @keywords internal
#'
#' @examples
#' \dontrun{
#' ## Extract email-like patterns:
#' .extract_regex(docs, urls, pattern = "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+")
#' }
#' @noRd
.extract_regex <- function(docs, urls, pattern, group = NULL, ignore_cases = TRUE) {
  # Clean and normalize HTML content
  docs <- sapply(docs, parse_HTML, keep_only_text = TRUE, USE.NAMES = FALSE)

  # Prepare pattern and content for matching
  regex_name <- ifelse(is.null(group), "pattern", group)

  if (ignore_cases == TRUE) {
    pattern <- tolower(pattern)
    docs <- tolower(docs)
    group <- tolower(group)
  }

  # Execute pattern matching
  str_extracted <- stringr::str_match_all(string = docs, pattern = pattern)

  # Determine group index based on name or index
  group_index <- 1
  if (!is.null(group) & length(group) != 0) {
    group_index <- which(colnames(str_extracted[[1]]) == group)
  }

  # Process and format match results
  names(str_extracted) <- urls
  str_extracted <- lapply(str_extracted, function(z) {
    z <- unique(z[, group_index])
    z <- z[!is.na(z)]
    if (length(z) == 0) {
      z <- NA_character_
    }
    z <- as.data.table(z)
    return(z)
  })

  # Consolidate results
  str_extracted <- rbindlist(str_extracted, idcol = "url")
  setnames(str_extracted, "z", regex_name)

  return(str_extracted)
}
