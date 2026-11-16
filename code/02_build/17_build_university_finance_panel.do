/**********************************************************************
* 17_build_university_finance_panel.do
*
* University finances (revenue channel behind the t-1 graduation
* coefficient of Design V). University x year panel joining finances,
* total enrollment and seats, for outcomes per enrolled student.
*
*   Unit   : university (MINEDUC cod_inst = SIES ID_IES) x year.
*            Fiscal year t of the finances = enrollment year t =
*            admission process year t.
*   Enrollment (MINEDUC matricula, 2013-2022): undergraduate students
*            (nivel_global pregrado), one row per student-program;
*            total and first-year (anio_ing_carr_ori = year). Covers
*            every program of the university, also those outside the
*            centralized admission system, as the finances do.
*   Seats  : Oferta Academica regular vacancies summed by university
*            (ProgramVA/01c, 2007-2025). DEMRE university code (first
*            two digits of the harmonized 5-digit program code) mapped
*            to cod_inst with the codigo_demre -> cod_inst pairs in the
*            matricula files 2013-2022 (modal cod_inst).
*   Per student (M$ current per student): tuition, total income, total
*            expenses, total salaries, academic salaries. Note: tuition
*            in the finances includes graduate programs, so tuition per
*            undergraduate is an upper bound; compare within university.
*
* Inputs:  $processed/ses_finance_2013_2025.dta (01_clean/08)
*          $mat_raw/Matrícula_Ed_Superior_YYYY.csv (2013-2022)
*          $processed/pva_vacancies_2007_2025.dta (ProgramVA/01c)
* Output:  $processed/university_finance_panel.dta
**********************************************************************/

clear all
set more off
do "code/config.do"

/**********************************************************************
* 1. Undergraduate enrollment by institution-year and DEMRE crosswalk
**********************************************************************/

tempfile enr cwp
local first 1
forvalues y = 2013/2022 {
    di as result "Matricula `y'"
    import delimited "$mat_raw/Matrícula_Ed_Superior_`y'.csv", ///
        delimiter(";") varnames(1) clear encoding(utf-8) stringcols(_all)
    rename *, lower
    keep cod_inst nivel_global anio_ing_carr_ori codigo_demre
    replace nivel_global = ustrlower(nivel_global)
    keep if strpos(nivel_global, "pregrado") > 0
    destring cod_inst anio_ing_carr_ori codigo_demre, replace force
    drop if missing(cod_inst)
    gen int  fy = `y'
    gen byte first_year = anio_ing_carr_ori == `y'
    preserve
        keep if codigo_demre > 0 & !missing(codigo_demre)
        contract codigo_demre cod_inst
        if !`first' append using `cwp'
        save `cwp', replace
    restore
    gen byte one = 1
    collapse (sum) enr_total = one enr_first = first_year, by(cod_inst fy)
    if !`first' append using `enr'
    save `enr', replace
    local first 0
}

* crosswalk: DEMRE university code -> modal cod_inst
use `cwp', clear
collapse (sum) _freq, by(codigo_demre cod_inst)
gen s = strtrim(string(codigo_demre, "%12.0f"))
gen long code_h = codigo_demre
replace code_h = real(substr(s, 1, length(s)-2) + "0" + substr(s, length(s)-1, 2)) if length(s) == 4
gen int u_demre = floor(code_h / 1000)
collapse (sum) _freq, by(u_demre cod_inst)
bysort u_demre: egen tot = total(_freq)
gsort u_demre -_freq
by u_demre: keep if _n == 1
gen double share = _freq / tot
list u_demre cod_inst share if share < 0.9, noobs
keep u_demre cod_inst
tempfile cw
save `cw'

/**********************************************************************
* 2. Seats by university-year
**********************************************************************/

use "$processed/pva_vacancies_2007_2025.dta", clear
gen int u_demre = floor(code_h / 1000)
collapse (sum) seats = vac, by(u_demre ao_proceso)
merge m:1 u_demre using `cw', keep(master match)
di as result "DEMRE universities without cod_inst:"
levelsof u_demre if _merge == 1
keep if _merge == 3
drop _merge
collapse (sum) seats, by(cod_inst ao_proceso)
rename ao_proceso fy
tempfile seats
save `seats'

/**********************************************************************
* 3. Panel
**********************************************************************/

use "$processed/ses_finance_2013_2025.dta", clear
keep if univ
rename id_ies cod_inst
merge 1:1 cod_inst fy using `enr', keep(master match) nogen
merge 1:1 cod_inst fy using `seats', keep(master match)
gen byte in_sua = _merge == 3
drop _merge

foreach v in aranceles ing_total gasto_total rem_total rem_acad {
    gen double pc_`v' = `v' / enr_total
}
label variable enr_total       "Undergraduate enrollment (students x programs)"
label variable enr_first       "First-year undergraduate enrollment"
label variable seats           "Regular vacancies, centralized admission (sum)"
label variable in_sua          "University with seats in the centralized admission"
label variable pc_aranceles    "Tuition per undergraduate (M$)"
label variable pc_ing_total    "Total income per undergraduate (M$)"
label variable pc_gasto_total  "Total expenses per undergraduate (M$)"
label variable pc_rem_total    "Salaries per undergraduate (M$)"
label variable pc_rem_acad     "Academic salaries per undergraduate (M$)"

tab fy in_sua
tabstat enr_total enr_first seats pc_aranceles pc_gasto_total pc_rem_acad ///
    if in_sua & fy <= 2022, by(fy) stat(mean) format(%10.1fc)

isid cod_inst fy
compress
save "$processed/university_finance_panel.dta", replace
di as result "17_build_university_finance_panel.do finished."
