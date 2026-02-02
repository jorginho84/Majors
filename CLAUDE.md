# Majors - RDD Analysis of College Major Eligibility

Research project analyzing threshold-crossing effects in Chilean higher education using regression discontinuity design (RDD).

## Workflow Rules

1. **Server execution**: Run commands on the server without asking for permission
2. **Code lives locally**: All edits happen locally, Git repo is local only
3. **Always sync before running**: After modifying any code, sync to server before executing
4. **Server is for running only**: Never edit files directly on the server

## Project Structure

```
code/
  config.do              # Main configuration (paths, globals)
  config_user.do         # User-specific overrides (gitignored)
  00_master.do           # Master script to run full pipeline
  01_clean/              # Data cleaning scripts
  02_build/              # Build analysis variables (cutoffs, running var)
  04_rdd/                # RDD estimation and figures
  ado/                   # Custom Stata ado files
data/
  processed/             # Cleaned datasets (.dta)
  PSU_scores/            # Raw PSU test scores
  MINEDUC/               # Ministry data (Applications, Enrollment, Graduates)
output/
  tables/                # Regression tables (.tex)
  figures/               # RDD plots (.pdf)
old/                     # Legacy code (reference only)
```

## Running Scripts

**All scripts must be run from project root** (not from code/ subdirectory).

### Server (jrodriguezo)
```bash
cd /home/jrodriguezo/majors
/usr/local/stata17/stata-mp -b do code/01_clean/01_clean_psu.do
```

### Local
Create `config_user.do` with your local root path (see `config_user_template.do`).

## Key Conventions

### Variable Naming
- Use `ao_proceso` (not `año_proceso`) - avoids CSV encoding issues with ñ
- **Auto-fix**: When encountering `año_proceso` in code, replace with `ao_proceso` without asking
- All variable names lowercase after import

### Config Loading
Scripts use relative path: `do "code/config.do"` (not `do "$code/config.do"`)
This is because `$code` global is not defined until config.do runs.

### Application Status Codes
- 24 = Admitted
- 25 = Waiting list
- 26 = Rejected
- Other codes (9, 16, 17, 31, 36) also exist and are valid

## Data Pipeline

1. **01_clean/** - Import and clean raw CSVs → .dta files
   - psu_scores.dta, applications.dta, enrollment.dta, weights.dta

2. **02_build/** - Construct analysis variables
   - cutoffs.dta (admission cutoffs by program-year)
   - applications_rd.dta (with running variable)
   - analysis_sample.dta (merged with outcomes)

3. **04_rdd/** - Estimation and visualization
   - RDD regressions, figures

## Parameters (in config.do)

- Years: 2007-2016
- RDD bandwidth: 25 points
- Stata scheme: s2color

## Server Details

- Host: 192.168.20.25
- User: jrodriguezo
- Path: /home/jrodriguezo/majors
- Stata: /usr/local/stata17/stata-mp (MP license)

## Sync Local to Server

```bash
rsync -avz --exclude '.git' --exclude '*.dta' --exclude 'data/' \
  /Users/jorge-home/Documents/Research/Majors/ \
  jrodriguezo@192.168.20.25:/home/jrodriguezo/majors/
```