/**********************************************************************
* 20_build_inframarginal_sample_2013_2016.do
*
* Objetivo:
*   Construir muestra inframarginal usando solo años 2013-2016.
*
* Motivación:
*   Desde 2013 entra ptje_ranking en la ponderación del puntaje de
*   postulación. Para evitar comparar cohortes con reglas distintas,
*   esta prueba restringe el ejercicio a 2013, 2014, 2015 y 2016.
*
* Definición:
*   Un estudiante i es inframarginal para su target program p si:
*
*       PSU_i' w_{p,t} >= cutoff_{p,t}
*
*   para todos los años t = 2013, 2014, 2015, 2016 en que el programa
*   existe con reglas observables.
*
* Importante:
*   En esta versión NO armonizamos códigos pre/post 2012.
*   Usamos codigo_carrera tal como viene, porque solo trabajamos con
*   años post-2012.
*
* Inputs:
*   $processed/applications_rd.dta
*   $processed/analysis_sample_delta_groups.dta
*
* Output:
*   $processed/analysis_sample_with_inframarginal_2013_2016.dta
**********************************************************************/

clear all
set more off

do "C:/Users/jigodoy/Documents/GitHub/Majors/code/config.do"


/**********************************************************************
* 0. Parámetros
**********************************************************************/

local apps     "$processed/applications_rd.dta"
local analysis "$processed/analysis_sample_delta_groups.dta"

local first_year 2013
local last_year  2016
local required_years = `last_year' - `first_year' + 1


/**********************************************************************
* 1. Cargar applications_rd y verificar variables
**********************************************************************/

use "`apps'", clear

foreach v in ///
    mrun ///
    ao_proceso ///
    preferencia ///
    codigo_carrera ///
    ptje_nem ///
    ptje_ranking ///
    lyc_actual ///
    mate_actual ///
    hycs_actual ///
    ciencias_actual ///
    lyc_anterior ///
    mate_anterior ///
    hycs_anterior ///
    ciencias_anterior ///
    w_gpa ///
    w_rank ///
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
* 2. Crear código estable del programa
*
* En esta prueba 2013-2016 NO quitamos el cero de códigos post-2012.
* El identificador estable es simplemente el codigo_carrera observado.
**********************************************************************/

gen str10 code_str = string(codigo_carrera, "%12.0f")
replace code_str = strtrim(code_str)

gen str10 program_code_harmonized = code_str

drop code_str

di as text "=================================================="
di as result "Diagnóstico códigos 2013-2016"
di as text "=================================================="

