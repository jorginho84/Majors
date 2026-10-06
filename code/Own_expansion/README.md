# Own_expansion — Design II, Design IV selective variant, composition effects

Issue: [#3](https://github.com/jorginho84/Majors/issues/3). Run from the project root, in order:

| Script | What it does | Output |
|---|---|---|
| `00_helpers.do` | `oe_stars`, `oe_es` (dynamic TWFE + Callaway–Sant'Anna event study, one figure) | — |
| `01_build_composition.do` | Entrant composition per program-year (PSU mean/SD, NEM, % female, % private-paid / municipal school, PSU and school of the last admitted) | `$processed/oe_composition_program_year.dta` |
| `02_own_expansion.do` | **Design II**: own sudden vacancy shock (Design IV definition) → own vacancies, enrollment, composition; TWFE, event study, CS | `$processed/oe_panel.dta`, `output/own_expansion/*/oe_*` |
| `03_selective_competitors.do` | **Design IV, selective vs selective**: exposure from shocks at selective programs, selective incumbents, selective-market denominator | `output/own_expansion/*/oe_sel_*` |
| `04_composition_designs.do` | Composition outcomes in Designs I (FD-IV), III (SUA levels), IV (competitor shocks) | `output/own_expansion/*/oe_comp_*` |

Inputs from other folders: `Vacancy_shocks/01–03` (`vs_panel_exposure.dta`, `vs_similarity_pairs.dta`),
`Sua/03` (`sua_incumbent_panel_w_broad_area_region_2007_2016.dta`), `02_build/13`
(`program_year_vacancies_2007_2016.dta`), `analysis_sample_with_fields_final.dta`.

Notes
- `GRUPO_DEPENDENCIA` (Formulario A): 1–2 municipal, 3 private subsidized, **4 private paid**, 5 delegated administration.
- Selective = top 20% of 2007–2009 mean entrant PSU (predetermined), not the post-2012 flag of `02_build/08`.
- Income is not in the data; school dependency is the SES proxy.
- The CS pretrend p-value is the test of the pre-period average (`Pre_avg`). `estat pretrend` rejects mechanically with one or two treated units per cohort.
