/*------------------------------------------------------------------------------
                    Threshold-Crossing Effects in Higher Education

                    02_clean_applications.do

                    Cleans and appends application data across years.

                    Input:  $app_raw/C_POSTULACIONES_SELECCION_PSU_YYYY_PRIV_MRUN.csv
                    Output: $processed/applications.dta
------------------------------------------------------------------------------*/

do "$code/config.do"

*-------------------------------------------------------------------------------
* Import and append applications across years
*-------------------------------------------------------------------------------

* First year: import and save
local y = $year_start
import delimited "$app_raw/C_POSTULACIONES_SELECCION_PSU_`y'_PRIV_MRUN.csv", ///
    delimiter(";") varnames(1) clear encoding(utf-8)

* Standardize variable names to lowercase
rename *, lower

tempfile applications
save `applications'

* Append remaining years
forvalues y = `=$year_start + 1'/$year_end {

    import delimited "$app_raw/C_POSTULACIONES_SELECCION_PSU_`y'_PRIV_MRUN.csv", ///
        delimiter(";") varnames(1) clear encoding(utf-8)

    rename *, lower

    append using `applications', force
    save `applications', replace
}

*-------------------------------------------------------------------------------
* Clean variables
*-------------------------------------------------------------------------------

* Keep only relevant variables
keep mrun año_proceso preferencia codigo_carrera estado_preferencia puntaje ///
     nombre_carrera sede_carrera sigla_universidad

* Clean application score (PUNTAJE)
* Some years have comma as decimal separator
capture confirm string variable puntaje
if !_rc {
    replace puntaje = subinstr(puntaje, ",", ".", .)
    destring puntaje, replace
}

* Divide by 100 if scores are in old scale (> 10000)
replace puntaje = puntaje / 100 if puntaje > 10000

rename puntaje application_score

* Label key variables
label variable mrun "Student ID"
label variable año_proceso "Application year"
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

* Check estado_preferencia values
tab estado_preferencia, missing
assert inlist(estado_preferencia, $admitted, $waiting_list, $rejected) | estado_preferencia == .

* Check year range
tab año_proceso
assert año_proceso >= $year_start & año_proceso <= $year_end

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
