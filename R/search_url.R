#' @title Search Google for Business URLs
#'
#' @description
#' Sends search queries to the Google Custom Search API to identify URLs
#' associated with businesses. The function processes queries provided in a
#' data frame and returns link results together with positional information.
#'
#' @details
#' To use this function, you must provide a valid Google Custom Search API key
#' via the environment variable `SCRAPING_APIKEY_GOOGLE`, for example by adding
#' it to your `~/.Renviron` file.
#' In addition, the Custom Search Engine (CSE) identifier must be available via
#' the environment variable `SCRAPING_ENGINE_GOOGLE`.
#'
#' @param cfg A [`cfg_googlesearch()`] configuration object containing API
#'   credentials and query-related settings.
#' @param dat A `data.frame` or `data.table` containing variables from which
#'   search queries were constructed.
#' @param file Optional CSV filename to which results will be written. If the
#'   file exists and `overwrite = FALSE` is set in `cfg`, previously saved
#'   results will be loaded and skipped.
#' @param query_col Character scalar; the name of the column in `dat` that
#'   contains encoded search queries created via [`buildQuery()`].
#'
#' @return
#' A `data.table` containing the following columns:
#' * `idcol` – Identifier for the business
#' * `attributes` – Fields extracted from Google results (e.g., link, title)
#' * `position` – Search result ranking position
#'
#' @export
#'
#' @examples
#' ## Example usage will be added in future versions
searchURL <- function(cfg, dat,
                      file = file,
                      query_col = query_col) {
  position <- NULL
  creds <- cfg$get("credentials")
  stopifnot(inherits(cfg, "cfg_googlesearch"))

  params <- cfg$current_config()
  id_col <- params$id_col
  verbose <- params$verbose
  print_every_n <- params$print_every_n
  save_every_n <- params$save_every_n
  max_queries <- params$max_queries
  max_query_rate <- params$max_query_rate
  overwrite <- params$overwrite
  scrape_attributes <- params$scrape_attributes

  if (is.null(query_col)) {
    rlang::abort("Please use `cfg$update_setting('query_col' = '...')` to specify a variable holding queries")
  }

  ##################
  # check inputs
  if (!any(class(dat) %in% c("data.frame", "data.table"))) {
    rlang::abort("dat needs to be a data.frame or data.table")
  }
  data.table::setDT(dat)

  if (!rlang::is_scalar_character(id_col)) {
    rlang::abort("`id_col` is not a column within `dat`")
  }
  if (!rlang::is_scalar_character(query_col)) {
    rlang::abort("`query_col` is not a column within `dat`")
  }

  searchQueries <- dat[[query_col]]
  if (!attributes(query_col)$query_attr == "built_encoded_query") {
    rlang::abort("`query_col` was not constructed using buildQuery()")
  }

  ##################
  # call api for each searchString
  if (verbose) {
    rlang::inform("Start sending queries...")
  }

  output <- list()
  if (overwrite == FALSE && !is.null(file) && file.exists(file)) {
    output_saved <- fread(file)
    output <- c(output, list(output_saved))
    dat <- dat[!get(id_col) %in% output_saved[[id_col]]]
    if (nrow(dat) == 0) {
      if (verbose) {
        rlang::inform("Everything already searched...nothing to do!")
      }
      return(output_saved)
    }
  }

  t <- t_rate <- Sys.time()
  for (q in 1:nrow(dat)) {
    if (q %% (max_query_rate - 1) == 0) {
      # check if waiting time was uphold
      # not more than max_query_rate requests per 100 seconds
      wait_time <- (t_rate + 100) - Sys.time()
      if (wait_time > 0) {
        wait_unit <- attr(wait_time, "units")
        if (verbose) {
          rlang::inform(glue::glue("Waiting for {wait_time} {wait_unit} to prohibit sending more than {max_query_rate} queries per 100 seconds."))
        }
        wait_time <- as.numeric(wait_time, units = "secs")
        Sys.sleep(wait_time)
        t_rate <- Sys.time() + wait_time / (max_query_rate - 1)
      }
    }
    query <- searchQueries[q]

    URLquery <- paste0(
      "https://www.googleapis.com/customsearch/v1?",
      "key=", creds$key,
      "&cx=", creds$engine,
      "&gl=at", # country
      "&lr=lang_de", # language
      "&start=1", # start at position 1, start=11 results in links 11:20
      "&q=", query
    )

    # read json with own help function
    # catches errors includes waiting time
    # and retries queries internally
    QueryRes <- read_json_wrapper(URLquery)

    # if no results were found but google suggests another spelling of query
    # use the suggestion
    if (QueryRes$searchInformation$totalResults == 0 && !is.null(QueryRes$spelling$correctedQuery)) {
      corrquery <- QueryRes$spelling$correctedQuery
      corrquery <- urltools::url_encode(corrquery)
      URLquery <- paste0(
        "https://www.googleapis.com/customsearch/v1?",
        "key=", creds$key,
        "&cx=", creds$engine,
        "&gl=at", # country
        "&lr=lang_de", # language
        "&start=1", # start at position 1, start=11 results in links 11:20
        "&q=", corrquery
      )
      QueryRes <- read_json_wrapper(URLquery)
    }

    urls <- lapply(QueryRes$items, function(z) {
      z <- as.data.table(z[attributes])
      return(z)
    })
    urls <- rbindlist(urls, use.names = TRUE, fill = TRUE)
    if (nrow(urls) > 0) {
      urls[, position := 1:.N]
    }

    urls[, c(id_col) := dat[q][[id_col]]]
    output <- c(output, list(urls))

    if (verbose && q %% print_every_n == 0) {
      rlang::inform(glue::glue("Number of queries processed: {q}"))
      t_elapsed <- Sys.time() - t
      t_unit <- attr(t_elapsed, "units")
      rlang::inform(glue::glue("Elapsed time: {t_elapsed} {t_unit}\n"))
    }

    if (!is.null(file) && q %% save_every_n == 0) {
      output_part <- rbindlist(output, fill = TRUE, use.names = TRUE)
      data.table::fwrite(output_part, file = file)
    }

    if (q == max_queries) {
      wait_time <- (t + 60 * 60 * 24) - Sys.time()
      if (wait_time > 0) {
        wait_unit <- attr(wait_time, "units")
        rlang::inform(glue::glue("\nReached maximum of {max_queries} requests per day; Waiting for {wait_time} {wait_unit}."))
        Sys.sleep(as.numeric(wait_time, units = "secs"))
        t <- t_rate <- Sys.time()
        rlang::inform("Continuing")
      }
    }
  }

  if (verbose) {
    t_elapsed <- Sys.time() - t
    t_unit <- attr(t_elapsed, "units")
    rlang::inform(glue::glue("All queries processed in {t_elapsed} {t_unit}."))
  }

  # combine output
  output <- rbindlist(output, fill = TRUE, use.names = TRUE)

  # save results
  if (!is.null(file)) {
    if (verbose) {
      rlang::inform(glue::glue("Saving results as '{file}'."))
    }
    fwrite(output, file = file)
  }
  return(output)
}

