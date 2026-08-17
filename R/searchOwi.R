#' Search keyword occurrences in OWI output
#'
#' @description
#' Searches OWI parquet files and returns rows where `keyword` occurs in a
#' selected text field. The default field is `main_content`. Parquet files are
#' queried directly with DuckDB.
#'
#' @param parquet_path Character scalar path, glob, or directory containing
#'   parquet files, such as the `parquet_path` returned by [runOwiSliceQuery()].
#' @param keyword Character scalar to search for.
#' @param field Character scalar naming the text field to search.
#' @param select Character vector of columns to return. Missing columns are
#'   ignored. The search field is always included for filtering.
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
  select = c("id", "url", "title", "url_domain", "url_suffix", "language", "warc_date", field),
  ignore_case = TRUE,
  fixed = TRUE,
  limit = NULL,
  as_data_table = TRUE
) {
  assert_scalar_character(parquet_path, "parquet_path")
  assert_scalar_character(keyword, "keyword")
  assert_scalar_character(field, "field")
  assert_character_select(select)
  assert_scalar_logical(ignore_case, "ignore_case")
  assert_scalar_logical(fixed, "fixed")
  assert_null_or_positive_integerish(limit, "limit")
  assert_scalar_logical(as_data_table, "as_data_table")

  files <- resolveParquetFiles(parquet_path)
  if (length(files) == 0) {
    rlang::abort(glue::glue("No parquet files found for `parquet_path`: {parquet_path}"))
  }

  schema <- arrow::ParquetFileReader$create(files[[1]])$GetSchema()
  columns <- unique(c(select, field))
  missing_field <- !field %in% names(schema)
  if (missing_field) {
    rlang::abort(glue::glue("Field `{field}` is not present in parquet schema."))
  }
  columns <- intersect(columns, names(schema))

  dat <- searchOwiDuckdb(
    parquet_path = parquet_path,
    files = files,
    keyword = keyword,
    field = field,
    select = select,
    columns = columns,
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
  ignore_case,
  fixed,
  limit
) {
  con <- DBI::dbConnect(
    duckdb::duckdb(shared_home = FALSE),
    dbdir = ":memory:"
  )
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  return_columns <- intersect(unique(select), columns)
  select_sql <- paste(DBI::dbQuoteIdentifier(con, return_columns), collapse = ", ")
  source_sql <- buildDuckdbParquetSource(con, parquet_path, files)
  field_sql <- DBI::dbQuoteIdentifier(con, field)
  keyword_sql <- DBI::dbQuoteString(con, keyword)
  field_value_sql <- paste0("COALESCE(CAST(", field_sql, " AS VARCHAR), '')")

  if (fixed && ignore_case) {
    where_sql <- paste0(
      "strpos(lower(", field_value_sql, "), lower(", keyword_sql, ")) > 0"
    )
  } else if (fixed) {
    where_sql <- paste0("strpos(", field_value_sql, ", ", keyword_sql, ") > 0")
  } else if (ignore_case) {
    where_sql <- paste0(
      "regexp_matches(", field_value_sql, ", ", keyword_sql, ", 'i')"
    )
  } else {
    where_sql <- paste0("regexp_matches(", field_value_sql, ", ", keyword_sql, ")")
  }

  sql <- paste0(
    "SELECT ", select_sql,
    " FROM read_parquet(", source_sql, ")",
    " WHERE ", where_sql
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
