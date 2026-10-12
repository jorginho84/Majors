# Deck tables → producing scripts

Map of every hardcoded `tabular` in `RDDs-Inframarginal/main.tex` (31 tabulars in 25 frames,
as of 2026-09-28) to the Stata script that produces its numbers. This is the worklist for
replacing hardcoded tables with generated `.tex` fragments under `output/`.

Line numbers refer to the deck before the Design III frames were added.

**Design numbering (2026-10-05, issue #3):** the deck now runs I (inframarginal) → II (own
sudden expansions, new) → III (SUA, formerly II) → IV (competitor vacancy shocks, formerly III).
Rows below written before that date use the old names.

**Emission today:** no SUA, cosine or inframarginal script writes `.tex`. SUA and cosine
scripts only `list` results to the log; inframarginal scripts `postfile` to csv/dta in
`$processed`. The RDD-by-field scripts (`04_rdd/03`, `07`) already write `.tex`, and so do
the four orphan files in `output/tables/` (committed in a91f9e5 with no generating script).

| Deck line | Frame | Producer | Status |
|---|---|---|---|
| 61 | Data and sample | mixed: `02_build/03_build_outcomes.do:56-58`, `04_rdd/01_rdd_enrollment.do:39-61`, orphan `output/tables/sample_overview_bw25.tex`, `descriptive_outcomes_bw25.tex` | partial; 786,071 students and 11,789 program-years have **no producer** |
| 347 | Target enrollment by field | `04_rdd/03_rdd_heterogeneity_field.do:56-150` | writes .tex |
| 386 | Univ & HE enrollment by field | same | Est/SE/N ok; **Baseline column: no producer** |
| 447 | Target graduation by field | `04_rdd/07_rdd_graduation_by_field.do:75-160` | writes .tex |
| 490 | Univ & HE graduation by field | same | **Baseline column: no producer** |
| 621 | Delta selectivity definitions | static text | nothing to generate |
| Design I (2026-10-06) | Univ. selectivity, first cohort | — | **no producer** (script 23 reads a .dta nothing builds; script 26 could do it with the `_first_enroll` panel) |
| Design I (2026-10-06) | Univ. selectivity, minimum cohort | `Inframarginals/26_...:183-422` | csv/dta |
| 1922, 1971 | SUA samples and exposure | `Sua/03c_...:228-270, 486, 662` | log only |
| 2156 | SUA levels first stage | `Sua/04_sua_levels_first_stages.do:109-722` | log only |
| appendix (`sua-fs-{lvl,log}-{entrant,positive}`) | SUA levels and log first stages, entrant regions only / positive exposure only | `Sua/04g_sua_first_stages_restricted_samples.do` | `output/tables/sua_fs_{lvl,log}_{entrant,positive}.tex` (`\input`) |
| appendix (`sua-es-{lvl,log}-{entrant,positive}`) | SUA levels and log event studies, same samples | `Sua/05_...do entrant\|positive`, `Sua/05a_...do entrant\|positive` | `output/sua_{event_study_exposure_comparison,log_event_study}_{baseline,regionyear}_{entrant,positive}.png`; pretrend p-values typed in the frame notes |
| `sua-kd-first-stage`, `sua-kd-log-first-stage` | SUA first stages with kernel-weighted denominator (levels, logs) | `Sua/Sua kernel weights/04i_sua_kernelden_first_stage_tables.do` (needs `03d`) | `output/tables/sua_fs_{lvl,log}_kd.tex` (`\input`) |
| appendix (`sua-kd-event-studies`, `sua-kd-log-event-studies`) | KD event studies | `Sua/05_...do kd`, `Sua/05a_...do kd` | `output/sua_{event_study_exposure_comparison,log_event_study}_{baseline,regionyear}_kd.png`; pretrend p-values typed in the frame notes |
| 2393 | SUA log first stage | `Sua/04b_sua_log_first_stages.do` | log only |
| 2770 | SUA similarity first stage | logs: `Sua/04e_...:495-675` | **levels columns: no producer** |
| 2883 | SUA selectivity heterogeneity | `Sua/04f_...:310-732` | log only |
| 3169, 3208 | Cosine samples and exposure | `Sua/Cosine/Cosine_Exposure_Descriptive_Statistics.do` | log only; full-sample column needs a second run (`minimum_enrollment_2011 0`) |
| 3374 | Cosine first stage | `Sua/Cosine/03_cosine_estimate_first_stages.do:517-700` | log only |
| 3598 | Non-harmonized fields | `02_build/05_build_field.do:403-418` | log only; Years column and 0.095% done by hand |

