/**********************************************************************
* 01c_build_vacancies_2007_2025.do
*
* Program value-added (issue #9): program-year regular vacancies from the
* DEMRE Oferta Académica, admission years 2007-2025.
*
*   vac = VACANTES_1SEM + VACANTES_2SEM (regular seats). This is the only
*   vacancy concept present in every year: TOTAL_CUPOS (regular +
*   sobrecupo + BEA) disappears from 2023 on, and its definition changes
*   in 2020-2022.
*
* Program code: CODIGO (2007-2017, 2020-2023) or CODIGO_CARRERA (2018,
* 2019, 2024, 2025); 4-digit pre-2012 codes harmonized to 5 digits.
* Files 2017-2025 come from Dropbox BEA/06_affirmative_action
* (05_documents and 00_Nueva estructura/01_data/10_high_school), copied
* to data/DEMRE/Postulacion with the same names as 2007-2016.
*
* Output: $processed/pva_vacancies_2007_2025.dta (code_h x ao_proceso)
**********************************************************************/

clear all
set more off
do "code/config.do"

capture log close
log using "$logs/pva_01c_build_vacancies.log", replace text

capture program drop harmonize_code
program define harmonize_code
    args in out
    tempvar s
    gen `s' = strtrim(string(`in', "%12.0f"))
    gen long `out' = `in'
    replace `out' = real(substr(`s', 1, length(`s')-2) + "0" + ///
        substr(`s', length(`s')-1, 2)) if length(`s') == 4
end

tempfile vac
forvalues y = 2007/2025 {
    import excel using "$demre_raw/Postulacion/OfertaAcadémica_Admisión`y'.xlsx", ///
        firstrow clear allstring
    rename *, upper
    capture rename CODIGO_CARRERA CODIGO
    keep CODIGO VACANTES_1SEM VACANTES_2SEM
    destring CODIGO VACANTES_1SEM VACANTES_2SEM, replace force
    drop if missing(CODIGO)
    gen double vac = cond(missing(VACANTES_1SEM), 0, VACANTES_1SEM) + ///
                     cond(missing(VACANTES_2SEM), 0, VACANTES_2SEM)
    gen int ao_proceso = `y'
    keep CODIGO ao_proceso vac
    if `y' > 2007 append using `vac'
    save `vac', replace
}

harmonize_code CODIGO code_h
collapse (sum) vac, by(code_h ao_proceso)
replace vac = . if vac <= 0
label var vac "Regular vacancies (1st + 2nd semester), Oferta Academica"

di as result "=== Programs and total regular vacancies by year ==="
tabstat vac, by(ao_proceso) stat(n sum)

compress
save "$processed/pva_vacancies_2007_2025.dta", replace

log close
