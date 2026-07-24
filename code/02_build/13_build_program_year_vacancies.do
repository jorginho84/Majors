****************************************************
* 13_build_program_year_vacancies.do
* Build program-year vacancies from clean Oferta Académica
****************************************************

clear all
set more off

do "C:/Users/jigodoy/Documents/GitHub/Majors/code/config.do"

****************************************************
* 0. Load appended clean file
****************************************************

global oferta_clean "$processed"

use "$oferta_clean/oferta_academica_2007_2016_appended.dta", clear

****************************************************
* 1. Inspect variables
****************************************************

describe
lookfor codigo carrera vacante cupo sobrecupo

****************************************************
* 2. Standardize key variables
****************************************************

* Código programa
capture confirm variable CODIGO
if _rc == 0 {
    rename CODIGO t_codigo_carrera
}

capture confirm variable codigo
if _rc == 0 {
    rename codigo t_codigo_carrera
}

capture confirm variable t_codigo_carrera
if _rc {
    di as error "No program code variable found."
    exit 111
}

****************************************************
* 3. Standardize vacancy variables
****************************************************

capture confirm variable VACANTES_1SEM
if _rc == 0 rename VACANTES_1SEM vacantes_1sem

capture confirm variable VACANTES_2SEM
if _rc == 0 rename VACANTES_2SEM vacantes_2sem

capture confirm variable SOBRECUPO_1SEM
if _rc == 0 rename SOBRECUPO_1SEM sobrecupo_1sem

capture confirm variable SOBRECUPO_2SEM
if _rc == 0 rename SOBRECUPO_2SEM sobrecupo_2sem

capture confirm variable TOTAL_CUPOS
if _rc == 0 rename TOTAL_CUPOS total_cupos

capture confirm variable CUPOS_BEA
if _rc == 0 rename CUPOS_BEA cupos_bea

****************************************************
* 4. Keep relevant variables
****************************************************

local keepvars ao_proceso t_codigo_carrera

foreach v in vacantes_1sem vacantes_2sem sobrecupo_1sem sobrecupo_2sem total_cupos cupos_bea {
    capture confirm variable `v'
    if _rc == 0 {
        local keepvars `keepvars' `v'
    }
}

keep `keepvars'

****************************************************
* 5. Ensure numeric
****************************************************

foreach v of varlist t_codigo_carrera vacantes_1sem vacantes_2sem ///
    sobrecupo_1sem sobrecupo_2sem total_cupos cupos_bea {

    capture confirm variable `v'
    if _rc == 0 {
        capture confirm numeric variable `v'
        if _rc {
            destring `v', replace
        }
    }
}

drop if missing(t_codigo_carrera)

****************************************************
* 6. Check duplicates
****************************************************

duplicates report ao_proceso t_codigo_carrera

* If duplicates exist, collapse conservatively
collapse ///
    (max) vacantes_1sem vacantes_2sem sobrecupo_1sem sobrecupo_2sem ///
          total_cupos cupos_bea, ///
    by(ao_proceso t_codigo_carrera)

duplicates report ao_proceso t_codigo_carrera

****************************************************
* 7. Create candidate IV variables
****************************************************

gen Z_vacantes_1sem = vacantes_1sem
gen Z_total_cupos   = total_cupos

label var Z_vacantes_1sem "Vacantes 1er semestre"
label var Z_total_cupos   "Total cupos"

****************************************************
* 8. Diagnostics
****************************************************

tab ao_proceso
summarize Z_vacantes_1sem Z_total_cupos, detail

****************************************************
* 9. Save
****************************************************

compress
save "$processed/program_year_vacancies_2007_2016.dta", replace

di as result "Saved:"
di as result "$processed/program_year_vacancies_2007_2016.dta"