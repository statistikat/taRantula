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
#'   originated. Used to resolve relative links and filter domains.
#'
#' @return
#' A `data.table` containing the following columns:
#' * `href` – Cleaned and validated absolute URLs
#' * `label` – Link text extracted from the anchor element
#' * `source_url` – The originating page from which links were extracted
#' * `level` – Extraction depth (always 0 for this function)
#' * `scraped_at` – Timestamp of extraction
#'
#' Duplicate URLs are automatically removed.
#'
#' @export
#'
#' @examples
#' html <- "<html><body><a href='/about'>About</a></body></html>"
#' extractLinks(html, baseurl = "https://example.com")
extractLinks <- function(doc, baseurl) {
  href <- NULL
  if (!inherits(doc, "xml_document")) {
    doc <- rvest::read_html(doc)
  }

  body_node <- xml2::xml_find_first(doc, "//body")

  links <- rvest::html_elements(body_node, "a, area, base, link")
  hrefs <- rvest::html_attr(links, "href")
  labels <- rvest::html_text(links, trim = TRUE)
  labels <- gsub("\\s+", " ", labels)

  # remove missing hrefs from labels and hrefs
  labels <- labels[!is.na(hrefs)]
  hrefs <- hrefs[!is.na(hrefs)]

  # make urls absolute
  hrefs <- xml2::url_absolute(
    x = sub("^/", "", hrefs),
    base = sub("/$", "", baseurl)
  )

  # set http:// -> https://
  hrefs <- gsub("^http://", "https://", hrefs, fixed = TRUE)

  # check links for validity
  # remove anker points
  # remove links which point to other homepages
  # remove links identical to baseurl
  # remove links pointing to image/video/document
  keep <- check_links(hrefs = hrefs, baseurl = baseurl)

  dt_links <- data.table::data.table(
    href = hrefs[keep],
    label = labels[keep],
    stringsAsFactors = FALSE
  )
  dt_links <- unique(dt_links)

  dt_links$source_url <- baseurl
  dt_links$level <- 0
  dt_links$scraped_at <- Sys.time()

  return(dt_links[!duplicated(href)][])
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
#'   path comparison.
#'
#' @return
#' A logical vector indicating which entries in `hrefs` should be retained.
#'
#' @export
#'
#' @keywords internal
check_links <- function(hrefs, baseurl) {
  # ----------------------------------------------------------
  # helper for pasting with missing values
  pasteNA <- function(y, x, sep = "", na.sub = "") {
    x[is.na(x)] <- na.sub
    y[is.na(y)] <- na.sub

    paste(x, y, sep = sep)
  }
  # ----------------------------------------------------------

  urlParsed <- urltools::url_parse(baseurl)
  urlPathParam <- pasteNA(urlParsed$path, urlParsed$parameter)
  linksParsed <- urltools::url_parse(hrefs)
  linksExtract <- urltools::suffix_extract(linksParsed$domain)

  ## cond1
  # same domain as url
  sameDomain <- get_domain(hrefs) == get_domain(baseurl)
  # cannot parse domain -> kick url out
  sameDomain[is.na(sameDomain)] <- FALSE

  ## cond2
  # specific file endings not allowed
  # no png, css, ...
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

  noFile <- !grepl(paste(file_string, collapse = "|"), linksParsed$path)
  # noFile <- (!grepl("\\.",linksParsed$path))|(grepl("(\\.shtm|\\.htm|\\.dhtm|\\.xhtm|\\.php|\\.aspx|\\.jsp)",linksParsed$path))

  ## cond3
  # identical sub paths and parameter
  subPathParam <- pasteNA(linksParsed$path, linksParsed$parameter)
  subPath <- linksParsed$path
  subPath[is.na(subPath)] <- ""
  param <- linksParsed$parameter
  param[is.na(param)] <- ""

  subPathParam <- paste0(subPath, param)

  diffPathParam <- subPathParam != "" & !duplicated(gsub("/$", "", subPathParam)) & subPath != "/"

  # check if path and parameter are not the same as in the main url
  if (!is.na(urltools::path(baseurl))) {
    diffPathParam <- diffPathParam & urlPathParam != subPathParam
  }

  ## cond4
  # remove fragments on main url only
  nofragment <- is.na(linksParsed$fragment) | urlPathParam != subPathParam

  # select link only if all conditions are met:
  # same domain
  # correct file ending
  # different path than main URL
  # no fragmants but only on main URL
  linksSelect <- sameDomain & noFile & nofragment & diffPathParam

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
#'   returned domain.
#'
#' @return
#' A character vector containing domain names. URLs that cannot be parsed
#' return the original input value.
#'
#' @keywords internal
get_domain <- function(x, include_scheme = FALSE) {
  # apply twice
  # needed for some urls
  x_help <- urltools::domain(x)
  # remove www in front
  # most common sub level domain and mostly not needed
  x_out <- gsub("^www\\.", "", x_help)

  # add schema -> needed in connection with robots.txt (example robotstxt("www.hm.com") vs robotstxt("https://www.hm.com"))
  if (include_scheme == TRUE) {
    x_scheme <- urltools::scheme(x)
    x_scheme <- fifelse(is.na(x_scheme), "", paste0(x_scheme, "://"))
    x_out <- paste0(x_scheme, x_out)
  }

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
#'   `xml_document`. `NA` inputs are returned unchanged.
#' @param keep_only_text Logical; if `TRUE`, returns only human‑readable text.
#'
#' @return
#' A cleaned XML node set or a character string (if `keep_only_text = TRUE`).
#'
#' @keywords internal
parse_HTML <- function(doc, keep_only_text = FALSE) {
  # -------------------------
  # return document
  if (is.na(doc)) {
    return(doc)
  }

  # -------------------------
  # prep html
  if (!inherits(doc, "xml_document")) {
    doc <- rvest::read_html(doc)
  }

  body_node <- xml2::xml_find_first(doc, "//body")

  # try remove cookie banner
  # to do

  # try remove scripts
  # remove specific nodes
  remove_nodes <- c("script", "style", "noscript")
  xpathExpr <- paste0("ancestor::", remove_nodes, ' or name()="', remove_nodes, '"')
  xpathExpr <- paste(xpathExpr, collapse = " or ")
  xpathExpr <- paste0("//*[not(", xpathExpr, ")]")
  if (keep_only_text == TRUE) {
    xpathExpr <- paste0(xpathExpr, "/text()")
  }
  doc <- rvest::html_elements(doc, xpath = xpathExpr)

  if (keep_only_text == TRUE) {
    # extract only text
    doc <- rvest::html_text(doc, trim = TRUE)
    doc <- doc[doc != ""]
    doc <- paste(doc, collapse = "\n")
    doc <- iconv(doc, sub = "byte") # if something is not right with the string
  }

  return(doc)
}



#' @title Extract Regular Expression Matches from Scraped HTML
#'
#' @description
#' Applies a regular expression to previously scraped HTML documents, optionally
#' restricted to a specific capture group.
#' Each document is first cleaned using [`parse_HTML()`] to remove non‑text
#' content, ensuring reliable pattern extraction.
#'
#' @details
#' The function:
#'
#' * Cleans and normalizes each HTML document
#' * Converts text to lowercase when `ignore_cases = TRUE`
#' * Extracts all regex matches using `stringr::str_match_all()`
#' * Supports named or numbered capture groups
#' * Returns a unified `data.table` indexed by URL
#'
#' Named groups allow meaningful column labeling in the result.
#'
#' @param docs Character vector or list of HTML source documents.
#' @param urls Character vector of URLs corresponding to `docs`.
#' @param pattern A regular expression to search for.
#' @param group Optional capture group name or index to extract.
#'   If `NULL`, the full match is returned.
#' @param ignore_cases Logical; if `TRUE`, performs case‑insensitive matching.
#'
#' @return
#' A `data.table` where each row corresponds to a match and includes:
#' * `url` – The originating document URL
#' * `pattern` (or the given group name) – Extracted values
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
.extract_regex <- function(docs, urls, pattern, group = NULL, ignore_cases = TRUE) {
  # -------------------------
  # parse HTML
  docs <- sapply(docs, parse_HTML, keep_only_text = TRUE, USE.NAMES = FALSE)

  # -------------------------
  # extract pattern
  regex_name <- ifelse(is.null(group), "pattern", group) # save for output
  if (ignore_cases == TRUE) {
    pattern <- tolower(pattern)
    docs <- tolower(docs)
    group <- tolower(group)
  }

  str_extracted <- stringr::str_match_all(string = docs, pattern = pattern)

  group_index <- 1
  if (!is.null(group) & length(group) != 0) {
    group_index <- which(colnames(str_extracted[[1]]) == group)
  }

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

  str_extracted <- rbindlist(str_extracted, idcol = "url")

  setnames(str_extracted, "z", regex_name)

  return(str_extracted)
}
