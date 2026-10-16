# ============================================================================
# Extract officials' endorsements from Democracy in Action (2016)
#
# Source page: "Endorsements by Federal and Statewide Elected Officials in
# the 2016 Republican Presidential Primary" -- headed "National
# Endorsements--Republicans...to Jan. 13, 2016 only" (updated January 13,
# 2016). This is a snapshot: endorsements after Jan. 13, 2016 are not on it.
# Input: data/raw/Democracy in Action/dia_2016_officials.html
# Output: data/raw/Democracy in Action/extracted/dia_2016_officials_extracted.csv
#
# Layout: one <table> per candidate (12 tables: BUSH ... WALKER). Row 1 holds
# the candidate name; row 2 holds seven cells, used as two column groups:
#   td[1] names | td[2] dates | td[3] links | td[4] counts   -> "Federal officials"
#   td[5] names | td[6] dates | td[7] links                  -> "Other statewide officials"
# Within a group, the three cells are lined up LINE BY LINE: the 5th <br>-
# separated line of the names cell goes with the 5th line of the dates cell
# and the 5th line of the links cell. Blank lines are spacers that keep the
# columns aligned, so they are kept while splitting (cell_slots() below) and
# only skipped once all three cells are blank on that line. `line_in_cell`
# records the position so any row can be checked against the page.
#
# The counts cell (td[4]) holds subtotals ("4" senators, "26"
# representatives for Bush). They are not data rows; Step 5 compares their
# sum to the number of parsed federal rows per candidate as a check.
#
# Date cells use a straight double quote (") as a ditto mark meaning "same
# date as the line above". date_raw is filled with that carried-forward date
# and date_ditto = TRUE flags it; raw_text keeps the original ".
#
# The cross-reference grids further down the page (Republican Governors,
# U.S. Senators, House members by state) have no dates or links -- not
# extracted, same decision as the 2012 officials script.
#
# Decisions applied in this script (Oct. 2026):
#   - Bush, "Other statewide officials": one date line reads "08/07/15 \""
#     (a date and a ditto with no <br> between them), so every date below it
#     is shifted one line down. Step 2b hand-codes the correct dates for
#     Cagel, Olens, Schuette and Pruitt (date_hand_corrected = TRUE) and
#     drops the two orphaned date lines.
#   - Kasich, "Other statewide officials": four names under one date
#     (09/02/15); the date is copied to DeWine, Husted and Yost (Step 2b).
#   - endorsee and switch_candidate use standardized full names ("Jeb
#     Bush"); the page heading is kept in endorsee_raw.
#   - At-large House districts are coded 0 ("WY-AL", "SD-AL" -> "0").
#   - record_type = "endorsement" for every endorsement row (no retractions
#     on this page); blank for [PAGE NOTE] rows.
#
# NOTE on source quirks (kept in output rather than silently "corrected"):
#   - "?" dates (Messer, Wagner) are left blank with note "date shown as '?'".
#   - "Sen. Maj. Leader Mitch McConnell" has no state; endorser_description
#     is "U.S. Senator" and the title is kept in note.
#   - "Rep. Marco Rubio (UT-3)" in the Rubio list is a source error (UT-3
#     was Jason Chaffetz). Kept as written.
#   - "Rep. Sean Duffy (WI-7) to RUBIO" (Walker list) -> switch_direction =
#     "to", switch_candidate = "RUBIO"; Duffy also appears in the Rubio list.
#   - Dropped-out candidates carry a bracket in the header, e.g.
#     "GRAHAM [to 12/21/15]"; endorsee is "Lindsey Graham" and the bracket
#     text is kept in candidate_status_note.
#   - Notes printed between candidate tables (Bush's "Note:" and Politico
#     paragraphs, Christie's "Correction:") are kept as "[PAGE NOTE]" rows.
# ============================================================================

library(rvest)
library(xml2)
library(stringr)
library(dplyr)
library(purrr)
library(tibble)

# ---- Config ----------------------------------------------------------------
input_path  <- "data/raw/Democracy in Action/dia_2016_officials.html"
output_path <- "data/raw/Democracy in Action/extracted/dia_2016_officials_extracted.csv"

# ---- Helper functions -------------------------------------------------------

link_token_re <- regex('<a\\s+[^>]*?href="([^"]*)"[^>]*>(.*?)</a>',
                       dotall = TRUE, ignore_case = TRUE)
url_token_re  <- regex("@@URL\\[([^\\]]*)\\]@@")
block_tag_re  <- regex("</?(?:p|div|tr|td|th|table|tbody|li|ul|center|blockquote|h1|h2|h3)\\b[^>]*>",
                       ignore_case = TRUE)

