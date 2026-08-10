/**********************************************************************
* 14_build_inframarginal_sample_2007_2012.do
*
* Objetivo:
*   Construir muestra inframarginal usando solo años 2007-2012,
*   excluyendo universidades privadas adscritas que entran al sistema
*   común en 2012 y no tienen historia observable 2007-2011.
*
* Universidades excluidas para esta ventana:
*   uah, uai, uande, udd, udp, uft, umayo, unab
*
* Motivación:
*   Para 2007-2012 no existe ranking en la fórmula de admisión.
*   Por lo tanto, este código NO usa ptje_ranking ni w_rank.
*
*   Además, 2012 introduce universidades nuevas en el sistema común.
*   Si las dejamos, aparecen con n_years_program == 1 y quedan como
*   no inframarginales por construcción.
*
* Definición:
*   Un estudiante i es inframarginal para su target program p si:
*
*       PSU_i' w_{p,t} >= cutoff_{p,t}
*
*   para todos los años t = 2007, ..., 2012 en que el programa existe
*   con reglas observables.
*
* Inputs:
*   $processed/applications_rd.dta
*   $processed/analysis_sample_delta_groups.dta
*
* Output:
*   $processed/analysis_sample_with_inframarginal_2007_2012.dta
**********************************************************************/

clear all
set more off

do "C:/Users/jigodoy/Documents/GitHub/Majors/code/config.do"


/**********************************************************************
* 0. Parámetros
**********************************************************************/

local apps     "$processed/applications_rd.dta"
local analysis "$processed/analysis_sample_delta_groups.dta"

local first_year 2007
local last_year  2012
local required_years = `last_year' - `first_year' + 1


/**********************************************************************
* 1. Cargar applications_rd y verificar variables
*
* Nota:
*   No se exige ptje_ranking ni w_rank porque no forman parte de la
*   regla 2007-2012.
**********************************************************************/

use "`apps'", clear

foreach v in ///
    mrun ///
    ao_proceso ///
    preferencia ///
    codigo_carrera ///
    sigla_universidad ///
    ptje_nem ///
    lyc_actual ///
    mate_actual ///
    hycs_actual ///
    ciencias_actual ///
    lyc_anterior ///
    mate_anterior ///
    hycs_anterior ///
    ciencias_anterior ///
    w_gpa ///
    w_reading ///
    w_math ///
    w_history ///
    w_science ///
    choose_hist_science ///
    min_application_score ///
    min_reading_math ///
    application_score ///
    cutoff_regular {

    capture confirm variable `v'

    if _rc != 0 {
        di as error "Falta variable necesaria: `v'"
        exit 111
    }
}

capture confirm numeric variable codigo_carrera
if _rc != 0 destring codigo_carrera, replace force

capture confirm numeric variable ao_proceso
if _rc != 0 destring ao_proceso, replace force


/**********************************************************************
* 1.1 Excluir universidades privadas adscritas que entran en 2012
*
* Estas universidades no tienen historia observable 2007-2011 dentro
* del sistema común, por lo que no pueden cumplir la definición estricta
* de inframarginal 2007-2012.
**********************************************************************/

gen str20 sigla_clean = lower(strtrim(sigla_universidad))

