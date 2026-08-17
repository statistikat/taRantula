#' Run an OWI query slice
#'
#' @description
#' Wraps the `owi query slice` command. Defaults reproduce the Austrian legal
#' pages query, while exposing the route, URL suffix, filter, selected columns,
#' collection, and CLI flags as parameters.
#'
#' @param route Character scalar passed to `owi query slice -R`.
#' @param url_suffix Character scalar used in the default `where` clause.
#' @param where Optional character scalar passed to `owi query slice --where`.
#'   If `NULL`, a default filter is built from `url_suffix`.
#' @param select Character vector or scalar passed to `owi query slice --select`.
#'   Vectors are collapsed into a comma-separated selection.
#' @param collection Character scalar passed to `owi query slice --collection`.
#' @param no_ciff Logical scalar. If `TRUE`, add `--no-ciff`.
#' @param yes Logical scalar. If `TRUE`, add `--yes`.
#' @param command Character scalar with the OWI executable name or path.
#' @param path_prepend Optional character scalar with a directory to prepend to
#'   `PATH` for the system call. Defaults to `Sys.getenv("owilix_path")`.
#' @param local_base_path Character scalar with the local OWI access directory
#'   used to discover the created parquet files.
#' @param stdout,stderr Passed through to [base::system2()].
#' @param dry_run Logical scalar. If `TRUE`, return the command and arguments
#'   without executing the system call.
#'
#' @return
#' A list with command metadata and `parquet_path`. For executed commands,
#' `result` contains the return value from [base::system2()].
#'
#' @export
#'
#' @examples
#' runOwiSliceQuery(dry_run = TRUE)
#' \dontrun{
#' runOwiSliceQuery(dry_run = FALSE)
#' # longer running examples
#' pq_slice <- runOwiSliceQuery(dry_run = FALSE,route = "all:2026-01-01..2026-08-13/collectionName=legal")
#' }
#'
#'
runOwiSliceQuery <- function(
  route = "all:latest/collectionName=legal",

  url_suffix = "at",
  where = NULL,
  select = c(
    "id",
    "url",
    "url_domain",
    "url_subdomain",
    "url_suffix",
    "title",
    "main_content",
    "microdata",
    "address",
    "language",
    "warc_date"
  ),
  collection = "austrian_legal_pages",
  no_ciff = TRUE,
  yes = TRUE,
  command = "owi",
  path_prepend = Sys.getenv("owilix_path"),
  local_base_path = file.path(path.expand("~"), ".owi", "public"),
  stdout = "",
  stderr = "",
  dry_run = FALSE
) {
  assert_scalar_character(route, "route")
  assert_scalar_character(url_suffix, "url_suffix")
  if (is.null(where)) {
    where <- buildOwiLegalPagesWhere(url_suffix = url_suffix)
  } else {
    assert_scalar_character(where, "where")
  }
  assert_character_select(select)
  assert_scalar_character(collection, "collection")
  assert_scalar_logical(no_ciff, "no_ciff")
  assert_scalar_logical(yes, "yes")
  assert_scalar_character(command, "command")
  if (identical(path_prepend, "")) {
    path_prepend <- NULL
  }
  assert_null_or_scalar_character(path_prepend, "path_prepend")
  assert_scalar_character(local_base_path, "local_base_path")
  assert_scalar_logical(dry_run, "dry_run")

  args <- buildOwiQuerySliceArgs(
    route = route,
    where = where,
    select = select,
    collection = collection,
    no_ciff = no_ciff,
    yes = yes
  )
  env <- buildOwiSystemEnv(path_prepend = path_prepend)
  started_at <- Sys.time()

  if (dry_run) {
    return(list(
      command = command,
      args = args,
      env = env,
      parquet_path = NA_character_
    ))
  }

  result <- system2(
    command = command,
    args = shQuote(args),
    env = env,
    stdout = stdout,
    stderr = stderr
  )

  list(
    result = result,
    command = command,
    args = args,
    env = env,
    parquet_path = findLatestOwiParquetPath(
      collection = collection,
      local_base_path = local_base_path,
      modified_after = started_at
    )
  )
}

buildOwiQuerySliceArgs <- function(
  route,
  where,
  select,
  collection,
  no_ciff,
  yes
) {
  select <- paste(trimws(select), collapse = ",\n")
  args <- c(
    "query",
    "slice",
    "-R",
    route,
    "--where",
    where,
    "--select",
    select,
    "--collection",
    collection
  )

  if (no_ciff) {
    args <- c(args, "--no-ciff")
  }
  if (yes) {
    args <- c(args, "--yes")
  }

  args
}

buildOwiLegalPagesWhere <- function(url_suffix) {
  as.character(glue::glue(
    "url_suffix='{url_suffix}' AND valid=true AND (ows_index=true OR ows_index IS NULL)"
  ))
}

buildOwiSystemEnv <- function(path_prepend) {
  if (is.null(path_prepend)) {
    return(character())
  }
  paste0("PATH=", path_prepend, ":", Sys.getenv("PATH"))
}

findLatestOwiParquetPath <- function(
  collection,
  local_base_path,
  modified_after = NULL
) {
  collection_path <- file.path(local_base_path, collection)
  if (!dir.exists(collection_path)) {
    return(NA_character_)
  }

  dataset_dirs <- list.dirs(
    collection_path,
    full.names = TRUE,
    recursive = FALSE
  )
  if (length(dataset_dirs) == 0) {
    return(NA_character_)
  }

  has_parquet <- vapply(
    dataset_dirs,
    function(path) {
      length(list.files(path, pattern = "\\.parquet$", full.names = TRUE)) > 0
    },
    logical(1)
  )
  dataset_dirs <- dataset_dirs[has_parquet]
  if (length(dataset_dirs) == 0) {
    return(NA_character_)
  }

  info <- file.info(dataset_dirs)
  if (!is.null(modified_after)) {
    recent <- !is.na(info$mtime) & info$mtime >= modified_after
    if (any(recent)) {
      dataset_dirs <- dataset_dirs[recent]
      info <- info[recent, , drop = FALSE]
    }
  }

  latest <- dataset_dirs[which.max(info$mtime)]
  file.path(latest, "*.parquet")
}

assert_scalar_character <- function(x, nm) {
  if (!rlang::is_scalar_character(x) || !nzchar(x)) {
    rlang::abort(glue::glue("`{nm}` must be a non-empty character scalar."))
  }
}

assert_null_or_scalar_character <- function(x, nm) {
  if (is.null(x)) {
    return(invisible(TRUE))
  }
  assert_scalar_character(x, nm)
}

assert_character_select <- function(x) {
  if (!is.character(x) || length(x) == 0 || any(!nzchar(trimws(x)))) {
    rlang::abort("`select` must be a non-empty character vector.")
  }
}

assert_scalar_logical <- function(x, nm) {
  if (!rlang::is_scalar_logical(x)) {
    rlang::abort(glue::glue("`{nm}` must be TRUE or FALSE."))
  }
}

assert_null_or_positive_integerish <- function(x, nm) {
  if (is.null(x)) {
    return(invisible(TRUE))
  }
  if (!rlang::is_scalar_integerish(x) || x < 0) {
    rlang::abort(glue::glue(
      "`{nm}` must be a non-negative integerish scalar or NULL."
    ))
  }
}
