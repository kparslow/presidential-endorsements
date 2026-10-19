# Manual Review Protocol

Rules for the manual review of extracted files in Excel
(`data/raw/<source>/review/*_review.xlsx`). Each review copy is checked against
its saved source page before any cleaning is done in R.

---

## Purpose

The review makes each file an accurate record of its source page, in a form R
can read. It is a check of the **extraction**, not a step toward the final
schema.

- **In scope:** fixing rows where the extraction script misread the page.
- **Out of scope:** standardizing names, parsing dates, filling values the page
  does not give, recoding states or districts, adding descriptions or flags.
  These happen in the cleaning scripts (`scripts/cleaning/`), where every change
  is written in code.

---

## Before starting a file

1. Open the **saved** HTML file from `data/raw/<source>/` in a browser, not the
   live website. Live pages change; the saved file is the record.
2. Open the matching `*_review.xlsx`. Turn on the filter row if it is off.
3. Note the start in the review log.

---

## What to check on each row

Compare the row with the page, using `raw_text` to find it.

| Check | Fix it if… |
| --- | --- |
| The row exists on the page | the row is not an endorsement on the page (e.g. a page note) |
| `endorsee` | the row is attached to the wrong candidate |
| `endorser_name`, `endorser_description` | the name and title are split at the wrong place, or text is cut off |
| `state`, `district` | the values do not match what the page shows |
| `date_raw` | it is not the date the page gives for this endorsement |
| `switch_direction`, `switch_candidate`, `record_type` | a switch or retraction on the page is missing or wrong |
| `evidence_url` | the link does not match the page's link for this entry |

Also check **completeness**: for each candidate section, compare the number of
entries on the page with the number of rows (filter on `endorsee`). A gap
means the extraction missed or duplicated entries.

---

## Rules

1. **Extraction errors are fixed; source errors are kept.** If the page itself
   is wrong (e.g. "Rep. Marco Rubio (UT-3)"), leave the value as the page shows
   it and explain in `review_note`. Corrections of source errors happen in R,
   where they are documented in code.
2. **Blank on the page stays blank.** Do not fill a value from memory or from
   another source, even if it is known.
3. **Keep values as the page writes them.** Dates stay as written in `date_raw`
   (e.g. `Mar. 4, 2008`, `"` for a ditto mark); names keep the page's spelling.
4. **Never edit `row_id` or `raw_text`.** `row_id` links each row to the
   extracted file; `raw_text` is the evidence of what the page said.
5. **Never delete a row.** Mark it with `review_action = drop` instead, so the
   decision stays visible.
6. **Leave `parsed_ok` as extracted.** It records what the script flagged.
   Every row with `parsed_ok = FALSE` must have a `review_action`.
7. **Sorting and filtering are fine.** `row_id` keeps track of each row. Remove
   filters before saving, so the next session starts with every row visible.
8. **Missing entries are added as new rows** at the bottom, with `row_id` set to
   `new-1`, `new-2`, … and `review_action = added`. Copy the page's text for the
   entry into `raw_text`.

---

## Recording decisions

Two columns on every review copy record the review:

| Column | Values | Use |
| --- | --- | --- |
| `review_action` | blank, `edited`, `drop`, `added`, `flag` | Blank means checked, no change |
| `review_note` | free text | Why: what was wrong, or what the source error is |

- `edited`: one or more cells changed to match the page.
- `drop`: not an endorsement on the page (page notes, headings, non-endorsements,
  duplicates created by the extraction).
- `added`: an entry the extraction missed.
- `flag`: unsure; describe the question in `review_note` and resolve it before
  the file is marked complete.

Every `edited`, `drop`, `added` and `flag` row needs a `review_note`.

---

## Finishing a file

A file is complete when:

- every row with `parsed_ok = FALSE` has a `review_action`;
- no rows are left as `flag`;
- entry counts per candidate match the page.

Then:

1. Save and close Excel (an open file may not be fully saved).
2. Update the file's **Review status** in `docs/data_sources.md` to `complete`.
3. Note the finish in the review log.
4. Commit the review file and the status change together, one file per commit.
   Example: `data: review DiA 2008 organizations (15 rows, 1 edited)`

---

## Sample check (Ballotpedia master table only)

`bp_master_endorsements_review.xlsx` (2,823 rows) is checked by sample:

1. Draw the sample in R so it can be reproduced:
   `set.seed(2026); sample_ids <- dplyr::slice_sample(extracted, n = 100)$row_id`
   (with `row_id` added as in `make_review_copies.R`).
2. Check those rows, plus every row with a blank or unusual value, against the page.
3. Mark checked rows by entering `checked` in `review_note` if no change was needed.
4. If the sample finds extraction errors of one kind, check every row where that
   error could occur.
5. Record the seed, sample size and result in the review log and in the commit
   message.