count if inrange(ao_proceso, `first_year', `last_year')
di as result "Observaciones applications_rd 2013-2016: " r(N)

tab ao_proceso if inrange(ao_proceso, `first_year', `last_year'), missing


/**********************************************************************
* 3. Construir base estudiante-target con vector de puntajes
**********************************************************************/

tempfile student_targets

preserve

    keep if inrange(ao_proceso, `first_year', `last_year')

    keep mrun ao_proceso preferencia codigo_carrera ///
         program_code_harmonized ///
         application_score ///
         ptje_nem ptje_ranking ///
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

    keep ao_proceso codigo_carrera program_code_harmonized ///
         cutoff_regular ///
         min_application_score ///
         min_reading_math ///
         w_gpa w_rank w_reading w_math w_history w_science ///
         choose_hist_science

    drop if missing(ao_proceso, codigo_carrera, program_code_harmonized)
    drop if missing(cutoff_regular)

    foreach w in w_gpa w_rank w_reading w_math w_history w_science {
        capture confirm numeric variable `w'
        if _rc != 0 destring `w', replace force

        replace `w' = `w' / 100 if `w' > 1 & !missing(`w')
    }

    capture confirm numeric variable min_application_score
    if _rc != 0 destring min_application_score, replace force

    capture confirm numeric variable min_reading_math
    if _rc != 0 destring min_reading_math, replace force

    gen str10 choose_clean = upper(strtrim(choose_hist_science))

	/*
	Normalizar tildes o variantes simples.
	En la base vimos que choose_hist_science viene como "SI" / "NO".
	*/

	replace choose_clean = "SI" if inlist(choose_clean, "SÍ", "SI.", "S")
	replace choose_clean = "NO" if inlist(choose_clean, "NO.", "N")

	gen byte choose_elective = .

	replace choose_elective = 1 if inlist(choose_clean, "1", "SI", "YES", "Y", "TRUE")
	replace choose_elective = 0 if inlist(choose_clean, "0", "NO", "FALSE")

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

    /*
    Regla electiva:
      0 = no usa Historia/Ciencias
      1 = permite elegir mejor Historia/Ciencias
      2 = exige Historia
      3 = exige Ciencias

    Importante:
      No se suman Historia y Ciencias. Si el programa permite elegir,
      se usa la prueba con mayor aporte ponderado.
    */

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
    Si aparecen ambos pesos positivos, no se suman.
    Lo tratamos como elección y usamos la prueba con mayor aporte.
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

    duplicates drop ao_proceso program_code_harmonized cutoff_regular ///
        min_application_score min_reading_math ///
        w_gpa w_rank w_reading w_math w_history w_science ///
        choose_elective elective_rule, force

    bysort ao_proceso program_code_harmonized: gen n_prog_year = _N

    di as text "=================================================="
    di as result "Programa-año con múltiples combinaciones de cutoff/pesos"
    di as text "=================================================="

    tab n_prog_year, missing

    bysort ao_proceso program_code_harmonized: keep if _n == 1

    rename ao_proceso cutoff_year
    rename codigo_carrera cutoff_codigo_carrera
    rename cutoff_regular cutoff_program_year

    keep cutoff_year cutoff_codigo_carrera program_code_harmonized ///
         cutoff_program_year ///
         min_application_score min_reading_math ///
         w_gpa w_rank w_reading w_math w_history w_science ///
         choose_elective elective_rule

    save `program_year_weights', replace

restore


/**********************************************************************
* 5. Cruzar cada estudiante-target con todos los años del programa
*
* Como solo usamos 2013-2016, cada estudiante-target debería cruzarse
* con hasta 4 años programa-año si el programa existe en todos esos años.
**********************************************************************/

use `student_targets', clear

joinby program_code_harmonized using `program_year_weights'


/**********************************************************************
* 6. Preparar puntajes
**********************************************************************/

foreach v in ///
    ptje_nem ptje_ranking ///
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

replace miss_required_actual = 1 if w_rank > 0 ///
    & missing(ptje_ranking)

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

gen double c_rank_actual = 0
replace c_rank_actual = ptje_ranking * w_rank ///
    if w_rank > 0 & !missing(ptje_ranking, w_rank)

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
    + c_rank_actual ///
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

replace miss_required_anterior = 1 if w_rank > 0 ///
    & missing(ptje_ranking)

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

gen double c_rank_anterior = 0
replace c_rank_anterior = ptje_ranking * w_rank ///
    if w_rank > 0 & !missing(ptje_ranking, w_rank)

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
    + c_rank_anterior ///
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
* Versión 2013-2016:
*   inframarginal = 1 si el estudiante habría sido admitido en los
*   cuatro años 2013, 2014, 2015 y 2016.
*
*   Si el programa no existe en los cuatro años observables, queda 0
*   al pegar en analysis. Revisar n_years_program para diagnóstico.
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

gen byte inframarginal_2013_2016 = ///
    n_years_program == `required_years' ///
    & n_years_admitted == `required_years' ///
    if n_years_program > 0

label define inframarginal_lbl ///
    0 "Not inframarginal 2013-2016" ///
    1 "Inframarginal 2013-2016", replace

label values inframarginal_2013_2016 inframarginal_lbl


/**********************************************************************
* 12. Volver a una observación por estudiante-target
*     Nota: se guarda solo en tempfile, no como output permanente.
**********************************************************************/

bysort mrun application_year preferencia target_codigo_carrera: keep if _n == 1

keep mrun application_year preferencia target_codigo_carrera ///
     program_code_harmonized ///
     inframarginal_2013_2016 ///
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
di as result "Diagnóstico general inframarginal 2013-2016"
di as text "=================================================="

tab inframarginal_2013_2016, missing

di as text "=================================================="
di as result "Inframarginal por año de aplicación"
di as text "=================================================="

tab ao_proceso inframarginal_2013_2016, missing row

di as text "=================================================="
di as result "Número de años disponibles por programa 2013-2016"
di as text "=================================================="

tab n_years_program, missing

di as text "=================================================="
di as result "Margen mínimo contrafactual"
di as text "=================================================="

summarize min_margin_all_years mean_margin_all_years ///
          min_cutoff_program max_cutoff_program, detail


/**********************************************************************
* 14. Pegar indicador inframarginal a analysis sample
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

capture confirm numeric variable codigo_carrera
if _rc != 0 destring codigo_carrera, replace force

capture confirm numeric variable ao_proceso
if _rc != 0 destring ao_proceso, replace force

foreach v in mrun ao_proceso preferencia codigo_carrera {
    capture confirm variable `v'
    if _rc != 0 {
        di as error "Falta variable de merge en analysis: `v'"
        exit 111
    }
}

foreach v in ///
    inframarginal ///
    inframarginal_2013_2016 ///
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
Para años fuera de 2013-2016 dejamos missing, no 0.
Para años 2013-2016 sin match, dejamos 0 porque no califican como
inframarginales bajo esta prueba.
*/

replace inframarginal_2013_2016 = 0 ///
    if inrange(ao_proceso, `first_year', `last_year') ///
    & missing(inframarginal_2013_2016)

label values inframarginal_2013_2016 inframarginal_lbl

di as text "=================================================="
di as result "Inframarginal 2013-2016 en analysis sample"
di as text "=================================================="

tab inframarginal_2013_2016 if inrange(ao_proceso, `first_year', `last_year'), missing

capture confirm variable score_rd
if _rc == 0 {
    tab inframarginal_2013_2016 ///
        if inrange(ao_proceso, `first_year', `last_year') ///
        & abs(score_rd) <= 25, missing
}

di as text "=================================================="
di as result "Inframarginal 2013-2016 por año en analysis sample"
di as text "=================================================="

tab ao_proceso inframarginal_2013_2016 ///
    if inrange(ao_proceso, `first_year', `last_year'), row missing

save "$processed/analysis_sample_with_inframarginal_2013_2016.dta", replace


/**********************************************************************
* End
**********************************************************************/

di as text "=================================================="
di as result "20_build_inframarginal_sample_2013_2016 terminado."
di as result "Output:"
di as result "$processed/analysis_sample_with_inframarginal_2013_2016.dta"
di as text "=================================================="