# Markup string -> text, with <br> (and optionally block tags) as @@BR@@.
# Links become "@@URL[href]@@text" -- the URL token goes BEFORE the link
# text here, because a few links wrap a <br> ("<a href=...>+<br></a>"); with
# the token first, the "+" and its URL stay on the same line.
markup_to_text <- function(html_str, block_tags) {
  html_str <- str_remove_all(html_str, regex("<script\\b.*?</script>", dotall = TRUE, ignore_case = TRUE))
  # An empty link may serialize as self-closing <a href="..."/>; drop it so
  # the link pattern cannot run on to the next </a>.
  html_str <- str_remove_all(html_str, regex("<a\\b[^>]*/>", ignore_case = TRUE))
  html_str <- str_replace_all(html_str, link_token_re, "@@URL[\\1]@@\\2")
  html_str <- str_replace_all(html_str, regex("<br\\b[^>]*>", ignore_case = TRUE), "@@BR@@")
  if (block_tags) html_str <- str_replace_all(html_str, block_tag_re, "@@BR@@")
  frag <- read_html(paste0("<html><body><div>", html_str, "</div></body></html>"),
                    encoding = "UTF-8")
  txt <- xml_text(frag)
  txt <- str_replace_all(txt, "\u00a0", " ")
  str_replace_all(txt, "\\s+", " ")
}

# One <td> -> its <br>-separated lines, KEEPING blank lines (they are
# alignment spacers); only trailing blanks are dropped.
cell_slots <- function(td) {
  html_str <- as.character(td)
  html_str <- str_remove(html_str, "^\\s*<td\\b[^>]*>")
  html_str <- str_remove(html_str, "</td>\\s*$")
  slots <- str_trim(str_split(markup_to_text(html_str, block_tags = FALSE), fixed("@@BR@@"))[[1]])
  while (length(slots) > 0 && slots[length(slots)] == "") slots <- slots[-length(slots)]
  slots
}

# Markup string -> non-empty lines (block tags also break lines).
flatten_html <- function(html_str) {
  lines <- str_trim(str_split(markup_to_text(html_str, block_tags = TRUE), fixed("@@BR@@"))[[1]])
  lines[lines != ""]
}

strip_urls <- function(x) str_squish(str_remove_all(x, url_token_re))

collect_urls <- function(x) {
  urls <- unlist(map(x, ~ str_match_all(.x, url_token_re)[[1]][, 2]))
  urls <- unique(urls[!is.na(urls) & urls != ""])
  if (length(urls) == 0) NA_character_ else paste(urls, collapse = "; ")
}

# ---- Name / title parsing ---------------------------------------------------
# "Rep. Mike Rogers (AL-3)", "Lt. Gov. Kay Ivey (AL)", "Treasurer Walker
# Stapleton (CO)". Longer titles are listed before shorter ones that they
# contain ("Sen. Maj. Leader" before "Sen.", "Lt. Gov." before "Gov.").

titles <- c(
  "Sen. Maj. Leader", "Lt. Gov.", "Gov.", "Sen.", "Rep.",
  "Attorney General", "Secretary of State", "State Treasurer", "Treasurer",
  "State Auditor", "Auditor", "Controller", "Agriculture Commissioner",
  "Land Commissioner", "Chief Financial Officer"
)
title_alt    <- paste(str_replace_all(titles, "\\.", "\\\\."), collapse = "|")
name_loc_re  <- regex(paste0("^(", title_alt, ")\\s+(.+?)\\s*\\(([A-Z]{2,4}(?:-[A-Z0-9]+)?)\\)\\s*(.*)$"))
name_only_re <- regex(paste0("^(", title_alt, ")\\s+(.+)$"))

title_description <- c(
  "Gov." = "Governor", "Lt. Gov." = "Lieutenant Governor",
  "Sen." = "U.S. Senator", "Sen. Maj. Leader" = "U.S. Senator",
  "Rep." = "U.S. Representative"
)

# Page headings -> standardized full candidate names (also used for
# switch_candidate). stopifnot() in Step 4 catches any heading not listed.
candidate_names <- c(
  "BUSH" = "Jeb Bush", "CHRISTIE" = "Chris Christie", "CRUZ" = "Ted Cruz",
  "FIORINA" = "Carly Fiorina", "GRAHAM" = "Lindsey Graham",
  "HUCKABEE" = "Mike Huckabee", "KASICH" = "John Kasich", "PAUL" = "Rand Paul",
  "PERRY" = "Rick Perry", "RUBIO" = "Marco Rubio", "SANTORUM" = "Rick Santorum",
  "WALKER" = "Scott Walker"
)
standardize_name <- function(x) {
  key <- toupper(x)
  unname(ifelse(!is.na(key) & key %in% names(candidate_names), candidate_names[key], x))
}

