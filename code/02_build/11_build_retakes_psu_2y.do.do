/**********************************************************************
* build_retakes_psu_2y.do
*
* Objetivo:
*   Crear:
*       retakes_psu_2y = 1 si el estudiante vuelve a rendir PSU
*       en t+1 o t+2.
*
* Base principal:
*   analysis_sample.dta
*
* Fuente PSU:
*   psu_scores.dta + psu_scores_2017.dta + psu_scores_2018.dta
**********************************************************************/

clear all
set more off

do "C:/Users/jigodoy/Documents/GitHub/Majors/code/config.do"

local bw_reg 25


/**********************************************************************
* 1. Crear base de rendidores PSU 2007-2018
**********************************************************************/

tempfile psu_all

use "$processed/psu_scores.dta", clear

foreach v in mrun ao_proceso {
    capture confirm variable `v'
    if _rc != 0 {
        di as error "Falta variable en psu_scores.dta: `v'"
        exit 111
    }
}

keep mrun ao_proceso
rename ao_proceso psu_year

duplicates drop mrun psu_year, force

save `psu_all', replace


/**********************************************************************
* 2. Agregar 2017 y 2018 si existen como .dta procesadas
**********************************************************************/

foreach yy in 2017 2018 {

    capture confirm file "$processed/psu_scores_`yy'.dta"

    if _rc == 0 {

        di as result "Agregando $processed/psu_scores_`yy'.dta"

        preserve

            use "$processed/psu_scores_`yy'.dta", clear

            foreach v in mrun ao_proceso {
                capture confirm variable `v'
                if _rc != 0 {
                    di as error "Falta variable `v' en psu_scores_`yy'.dta"
                    exit 111
                }
            }

            keep mrun ao_proceso
            rename ao_proceso psu_year

            duplicates drop mrun psu_year, force

            append using `psu_all'

            duplicates drop mrun psu_year, force

            save `psu_all', replace

        restore
    }
    else {
        di as text "No existe $processed/psu_scores_`yy'.dta. Se salta por ahora."
    }
}


/**********************************************************************
* 3. Guardar base auxiliar de rendidores PSU
**********************************************************************/

use `psu_all', clear

duplicates drop mrun psu_year, force

gen took_psu = 1

sort mrun psu_year

tab psu_year, missing

save "$processed/psu_takers_2007_2018.dta", replace


/**********************************************************************
* 4. Cargar analysis_sample
**********************************************************************/

use "$processed/analysis_sample.dta", clear

capture confirm variable program_year_id

if _rc != 0 {
    di as text "program_year_id no existe. Creándolo."
    egen program_year_id = group(ao_proceso t_codigo_carrera)
    label variable program_year_id "Program-year FE: ao_proceso x t_codigo_carrera"
}

foreach v in mrun ao_proceso score_rd above_cutoff program_year_id {
    capture confirm variable `v'
    if _rc != 0 {
        di as error "Falta variable necesaria en analysis_sample.dta: `v'"
        exit 111
    }
}

gen app_year = ao_proceso


/**********************************************************************
* 5. Crear retakes_psu_2y
*
* Definición:
*   = 1 si aparece rindiendo PSU en t+1 o t+2.
*
* No incluimos t porque todos pertenecen al proceso inicial.
**********************************************************************/

preserve

    keep mrun ao_proceso app_year

    duplicates drop mrun ao_proceso, force

    expand 2

    bysort mrun ao_proceso: gen k = _n

    gen psu_year = app_year + k

    merge m:1 mrun psu_year using "$processed/psu_takers_2007_2018.dta", ///
        keep(master match) nogen

    replace took_psu = 0 if missing(took_psu)

    collapse ///
        (max) retakes_psu_2y = took_psu, ///
        by(mrun ao_proceso)

    tempfile retakes
    save `retakes', replace

restore

merge m:1 mrun ao_proceso using `retakes', ///
    keep(master match) nogen

replace retakes_psu_2y = 0 if missing(retakes_psu_2y)

label variable retakes_psu_2y ///
    "Retakes PSU in t+1 or t+2"


/**********************************************************************
* 6. Diagnóstico
**********************************************************************/

di as text "=================================================="
di as result "Diagnóstico retakes_psu_2y"
di as text "=================================================="

tab retakes_psu_2y if abs(score_rd) <= `bw_reg', missing

tab above_cutoff retakes_psu_2y if abs(score_rd) <= `bw_reg', missing

sum retakes_psu_2y if abs(score_rd) <= `bw_reg'

tab ao_proceso retakes_psu_2y if abs(score_rd) <= `bw_reg', missing


/**********************************************************************
* 7. Guardar base final
**********************************************************************/

save "$processed/analysis_sample_retakes_psu_2y.dta", replace

di as text "=================================================="
di as result "Listo. Base creada:"
di as result "$processed/analysis_sample_retakes_psu_2y.dta"
di as result "Base auxiliar:"
di as result "$processed/psu_takers_2007_2018.dta"
di as text "=================================================="