/**********************************************************************
* 01_build_program_year_panel.do
*
* Design III (vacancy shocks) — program × year panel, 2007-2016.
*
* Unit: DEMRE program, identified by the harmonized DEMRE code
*       (4-digit pre-2012 codes XXYY -> XX0YY, same rule as Sua/03b).
*       The harmonized code embeds the university, so it is unique.
*
* Builds, per program-year:
*   N_first       first-year enrollment (Formulario D)
*   psu_first     mean LM PSU of first-year enrollees
*   n_admitted    regular admissions (estado_preferencia == 24)
*   cutoff        regular admission cutoff (cutoffs.dta)
*   vac_demre     regular-admission vacancies (DEMRE Oferta Académica,
*                 VACANTES_1SEM) — main vacancy measure
*   vac_indices   vacancies, CNED INDICES, linked SIES -> DEMRE code
*                 (robustness; total vacancies, all admission routes)
*   field, region, university attributes
*
* Also reports the year alignment of INDICES vacancies against DEMRE
* admissions (same year vs. +/-1), which fixes the timing convention.
*
* Inputs:
*   $demre_raw/D_MATRICULA_*_PSU_MRUN.csv
*   $processed/psu_scores.dta, applications.dta, cutoffs.dta
*   $processed/sies_program_year_geo_2007_2016.dta
*   $processed/sua_university_roster_manual.dta
*   $processed/oferta_academica_2007_2016_appended.dta  (01_clean/07)
*   $raw/INDICES/BaseDefinitivaINDICES-2005-2024.csv
*
* Output:
*   $processed/vs_program_year_2007_2016.dta
**********************************************************************/

do "code/config.do"

global vs_out "$output/vacancy_shocks"
cap mkdir "$vs_out"
cap mkdir "$vs_out/tables"
cap mkdir "$vs_out/figures"

tempfile psu fd adm cut ofe ind link attrs