count if inrange(ao_proceso, `first_year', `last_year') ///
    & inlist(sigla_clean, ///
        "uah", ///
        "uai", ///
        "uande", ///
        "udd", ///
        "udp", ///
        "uft", ///
        "umayo", ///
        "unab")

di as result "Obs excluidas por universidades privadas adscritas 2012: " r(N)

drop if inrange(ao_proceso, `first_year', `last_year') ///
    & inlist(sigla_clean, ///
        "uah", ///
        "uai", ///
        "uande", ///
        "udd", ///
        "udp", ///
        "uft", ///
        "umayo", ///
        "unab")

drop sigla_clean


/**********************************************************************
* 2. Crear código armonizado del programa
*
* Para 2007-2012 usamos como formato común el código pre-2012.
*
* Regla:
*   Si codigo_carrera tiene 5 dígitos y el tercer carácter es "0",
*   eliminamos ese "0".
*
* Ejemplos:
*   11022 -> 1122
*   41028 -> 4128
**********************************************************************/

gen str10 code_str = string(codigo_carrera, "%12.0f")
replace code_str = strtrim(code_str)

gen str10 program_code_harmonized = code_str

replace program_code_harmonized = ///
    substr(code_str, 1, 2) + substr(code_str, 4, .) ///
    if strlen(code_str) == 5 ///
    & substr(code_str, 3, 1) == "0"

drop code_str

di as text "=================================================="
di as result "Diagnóstico códigos 2007-2012"
di as text "=================================================="

count if inrange(ao_proceso, `first_year', `last_year')
di as result "Observaciones applications_rd 2007-2012 luego de exclusión: " r(N)

tab ao_proceso if inrange(ao_proceso, `first_year', `last_year'), missing

di as text "--------------------------------------------------"
di as result "Ejemplos de códigos armonizados"
di as text "--------------------------------------------------"

preserve

    keep if inrange(ao_proceso, `first_year', `last_year')
    keep ao_proceso codigo_carrera program_code_harmonized
    duplicates drop

    list ao_proceso codigo_carrera program_code_harmonized in 1/30, noobs

restore


/**********************************************************************
* 3. Construir base estudiante-target con vector de puntajes
**********************************************************************/

tempfile student_targets

preserve

    keep if inrange(ao_proceso, `first_year', `last_year')

    keep mrun ao_proceso preferencia codigo_carrera ///
         sigla_universidad ///
         program_code_harmonized ///
         application_score ///
         ptje_nem ///
         lyc_actual mate_actual hycs_actual ciencias_actual ///
         lyc_anterior mate_anterior hycs_anterior ciencias_anterior

    drop if missing(mrun, ao_proceso, preferencia, codigo_carrera)
    drop if missing(program_code_harmonized)

    duplicates drop mrun ao_proceso preferencia codigo_carrera, force

    rename ao_proceso application_year
    rename codigo_carrera target_codigo_carrera

    save `student_targets', replace

restore


/**********************************************************************
* 4. Construir base programa-año con pesos, cutoffs y mínimos
**********************************************************************/

tempfile program_year_weights

preserve

    keep if inrange(ao_proceso, `first_year', `last_year')

    keep ao_proceso codigo_carrera sigla_universidad ///
         program_code_harmonized ///
         cutoff_regular ///
         min_application_score ///
         min_reading_math ///
         w_gpa w_reading w_math w_history w_science ///
         choose_hist_science

    drop if missing(ao_proceso, codigo_carrera, program_code_harmonized)
    drop if missing(cutoff_regular)

    foreach w in w_gpa w_reading w_math w_history w_science {

        capture confirm numeric variable `w'
        if _rc != 0 destring `w', replace force

        replace `w' = `w' / 100 if `w' > 1 & !missing(`w')
    }

    capture confirm numeric variable min_application_score
    if _rc != 0 destring min_application_score, replace force

    capture confirm numeric variable min_reading_math
    if _rc != 0 destring min_reading_math, replace force


    /************************************************************
    * 4.1 Leer choose_hist_science robustamente
    ************************************************************/

    gen str10 choose_clean = upper(strtrim(choose_hist_science))

    replace choose_clean = "SI" if inlist(choose_clean, "SÍ", "SI.", "S")
    replace choose_clean = "NO" if inlist(choose_clean, "NO.", "N")

    gen byte choose_elective = .

    replace choose_elective = 1 if inlist(choose_clean, "1", "SI", "YES", "Y", "TRUE")
    replace choose_elective = 0 if inlist(choose_clean, "0", "NO", "FALSE")

    /*
    Si quedan missing, inferimos desde los pesos.
    */

    replace choose_elective = 1 if missing(choose_elective) ///
        & w_history > 0 ///
        & w_science > 0

    replace choose_elective = 0 if missing(choose_elective) ///
        & ((w_history > 0 & (w_science == 0 | missing(w_science))) ///
        |  (w_science > 0 & (w_history == 0 | missing(w_history))) ///
        |  ((w_history == 0 | missing(w_history)) ///
        &   (w_science == 0 | missing(w_science))))

    di as text "=================================================="
    di as result "Diagnóstico choose_hist_science"
    di as text "=================================================="

    tab choose_hist_science choose_elective, missing

    count if missing(choose_elective)

    if r(N) > 0 {
        di as error "Hay valores no reconocidos en choose_hist_science."
        tab choose_hist_science if missing(choose_elective), missing
        exit 111
    }


    /************************************************************
    * 4.2 Regla electiva
    *
    * No se suman Historia y Ciencias.
    * Si se permite elegir, se usa el mayor aporte ponderado.
    ************************************************************/

    gen byte elective_rule = .

    replace elective_rule = 1 if choose_elective == 1

    replace elective_rule = 2 if choose_elective == 0 ///
        & w_history > 0 ///
        & (w_science == 0 | missing(w_science))

    replace elective_rule = 3 if choose_elective == 0 ///
        & w_science > 0 ///
        & (w_history == 0 | missing(w_history))

    replace elective_rule = 0 if choose_elective == 0 ///
        & (w_history == 0 | missing(w_history)) ///
        & (w_science == 0 | missing(w_science))

    /*
    Seguridad: si ambos pesos son positivos aunque choose_elective==0,
    no sumamos ambas. Lo tratamos como elección.
    */

    replace elective_rule = 1 if choose_elective == 0 ///
        & w_history > 0 ///
        & w_science > 0

    label define elective_rule_lbl ///
        0 "No history/science" ///
        1 "Choose best history/science" ///
        2 "Requires history" ///
        3 "Requires science", replace

    label values elective_rule elective_rule_lbl

    di as text "=================================================="
    di as result "Diagnóstico regla electiva"
    di as text "=================================================="

    tab elective_rule, missing


    /************************************************************
    * 4.3 Una regla por programa-año armonizado
    ************************************************************/

    duplicates drop ao_proceso program_code_harmonized cutoff_regular ///
        min_application_score min_reading_math ///
        w_gpa w_reading w_math w_history w_science ///
        choose_elective elective_rule, force

    bysort ao_proceso program_code_harmonized: gen n_prog_year = _N

    di as text "=================================================="
    di as result "Programa-año con múltiples combinaciones de cutoff/pesos"
    di as text "=================================================="

    tab n_prog_year, missing

    /*
    Si queda más de una combinación para un mismo programa-año armonizado,
    mantenemos la primera para esta prueba exploratoria.
    */

    bysort ao_proceso program_code_harmonized: keep if _n == 1

    rename ao_proceso cutoff_year
    rename codigo_carrera cutoff_codigo_carrera
    rename cutoff_regular cutoff_program_year

    keep cutoff_year cutoff_codigo_carrera program_code_harmonized ///
         cutoff_program_year ///
         min_application_score min_reading_math ///
         w_gpa w_reading w_math w_history w_science ///
         choose_elective elective_rule

    save `program_year_weights', replace

restore


/**********************************************************************
* 5. Cruzar cada estudiante-target con todos los años del programa
*
* Como usamos 2007-2012, cada estudiante-target debería cruzarse
* con hasta 6 años programa-año si el programa existe en todos esos años.
**********************************************************************/

use `student_targets', clear

joinby program_code_harmonized using `program_year_weights'


/**********************************************************************
* 6. Preparar puntajes
**********************************************************************/

foreach v in ///
    ptje_nem ///
    lyc_actual mate_actual hycs_actual ciencias_actual ///
    lyc_anterior mate_anterior hycs_anterior ciencias_anterior ///
    application_score {

    capture confirm numeric variable `v'
    if _rc != 0 destring `v', replace force
}


/**********************************************************************
* 7. Calcular puntaje contrafactual: batería actual
**********************************************************************/

gen byte miss_required_actual = 0

replace miss_required_actual = 1 if w_gpa > 0 ///
    & missing(ptje_nem)

replace miss_required_actual = 1 if w_reading > 0 ///
    & missing(lyc_actual)

replace miss_required_actual = 1 if w_math > 0 ///
    & missing(mate_actual)


/************************************************************
* 7.1 Componentes comunes actuales
************************************************************/

gen double c_gpa_actual = 0
replace c_gpa_actual = ptje_nem * w_gpa ///
    if w_gpa > 0 & !missing(ptje_nem, w_gpa)

gen double c_read_actual = 0
replace c_read_actual = lyc_actual * w_reading ///
    if w_reading > 0 & !missing(lyc_actual, w_reading)

gen double c_math_actual = 0
replace c_math_actual = mate_actual * w_math ///
    if w_math > 0 & !missing(mate_actual, w_math)


/************************************************************
* 7.2 Historia/Ciencias actual
************************************************************/

gen double hist_actual = .
replace hist_actual = hycs_actual * w_history ///
    if w_history > 0 & !missing(hycs_actual, w_history)

gen double sci_actual = .
replace sci_actual = ciencias_actual * w_science ///
    if w_science > 0 & !missing(ciencias_actual, w_science)

egen double best_elective_actual = rowmax(hist_actual sci_actual)

gen double elective_actual = 0

replace elective_actual = 0 if elective_rule == 0

replace elective_actual = best_elective_actual ///
    if elective_rule == 1 ///
    & !missing(best_elective_actual)

replace miss_required_actual = 1 ///
    if elective_rule == 1 ///
    & missing(best_elective_actual)

replace elective_actual = hist_actual ///
    if elective_rule == 2 ///
    & !missing(hist_actual)

replace miss_required_actual = 1 ///
    if elective_rule == 2 ///
    & missing(hist_actual)

replace elective_actual = sci_actual ///
    if elective_rule == 3 ///
    & !missing(sci_actual)

replace miss_required_actual = 1 ///
    if elective_rule == 3 ///
    & missing(sci_actual)


/************************************************************
* 7.3 Score actual y reglas mínimas
************************************************************/

gen double score_cf_actual = ///
      c_gpa_actual ///
    + c_read_actual ///
    + c_math_actual ///
    + elective_actual

replace score_cf_actual = . if miss_required_actual == 1

gen double lm_actual = (lyc_actual + mate_actual) / 2 ///
    if !missing(lyc_actual, mate_actual)

gen byte valid_actual = 1

replace valid_actual = 0 if missing(score_cf_actual)

replace valid_actual = 0 if !missing(min_application_score) ///
    & score_cf_actual < min_application_score

replace valid_actual = 0 if !missing(min_reading_math) ///
    & lm_actual < min_reading_math

gen double score_cf_actual_valid = score_cf_actual
replace score_cf_actual_valid = . if valid_actual == 0


/**********************************************************************
* 8. Calcular puntaje contrafactual: batería anterior
**********************************************************************/

gen byte miss_required_anterior = 0

replace miss_required_anterior = 1 if w_gpa > 0 ///
    & missing(ptje_nem)

replace miss_required_anterior = 1 if w_reading > 0 ///
    & missing(lyc_anterior)

replace miss_required_anterior = 1 if w_math > 0 ///
    & missing(mate_anterior)


/************************************************************
* 8.1 Componentes comunes anteriores
************************************************************/

gen double c_gpa_anterior = 0
replace c_gpa_anterior = ptje_nem * w_gpa ///
    if w_gpa > 0 & !missing(ptje_nem, w_gpa)

gen double c_read_anterior = 0
replace c_read_anterior = lyc_anterior * w_reading ///
    if w_reading > 0 & !missing(lyc_anterior, w_reading)

gen double c_math_anterior = 0
replace c_math_anterior = mate_anterior * w_math ///
    if w_math > 0 & !missing(mate_anterior, w_math)


/************************************************************
* 8.2 Historia/Ciencias anterior
************************************************************/

gen double hist_anterior = .
replace hist_anterior = hycs_anterior * w_history ///
    if w_history > 0 & !missing(hycs_anterior, w_history)

gen double sci_anterior = .
replace sci_anterior = ciencias_anterior * w_science ///
    if w_science > 0 & !missing(ciencias_anterior, w_science)

egen double best_elective_anterior = rowmax(hist_anterior sci_anterior)

gen double elective_anterior = 0

replace elective_anterior = 0 if elective_rule == 0

replace elective_anterior = best_elective_anterior ///
    if elective_rule == 1 ///
    & !missing(best_elective_anterior)

replace miss_required_anterior = 1 ///
    if elective_rule == 1 ///
    & missing(best_elective_anterior)

replace elective_anterior = hist_anterior ///
    if elective_rule == 2 ///
    & !missing(hist_anterior)

replace miss_required_anterior = 1 ///
    if elective_rule == 2 ///
    & missing(hist_anterior)

replace elective_anterior = sci_anterior ///
    if elective_rule == 3 ///
    & !missing(sci_anterior)

replace miss_required_anterior = 1 ///
    if elective_rule == 3 ///
    & missing(sci_anterior)


/************************************************************
* 8.3 Score anterior y reglas mínimas
************************************************************/

gen double score_cf_anterior = ///
      c_gpa_anterior ///
    + c_read_anterior ///
    + c_math_anterior ///
    + elective_anterior

replace score_cf_anterior = . if miss_required_anterior == 1

gen double lm_anterior = (lyc_anterior + mate_anterior) / 2 ///
    if !missing(lyc_anterior, mate_anterior)

gen byte valid_anterior = 1

replace valid_anterior = 0 if missing(score_cf_anterior)

replace valid_anterior = 0 if !missing(min_application_score) ///
    & score_cf_anterior < min_application_score

replace valid_anterior = 0 if !missing(min_reading_math) ///
    & lm_anterior < min_reading_math

gen double score_cf_anterior_valid = score_cf_anterior
replace score_cf_anterior_valid = . if valid_anterior == 0


/************************************************************
* 9. Elegir mejor batería válida: actual vs anterior
************************************************************/

egen double score_counterfactual = rowmax(score_cf_actual_valid score_cf_anterior_valid)

gen double margin_counterfactual = ///
    score_counterfactual - cutoff_program_year

gen byte would_be_admitted_year = ///
    score_counterfactual >= cutoff_program_year ///
    if !missing(score_counterfactual, cutoff_program_year)

label define admit_lbl ///
    0 "Would not be admitted" ///
    1 "Would be admitted", replace

label values would_be_admitted_year admit_lbl


/**********************************************************************
* 10. Diagnóstico: comparar score contrafactual del año real
*     con application_score observado
**********************************************************************/

preserve

    keep if cutoff_year == application_year

    gen double diff_score = score_counterfactual - application_score

    di as text "=================================================="
    di as result "Diagnóstico: score contrafactual año real vs application_score"
    di as text "=================================================="

    summarize score_counterfactual application_score diff_score, detail

    count if abs(diff_score) <= 0.01
    di as result "Obs con diferencia <= 0.01: " r(N)

    count if abs(diff_score) > 1 & !missing(diff_score)
    di as result "Obs con diferencia > 1 punto: " r(N)

    count if abs(diff_score) > 5 & !missing(diff_score)
    di as result "Obs con diferencia > 5 puntos: " r(N)

    count if missing(score_counterfactual)
    di as result "Obs con score_counterfactual missing en año real: " r(N)

    count if missing(application_score)
    di as result "Obs con application_score missing en año real: " r(N)

restore


/**********************************************************************
* 11. Definir inframarginal
*
* Versión 2007-2012:
*   inframarginal = 1 si el estudiante habría sido admitido en los
*   seis años 2007, 2008, 2009, 2010, 2011 y 2012.
**********************************************************************/

bysort mrun application_year preferencia target_codigo_carrera: ///
    egen n_years_program = count(cutoff_year)

bysort mrun application_year preferencia target_codigo_carrera: ///
    egen n_years_admitted = total(would_be_admitted_year)

bysort mrun application_year preferencia target_codigo_carrera: ///
    egen min_margin_all_years = min(margin_counterfactual)

bysort mrun application_year preferencia target_codigo_carrera: ///
    egen mean_margin_all_years = mean(margin_counterfactual)

bysort mrun application_year preferencia target_codigo_carrera: ///
    egen max_cutoff_program = max(cutoff_program_year)

bysort mrun application_year preferencia target_codigo_carrera: ///
    egen min_cutoff_program = min(cutoff_program_year)

gen byte inframarginal_2007_2012 = ///
    n_years_program == `required_years' ///
    & n_years_admitted == `required_years' ///
    if n_years_program > 0

label define inframarginal_0712_lbl ///
    0 "Not inframarginal 2007-2012" ///
    1 "Inframarginal 2007-2012", replace

label values inframarginal_2007_2012 inframarginal_0712_lbl


/**********************************************************************
* 12. Volver a una observación por estudiante-target
**********************************************************************/

bysort mrun application_year preferencia target_codigo_carrera: keep if _n == 1

keep mrun application_year preferencia target_codigo_carrera ///
     program_code_harmonized ///
     inframarginal_2007_2012 ///
     n_years_program n_years_admitted ///
     min_margin_all_years mean_margin_all_years ///
     min_cutoff_program max_cutoff_program

rename application_year ao_proceso
rename target_codigo_carrera codigo_carrera

tempfile inframarginal_aux
save `inframarginal_aux', replace


/**********************************************************************
* 13. Diagnósticos de inframarginal
**********************************************************************/

di as text "=================================================="
di as result "Diagnóstico general inframarginal 2007-2012"
di as text "=================================================="

tab inframarginal_2007_2012, missing

di as text "=================================================="
di as result "Inframarginal por año de aplicación"
di as text "=================================================="

tab ao_proceso inframarginal_2007_2012, missing row

di as text "=================================================="
di as result "Número de años disponibles por programa 2007-2012"
di as text "=================================================="

tab n_years_program, missing

di as text "=================================================="
di as result "Margen mínimo contrafactual"
di as text "=================================================="

summarize min_margin_all_years mean_margin_all_years ///
          min_cutoff_program max_cutoff_program, detail


/**********************************************************************
* 14. Pegar indicador inframarginal a analysis sample
*
* Importante:
*   En analysis_sample_delta_groups.dta también están 2012 y las
*   universidades privadas adscritas. Las excluimos antes del merge
*   para que el output sea consistente con el universo construido.
**********************************************************************/

use "`analysis'", clear

capture confirm variable codigo_carrera
if _rc != 0 {
    capture confirm variable t_codigo_carrera
    if _rc == 0 rename t_codigo_carrera codigo_carrera
    else {
        di as error "No existe codigo_carrera ni t_codigo_carrera en analysis."
        exit 111
    }
}

capture confirm variable sigla_universidad
if _rc != 0 {
    di as error "Falta sigla_universidad en analysis para aplicar exclusión."
    exit 111
}

capture confirm numeric variable codigo_carrera
if _rc != 0 destring codigo_carrera, replace force

capture confirm numeric variable ao_proceso
if _rc != 0 destring ao_proceso, replace force

gen str20 sigla_clean = lower(strtrim(sigla_universidad))

drop if inrange(ao_proceso, `first_year', `last_year') ///
    & inlist(sigla_clean, ///
        "uah", ///
        "uai", ///
        "uande", ///
        "udd", ///
        "udp", ///
        "uft", ///
        "umayo", ///
        "unab")

drop sigla_clean

foreach v in mrun ao_proceso preferencia codigo_carrera {
    capture confirm variable `v'
    if _rc != 0 {
        di as error "Falta variable de merge en analysis: `v'"
        exit 111
    }
}

foreach v in ///
    inframarginal ///
    inframarginal_2007_2012 ///
    n_years_program ///
    n_years_admitted ///
    min_margin_all_years ///
    mean_margin_all_years ///
    min_cutoff_program ///
    max_cutoff_program ///
    program_code_harmonized {

    capture drop `v'
}

merge m:1 mrun ao_proceso preferencia codigo_carrera ///
    using `inframarginal_aux', ///
    keep(master match) nogen

/*
Para años fuera de 2007-2012 dejamos missing.
Para años 2007-2012 sin match, dejamos 0.
*/

replace inframarginal_2007_2012 = 0 ///
    if inrange(ao_proceso, `first_year', `last_year') ///
    & missing(inframarginal_2007_2012)

label values inframarginal_2007_2012 inframarginal_0712_lbl

di as text "=================================================="
di as result "Inframarginal 2007-2012 en analysis sample"
di as text "=================================================="

tab inframarginal_2007_2012 if inrange(ao_proceso, `first_year', `last_year'), missing

capture confirm variable score_rd
if _rc == 0 {
    tab inframarginal_2007_2012 ///
        if inrange(ao_proceso, `first_year', `last_year') ///
        & abs(score_rd) <= 25, missing
}

di as text "=================================================="
di as result "Inframarginal 2007-2012 por año en analysis sample"
di as text "=================================================="

tab ao_proceso inframarginal_2007_2012 ///
    if inrange(ao_proceso, `first_year', `last_year'), row missing

di as text "=================================================="
di as result "Años disponibles por programa en analysis sample"
di as text "=================================================="

tab ao_proceso n_years_program ///
    if inrange(ao_proceso, `first_year', `last_year'), row missing

save "$processed/analysis_sample_with_inframarginal_2007_2012.dta", replace


/**********************************************************************
* End
**********************************************************************/

di as text "=================================================="
di as result "20_build_inframarginal_sample_2007_2012 terminado."
di as result "Output:"
di as result "$processed/analysis_sample_with_inframarginal_2007_2012.dta"
di as text "=================================================="