#' @title Helper: JSON Reader with Retry Logic
#'
#' @description
#' Internal helper that reads JSON from a URL, automatically retrying with
#' exponential backoff when errors or warnings occur.
#'
#' @param path URL from which JSON should be read.
#' @param count Integer specifying the current retry interval. Used internally.
#'
#' @return
#' Parsed JSON content or an error/warning object when all retries fail.
#'
#' @keywords internal
read_json_wrapper <- function(path, count = 1) {
  output_json <- tryCatch(
    {
      jsonlite::read_json(path = path)
    },
    error = function(cond) {
      return(cond)
    },
    warning = function(cond) {
      return(cond)
    }
  )

  call_failed <- is(output_json, "simpleWarning") | is(output_json, "try-error")
  if (call_failed & count < 16) {
    Sys.sleep(count)
    output_json <- read_json_wrapper(path, count = count * 2)
  }
  return(output_json)
}


#' @title Build Encoded Search Queries
#'
#' @description
#' Constructs URL‑encoded search queries from selected columns in a data frame
#' or data table. This function is typically used to prepare query strings for
#' the Google Custom Search API.
#'
#' @param dat A `data.frame` or `data.table` containing the text variables used
#'   to assemble the search string.
#' @param selectCols Character vector of column names to include in the query.
#'   If `NULL`, all columns in `dat` are used.
#'
#' @return
#' A character vector of encoded search queries. The returned object includes an
#' attribute `"query_attr" = "built_encoded_query"` used for downstream checks.
#'
#' @export
#'
#' @examples
#' ## Example usage will be added later
buildQuery <- function(dat, selectCols = NULL) {
  # check inputs
  if (!inherits(data.table(), c("data.frame", "data.table"))) {
    rlang::abort("dat needs to be a data.frame or data.table")
  }
  setDT(dat)

  if (is.null(selectCols)) {
    selectCols <- colnames(dat)
  }

  if (!is.character(selectCols)) {
    rlang::abort("selectCols needs to be a character vector")
  }

  if (!all(selectCols %in% names(dat))) {
    rlang::abort("Not all elements of selectCols are column names in dat")
  }

  # build and return search query
  searchStrings <- dat[, do.call(paste, .SD), .SDcols = c(selectCols)]
  q <- urltools::url_encode(base::trimws(searchStrings))

  attr(q, "query_attr") <- "built_encoded_query"
  return(q)
}