| Design II frames | Own sudden expansions: thresholds, TWFE/CS, composition, threshold robustness | `Own_expansion/02_own_expansion.do` (needs `01`, `Vacancy_shocks/03`) | `output/own_expansion/tables/oe_{thresholds,twfe_enroll,twfe_comp,threshold_sens}.tex` (`\input`); figures `oe_dV_hist_sel`, `oe_es_*_sel` |
| Design IV, selective vs selective | Exposure moments, levels/log first stages, composition, event study | `Own_expansion/03_selective_competitors.do` (needs `02`) | `output/own_expansion/tables/oe_sel_{exposure_moments,fs_N_first,fs_lnN,composition}.tex` (`\input`); figure `oe_sel_es_N_first` |
| Composition frames inside Designs I, III, IV (the separate section was removed 2026-10-06) | Entrant composition outcomes | `Own_expansion/04_composition_designs.do` (needs `01`, `02`); Design I in `Inframarginals/32` | `output/own_expansion/tables/oe_comp_{sua,vs}.tex` (`\input`); figures `oe_comp_sua_es_c_psu_mean`, `oe_comp_vs_es_c_psu_mean` |

| Design I: data, results, placebo, threshold and horizon robustness, field (issue #5) | Pooled 2007--2016, First Cohort threshold; FS/RF/2SLS with year FE and with university-year FE; placebo leads/lags figure | `Inframarginals/31_design1_main.do` (needs `21b`, `21c`, `28b`, `27`) | `output/inframarginal/tables/im_d1_{desc,main,thresholds,horizon,field}.tex`; figure `output/inframarginal/figures/im_d1_placebo.pdf` |
| Design I: composition of the entering cohort | Pooled, year FE and university-year FE | `Inframarginals/32_design1_composition.do` | `output/own_expansion/tables/oe_comp_design1.tex` |
| Design I: heterogeneity by predetermined selectivity (2 frames) | FS/RF/2SLS by quartile of 2007--09 entrant PSU; university-year FE, continuous interaction, placebo leads/lags | `Inframarginals/29_selectivity_heterogeneity_predetermined.do` (needs `21b`, `Vacancy_shocks/01`) | `output/inframarginal/tables/im_sel_{Q,G,robust,placebo}_{first,min}.tex` (`\input`) |
| Design I: selectivity heterogeneity by inframarginal population | 2SLS by quartile for all ranked / enrolled / top half / near threshold | `Inframarginals/30_selectivity_heterogeneity_population.do` (needs `21b`) | `output/inframarginal/tables/im_pop_{first,min}.tex` (`\input`) |
| Reduced form: slot shocks and inframarginal graduation (4 frames) | Designs II-IV shocks on inframarginal graduation, 8y and 10y | `Own_expansion/05_reduced_form_infra.do` (needs `21b`, `28b`, `02`; titulados through 2024) | `output/own_expansion/tables/oe_rf_{design2,sua,vs}.tex`; figures `oe_rf_{d2,sua,vs}_es_g8p_f` |

## Blocking inputs

- ~~`admission_rank_inframarginal_2007_2016.dta`~~ — now built by `02_build/15_build_admission_rank.do`
  from the raw `LUGAR` column (issue #4).
- Titulados 2017--2024 must be in `data/MINEDUC/Base Titulados/` (named `titulados_ed_superior_YYYY_web.csv`);
  without them graduation is censored after cohort 2008 (issue #4).

- **Oferta Académica** Excel files (`$demre_raw/Postulacion/OfertaAcadémica_Admisión<year>.xlsx`)
  — feed `13_build_program_year_vacancies.do` → inframarginal design I (21b, 21c, 28b).
- `weights_2004_2016.csv` — `04_clean_weights.do` cannot rebuild `weights.dta`.
- `psu2011_student_geo_psu_cells.dta` — input to `Sua/Cosine/01`, no producer in the repo.
