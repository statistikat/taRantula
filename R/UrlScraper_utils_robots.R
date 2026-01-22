#' Retrieve and Store robots.txt Information in a DuckDB Database
#'
#' @description
#' Retrieves **robots.txt** files for a set of domains, parses their permissions,
#' and stores them in a DuckDB table named `"robots"`.  
#' Existing entries are not overwritten. Domains for which no valid
#' `robots.txt` can be retrieved are stored with empty permissions, implying
#' fully permissive access.
#'
#' @details
#' The function processes domains in parallel, retrieves their
#' `robots.txt` rules, and stores them in chunks to improve efficiency.
#' It automatically detects which domains are already present in the database
#' and only processes the missing ones.
#'
#' The stored permissions can later be queried using [query_robotsdata()].
#'
#' @param db_file `character(1)`  
#'   Path to the DuckDB database file.
#' @param snapshot_every `integer(1)`  
#'   Number of domains to process per chunk.
#' @param workers `integer(1)`  
#'   Number of worker processes used for parallel retrieval.
#' @param urls `character`  
#'   Vector of URLs from which the corresponding domains will be extracted.
#' @param user_agent `character(1)`  
#'   Optional user agent string passed to `robotstxt::robotstxt()`.
#'
#' @return
#' Invisibly returns `NULL`.  
#' Side effect: updates (or creates) table `"robots"` in the supplied DuckDB file.
#'
#' @examples
#' \dontrun{
#' db <- "robots.duckdb"
#' urls <- c("https://example.com", "https://r-project.org")
#' .handle_robots(db_file = db, snapshot_every = 10, workers = 2, urls = urls)
#' }
#'
#' @seealso
#' * [query_robotsdata()]  
#' * [check_robotsdata()]
#' @keywords internal
.handle_robots <- function(db_file,
                           snapshot_every,
                           workers,
                           urls,
                           user_agent = NULL) {
  # make use of existing db-connection
  .insert_chunk_to_db <- function(conn, res) {
    stopifnot(inherits(conn, "duckdb_connection"))
    df <- do.call("rbind", res)
    n <- nrow(df)
    sql_values <- paste(rep("(?, ?)", n), collapse = ", ")
    sql_insert <- glue::glue("INSERT OR IGNORE INTO {tab} (domain, permissions) VALUES {sql_values}")
    params <- as.list(as.vector(t(df)))

    DBI::dbExecute(conn = conn, sql_insert, params = params)
    return(invisible(NULL))
  }

  domains <- get_domain(
    x = unique(urls),
    include_scheme = TRUE
  )

  # query db which domains are not yet listed:
  conn <- DBI::dbConnect(drv = duckdb::duckdb(db_file, read_only = FALSE))
  on.exit(try(DBI::dbDisconnect(conn, shutdown = TRUE), silent = TRUE), add = TRUE)

  tab <- "robots"
  ex_domains <- DBI::dbGetQuery(
    conn = conn,
    statement = glue::glue("select distinct(domain) from {tab}")
  )[[1]]

  if (length(ex_domains) > 0) {
    cli::cli_alert_info(
      text = glue::glue("found robots-data for {length(ex_domains)} domains")
    )
  }

  domains <- setdiff(domains, ex_domains)
  if (length(domains) == 0) {
    cli::cli_alert_success(
      text = "robots-data already available."
    )
    return(invisible(NULL))
  }

  cli::cli_alert_info(text = glue::glue("retrieving robots-data for {length(domains)} domains"))

  # Setup parallelized robots-retrieval
  oplan <- future::plan()
  on.exit(future::plan(oplan), add = TRUE)
  future::plan(strategy = future::multisession, workers = workers)

  # chunk-size
  chunks <- split(x = domains, f = ceiling(seq_along(domains) / snapshot_every))

  p <- progressr::progressor(steps = length(chunks), auto_finish = TRUE)
  for (i in seq_along(chunks)) {
    chunk <- chunks[[i]]
    # Fetch robots.txt in parallel
    res <- future.apply::future_lapply(chunk, function(x, user_agent) {
      tryCatch(
        expr = {
          rt <- robotstxt::robotstxt(
            domain = x,
            user_agent = user_agent,
            force = TRUE,
            warn = FALSE
          )
          data.frame(domain = x, permissions = as.character(rt$text))
        },
        error = function(e) {
          # print(e)
          data.frame(domain = x, permissions = "")
        }
      )
    }, user_agent = user_agent, future.seed = TRUE, future.packages = c("robotstxt"))

    # insert chunk-data in db
    .insert_chunk_to_db(conn = conn, res = res)
    p(message = glue::glue("Added {length(res)} robots-data entries"))
  }
  cli::cli_alert_success(
    text = "required robots-data successfully retrieved."
  )
  return(invisible(NULL))
}

