/**********************************************************************
* 18_build_university_entrants_fields.do
*
* University-year inputs for the finance check of the T-1 graduation
* coefficient (45_finance_seats_rf.do), admission years 2007-2022:
*
*   E   : first-year entrants through the centralized admission (DEMRE
*         D_MATRICULA, one row per enrolled student; from 2017 only the
*         regular route, VIA_INGRESO / VIA_ADMISION = 1), summed over
*         the university's programs
*   V   : regular vacancies of the university's programs (Oferta
*         Academica, ProgramVA/01c), summed. Equals `seats' of 17 in
*         2013-2022 and extends it back to 2007 for lags.
*   sh# : share of each knowledge area (MINEDUC area_conocimiento: 10
*         areas plus "Sin area definida", 11 categories) in the
*         university's undergraduate enrollment, 2013-2022
*
*   Program codes: 4-digit pre-2012 codes XXYY -> XX0YY. A program
*   belongs to the university given by its first two digits; the map to
*   the MINEDUC/SIES institution code (cod_inst) comes from the DEMRE
*   files that carry both codes (COD_IES, 2021-2022).
*
* Inputs:  $demre_raw/D_MATRICULA_YYYY_PSU_MRUN.csv (2007-2022)
*          $processed/pva_vacancies_2007_2025.dta (ProgramVA/01c)
*          $mat_raw/Matrícula_Ed_Superior_YYYY.csv (2013-2022)
* Output:  $processed/university_entrants_fields.dta (cod_inst x fy)
**********************************************************************/

clear all
set more off
do "code/config.do"

/**********************************************************************
* 1. DEMRE entrants by program-year, and DEMRE code -> cod_inst
**********************************************************************/

tempfile enr cw
local first 1
forvalues y = 2007/2022 {
    import delimited "$demre_raw/D_MATRICULA_`y'_PSU_MRUN.csv", delimiter(";") ///
        varnames(1) clear stringcols(_all)
    * regular admission route only (the column exists from 2017)
    capture confirm variable via_ingreso
    if !_rc keep if strtrim(via_ingreso) == "1"
    capture confirm variable via_admision
    if !_rc keep if strtrim(via_admision) == "1"
    capture confirm variable cod_ies
    local hasies = !_rc
    destring codigo_carrera, gen(code) force
    drop if missing(code)
    gen long code_h = cond(code < 10000, floor(code / 100) * 1000 + mod(code, 100), code)
    if `hasies' {
        preserve
        destring cod_ies, gen(cod_inst) force
        gen int u_demre = floor(code_h / 1000)
        contract u_demre cod_inst
        capture append using `cw'
        save `cw', replace
        restore
    }
    gen byte one = 1
    collapse (sum) enr = one, by(code_h)
    gen int ao_proceso = `y'
    if !`first' append using `enr'
    save `enr', replace
    local first 0
}

use `cw', clear
drop if missing(cod_inst)
collapse (sum) _freq, by(u_demre cod_inst)
bysort u_demre (_freq): keep if _n == _N
keep u_demre cod_inst
save `cw', replace
list, clean noobs

/**********************************************************************
* 2. Vacancies + entrants by program-year -> university-year
**********************************************************************/

use "$processed/pva_vacancies_2007_2025.dta", clear
keep if ao_proceso <= 2022
merge 1:1 code_h ao_proceso using `enr'
* every DEMRE program-year should have vacancies
count if _merge == 2
assert r(N) == 0
drop _merge
replace enr = 0 if missing(enr)
gen int u_demre = floor(code_h / 1000)
merge m:1 u_demre using `cw', keep(master match)
count if _merge == 1
assert r(N) == 0
drop _merge
collapse (sum) E = enr V = vac, by(cod_inst ao_proceso)
rename ao_proceso fy
label variable E "First-year entrants, centralized admission, regular route (DEMRE)"
label variable V "Regular vacancies, centralized admission (Oferta Academica)"
tempfile uni
save `uni'

/**********************************************************************
* 3. Knowledge-area shares of undergraduate enrollment (MINEDUC)
**********************************************************************/

tempfile ar
local first 1
forvalues y = 2013/2022 {
    import delimited "$mat_raw/Matrícula_Ed_Superior_`y'.csv", ///
        delimiter(";") varnames(1) clear encoding(utf-8) stringcols(_all)
    rename *, lower
    keep cod_inst nivel_global area_conocimiento
    replace nivel_global = ustrlower(nivel_global)
    keep if strpos(nivel_global, "pregrado") > 0
    destring cod_inst, replace force
    drop if missing(cod_inst)
    contract cod_inst area_conocimiento
    gen int fy = `y'
    if !`first' append using `ar'
    save `ar', replace
    local first 0
}
tab area_conocimiento
egen int a = group(area_conocimiento)
bysort cod_inst fy: egen double tot = total(_freq)
gen double sh = _freq / tot
keep cod_inst fy a sh
reshape wide sh, i(cod_inst fy) j(a)
foreach v of varlist sh* {
    replace `v' = 0 if missing(`v')
    label variable `v' "Share of undergraduate enrollment, knowledge area `=substr("`v'", 3, .)'"
}

/**********************************************************************
* 4. Save
**********************************************************************/

merge 1:1 cod_inst fy using `uni'
tab fy _merge
drop if _merge == 1
drop _merge
order cod_inst fy E V
sort cod_inst fy
compress
save "$processed/university_entrants_fields.dta", replace

di as result "18_build_university_entrants_fields.do finished."
