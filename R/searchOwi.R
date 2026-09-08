#' Search keyword occurrences in OWI output
#'
#' @description
#' Searches OWI parquet files and returns rows where `keyword` occurs in a
#' selected text field. The default field is `main_content`. Parquet files are
#' queried directly with DuckDB.
#'
#' @param parquet_path Character scalar path, or directory containing
#'   parquet files, such as the `parquet_path` returned by [runOwiSliceQuery()]
#' or a duckdb connection object.
#' @param keyword Character scalar to search for.
#' @param field Character scalar naming the text field to search.
#' @param select Character vector of columns to return. Missing columns are
#'   ignored. The search field is always included for filtering.
#' @param exclude_domains Optional character vector of domain names to exclude
#'   from results. Values may be domains or URLs. They are compared against
#'   OWI's `url_domain` column and, when available, reconstructed
#'   `url_domain.url_suffix` values after trimming, lower-casing, and removing
#'   a leading `www.`.
#' @param ignore_case Logical scalar. If `TRUE`, match case-insensitively.
#' @param fixed Logical scalar. If `TRUE`, treat `keyword` as literal text.
#'   Otherwise `keyword` is interpreted as a regular expression.
#' @param limit Optional integerish scalar limiting the number of returned rows.
#' @param as_data_table Logical scalar. If `TRUE`, return a `data.table`;
#'   otherwise return a `data.frame`.
#'
#' @return A `data.table` or `data.frame` containing matching rows.
#'
#' @export
#'
#' @examples
#' # searchOwi("/path/to/*.parquet", keyword = "Impressum")
searchOwi <- function(
  parquet_path,
  keyword,
  field = "main_content",
  select = c(
    "id",
    "url",
    "title",
    "url_domain",
    "url_suffix",
    "language",
    "warc_date",
    field
  ),
  exclude_domains = NULL,
  ignore_case = TRUE,
  fixed = TRUE,
  limit = NULL,
  as_data_table = TRUE
) {
  assert_scalar_character(keyword, "keyword")
  assert_scalar_character(field, "field")
  assert_character_select(select)
  exclude_domains <- normalizeOwiExcludeDomains(exclude_domains)
  assert_scalar_logical(ignore_case, "ignore_case")
  assert_scalar_logical(fixed, "fixed")
  assert_null_or_positive_integerish(limit, "limit")
  assert_scalar_logical(as_data_table, "as_data_table")
  if (inherits(parquet_path, "duckdb_connection")) {
    message("The provided duckdb connection is used.")
  } else {
    assert_scalar_character(parquet_path, "parquet_path")
    files <- resolveParquetFiles(parquet_path)
    if (length(files) == 0) {
      rlang::abort(glue::glue(
        "No parquet files found for `parquet_path`: {parquet_path}"
      ))
    }
  }

  schema <- arrow::ParquetFileReader$create(files[[1]])$GetSchema()
  has_url_suffix <- "url_suffix" %in% names(schema)
  columns <- unique(c(
    select,
    field,
    if (!is.null(exclude_domains)) "url_domain",
    if (!is.null(exclude_domains) && has_url_suffix) "url_suffix"
  ))
  missing_field <- !field %in% names(schema)
  if (missing_field) {
    rlang::abort(glue::glue(
      "Field `{field}` is not present in parquet schema."
    ))
  }
  if (!is.null(exclude_domains) && !"url_domain" %in% names(schema)) {
    rlang::abort(
      "`exclude_domains` requires a `url_domain` column in the parquet schema."
    )
  }
  columns <- intersect(columns, names(schema))

  dat <- searchOwiDuckdb(
    parquet_path = parquet_path,
    files = files,
    keyword = keyword,
    field = field,
    select = select,
    columns = columns,
    exclude_domains = exclude_domains,
    ignore_case = ignore_case,
    fixed = fixed,
    limit = limit
  )
  if (as_data_table) {
    return(data.table::as.data.table(dat))
  }
  as.data.frame(dat)
}