valid_date_re <- regex("^\\d{1,2}/\\d{1,2}[/.]\\d{2}$|^\\d{1,2}/\\d{2}$")
ditto_marks   <- c('"', "\u201c", "\u201d", "''")

# ---- Parse one column group (names / dates / links cells) -------------------

parse_group <- function(name_td, date_td, link_td, endorsee, column_label) {
  N <- cell_slots(name_td)
  D <- cell_slots(date_td)
  L <- cell_slots(link_td)
  n <- max(length(N), length(D), length(L))
  if (n == 0) return(NULL)
  pad <- function(x) c(x, rep("", n - length(x)))
  N <- pad(N); D <- pad(D); L <- pad(L)
  
  last_date <- NA_character_
  out <- list()
  
  for (k in seq_len(n)) {
    name_txt <- strip_urls(N[k])
    date_txt <- strip_urls(D[k])
    link_txt <- strip_urls(L[k])
    if (name_txt == "" && date_txt == "" && link_txt == "") next   # spacer line
    
    # Date: real date, ditto (carry forward), or something else (kept in note)
    date_ditto <- date_txt %in% ditto_marks
    if (date_ditto) {
      date_val <- last_date
    } else if (str_detect(date_txt, valid_date_re)) {
      date_val  <- date_txt
      last_date <- date_txt
    } else {
      date_val <- NA_character_
    }
    
    m1 <- str_match(name_txt, name_loc_re)
    m2 <- str_match(name_txt, name_only_re)
    if (!is.na(m1[1, 1])) {
      title <- m1[1, 2]; endorser <- m1[1, 3]; loc <- m1[1, 4]; post <- str_squish(m1[1, 5])
    } else if (!is.na(m2[1, 1])) {
      title <- m2[1, 2]; endorser <- m2[1, 3]; loc <- NA_character_; post <- ""
    } else {
      title <- NA_character_; endorser <- NA_character_; loc <- NA_character_; post <- ""
    }
    parsed <- !is.na(title)
    
    # Switch written after the name: "Rep. Sean Duffy (WI-7) to RUBIO"
    to_match <- str_match(post, "^to\\s+([A-Z'][A-Za-z' ]+)$")
    switch_direction <- if (!is.na(to_match[1, 1])) "to" else NA_character_
    switch_candidate <- if (!is.na(to_match[1, 1])) to_match[1, 2] else NA_character_
    
    note_parts <- c(
      if (post != "" && is.na(switch_direction)) post,
      if (identical(title, "Sen. Maj. Leader")) "Senate Majority Leader",
      if (date_txt == "?") "date shown as '?'",
      if (date_txt != "" && !date_ditto && is.na(date_val) && date_txt != "?") paste0("date cell reads: ", date_txt)
    )
    
    description <- if (!parsed) {
      NA_character_
    } else if (title %in% names(title_description)) {
      title_description[[title]]
    } else {
      title   # statewide offices kept as written, e.g. "Attorney General"
    }
    
    raw <- paste(name_txt, date_txt, link_txt, sep = " | ")
    raw <- if (name_txt == "") paste0("[ORPHAN LINE] ", raw) else if (!parsed) paste0("[UNMATCHED] ", raw) else raw
    
    out[[length(out) + 1]] <- tibble(
      endorsee             = endorsee,
      endorser_name        = endorser,
      endorser_description = description,
      state                = if (!is.na(loc)) str_remove(loc, "-[A-Z0-9]+$") else NA_character_,
      district             = if (!is.na(loc)) str_extract(loc, "(?<=-)[A-Z0-9]+$") else NA_character_,
      date_raw             = date_val,
      note                 = if (length(note_parts) > 0) paste(note_parts, collapse = "; ") else NA_character_,
      switch_direction     = switch_direction,
      switch_candidate     = switch_candidate,
      evidence_url         = collect_urls(L[k]),
      parsed_ok            = parsed,
      raw_text             = raw,
      table_column         = column_label,
      line_in_cell         = k,
      date_ditto           = date_ditto
    )
  }
  bind_rows(out)
}

# ---- Step 1: Read HTML and find the candidate tables ------------------------
# Candidate tables are the ones whose first row has exactly 7 cells and that
# contain a <big> candidate name. (The cross-reference grids have different
# shapes and no <big> header.)

