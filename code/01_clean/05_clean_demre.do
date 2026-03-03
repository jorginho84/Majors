/*------------------------------------------------------------------------------
                    Threshold-Crossing Effects in Higher Education

                    05_clean_demre.do

                    Cleans and appends DEMRE Formulario D enrollment data.

                    Formulario D records the program each PSU applicant actually
                    enrolled in, as reported to DEMRE. One record per student
                    per year. Used to recover target-program enrollment when
                    codigo_demre is missing in the MINEDUC Matricula data.

                    Input:  $demre_raw/D_MATRICULA_YYYY_PSU_MRUN.csv
                    Output: $processed/enrollment_demre.dta
------------------------------------------------------------------------------*/

do "code/config.do"

*-------------------------------------------------------------------------------
* Import and append Formulario D files (2007-2016)
*-------------------------------------------------------------------------------

local y = $year_start

import delimited "$demre_raw/D_MATRICULA_`y'_PSU_MRUN.csv", ///
    delimiter(";") varnames(1) clear encoding(windows-1252)

rename *, lower

* Handle garbled año_proceso column (ñ encoding variants)
capture rename año_proceso  ao_proceso
capture rename ano_proceso  ao_proceso
capture rename a_o_proceso  ao_proceso
capture rename aæo_proceso  ao_proceso

* Keep only what we need for target-program matching
keep mrun ao_proceso codigo_carrera

destring mrun codigo_carrera ao_proceso, replace force

tempfile demre
save `demre'

forvalues y = `=$year_start + 1'/$year_end {

    import delimited "$demre_raw/D_MATRICULA_`y'_PSU_MRUN.csv", ///
        delimiter(";") varnames(1) clear encoding(windows-1252)

    rename *, lower

    capture rename año_proceso  ao_proceso
    capture rename ano_proceso  ao_proceso
    capture rename a_o_proceso  ao_proceso
    capture rename aæo_proceso  ao_proceso

    keep mrun ao_proceso codigo_carrera

    destring mrun codigo_carrera ao_proceso, replace force

    append using `demre', force
    save `demre', replace
}

*-------------------------------------------------------------------------------
* Clean and deduplicate
*-------------------------------------------------------------------------------

drop if mrun == . | codigo_carrera == . | ao_proceso == .

* Formulario D should have one record per student per year (actual enrollment)
duplicates report mrun ao_proceso
duplicates drop mrun ao_proceso, force

label variable mrun           "Student ID"
label variable ao_proceso     "Enrollment year"
label variable codigo_carrera "DEMRE program code (enrolled)"

*-------------------------------------------------------------------------------
* Validation
*-------------------------------------------------------------------------------

tab ao_proceso
count
di "Total DEMRE enrollment records: " r(N)

*-------------------------------------------------------------------------------
* Save
*-------------------------------------------------------------------------------

compress
save "$processed/enrollment_demre.dta", replace

di _n "DEMRE enrollment data saved to: $processed/enrollment_demre.dta"
