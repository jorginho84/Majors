/**********************************************************************
* clean_psu_2017_2018_for_retakes.do
*
* Objetivo:
*   Procesar solo PSU 2017 y 2018 desde archivos raw CSV
*   para construir retakes_psu_2y.
*
* Input:
*   $psu_raw/A_INSCRITOS_PUNTAJES_PSU_2017_PRIV_MRUN.csv
*   $psu_raw/A_INSCRITOS_PUNTAJES_PSU_2018_PRIV_MRUN.csv
*
* Output:
*   $processed/psu_scores_2017.dta
*   $processed/psu_scores_2018.dta
**********************************************************************/

clear all
set more off

do "C:/Users/jigodoy/Documents/GitHub/Majors/code/config.do"


foreach y in 2017 2018 {

    di as text "=================================================="
    di as result "Importando PSU `y'"
    di as text "=================================================="

    import delimited "$psu_raw/A_INSCRITOS_PUNTAJES_PSU_`y'_PRIV_MRUN.csv", ///
        delimiter(";") varnames(1) clear encoding(utf-8)

    rename *, lower

    * Estandarizar año de proceso
    capture rename año_proceso ao_proceso
    capture rename ano_proceso ao_proceso
    capture rename a_o_proceso ao_proceso
    capture rename aæo_proceso ao_proceso
    capture rename v3 ao_proceso

    * Revisar variables mínimas
    foreach v in mrun ao_proceso {
        capture confirm variable `v'
        if _rc != 0 {
            di as error "Falta variable `v' en PSU `y'"
            describe
            exit 111
        }
    }

    keep mrun ao_proceso

    * Asegurar que el año corresponda
    tab ao_proceso, missing

    * Si por alguna razón ao_proceso viene missing o raro, forzar año
    replace ao_proceso = `y' if missing(ao_proceso)

    keep if ao_proceso == `y'

    duplicates drop mrun ao_proceso, force

    compress

    save "$processed/psu_scores_`y'.dta", replace

    di as result "Guardado: $processed/psu_scores_`y'.dta"
}