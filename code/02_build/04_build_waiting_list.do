/*------------------------------------------------------------------------------
                    Threshold-Crossing Effects in Higher Education

                    04_build_waiting_list.do

                    Identifies program-years that have waiting lists.

                    A program-year has a waiting list if at least one applicant
                    has estado_preferencia == 25 (waiting list status).

                    Based on legacy code: 03_a_waiting_list.do

                    Input:  $processed/applications.dta
                    Output: $processed/waiting_list.dta
------------------------------------------------------------------------------*/

do "code/config.do"

*-------------------------------------------------------------------------------
* Load applications data
*-------------------------------------------------------------------------------

use "$processed/applications.dta", clear

*-------------------------------------------------------------------------------
* Identify program-years with waiting lists
* (Following legacy code: 03_a_waiting_list.do)
*-------------------------------------------------------------------------------

* Flag applicants on waiting list
gen on_waiting_list = (estado_preferencia == $waiting_list)

* Count waiting list applicants per program-year
bysort codigo_carrera ao_proceso: egen wl_count = total(on_waiting_list)

* Keep only program-years with at least one person on waiting list
keep if wl_count > 0 & wl_count != .

* Collapse to program-year level
collapse (first) wl_count, by(codigo_carrera ao_proceso)

* Rename to match legacy code convention
rename codigo_carrera t_codigo_carrera
rename wl_count waiting_list_size

* Create indicator
gen has_waiting_list = 1

label variable t_codigo_carrera "Program code"
label variable ao_proceso "Application year"
label variable waiting_list_size "Number of applicants on waiting list"
label variable has_waiting_list "Program-year has waiting list"

*-------------------------------------------------------------------------------
* Summary
*-------------------------------------------------------------------------------

di _n "=== Waiting List Summary ==="
count
di "Program-years with waiting lists: " r(N)

tab ao_proceso

summarize waiting_list_size, detail

*-------------------------------------------------------------------------------
* Save
*-------------------------------------------------------------------------------

compress
save "$processed/waiting_list.dta", replace

di _n "Waiting list data saved to: $processed/waiting_list.dta"