#' Query Stored robots.txt Permissions for a Given URL
#'
#' @description
#' Retrieves the stored robots.txt permissions for the domain of the given URL
#' from a DuckDB database and returns them as a `robotstxt` object.
#'
#' @details
#' If the domain does not exist in the `"robots"` table, the function returns
#' a `robotstxt` object with empty permissions, implying full access.
#'
#' @param db_file `character(1)`  
#'   Path to the DuckDB database file.
#' @param url `character(1)`  
#'   URL for which the stored robots.txt information should be retrieved.
#'
#' @return
#' A `robotstxt` object from the **robotstxt** package.
#'
#' @examples
#' \dontrun{
#' query_robotsdata("robots.duckdb", "https://example.com/page")
#' }
#'
#' @seealso
#' * [check_robotsdata()]
#' @keywords internal
query_robotsdata <- function(db_file, url) {
  stopifnot(rlang::is_scalar_character(db_file))
  stopifnot(rlang::is_scalar_character(url))

  domain <- get_domain(url, include_scheme = TRUE)
  conn <- DBI::dbConnect(
    drv = duckdb::duckdb(db_file, read_only = TRUE)
  )
  on.exit(try(DBI::dbDisconnect(conn, shutdown = TRUE), silent = TRUE), add = TRUE)
  tab <- "robots"
  df <- DBI::dbGetQuery(
    conn = conn,
    statement = glue::glue("SELECT * FROM {tab} where domain = {shQuote(domain)}")
  )

  if (nrow(df) == 0) {
    df <- data.frame(domain = domain, permissions = "")
  }
  rtxt <- robotstxt::robotstxt(domain = df$domain, text = df$permissions)
  return(rtxt)
}

#' Check Whether a URL Is Allowed According to Stored robots.txt Rules
#'
#' @description
#' Determines whether a URL is permitted to be scraped according to the
#' `robots.txt` rules stored in a DuckDB `"robots"` table.
#'
#' @details
#' Internally calls [query_robotsdata()] and evaluates permissions via
#' `robotstxt::paths_allowed()`.  
#' If no valid robots.txt information is available for the domain, the function
#' returns `TRUE` (i.e., scraping is allowed).
#'
#' @param db_file `character(1)`  
#'   Path to the DuckDB database file.
#' @param url `character(1)`  
#'   URL to evaluate.
#'
#' @return
#' `TRUE` if scraping the URL is allowed, `FALSE` otherwise.
#'
#' @examples
#' \dontrun{
#' check_robotsdata("robots.duckdb", "https://example.com/secret")
#' }
#'
#' @seealso
#' * [query_robotsdata()]
#' @keywords internal
check_robotsdata <- function(db_file, url) {
  rtxt <- query_robotsdata(db_file = db_file, url = url)

  if (is.na(rtxt$domain)) {
    # rtxt does not exist or is not valid
    return(TRUE)
  }
  allowed <- rtxt$check(url, bot = "*")
  return(allowed)
}