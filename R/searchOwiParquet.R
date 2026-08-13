#' Search keyword occurrences in OWI parquet output
#'
#' @description
#' Reads OWI parquet files with Arrow and returns rows where `keyword` occurs in
#' a selected text field. The default field is `main_content`.
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
#' # searchOwiParquet("/path/to/*.parquet", keyword = "Impressum")
searchOwiParquet <- function(
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

  dat <- lapply(files, function(file) {
    file_dat <- arrow::read_parquet(
      file = file,
      as_data_frame = TRUE
    )
    file_dat[, intersect(columns, names(file_dat)), drop = FALSE]
  })
  dat <- data.table::rbindlist(dat, use.names = TRUE, fill = TRUE)

  field_values <- dat[[field]]
  pattern <- keyword
  if (fixed && ignore_case) {
    field_values <- tolower(field_values)
    pattern <- tolower(pattern)
    ignore_case <- FALSE
  }
  matches <- grepl(
    pattern = pattern,
    x = field_values,
    ignore.case = ignore_case,
    fixed = fixed
  )
  matches[is.na(matches)] <- FALSE
  dat <- dat[matches, , drop = FALSE]

  return_columns <- intersect(unique(select), names(dat))
  dat <- dat[, ..return_columns]

  if (!is.null(limit)) {
    dat <- utils::head(dat, limit)
  }
  if (as_data_table) {
    data.table::as.data.table(dat)
  } else {
    as.data.frame(dat)
  }
}

resolveParquetFiles <- function(parquet_path) {
  if (dir.exists(parquet_path)) {
    return(list.files(parquet_path, pattern = "\\.parquet$", full.names = TRUE))
  }
  files <- Sys.glob(parquet_path)
  files[file.exists(files) & grepl("\\.parquet$", files)]
}
