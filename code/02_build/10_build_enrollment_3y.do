/**********************************************************************
* 10_build_enrollment_3y.do
*
* Objetivo:
*   Crear outcomes de matrícula dentro de 3 años:
*
*       enrolls_he_3y
*       enrolls_uni_3y
*       enrolls_target_3y
*
*   Ventana:
*       t, t+1, t+2
**********************************************************************/

clear all
set more off

do "C:/Users/jigodoy/Documents/GitHub/Majors/code/config.do"

local bw_reg 25


/**********************************************************************
* 1. Preparar matrícula MINEDUC por estudiante-año-programa
**********************************************************************/

use "$processed/enrollment.dta", clear

foreach v in mrun ao_proceso codigo_demre enrolls_he enrolls_uni {
    capture confirm variable `v'
    if _rc != 0 {
        di as error "Falta variable necesaria en enrollment.dta: `v'"
        exit 111
    }
}

rename ao_proceso enroll_year
rename codigo_demre codigo_carrera_demre

gen enrolled_mineduc_program = 1

replace enrolls_he  = 0 if missing(enrolls_he)
replace enrolls_uni = 0 if missing(enrolls_uni)

keep mrun enroll_year codigo_carrera_demre ///
     enrolls_he enrolls_uni enrolled_mineduc_program

collapse ///
    (max) enrolled_he_any = enrolls_he ///
    (max) enrolled_uni_any = enrolls_uni ///
    (max) enrolled_mineduc_program, ///
    by(mrun enroll_year codigo_carrera_demre)

tempfile mineduc_year_program
save `mineduc_year_program', replace


/**********************************************************************
* 2. Preparar matrícula MINEDUC por estudiante-año
*    Para enrolls_he_3y y enrolls_uni_3y
**********************************************************************/

use `mineduc_year_program', clear

collapse ///
    (max) enrolled_he_any enrolled_uni_any, ///
    by(mrun enroll_year)

tempfile mineduc_year
save `mineduc_year', replace


/**********************************************************************
* 3. Preparar matrícula DEMRE Formulario D por estudiante-año-programa
*    Para enrolls_target_3y
**********************************************************************/

use "$processed/enrollment_demre.dta", clear

foreach v in mrun ao_proceso codigo_carrera {
    capture confirm variable `v'
    if _rc != 0 {
        di as error "Falta variable necesaria en enrollment_demre.dta: `v'"
        exit 111
    }
}

rename ao_proceso enroll_year
rename codigo_carrera codigo_carrera_demre

gen enrolled_demre_program = 1

keep mrun enroll_year codigo_carrera_demre enrolled_demre_program

collapse ///
    (max) enrolled_demre_program, ///
    by(mrun enroll_year codigo_carrera_demre)

tempfile demre_year_program
save `demre_year_program', replace


/**********************************************************************
* 4. Cargar analysis_sample como base principal RDD
**********************************************************************/

use "$processed/analysis_sample.dta", clear

capture confirm variable program_year_id

if _rc != 0 {
    di as text "program_year_id no existe. Creándolo."
    egen program_year_id = group(ao_proceso t_codigo_carrera)
    label variable program_year_id "Program-year FE: ao_proceso x t_codigo_carrera"
}

foreach v in mrun ao_proceso t_codigo_carrera ///
             score_rd above_cutoff program_year_id ///
             enrolls_he enrolls_uni enrolls_target {

    capture confirm variable `v'

    if _rc != 0 {
        di as error "Falta variable necesaria en analysis_sample.dta: `v'"
        exit 111
    }
}

gen app_year = ao_proceso


/**********************************************************************
* 5. Crear enrolls_he_3y y enrolls_uni_3y
**********************************************************************/

preserve

    keep mrun ao_proceso app_year

    duplicates drop mrun ao_proceso, force

    expand 3
    bysort mrun ao_proceso: gen k = _n - 1

    gen enroll_year = app_year + k

    merge m:1 mrun enroll_year using `mineduc_year', ///
        keep(master match) nogen

    replace enrolled_he_any  = 0 if missing(enrolled_he_any)
    replace enrolled_uni_any = 0 if missing(enrolled_uni_any)

    collapse ///
        (max) enrolls_he_3y  = enrolled_he_any ///
        (max) enrolls_uni_3y = enrolled_uni_any, ///
        by(mrun ao_proceso)

    tempfile enrollment_3y_student
    save `enrollment_3y_student', replace