doc <- read_html(input_path, encoding = "UTF-8")
cand_tables <- xml_find_all(doc, "//table[./tbody/tr[1]/td[7] and not(./tbody/tr[1]/td[8]) and .//big]")
stopifnot(length(cand_tables) == 12)
cand_paths <- xml_path(cand_tables)

# ---- Step 2: Parse each candidate table --------------------------------------

count_checks <- list()

endorse_df <- map_dfr(cand_tables, function(tbl) {
  header   <- str_squish(xml_text(xml_find_first(tbl, ".//big")))
  endorsee <- str_squish(str_remove(header, "\\s*\\[.*\\]\\s*$"))
  status   <- str_match(header, "\\[(.*)\\]")[1, 2]
  
  trs   <- xml_find_all(tbl, "./tbody/tr")
  cells <- xml_find_all(trs[[length(trs)]], "./td")
  stopifnot(length(cells) == 7)
  
  federal   <- parse_group(cells[[1]], cells[[2]], cells[[3]], endorsee, "Federal officials")
  statewide <- parse_group(cells[[5]], cells[[6]], cells[[7]], endorsee, "Other statewide officials")
  
  # Subtotals cell, for the Step 5 check
  counts <- suppressWarnings(as.numeric(strip_urls(cell_slots(cells[[4]]))))
  count_checks[[endorsee]] <<- tibble(
    endorsee = endorsee,
    page_subtotal = sum(counts, na.rm = TRUE),
    parsed_federal = if (is.null(federal)) 0L else sum(federal$parsed_ok)
  )
  
  bind_rows(federal, statewide) %>% mutate(candidate_status_note = status)
})
cat("Rows extracted from candidate tables:", nrow(endorse_df), "\n")

# Expected before corrections: 143 rows, 141 parsed (the other 2 are Bush's
# orphaned statewide dates, handled next).
stopifnot(nrow(endorse_df) == 143, sum(endorse_df$parsed_ok) == 141)

# ---- Step 2b: Hand-coded corrections -----------------------------------------
# (1) Bush, "Other statewide officials": one date line reads '08/07/15 "' --
#     a date and a ditto with no <br> between them -- so every date below it
#     sits one line too low. Corrected dates, checked against the page and
#     the press-release file names (bush081915prmi.html,
#     bush092915prok.html). The two orphaned date lines are dropped.

bush_date_fix <- tribble(
  ~endorsee, ~endorser_name,   ~fixed_date, ~fixed_ditto,
  "BUSH",    "Casey Cagel",    "08/07/15",  FALSE,
  "BUSH",    "Sam Olens",      "08/07/15",  TRUE,    # the ditto mark
  "BUSH",    "Bill Schuette",  "08/19/15",  FALSE,
  "BUSH",    "Scott Pruitt",   "09/29/15",  FALSE
)

orphans <- endorse_df$endorsee == "BUSH" &
  endorse_df$table_column == "Other statewide officials" &
  str_starts(endorse_df$raw_text, fixed("[ORPHAN LINE]"))
stopifnot(sum(orphans) == 2)
endorse_df <- endorse_df[!orphans, ]

endorse_df <- endorse_df %>%
  left_join(bush_date_fix, by = c("endorsee", "endorser_name")) %>%
  mutate(
    date_hand_corrected = !is.na(fixed_date),
    date_raw   = if_else(date_hand_corrected, fixed_date, date_raw),
    date_ditto = if_else(date_hand_corrected, fixed_ditto, date_ditto),
    note       = if_else(date_hand_corrected,
                         "date hand-corrected: page dates shifted one line in this column",
                         note)
  ) %>%
  select(-fixed_date, -fixed_ditto)
stopifnot(sum(endorse_df$date_hand_corrected) == 4)

# (2) Groups listed under ONE date: the date on the first member's line
#     applies to every member below it. On this page: Kasich's Ohio
#     statewide officials (Taylor, DeWine, Husted, Yost -- 09/02/15).

shared_date_groups <- tribble(
  ~endorsee, ~table_column,
  "KASICH",  "Other statewide officials"
)

fill_shared_dates <- function(df, groups) {
  for (g in seq_len(nrow(groups))) {
    idx <- which(df$endorsee == groups$endorsee[g] &
                   df$table_column == groups$table_column[g] & df$parsed_ok)
    idx <- idx[order(df$line_in_cell[idx])]
    last_date <- NA_character_
    for (i in idx) {
      if (!is.na(df$date_raw[i])) {
        last_date <- df$date_raw[i]
      } else if (!is.na(last_date)) {
        df$date_raw[i] <- last_date
        df$note[i] <- paste(na.omit(c(df$note[i], "date copied from the group's first listed member")),
                            collapse = "; ")
      }
    }
  }
  df
}
endorse_df <- fill_shared_dates(endorse_df, shared_date_groups)

