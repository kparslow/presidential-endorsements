# Presidential Candidate Endorsements Dataset

This repository produces a public dataset of recorded endorsements of U.S. presidential candidates.
This dataset is compiled from multiple publicly available sources and harmonized into a single, analysis-ready file.

## What this repository contains

- Goal: Create a cleaned, merged dataset of endorsements for public use
- Unit of observation: one endorsement by one endorser (or group) of one candidate on a specific date
- Coverage: primary election years 1972-2012

## Data sources

This dataset is an amalgamation of three primary sources:

1. **The Party Decides endorsement data** (Marty Cohen et al.)
  - Source files:
  - Notes:
  
2. **FiveThirtyEight endorsement data** (Nathaniel Rakich / FiveThirtyEight)
  - Source files:
  - Notes:
  
3. **Democracy in Action (DIA)** (web pages)
  - Raw HTML
  - Manual data entry:
  - Notes:
  
## Repository structure

  - `data/raw/` - original source files (do not edit)
  - `data/manual/` - manually entered data (with logs/notes)
  - `data/interim/` - intermediate cleaned outputs
  - `data/final/` - final published dataset(s) and codebook
  - `scripts/` - scripts that download, clean, and merge data
  - `docs/` - methodology, source notes, and codebook
