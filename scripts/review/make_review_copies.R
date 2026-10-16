# ==============================================================================
# make_review_copies.R
#
# Purpose: Create Excel (.xlsx) review copies of the extracted CSV files for
#          each source, so they can be edited by hand without Excel
#          changing dates, numbers, or special characters.
#
# Input:   data/raw/<source>/extracted/*_extracted.csv
# Output:  data/raw/<source>/review/*_review.xlsx
#          for each <source> listed in `sources` below (currently
#          Democracy in Action and Ballotpedia). To add a source, add its
#          folder name under data/raw/ to `sources`.
#
# How data is protected:
#   1. Every column is read as text, so R does not guess types.
#   2. Every cell in the workbook is formatted as Text ("@"), including empty
#      rows below the data, so values typed into Excel stay text as well.
#   3. A row_id column records each row's position in the extracted file.
#      It stays attached to the row even after rows are deleted or sorted,
#      so edits can always be traced back to the extracted data.
#
# Safety: an existing review copy is never overwritten unless
#         overwrite = TRUE is set below. Review copies hold manual work.
#
# ==============================================================================

library(readr)
library(openxlsx)

# ---- Settings ---------------------------------------------------------------

# Folder names under data/raw/. Each must contain an extracted/ subfolder.
sources       <- c("Democracy in Action", "Ballotpedia")
overwrite     <- FALSE  # TRUE replaces existing review copies. Use with care.
spare_rows    <- 200    # empty rows below the data also formatted as Text

# ---- Function: one CSV to one review workbook -------------------------------
# review_dir is passed in, so the same function serves every source.

make_review_copy <- function(csv_path, review_dir) {
  
  out_name <- sub("_extracted\\.csv$", "_review.xlsx", basename(csv_path))
  out_path <- file.path(review_dir, out_name)
  
  if (file.exists(out_path) && !overwrite) {
    message("SKIPPED (already exists): ", out_name)
    return(invisible(NULL))
  }
  
  # Read every column as text; keep empty cells empty rather than NA strings.
  dat <- read_csv(csv_path,
                  col_types = cols(.default = col_character()),
                  na = "",
                  locale = locale(encoding = "UTF-8"),
                  show_col_types = FALSE)
  
  dat <- data.frame(row_id = as.character(seq_len(nrow(dat))), dat,
                    check.names = FALSE, stringsAsFactors = FALSE)
  
  wb <- createWorkbook()
  addWorksheet(wb, "review")
  
  # Apply Text format to the whole working area before writing the data.
  text_style <- createStyle(numFmt = "@")
  addStyle(wb, "review", text_style,
           rows = 1:(nrow(dat) + 1 + spare_rows),
           cols = 1:ncol(dat),
           gridExpand = TRUE)
  
  writeData(wb, "review", dat, keepNA = FALSE, withFilter = TRUE)
  
  # Bold header, frozen top row, readable column widths.
  addStyle(wb, "review", createStyle(textDecoration = "bold", numFmt = "@"),
           rows = 1, cols = 1:ncol(dat), gridExpand = TRUE, stack = TRUE)
  freezePane(wb, "review", firstRow = TRUE)
  # Width = longest value in the column, between 8 and 40 characters;
  # raw_text gets 80 so the source line is easy to read.
  widths <- vapply(names(dat), function(col) {
    longest <- max(nchar(c(col, dat[[col]])), na.rm = TRUE)
    min(max(longest + 2, 8), 40)
  }, numeric(1))
  widths[names(dat) == "raw_text"] <- 80
  setColWidths(wb, "review", cols = 1:ncol(dat), widths = widths)
  
  saveWorkbook(wb, out_path, overwrite = overwrite)
  message("CREATED: ", out_name, " (", nrow(dat), " rows)")
  invisible(out_path)
}

# ---- Run: each source's extracted/ folder -> its review/ folder -------------

for (source_name in sources) {
  extracted_dir <- file.path("data", "raw", source_name, "extracted")
  review_dir    <- file.path("data", "raw", source_name, "review")
  
  csv_files <- list.files(extracted_dir, pattern = "_extracted\\.csv$",
                          full.names = TRUE)
  if (length(csv_files) == 0) {
    stop("No *_extracted.csv files found in ", extracted_dir,
         ". Check that the working directory is the project root and that ",
         "the folder name in `sources` is spelled exactly as on disk.")
  }
  
  message("--- ", source_name, ": ", length(csv_files), " extracted file(s)")
  dir.create(review_dir, showWarnings = FALSE, recursive = TRUE)
  for (csv_path in csv_files) make_review_copy(csv_path, review_dir)
}