capture program drop harmonize_code
program define harmonize_code
    * 4-digit pre-2012 DEMRE code XXYY -> XX0YY
    syntax varname, Generate(name)
    tempvar s
    gen str12 `s' = strtrim(string(`varlist', "%12.0f"))
    gen long `generate' = `varlist'
    replace `generate' = real(substr(`s', 1, 2) + "0" + substr(`s', 3, 2)) ///
        if length(`s') == 4
end


/**********************************************************************
* 1. PSU (LM average; current score, else previous)
**********************************************************************/

use mrun ao_proceso lyc_actual mate_actual lyc_anterior mate_anterior ///
    using "$processed/psu_scores.dta", clear
keep if inrange(ao_proceso, 2007, 2016)
gen double psu_lm = (lyc_actual + mate_actual) / 2 ///
    if inrange(lyc_actual, 150, 850) & inrange(mate_actual, 150, 850)
replace psu_lm = (lyc_anterior + mate_anterior) / 2 ///
    if missing(psu_lm) & inrange(lyc_anterior, 150, 850) & inrange(mate_anterior, 150, 850)
keep mrun ao_proceso psu_lm
duplicates drop mrun ao_proceso, force
save `psu'


/**********************************************************************
* 2. First-year enrollment from Formulario D
**********************************************************************/

forvalues y = 2007/2016 {
    import delimited "$demre_raw/D_MATRICULA_`y'_PSU_MRUN.csv", ///
        delimiter(";") varnames(1) clear encoding(windows-1252)
    rename *, lower
    foreach v in mrun codigo_carrera {
        capture confirm numeric variable `v'
        if _rc destring `v', replace force
    }
    gen ao_proceso = `y'
    replace sigla_universidad = upper(itrim(ustrtrim(sigla_universidad)))
    keep mrun ao_proceso codigo_carrera sigla_universidad
    drop if missing(codigo_carrera)
    if `y' > 2007 append using `fd'
    save `fd', replace
}

merge m:1 mrun ao_proceso using `psu', keep(master match) nogen

harmonize_code codigo_carrera, generate(code_h)

collapse (count) N_first = mrun ///
         (mean) psu_first = psu_lm ///
         (firstnm) sigla_universidad, ///
         by(code_h ao_proceso)
label var N_first   "First-year enrollment (Formulario D)"
label var psu_first "Mean LM PSU, first-year enrollees"
save `fd', replace


/**********************************************************************
* 3. Regular admissions and cutoffs
**********************************************************************/

use ao_proceso codigo_carrera estado_preferencia ///
    using "$processed/applications.dta", clear
keep if estado_preferencia == $admitted
harmonize_code codigo_carrera, generate(code_h)
gen byte one = 1
collapse (sum) n_admitted = one, by(code_h ao_proceso)
label var n_admitted "Regular admissions (status 24)"
save `adm'

use codigo_carrera ao_proceso cutoff_regular using "$processed/cutoffs.dta", clear
harmonize_code codigo_carrera, generate(code_h)
collapse (min) cutoff = cutoff_regular, by(code_h ao_proceso)
label var cutoff "Regular admission cutoff"
save `cut'

* DEMRE Oferta Académica: regular vacancies, keyed by DEMRE code
use ao_proceso CODIGO VACANTES_1SEM TOTAL_CUPOS ///
    using "$processed/oferta_academica_2007_2016_appended.dta", clear
drop if missing(CODIGO)
harmonize_code CODIGO, generate(code_h)
collapse (max) vac_demre = VACANTES_1SEM cupos_demre = TOTAL_CUPOS, by(code_h ao_proceso)
label var vac_demre   "Regular vacancies (DEMRE Oferta, 1st semester)"
label var cupos_demre "Total seats incl. extra quotas (DEMRE Oferta)"
save `ofe'

di as text _n "DEMRE vacancies vs regular admissions"
merge 1:1 code_h ao_proceso using `adm', keep(match) nogen
gen lv = ln(vac_demre)
gen la = ln(n_admitted)
corr lv la
gen r = n_admitted / vac_demre
summarize r, detail


/**********************************************************************
* 4. INDICES vacancies, linked SIES code -> DEMRE code
*
* Column positions (header has accents Stata mangles):
*   1 Año, 4 Tipo Institución, 5 Clasificación1 (CRUCH / private),
*   6 Clasificación2 (state / private within CRUCH),
*   50 Vacantes, 55 Matrícula Primer Año, 60 Código SIES, 61 Pregrado/Posgrado
**********************************************************************/

import delimited "$raw/INDICES/BaseDefinitivaINDICES-2005-2024.csv", ///
    varnames(nonames) rowrange(2) delimiter(",") bindquote(strict) ///
    encoding(utf-8) stringcols(_all) clear

keep v1 v4 v5 v6 v50 v55 v60 v61
rename (v1 v4 v5 v6 v50 v55 v60 v61) ///
       (year tipo_inst clasif1 clasif2 vacantes mat1_indices codigo_unico nivel)
keep if nivel == "Pregrado"
destring year, replace
keep if inrange(year, 2006, 2016)
destring vacantes mat1_indices, replace ignore(",") force
replace codigo_unico = strtrim(codigo_unico)
drop if codigo_unico == "" | missing(vacantes)
gen byte cruch = strpos(clasif1, "CRUCH") > 0
gen byte state = strpos(clasif2, "Estatal") > 0
collapse (sum) vacantes mat1_indices (max) cruch state, by(codigo_unico year)
save `ind'

* SIES -> DEMRE link, per year
use codigo_unico ao_proceso codigo_demre ///
    using "$processed/sies_program_year_geo_2007_2016.dta", clear
drop if missing(codigo_demre) | codigo_unico == ""
duplicates drop
harmonize_code codigo_demre, generate(code_h)
keep codigo_unico ao_proceso code_h
save `link'

* Year alignment check: INDICES year = ao_proceso + lag, lag in {-1,0,1}
use `adm', clear
tempfile admcheck
save `admcheck'

di as text _n "Year alignment of INDICES vacancies vs DEMRE admissions"
foreach lag in -1 0 1 {
    use `link', clear
    gen year = ao_proceso + `lag'
    merge m:1 codigo_unico year using `ind', keep(match) nogen
    collapse (sum) vacantes, by(code_h ao_proceso)
    merge 1:1 code_h ao_proceso using `admcheck', keep(match) nogen
    gen lv = ln(vacantes)
    gen la = ln(n_admitted)
    quietly corr lv la
    di as result "  lag `lag': corr(log vac, log admitted) = " %5.3f r(rho) ///
        "   N = " r(N)
}

* Main linkage: same year (adjust here if the check above says otherwise)
use `link', clear
gen year = ao_proceso
merge m:1 codigo_unico year using `ind', keep(match) nogen
collapse (sum) vac_indices = vacantes mat1_indices (max) cruch state, by(code_h ao_proceso)
label var vac_indices  "Vacancies (CNED INDICES)"
label var mat1_indices "First-year enrollment (CNED INDICES)"
save `ind', replace


/**********************************************************************
* 5. Program attributes: field, region, university status
**********************************************************************/

use codigo_demre ao_proceso area_conocimiento area_carrera_generica ///
    id_region_2018 sigla_universidad entrant_2012 sua_incumbent ///
    using "$processed/sies_program_year_geo_2007_2016.dta", clear
drop if missing(codigo_demre)
harmonize_code codigo_demre, generate(code_h)
* one attribute row per program: modal / first non-missing across years
bys code_h (ao_proceso): keep if _n == 1
keep code_h area_conocimiento area_carrera_generica id_region_2018 ///
    entrant_2012 sua_incumbent
rename (area_conocimiento area_carrera_generica id_region_2018) ///
       (field generic_field region)
save `attrs'


/**********************************************************************
* 6. Assemble
**********************************************************************/

use `fd', clear
merge 1:1 code_h ao_proceso using `adm', nogen
merge 1:1 code_h ao_proceso using `cut', keep(master match) nogen
merge 1:1 code_h ao_proceso using `ofe', keep(master match) nogen
merge 1:1 code_h ao_proceso using `ind', keep(master match) nogen
merge m:1 code_h using `attrs', keep(master match) gen(_attr)

keep if inrange(ao_proceso, 2007, 2016)
* CRUCH status is a university attribute: fill across years and programs
* (before 2012 only CRUCH universities were in DEMRE, so every incumbent
*  is CRUCH; the useful split is state vs. private CRUCH)
foreach v in cruch state {
    bys sigla_universidad: egen byte `v'_u = max(`v')
    replace `v' = `v'_u
    drop `v'_u
}
label var cruch "CRUCH university"
label var state "State university"
replace N_first    = 0 if missing(N_first)
replace n_admitted = 0 if missing(n_admitted)

* University fills from admissions-only rows
bys code_h (sigla_universidad): replace sigla_universidad = sigla_universidad[_N] ///
    if sigla_universidad == ""

egen long pid = group(code_h)
label var pid "Program id (harmonized DEMRE code)"

* Pre-period (2007-2009) program characteristics
foreach v in N_first psu_first {
    bys pid: egen `v'_pre = mean(cond(inrange(ao_proceso, 2007, 2009), `v', .))
}
label var N_first_pre   "Mean first-year enrollment, 2007-2009"
label var psu_first_pre "Mean entrant PSU, 2007-2009"

compress
order pid code_h sigla_universidad ao_proceso
sort pid ao_proceso
isid pid ao_proceso
save "$processed/vs_program_year_2007_2016.dta", replace


/**********************************************************************
* 7. Coverage report
**********************************************************************/

di as text _n "Coverage by year"
tabstat N_first n_admitted vac_demre vac_indices cutoff, ///
    by(ao_proceso) statistics(n mean) columns(statistics) format(%9.1f)

gen byte has_vac = !missing(vac_demre)
gen byte has_attr = _attr == 3
tab ao_proceso has_vac
tab ao_proceso has_attr

di as result "vs_program_year_2007_2016.dta saved."
