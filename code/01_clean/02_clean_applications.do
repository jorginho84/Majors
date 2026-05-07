/*------------------------------------------------------------------------------
                    Threshold-Crossing Effects in Higher Education

                    02_clean_applications.do

                    Cleans and appends application data across years.

                    Input:  $app_raw/C_POSTULACIONES_SELECCION_PSU_YYYY_PRIV_MRUN.csv
                    Output: $processed/applications.dta
------------------------------------------------------------------------------*/

do "code/config.do"

*-------------------------------------------------------------------------------
* Import and append applications across years
*-------------------------------------------------------------------------------

* Helper macro: standardize puntaje to numeric within each year.
* Must run immediately after import, before appending, to avoid type conflicts
* across years (2007-2015 use integer×100 format; 2016 uses comma-decimal).
capture program drop clean_puntaje
program clean_puntaje
    capture confirm string variable puntaje
    if !_rc {
        replace puntaje = subinstr(puntaje, ",", ".", .)
        destring puntaje, replace force
    }
    replace puntaje = puntaje / 100 if puntaje > 10000 & puntaje != .
end

* First year: import, clean puntaje, and save
local y = $year_start
import delimited "$app_raw/C_POSTULACIONES_SELECCION_PSU_`y'_PRIV_MRUN.csv", ///
    delimiter(";") varnames(1) clear encoding(utf-8)

* Standardize variable names to lowercase
rename *, lower

* Fix encoding issues with año (standardize to ao_proceso)
capture rename año_proceso ao_proceso
capture rename ano_proceso ao_proceso
capture rename a_o_proceso ao_proceso
capture rename aæo_proceso ao_proceso

clean_puntaje

tempfile applications
save `applications'

* Append remaining years
forvalues y = `=$year_start + 1'/$year_end {

    import delimited "$app_raw/C_POSTULACIONES_SELECCION_PSU_`y'_PRIV_MRUN.csv", ///
        delimiter(";") varnames(1) clear encoding(utf-8)

    rename *, lower

    * Fix encoding issues with año (standardize to ao_proceso)
    capture rename año_proceso ao_proceso
    capture rename ano_proceso ao_proceso
    capture rename a_o_proceso ao_proceso
    capture rename aæo_proceso ao_proceso

    clean_puntaje

    append using `applications'
    save `applications', replace
}

*-------------------------------------------------------------------------------
* Clean variables
*-------------------------------------------------------------------------------

* Keep only relevant variables
keep mrun ao_proceso preferencia codigo_carrera estado_preferencia puntaje ///
     nombre_carrera sede_carrera sigla_universidad

* puntaje already cleaned per-year in the loop above; just rename
rename puntaje application_score

* Label key variables
label variable mrun "Student ID"
label variable ao_proceso "Application year"
label variable preferencia "Preference rank (1-10)"
label variable codigo_carrera "Program code"
label variable estado_preferencia "Application status (24=adm, 25=wait, 26=rej)"
label variable application_score "Application score"

* Clean text variables (remove accents, lowercase)
foreach var of varlist nombre_carrera sede_carrera sigla_universidad {
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

*-------------------------------------------------------------------------------
* Basic validation
*-------------------------------------------------------------------------------

* Check estado_preferencia values (24=admitted, 25=waitlist, 26=rejected are main ones)
tab estado_preferencia, missing
* Note: Other status codes exist (e.g., 9, 16, 17, 31, 36) - these are valid

* Check year range
tab ao_proceso
assert ao_proceso >= $year_start & ao_proceso <= $year_end

* Check preference rank
assert preferencia >= 1 & preferencia <= 10 if preferencia != .

* Summary stats
di _n "=== Applications Summary ==="
di "Years: $year_start - $year_end"
count
di "Total observations: " r(N)
distinct mrun
di "Unique students: " r(ndistinct)
distinct codigo_carrera
di "Unique programs: " r(ndistinct)

*-------------------------------------------------------------------------------
* Save
*-------------------------------------------------------------------------------

compress
save "$processed/applications.dta", replace

di _n "Applications data saved to: $processed/applications.dta"
