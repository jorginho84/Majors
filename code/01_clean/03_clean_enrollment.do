/*------------------------------------------------------------------------------
                    Threshold-Crossing Effects in Higher Education

                    03_clean_enrollment.do

                    Cleans and appends enrollment (matrícula) data across years.

                    Based on legacy code: 03_returns.do (Section 3: Enrollment - MINEDUC)

                    Input:  $mat_raw/Matrícula_Ed_Superior_YYYY.csv
                    Output: $processed/enrollment.dta
------------------------------------------------------------------------------*/

do "$code/config.do"

*-------------------------------------------------------------------------------
* Import and process enrollment data year by year
*-------------------------------------------------------------------------------

* Process first year
local y = $year_start

import delimited "$mat_raw/Matrícula_Ed_Superior_`y'.csv", ///
    delimiter(";") varnames(1) clear encoding(utf-8)

* Standardize variable names to lowercase
rename *, lower

* Rename mrun if needed (legacy code used numero_documento_inn)
capture rename numero_documento_inn mrun

* Destring key variables
destring mrun, replace force
destring codigo_demre, replace force

* Keep only undergraduate (pregrado)
replace nivel_global = lower(nivel_global)
keep if strpos(nivel_global, "pregrado") > 0

* Standardize institution type
replace tipo_inst_1 = lower(tipo_inst_1)

*-------------------------------------------------------------------------------
* Handle multiple enrollments per student
* Priority: Universidad > IP > CFT
* (Following legacy code logic)
*-------------------------------------------------------------------------------

* Generate institution type indicators
tab tipo_inst_1, gen(inst_)

* Identify best institution type per student
* Assuming: inst_1=CFT, inst_2=IP, inst_3=Universidad (check actual order)
capture {
    bysort mrun: egen has_cft = max(inst_1)
    bysort mrun: egen has_ip = max(inst_2)
    bysort mrun: egen has_uni = max(inst_3)
    bysort mrun: gen N = _N

    * Keep university if enrolled in multiple institution types
    drop if N > 1 & has_cft == 1 & (has_ip + has_uni) >= 1
    drop if N > 1 & has_ip == 1 & has_uni >= 1

    drop N has_cft has_ip has_uni inst_*
}

* Prefer records with DEMRE code when duplicates exist
gen has_demre = codigo_demre != .
bysort mrun: egen any_demre = max(has_demre)
bysort mrun: gen N = _N
drop if N > 1 & any_demre == 1 & codigo_demre == .
drop has_demre any_demre N

* Final deduplication: keep one record per student
duplicates drop mrun, force

* Add year variable
gen año_proceso = `y'

tempfile enrollment
save `enrollment'

*-------------------------------------------------------------------------------
* Append remaining years
*-------------------------------------------------------------------------------

forvalues y = `=$year_start + 1'/$year_end {

    import delimited "$mat_raw/Matrícula_Ed_Superior_`y'.csv", ///
        delimiter(";") varnames(1) clear encoding(utf-8)

    rename *, lower
    capture rename numero_documento_inn mrun

    destring mrun, replace force
    destring codigo_demre, replace force

    * Keep only undergraduate
    replace nivel_global = lower(nivel_global)
    keep if strpos(nivel_global, "pregrado") > 0

    replace tipo_inst_1 = lower(tipo_inst_1)

    * Handle multiple enrollments (same logic as above)
    capture {
        tab tipo_inst_1, gen(inst_)
        bysort mrun: egen has_cft = max(inst_1)
        bysort mrun: egen has_ip = max(inst_2)
        bysort mrun: egen has_uni = max(inst_3)
        bysort mrun: gen N = _N
        drop if N > 1 & has_cft == 1 & (has_ip + has_uni) >= 1
        drop if N > 1 & has_ip == 1 & has_uni >= 1
        drop N has_cft has_ip has_uni inst_*
    }

    gen has_demre = codigo_demre != .
    bysort mrun: egen any_demre = max(has_demre)
    bysort mrun: gen N = _N
    drop if N > 1 & any_demre == 1 & codigo_demre == .
    drop has_demre any_demre N

    duplicates drop mrun, force

    gen año_proceso = `y'

    append using `enrollment', force
    save `enrollment', replace
}

*-------------------------------------------------------------------------------
* Clean variables
*-------------------------------------------------------------------------------

* Keep relevant variables
keep mrun año_proceso codigo_demre cod_inst nomb_inst nomb_carrera tipo_inst_1 ///
     nivel_global

* Clean text variables (remove accents, lowercase)
foreach var of varlist nomb_inst nomb_carrera {
    capture {
        replace `var' = lower(`var')
        replace `var' = subinstr(`var', "á", "a", .)
        replace `var' = subinstr(`var', "é", "e", .)
        replace `var' = subinstr(`var', "í", "i", .)
        replace `var' = subinstr(`var', "ó", "o", .)
        replace `var' = subinstr(`var', "ú", "u", .)
        replace `var' = subinstr(`var', "ñ", "n", .)
        replace `var' = subinstr(`var', "ü", "u", .)
        replace `var' = subinstr(`var', "Á", "a", .)
        replace `var' = subinstr(`var', "É", "e", .)
        replace `var' = subinstr(`var', "Í", "i", .)
        replace `var' = subinstr(`var', "Ó", "o", .)
        replace `var' = subinstr(`var', "Ú", "u", .)
        replace `var' = subinstr(`var', "Ñ", "n", .)
        replace `var' = subinstr(`var', "Ü", "u", .)
    }
}

*-------------------------------------------------------------------------------
* Create enrollment indicators
* (Following legacy code)
*-------------------------------------------------------------------------------

* Enrolled in higher education (any type)
gen enrolls_he = 1

* Enrolled in university
gen enrolls_uni = strpos(tipo_inst_1, "universidad") > 0

label variable enrolls_he "Enrolled in higher education"
label variable enrolls_uni "Enrolled in university"

*-------------------------------------------------------------------------------
* Label variables
*-------------------------------------------------------------------------------

label variable mrun "Student ID"
label variable año_proceso "Enrollment year"
label variable codigo_demre "DEMRE program code"
label variable cod_inst "Institution code"
label variable nomb_inst "Institution name"
label variable nomb_carrera "Program name"
label variable tipo_inst_1 "Institution type"

*-------------------------------------------------------------------------------
* Basic validation
*-------------------------------------------------------------------------------

* Check year range
tab año_proceso

* Check enrollment indicators
tab enrolls_uni

* Summary stats
di _n "=== Enrollment Summary ==="
di "Years: $year_start - $year_end"
count
di "Total observations: " r(N)
distinct mrun
di "Unique students: " r(ndistinct)

tab año_proceso enrolls_uni

*-------------------------------------------------------------------------------
* Save
*-------------------------------------------------------------------------------

compress
save "$processed/enrollment.dta", replace

di _n "Enrollment data saved to: $processed/enrollment.dta"
