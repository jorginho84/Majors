/*------------------------------------------------------------------------------
                    Threshold-Crossing Effects in Higher Education

                    04_clean_weights.do

                    Cleans program weights data for computing application scores.

                    Based on legacy code: 03_returns.do (Section 1: Weights)

                    Input:  $data/weights_2004_2016.csv
                    Output: $processed/weights.dta
------------------------------------------------------------------------------*/

do "$code/config.do"

*-------------------------------------------------------------------------------
* Import weights data
*-------------------------------------------------------------------------------

import delimited "$data/weights_2004_2016.csv", ///
    delimiter(";") varnames(1) clear encoding(utf-8)

* Standardize variable names to lowercase
rename *, lower

* Rename variables if needed (check legacy code naming)
capture rename program_code codigo_carrera
capture rename application_year año_proceso

*-------------------------------------------------------------------------------
* Clean variables
*-------------------------------------------------------------------------------

* Handle missing values for minimum score thresholds
* (Following legacy code: replace missing with 0)
capture replace min_application_score = 0 if min_application_score == .
capture replace min_reading_math = 0 if min_reading_math == .

* Ensure weights are in proportion form (0-1) not percentage (0-100)
* Check if weights sum to approximately 1 or 100
egen weight_sum = rowtotal(w_gpa w_rank w_reading w_math w_history w_science)
summarize weight_sum

* If weights are in percentage form (sum ~100), convert to proportions
* Note: Legacy code suggests they might already be in correct form
* Uncomment below if needed:
/*
if r(mean) > 50 {
    foreach var of varlist w_gpa w_rank w_reading w_math w_history w_science {
        replace `var' = `var' / 100
    }
}
*/

drop weight_sum

*-------------------------------------------------------------------------------
* Label variables
*-------------------------------------------------------------------------------

label variable codigo_carrera "Program code"
label variable año_proceso "Application year"

capture label variable w_gpa "Weight: GPA (NEM)"
capture label variable w_rank "Weight: Class ranking"
capture label variable w_reading "Weight: Language/Reading"
capture label variable w_math "Weight: Math"
capture label variable w_history "Weight: History/Social Sciences"
capture label variable w_science "Weight: Science"
capture label variable choose_hist_science "Program allows choice between history and science"
capture label variable min_application_score "Minimum application score required"
capture label variable min_reading_math "Minimum language-math average required"

*-------------------------------------------------------------------------------
* Basic validation
*-------------------------------------------------------------------------------

* Check for duplicates (should be unique by program-year)
duplicates tag codigo_carrera año_proceso, gen(dup)
tab dup
if r(N) > 0 {
    di as text "Warning: Duplicate program-years found"
    list codigo_carrera año_proceso if dup > 0
}
drop dup

* Summary statistics
di _n "=== Weights Summary ==="
tab año_proceso

distinct codigo_carrera
di "Unique programs: " r(ndistinct)

summarize w_gpa w_rank w_reading w_math w_history w_science

* Check choose_hist_science values
tab choose_hist_science, missing

*-------------------------------------------------------------------------------
* Save
*-------------------------------------------------------------------------------

compress
save "$processed/weights.dta", replace

di _n "Weights data saved to: $processed/weights.dta"
