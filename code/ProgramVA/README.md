# Program value-added (issue #9)

Mountjoy & Hickman (2021), "The Returns to College(s)", adapted to the DEMRE deferred acceptance.

**Idea.** Compare students who were admitted to the same set of options but ended up in different programs. Under DA, a student's assignment is the top-ranked program in their ROL where they are *feasible* (score ≥ cutoff). So:

- **portfolio** = cohort × the unordered set of feasible ROL programs;
- **treatment variation** = the order of the ROL inside that set.

Crossing a cutoff changes the portfolio, so the RD variation is absorbed by the portfolio FE. VA is identified within portfolios, from variation disjoint from the RD.

## Run order (from project root, on the server)

| Script | Does | Output |
|---|---|---|
| `00_va_helpers.do` | Programs shared by 02 and 04 (controls, identifying sample, connected set, VA with centred vcov, signal/noise) | — |
| `01_build_feasibility.do` | Weighted score for every ROL entry, feasibility, validation, portfolios, treatments (assigned / enrolled), controls, graduation outcomes | `pva_students_2007_2016.dta`, `pva_applications_2007_2016.dta`, `output/tables/pva_feasibility_validation.csv` |
| `01b_build_income_rank.do` | Main outcome: Mi Futuro income rank of the program the student graduates from within 8 years (0 if no title) | adds `inc_rank`, `grad_any_8y` to `pva_students_2007_2016.dta`; `pva_mifuturo_index.dta` |
| `01c_build_vacancies_2007_2025.do` | Regular vacancies (1st + 2nd semester) from DEMRE Oferta Académica 2007–2025 (2017–2025 from Dropbox BEA); program names with accents (double-encoded years repaired) | `pva_vacancies_2007_2025.dta`, `pva_program_names.dta` |
| `02_estimate_va.do` | Identifying sample, largest connected set, ladder raw → typical → baseline → main, balance test, centered VA with full vcov, signal/noise SD, EB | `pva_program_va.dta`, `pva_univ_va.dta`, `output/tables/pva_dispersion.csv` |
| `03_va_correlates.do` | VA vs average PSU, field, vacancies (level, growth, evolution by VA tercile) | `output/tables/pva_correlates.csv`, `pva_field.csv`, `pva_vacancies_by_tercile_*.csv`, `output/figures/pva_*.pdf` |
| `04_diagnostics_figures.do` | Balance figures, VA histogram, binned correlates, institution share, vacancies by VA decile and top 5% (2007–2025), mean VA by institution, names of top-decile programs | `output/figures/ProgramVA/`, `output/tables/pva_inst_share.csv`, `pva_vacancies_by_decile*.csv`, `pva_mean_va_by_institution.csv`, `pva_top_programs*.tex` |
| `04b_split_sample.do` | Split-sample reliability (odd/even cohorts), stability (2007–11 vs 2012–16), sensitivity to controls. Slow (~40 min) | `pva_split_*.pdf`, `pva_sensitivity_controls.pdf`, `output/tables/pva_split_sample.csv` |
| `05_forecast_bias.do` | Forecast-bias test against the RD at each oversubscribed cutoff (AHPW 2017): 2SLS of Y on VA of the assigned program, instruments Z × 10 bins of the predicted jump v̂_j − v̂_k, Hansen J, omnibus test, placebo on predicted outcome. Cross-fit VA (random student halves) and full-sample VA, EB and unshrunk; also cutoffs with large j and k. Per-cutoff local-linear RDs. ~1.5 h | `output/tables/pva_forecast_bias.csv/.tex`, `pva_forecast_bias_cutoffs.csv`, `pva_forecast_bias_*.pdf` |

`run_all.sh [first_script]` runs the chain from a given script and stops on the first `r()` error in a log.

Deck: first section of `slides/RDDs-Inframarginal/main.tex` (Step 0).

## Definitions

- **Feasible at j**: status ∈ {24, 25, 26}. If j has a waiting list, the score must also be ≥ the first-round cutoff (`cutoffs.dta`); if it has none, every eligible applicant is feasible.
- **Score**: official `PUNTAJE` when > 0, otherwise recomputed from `weights.dta`, using the best of current and previous-year PSU. The weights are fractions (sum ≈ 1) in every year; the scale is still detected from the weights themselves. `02_build/01–02` divide by 100 instead, which gives scores of ~6 when the official score is missing (not fixed).
- **Versions**:
  - `itt`: assigned program, `port_bin` (main).
  - `enr`: enrolled program from Formulario D, which must be on the ROL. The portfolio adds that program, which covers waitlist calls.
  - `ter`: assigned program, with a portfolio that also includes the applied-but-infeasible programs.
- **Programs** are harmonized 5-digit DEMRE codes (4-digit pre-2012 codes are converted as in `02_build/16`).
- **Outcome (main)** `inc_rank`: percentile (1–100) among the sample's graduates of the Mi Futuro income index of the program of the student's first undergraduate title within 8 years (entered in t or later). It is 0 for students with no title. The index is log mean income in the 4th year after the title (bracket midpoint), demeaned by reference year and averaged over 2017–2024.
  - Mi Futuro's unit is institution × carrera genérica. The title's `codigo_unico` is mapped to it through `area_generica` in the raw titulados files.
  - Fallbacks when that cell has no income: national mean of the carrera genérica, then institution mean.
  - The raw files "2010–2015" duplicate "2018–2023" and are dropped.
  - Source: `data/MINEDUC/Mifuturo/08_mifuturo_supply.dta`, a copy of `~/Documents/mifuturo/data/` built by `cuposBEA/01_code/02c_mifuturo_supply_data.do`.
  - Placeholder until individual earnings are available.
- **Outcome (secondary)** `grad_any_8y`: any undergraduate title within 8 years.
- **VA** is relative to the enrollment-weighted mean over the connected set.
- **Classification** (deciles, top 5%, examples, institution ranges): deciles of *programs* by EB VA among programs with ≥ 20 students in the identifying sample (1,318 of 1,665). Robust SEs understate the noise of smaller programs: for n < 5 the SD of the estimates is ~3× the reported SE, so EB does not shrink them.
- **Run detached** on the server: `setsid nohup bash code/ProgramVA/run_all.sh <first> > pva_run_all.out 2>&1 < /dev/null &` survives closing the ssh session.