searchOwiDuckdb <- function(
  parquet_path,
  files,
  keyword,
  field,
  select,
  columns,
  exclude_domains,
  ignore_case,
  fixed,
  limit
) {
  if (inherits(parquet_path, "duckdb_connection")) {
    message("The provided duckdb connection is used.")
  } else {
    con <- DBI::dbConnect(
      duckdb::duckdb(shared_home = FALSE),
      dbdir = ":memory:"
    )
    on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  }

  return_columns <- intersect(unique(select), columns)
  select_sql <- paste(
    DBI::dbQuoteIdentifier(con, return_columns),
    collapse = ", "
  )
  source_sql <- buildDuckdbParquetSource(con, parquet_path, files)
  field_sql <- DBI::dbQuoteIdentifier(con, field)
  keyword_sql <- DBI::dbQuoteString(con, keyword)
  field_value_sql <- paste0("COALESCE(CAST(", field_sql, " AS VARCHAR), '')")

  if (fixed && ignore_case) {
    where_sql <- paste0(
      "strpos(lower(",
      field_value_sql,
      "), lower(",
      keyword_sql,
      ")) > 0"
    )
  } else if (fixed) {
    where_sql <- paste0("strpos(", field_value_sql, ", ", keyword_sql, ") > 0")
  } else if (ignore_case) {
    where_sql <- paste0(
      "regexp_matches(",
      field_value_sql,
      ", ",
      keyword_sql,
      ", 'i')"
    )
  } else {
    where_sql <- paste0(
      "regexp_matches(",
      field_value_sql,
      ", ",
      keyword_sql,
      ")"
    )
  }
  if (!is.null(exclude_domains)) {
    url_domain_sql <- DBI::dbQuoteIdentifier(con, "url_domain")
    exclude_sql <- paste(
      DBI::dbQuoteString(con, exclude_domains),
      collapse = ", "
    )
    domain_value_sql <- paste0(
      "regexp_replace(lower(COALESCE(CAST(",
      url_domain_sql,
      " AS VARCHAR), '')), '^www\\.', '')"
    )
    domain_exclusion_sql <- paste0(
      domain_value_sql,
      " NOT IN (",
      exclude_sql,
      ")"
    )
    if ("url_suffix" %in% columns) {
      url_suffix_sql <- DBI::dbQuoteIdentifier(con, "url_suffix")
      suffix_value_sql <- paste0(
        "lower(COALESCE(CAST(",
        url_suffix_sql,
        " AS VARCHAR), ''))"
      )
      full_domain_sql <- paste0(
        "CASE WHEN ",
        domain_value_sql,
        " = '' OR ",
        suffix_value_sql,
        " = '' THEN ",
        domain_value_sql,
        " ELSE ",
        domain_value_sql,
        " || '.' || ",
        suffix_value_sql,
        " END"
      )
      domain_exclusion_sql <- paste0(
        "(",
        domain_exclusion_sql,
        " AND ",
        full_domain_sql,
        " NOT IN (",
        exclude_sql,
        "))"
      )
    }
    where_sql <- paste0(
      "(",
      where_sql,
      ") AND ",
      domain_exclusion_sql
    )
  }

  sql <- paste0(
    "SELECT ",
    select_sql,
    " FROM read_parquet(",
    source_sql,
    ")",
    " WHERE ",
    where_sql
  )
  if (!is.null(limit)) {
    sql <- paste(sql, "LIMIT", as.integer(limit))
  }

  data.table::as.data.table(DBI::dbGetQuery(con, sql))
}

buildDuckdbParquetSource <- function(con, parquet_path, files) {
  if (dir.exists(parquet_path)) {
    return(DBI::dbQuoteString(con, file.path(parquet_path, "*.parquet")))
  }
  if (hasGlobPattern(parquet_path)) {
    return(DBI::dbQuoteString(con, parquet_path))
  }
  if (length(files) == 1) {
    return(DBI::dbQuoteString(con, files[[1]]))
  }

  quoted_files <- DBI::dbQuoteString(con, files)
  paste0("[", paste(quoted_files, collapse = ", "), "]")
}

hasGlobPattern <- function(path) {
  grepl("[*?\\[]", path)
}

resolveParquetFiles <- function(parquet_path) {
  if (dir.exists(parquet_path)) {
    return(list.files(parquet_path, pattern = "\\.parquet$", full.names = TRUE))
  }
  files <- Sys.glob(parquet_path)
  files[file.exists(files) & grepl("\\.parquet$", files)]
}

normalizeOwiExcludeDomains <- function(exclude_domains) {
  if (is.null(exclude_domains)) {
    return(NULL)
  }
  if (!is.character(exclude_domains)) {
    rlang::abort("`exclude_domains` must be a character vector or NULL.")
  }

  exclude_domains <- vapply(
    exclude_domains,
    function(x) {
      host <- tryCatch(
        urltools::domain(x),
        error = function(e) NA_character_
      )
      if (is.na(host) || !nzchar(host)) {
        return(x)
      }
      host
    },
    character(1),
    USE.NAMES = FALSE
  )
  exclude_domains <- trimws(tolower(exclude_domains))
  exclude_domains <- exclude_domains[
    !is.na(exclude_domains) & nzchar(exclude_domains)
  ]
  if (length(exclude_domains) == 0) {
    return(NULL)
  }

  exclude_domains <- sub("^www\\.", "", exclude_domains)
  unique(exclude_domains)
}
