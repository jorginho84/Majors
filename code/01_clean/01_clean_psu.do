/*------------------------------------------------------------------------------
                    Threshold-Crossing Effects in Higher Education

                    01_clean_psu.do

                    Cleans and appends PSU score data across years.

                    Based on legacy code: 03_returns.do (Section 2: Scores)

                    Input:  $psu_raw/A_INSCRITOS_PUNTAJES_PSU_YYYY_PRIV_MRUN.csv
                    Output: $processed/psu_scores.dta
------------------------------------------------------------------------------*/

do "code/config.do"

*-------------------------------------------------------------------------------
* Import and append PSU scores across years
*-------------------------------------------------------------------------------

* First year: import and save
local y = $year_start
import delimited "$psu_raw/A_INSCRITOS_PUNTAJES_PSU_`y'_PRIV_MRUN.csv", ///
    delimiter(";") varnames(1) clear encoding(utf-8)

* Standardize variable names to lowercase
rename *, lower

* Fix encoding issues with año (ñ gets garbled in CSV headers)
* Standardize to ao_proceso (without ñ) to avoid encoding issues
capture rename año_proceso ao_proceso
capture rename ano_proceso ao_proceso
capture rename a_o_proceso ao_proceso
capture rename aæo_proceso ao_proceso
capture rename v3 ao_proceso

tempfile psu_scores
save `psu_scores'

* Append remaining years
forvalues y = `=$year_start + 1'/$year_end {

    import delimited "$psu_raw/A_INSCRITOS_PUNTAJES_PSU_`y'_PRIV_MRUN.csv", ///
        delimiter(";") varnames(1) clear encoding(utf-8)

    rename *, lower

    * Fix encoding issues with año (standardize to ao_proceso)
    capture rename año_proceso ao_proceso
    capture rename ano_proceso ao_proceso
    capture rename a_o_proceso ao_proceso
    capture rename aæo_proceso ao_proceso
    capture rename v3 ao_proceso

    append using `psu_scores', force
    save `psu_scores', replace
}

*-------------------------------------------------------------------------------
* Clean variables
*-------------------------------------------------------------------------------

* Keep relevant variables for RDD analysis
* Test scores: current year (_actual) and previous year (_anterior)
* GPA scores: ptje_nem, ptje_ranking
* Average scores: promlm (language + math average)
* BEA: scholarship indicator

local keep_vars mrun ao_proceso ///
    ptje_nem ptje_ranking ///
    lyc_actual mate_actual hycs_actual ciencias_actual promlm_actual ///
    lyc_anterior mate_anterior hycs_anterior ciencias_anterior promlm_anterior ///
    bea

* Check which variables exist and keep only those that do
foreach var of local keep_vars {
    capture confirm variable `var'
    if _rc {
        di "Warning: Variable `var' not found in data"
    }
}

* Keep only variables that exist
keep `keep_vars'

*-------------------------------------------------------------------------------
* Register first time an individual applies for college
* (Following legacy code from 03_returns.do)
*-------------------------------------------------------------------------------

bysort mrun: egen first_year = min(ao_proceso)
label variable first_year "First year student applied"

*-------------------------------------------------------------------------------
* Handle duplicates
* (Legacy code: "duplicates drop mrun año_proceso, force //one observation deleted")
*-------------------------------------------------------------------------------

* Check for duplicates before dropping
duplicates tag mrun ao_proceso, gen(dup)
tab dup
drop dup

* Drop duplicates (keep first occurrence)
duplicates drop mrun ao_proceso, force

*-------------------------------------------------------------------------------
* Label variables
*-------------------------------------------------------------------------------

label variable mrun "Student ID"
label variable ao_proceso "Application year"
label variable ptje_nem "GPA score (NEM)"
label variable ptje_ranking "Class ranking score"

capture label variable lyc_actual "Language score (current year)"
capture label variable mate_actual "Math score (current year)"
capture label variable hycs_actual "History/Social Sciences score (current year)"
capture label variable ciencias_actual "Science score (current year)"
capture label variable promlm_actual "Language-Math average (current year)"

capture label variable lyc_anterior "Language score (previous year)"
capture label variable mate_anterior "Math score (previous year)"
capture label variable hycs_anterior "History/Social Sciences score (previous year)"
capture label variable ciencias_anterior "Science score (previous year)"
capture label variable promlm_anterior "Language-Math average (previous year)"

capture label variable bea "BEA scholarship indicator"

*-------------------------------------------------------------------------------
* Basic validation
*-------------------------------------------------------------------------------

* Check year range
tab ao_proceso
assert ao_proceso >= $year_start & ao_proceso <= $year_end

* Check score ranges (valid PSU scores are 150-850)
foreach var in lyc_actual mate_actual hycs_actual ciencias_actual {
    capture confirm variable `var'
    if !_rc {
        count if `var' < 150 & `var' != . & `var' != 0
        count if `var' > 850 & `var' != .
    }
}

* Summary stats
di _n "=== PSU Scores Summary ==="
di "Years: $year_start - $year_end"
count
di "Total observations: " r(N)
distinct mrun
di "Unique students: " r(ndistinct)

summarize ptje_nem ptje_ranking promlm_actual, detail

*-------------------------------------------------------------------------------
* Save
*-------------------------------------------------------------------------------

compress
save "$processed/psu_scores.dta", replace

di _n "PSU scores data saved to: $processed/psu_scores.dta"
