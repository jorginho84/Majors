/**********************************************************************
* 16b_build_design5_rol_groupings.do
*
* Design V (issue #8): coarser application-portfolio (ROL) groupings,
* agreed on 2026-10-27 because exact ROLs are mostly unique.
*
* Each program in the student's ROL is replaced by a category and the
* ROL becomes the UNORDERED SET of categories applied to:
*   rol_oecd1      broad OECD/UNESCO field (area_conocimiento, 10)
*   rol_oecd2      ISCED-97 sub-area (cine_f_97_subarea, 22)
*   rol_fieldsel   broad field x selectivity tercile of the program
*   rol_univfield  university x broad field
*
* Program attributes (deterministic, one value per harmonized code):
*   field: most frequent value across all SIES rows of the DEMRE code
*          (sies_program_year_geo_2007_2016.dta); ties broken by the
*          alphabetical order of the value. Codes without SIES rows get
*          "Missing" (0.2% of applications).
*   selectivity: terciles (across programs, unweighted) of psu_S, the
*          mean entrant PSU in 2007-09 or the program's first three
*          years (Vacancy_shocks/01); "Missing" if absent (0.03%).
*
* Unit: student x application year (mrun ao_proceso), 2007-2016.
* Inputs:  $processed/applications.dta
*          $processed/sies_program_year_geo_2007_2016.dta (Sua/02)
*          $processed/vs_program_year_2007_2016.dta (Vacancy_shocks/01)
* Output:  $processed/design5_rol_groupings_2007_2016.dta
**********************************************************************/

clear all
set more off
do "code/config.do"

* 4-digit DEMRE codes (pre-2012) -> 5-digit format, as in 16 and 21b
capture program drop harmonize_code
program define harmonize_code
    args in out
    tempvar s
    gen `s' = strtrim(string(`in', "%12.0f"))
    gen long `out' = `in'
    replace `out' = real(substr(`s', 1, length(`s')-2) + "0" + ///
        substr(`s', length(`s')-1, 2)) if length(`s') == 4
end

/**********************************************************************
* 1. Program attributes
**********************************************************************/

use codigo_demre area_conocimiento cine_f_97_subarea ///
    using "$processed/sies_program_year_geo_2007_2016.dta", clear
drop if missing(codigo_demre)
harmonize_code codigo_demre code_h
keep code_h area_conocimiento cine_f_97_subarea
foreach v in area_conocimiento cine_f_97_subarea {
    preserve
    keep code_h `v'
    drop if strtrim(`v') == ""
    contract code_h `v', freq(nf)
    gsort code_h -nf `v'
    by code_h: gen byte tie = _N > 1 & nf[1] == nf[2]
    quietly count if tie & _n == 1
    di as text "`v': codes with a tie for the mode: " r(N)
    by code_h: keep if _n == 1
    keep code_h `v'
    tempfile m_`v'
    save `m_`v''
    restore
}
keep code_h
duplicates drop
merge 1:1 code_h using `m_area_conocimiento', nogen
merge 1:1 code_h using `m_cine_f_97_subarea', nogen
rename (area_conocimiento cine_f_97_subarea) (f1 f2)

* selectivity tercile, from the vacancy-shock panel
preserve
use code_h psu_S using "$processed/vs_program_year_2007_2016.dta", clear
bys code_h: keep if _n == 1
drop if missing(psu_S)
xtile sel3 = psu_S, nq(3)
keep code_h sel3
tempfile sel
save `sel'
restore
merge 1:1 code_h using `sel', nogen

replace f1 = "Missing" if missing(f1)
replace f2 = "Missing" if missing(f2)
gen str1 s3 = cond(missing(sel3), "M", string(sel3))
tab f1, missing
tab s3, missing
keep code_h f1 f2 s3
tempfile attrs
save `attrs'

/**********************************************************************
* 2. Applications -> category sets
**********************************************************************/

use mrun ao_proceso codigo_carrera sigla_universidad ///
    using "$processed/applications.dta", clear
keep if inrange(ao_proceso, 2007, 2016)
capture confirm numeric variable codigo_carrera
if _rc destring codigo_carrera, replace force
harmonize_code codigo_carrera code_h
replace sigla_universidad = upper(strtrim(sigla_universidad))
drop if missing(mrun, code_h)
duplicates drop mrun ao_proceso code_h, force
merge m:1 code_h using `attrs', keep(master match) nogen
replace f1 = "Missing" if missing(f1)
replace f2 = "Missing" if missing(f2)
replace s3 = "M" if s3 == ""

gen str80  c_oecd1     = f1
gen str120 c_oecd2     = f2
gen str90  c_fieldsel  = f1 + "#" + s3
gen str100 c_univfield = sigla_universidad + "#" + f1
keep mrun ao_proceso c_*
tempfile apps
save `apps'

local first 1
foreach g in oecd1 oecd2 fieldsel univfield {
    use mrun ao_proceso c_`g' using `apps', clear
    duplicates drop
    sort mrun ao_proceso c_`g'
    gen str2045 s = ""
    by mrun ao_proceso: replace s = cond(_n == 1, c_`g', s[_n-1] + "|" + c_`g')
    by mrun ao_proceso: keep if _n == _N
    egen long rol_`g' = group(s)
    keep mrun ao_proceso rol_`g'
    if !`first' merge 1:1 mrun ao_proceso using `out', nogen
    tempfile out
    save `out'
    local first 0
}

label var rol_oecd1     "ROL: set of broad OECD fields"
label var rol_oecd2     "ROL: set of ISCED-97 sub-areas"
label var rol_fieldsel  "ROL: set of broad field x selectivity tercile"
label var rol_univfield "ROL: set of university x broad field"

foreach g in oecd1 oecd2 fieldsel univfield {
    quietly distinct rol_`g'
    di as result "rol_`g': " r(ndistinct) " groups"
}

compress
save "$processed/design5_rol_groupings_2007_2016.dta", replace
di as result "design5_rol_groupings_2007_2016.dta saved."