# ---- Step 3: Notes printed between candidate tables --------------------------
# Collect the sibling nodes after each candidate table, up to the next
# candidate table or the "_____" rule that starts the cross-reference grids.

note_df <- map_dfr(cand_tables, function(tbl) {
  header   <- str_squish(xml_text(xml_find_first(tbl, ".//big")))
  endorsee <- str_squish(str_remove(header, "\\s*\\[.*\\]\\s*$"))
  sibs <- xml_find_all(tbl, "following-sibling::node()")
  html_parts <- character(0)
  for (s in sibs) {
    if (xml_path(s) %in% cand_paths) break
    if (str_starts(str_remove_all(xml_text(s), "\\s"), "____")) break
    html_parts <- c(html_parts, as.character(s))
  }
  if (length(html_parts) == 0) return(NULL)
  lines <- flatten_html(paste(html_parts, collapse = ""))
  lines <- lines[strip_urls(lines) != ""]
  if (length(lines) == 0) return(NULL)
  tibble(
    endorsee     = endorsee,
    evidence_url = map_chr(lines, collect_urls),
    parsed_ok    = FALSE,
    raw_text     = paste0("[PAGE NOTE] ", strip_urls(lines)),
    table_column = "Between tables"
  )
})
cat("Page-note rows:", nrow(note_df), "\n")

# ---- Step 4: Combine, add constant fields, order columns -------------------

stopifnot(all(unique(endorse_df$endorsee) %in% names(candidate_names)))

df <- bind_rows(endorse_df, note_df) %>%
  mutate(
    endorsee_raw = endorsee,                       # heading as on the page
    endorsee = standardize_name(endorsee),
    switch_candidate = standardize_name(switch_candidate),
    # At-large House seats are coded 0 (docs/final_schema.md): "WY-AL",
    # and any Representative listed with a state but no district number.
    district = case_when(
      district == "AL" ~ "0",
      endorser_description == "U.S. Representative" & is.na(district) & !is.na(state) ~ "0",
      TRUE ~ district
    ),
    record_type = if_else(str_starts(raw_text, fixed("[PAGE NOTE]")), NA_character_, "endorsement"),
    contest_id = "2016R",
    year = 2016,
    party = "R",
    endorser_party_note = NA_character_
  ) %>%
  select(
    contest_id, year, party, endorsee,
    endorser_name, endorser_description, endorser_party_note,
    state, district,
    date_raw, note, record_type, switch_direction, switch_candidate,
    evidence_url,
    parsed_ok, raw_text,
    # 2016-officials-specific columns (see header comments)
    endorsee_raw, table_column, line_in_cell, date_ditto, date_hand_corrected,
    candidate_status_note
  )

# ---- Step 5: Validation checkpoints, report, and write out -----------------

# Graham, Perry, Santorum and Walker have no subtotal on the page (shown
# as 0 here), so they are not compared.
cat("\nPage subtotal (counts cell) vs. parsed federal rows, per candidate:\n")
checks <- bind_rows(count_checks) %>%
  mutate(match = page_subtotal == 0 | page_subtotal == parsed_federal)
print(checks)
stopifnot(all(checks$match))

cat("\nEndorsements per candidate and column:\n")
print(count(df %>% filter(parsed_ok), endorsee, table_column))

# Expected after corrections: 141 table rows, all parsed; the only parsed
# rows without a date are the two "?" dates (Messer, Wagner).
stopifnot(
  nrow(endorse_df) == 141,
  all(endorse_df$parsed_ok),
  sum(is.na(endorse_df$date_raw)) == 2
)

n_failed <- sum(!df$parsed_ok)
cat("\nSuccessfully parsed:", sum(df$parsed_ok), "/", nrow(df), "\n")
cat(n_failed, "row(s) need manual review:\n")
print(df %>% filter(!parsed_ok) %>% pull(raw_text) %>% str_trunc(110))

cat("\nParsed rows with no date (check alignment on the page):\n")
print(df %>% filter(parsed_ok, is.na(date_raw)) %>% select(endorsee, endorser_name, table_column, line_in_cell, note))

dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
write.csv(df, output_path, row.names = FALSE, na = "", fileEncoding = "UTF-8")

cat("Written to:", output_path, "\n")