restore

merge m:1 mrun ao_proceso using `enrollment_3y_student', ///
    keep(master match) nogen

replace enrolls_he_3y  = 0 if missing(enrolls_he_3y)
replace enrolls_uni_3y = 0 if missing(enrolls_uni_3y)

label variable enrolls_he_3y ///
    "Enrolled in higher education within 3 years: t, t+1, t+2"

label variable enrolls_uni_3y ///
    "Enrolled in university within 3 years: t, t+1, t+2"


/**********************************************************************
* 6. Crear enrolls_target_3y
**********************************************************************/

preserve

    keep mrun ao_proceso app_year t_codigo_carrera

    duplicates drop mrun ao_proceso t_codigo_carrera, force

    expand 3
    bysort mrun ao_proceso t_codigo_carrera: gen k = _n - 1

    gen enroll_year = app_year + k

    gen double codigo_carrera_demre = t_codigo_carrera

    /************************************************************
    * Match con MINEDUC
    ************************************************************/

    merge m:1 mrun enroll_year codigo_carrera_demre ///
        using `mineduc_year_program', ///
        keepusing(enrolled_mineduc_program) ///
        keep(master match) nogen

    replace enrolled_mineduc_program = 0 ///
        if missing(enrolled_mineduc_program)

    /************************************************************
    * Match con DEMRE Formulario D
    ************************************************************/

    merge m:1 mrun enroll_year codigo_carrera_demre ///
        using `demre_year_program', ///
        keepusing(enrolled_demre_program) ///
        keep(master match) nogen

    replace enrolled_demre_program = 0 ///
        if missing(enrolled_demre_program)

    gen enrolled_target_window = ///
        enrolled_mineduc_program == 1 | enrolled_demre_program == 1

    collapse ///
        (max) enrolls_target_3y = enrolled_target_window, ///
        by(mrun ao_proceso t_codigo_carrera)

    tempfile enrollment_3y_target
    save `enrollment_3y_target', replace

restore

merge m:1 mrun ao_proceso t_codigo_carrera ///
    using `enrollment_3y_target', ///
    keep(master match) nogen

replace enrolls_target_3y = 0 if missing(enrolls_target_3y)

label variable enrolls_target_3y ///
    "Enrolled in target program within 3 years: t, t+1, t+2"


/**********************************************************************
* 7. Diagnósticos
**********************************************************************/

di as text "=================================================="
di as result "Confirmar outcomes 3y"
di as text "=================================================="

describe enrolls_he_3y enrolls_uni_3y enrolls_target_3y


di as text "=================================================="
di as result "Outcomes inmediatos vs 3y"
di as text "=================================================="

tab enrolls_he enrolls_he_3y if abs(score_rd) <= `bw_reg', missing
tab enrolls_uni enrolls_uni_3y if abs(score_rd) <= `bw_reg', missing
tab enrolls_target enrolls_target_3y if abs(score_rd) <= `bw_reg', missing

sum enrolls_he enrolls_he_3y ///
    enrolls_uni enrolls_uni_3y ///
    enrolls_target enrolls_target_3y ///
    if abs(score_rd) <= `bw_reg'


di as text "=================================================="
di as result "Chequeo: immediate enrollment debe estar contenido en 3y"
di as text "=================================================="

foreach pair in he uni target {

    count if enrolls_`pair' == 1 & enrolls_`pair'_3y == 0 ///
        & abs(score_rd) <= `bw_reg'

    if r(N) > 0 {
        di as error "OJO: hay casos enrolls_`pair' == 1 pero enrolls_`pair'_3y == 0."
    }
    else {
        di as result "OK: enrolls_`pair'_3y contiene todos los enrolls_`pair'."
    }
}


/**********************************************************************
* 8. Guardar base auxiliar
**********************************************************************/

save "$processed/analysis_sample_enrollment_3y.dta", replace

di as text "=================================================="
di as result "Listo. Base creada:"
di as result "$processed/analysis_sample_enrollment_3y.dta"
di as text "=================================================="