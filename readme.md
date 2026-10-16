presidential-endorsements
================

# Presidential Endorsements Data

The project compiles and cleans data from presidential primary contests
to create a history of endorsements by elected officials, interest
groups, and other individuals. The purpose of the dataset is to document
and analyze patterns in the endorsement behavior of political insiders
for the purpose of understanding who they endorse and when they endorse.

## Project Status

*In progress — data compilation phase.* Raw data from all four sources
has been acquired and extracted; manual review of the extracted files is
next.

## Overview

Endorsements act as a strategic tool for political insiders and elite to
transmit information about candidates and influence voter beliefs and
behavior. Other data sets tracking endorsement-level activity have
limited scope and are often disjointed by individual election contests.
Earlier more comprehensive endorsement data sets, e.g. Cohen et
al. (2008), have not maintained data from elections over the past two
decades. This project seeks to build on the comprehensive data set built
by Cohen et al. to create an up-to-date database of endorsements
beginning in 1972 up to the 2024 presidential primary.

## Repository Structure

    .
    ├── README.Rmd
    ├── README.md
    ├── data
    │   ├── processed
    │   └── raw
    │       ├── Ballotpedia
    │       ├── Codebook for endorsement data.doc
    │       ├── Democracy in Action
    │       ├── Endorsement data.xls
    │       └── Prez primary endorsements 1972-2012.xlsx
    ├── docs
    │   ├── data_sources.md
    │   ├── final_schema.md
    │   └── hidden
    │       └── review_log.csv
    ├── output
    └── scripts
        ├── extraction
        │   ├── extract_bp_2020_crossparty.R
        │   ├── extract_bp_2024_endorsements.R
        │   ├── extract_bp_master_endorsements.R
        │   ├── extract_dia_2004_labor.R
        │   ├── extract_dia_2008_labor.R
        │   ├── extract_dia_2008_newspapers.R
        │   ├── extract_dia_2008_officials.R
        │   ├── extract_dia_2008_organizations.R
        │   ├── extract_dia_2012_newspapers.R
        │   ├── extract_dia_2012_officials.R
        │   ├── extract_dia_2012_organizations.R
        │   ├── extract_dia_2016_officials.R
        │   ├── extract_dia_2016_organizations.R
        │   └── extract_dia_2020_officials.R
        └── review
            └── make_review_copies.R

- `data/raw/` — source files as acquired, with extracted (`extracted/`)
  and manually reviewed (`review/`) copies for the HTML sources
- `docs/` — data source documentation (`data_sources.md`) and the final
  dataset schema (`final_schema.md`)
- `scripts/extraction/` — one script per HTML page, extracting
  endorsements to CSV
- `scripts/review/` — creates the Excel review copies

## Data Sources

This project compiles data from the following sources (see
`docs/data_sources.md` for full documentation of structure, known
issues, and cleaning steps for each):

1.  **The Party Decides** — Cohen, Karol, Noel, and Zaller (2008);
    1980–2004 contests
2.  **FiveThirtyEight (538)** — endorsement data shared by Nathaniel
    Rakich; 1972–2012 contests
3.  **Democracy in Action** — Eric M. Appleman’s endorsement pages;
    2004–2020 contests
4.  **Ballotpedia** — presidential endorsement pages; 2012–2024 contests

The FiveThirtyEight raw file was shared through personal correspondence
and is not included in this repository. Its rows are included in the
final dataset; the raw file is available on request from
FiveThirtyEight.

## Reproducing the Pipeline

Scripts are organized by stage in `scripts/` (extraction, then review).
A single script to run the full pipeline in order will be added once the
cleaning and merging stages are written.

## Requirements

- R version \[output of `R.version.string`\]
- Key packages: `rvest`, `xml2`, `stringr`, `dplyr`, `purrr`, `tibble`
  (extraction); `readr`, `openxlsx` (review copies); `fs` (this README)

## Data Editing Notes

Manual data entry/edits are made in Excel and documented via Git commit
messages. See commit history for full change log of data edits.

## Author

Katherine Parslow, Vanderbilt University Department of Economics.
Contact: <katherine.r.parslow@vanderbilt.edu>