#' @title Run Google Search Workflow
#'
#' @description
#' Executes one or multiple Google Custom Search API queries derived from a
#' prepared dataset. Results are saved into the directory structure defined in
#' the provided [`cfg_googlesearch()`] configuration object.
#'
#' @param cfg A [`cfg_googlesearch()`] configuration object containing all
#'   required search, credential, and file‑handling settings.
#' @param dat A `data.table` containing variables referenced in
#'   `cfg$query_col`. All referenced columns must exist in `dat`.
#'
#' @returns
#' Returns `TRUE` invisibly when all queries have completed successfully.
#' Result files are written to the directory specified in `cfg`.
#'
#' @export
#'
#' @examples
#' ## Example use will be added in future releases
runGoogleSearch <- function(cfg = cfg_googlesearch$new(), dat) {
  stopifnot(inherits(cfg, "cfg_googlesearch"))

  # Set Parameters
  params <- cfg$show_config()
  id_col <- params$id_col

  queries <- cfg$get(key = "query_col")

  for (v in queries) {
    if (!v %in% names(dat)) {
      rlang::abort(paste("Variable", shQuote(v), "is missing in `dat`"))
    }
  }

  save_files <- cfg$get(key = "file")
  if (is.null(save_files)) {
    save_files <- paste0("URL_GoogleAPI", 1:length(queries), ".csv")
    cfg$set(key = "file", save_files)
  } else {
    if (rlang::is_character(save_files, n = length(queries))) {
      rlang::abort("Files must be a character vector with the same length as queries,\n
                   e.g length(cfg$get(key = 'file')) == length(cfg$get(key = 'query_col'))")
    }
  }

  # build paths
  path_web <- params$path
  EID <- basename(path_web)

  path_urls <- file.path(path_web, "url_search")
  if (!dir.exists(path_urls)) {
    dir.create(path_urls)
  }

  # Use all possible attributes
  cfg$set(
    key = "scrape_attributes",
    val = c("title", "link", "displayLink", "snippet")
  )

  for (q in seq_along(queries)) {
    # Update settings for the first query
    file <- cfg$get(key = "file")[q]
    query_col <- cfg$get(key = "query_col")[q]
    url_res1 <- searchURL(
      cfg = cfg,
      dat = dat,
      file = file,
      query_col = query_col
    )
    rlang::inform(paste0("Saved results for query #", q, " under: "), file)
  }

  rlang::inform("Finished!\n")
  return(TRUE)
}


#' @title Retrieve Google Search Credentials
#'
#' @description
#' Reads Google Custom Search API credentials from environment variables.
#' This allows secure decoupling of API keys from code.
#'
#' @details
#' The following environment variables must be defined:
#' * `SCRAPING_APIKEY_GOOGLE` – Your Google Custom Search API key
#' * `SCRAPING_ENGINE_GOOGLE` – The Custom Search Engine (CSE) identifier
#'
#' These values can be defined inside `~/.Renviron` or set at runtime using
#' `Sys.setenv()`.
#'
#' @return
#' A named list with elements:
#' * `engine` – The Google Custom Search Engine ID
#' * `key` – The API key string
#'
#' @export
#'
#' @examples
#' ## Example:
#' Sys.setenv(SCRAPING_APIKEY_GOOGLE = "your_key")
#' Sys.setenv(SCRAPING_ENGINE_GOOGLE = "your_engine")
#' creds <- getGoogleCreds()
#' print(creds)
getGoogleCreds <- function() {
  envname <- "SCRAPING_APIKEY_GOOGLE"
  key <- Sys.getenv(envname, unset = NA)
  if (is.na(key)) {
    rlang::abort(paste("No API-Key for Google found; Please set Environment Variable", shQuote(envname)))
  }

  envname <- "SCRAPING_ENGINE_GOOGLE"
  engine <- Sys.getenv(envname, unset = NA)
  if (is.na(engine)) {
    rlang::abort(paste("No API-Key for Google found; Please set Environment Variable", shQuote(envname)))
  }

  invisible(list(engine = engine, key = key))
}
