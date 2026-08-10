************************************************************
* 08_build_selective_programs.do
* Build selectivity using pooled post-2012 program-years
*
* Definición:
* - Usar applications_rd.dta.
* - Mantener años >= 2012.
* - Admitidos: estado_preferencia == 24.
* - Calcular promedio PSU LM por programa-año.
* - Apilar todos los programa-años en una sola lista.
* - Seleccionar el top 20% de esa lista.
* - Un programa queda selectivo si aparece en ese top 20%.
*
* Output único:
* $processed/analysis_sample_with_selectivity_post2012_pooled_top20.dta
************************************************************

clear all
set more off

************************************************************
* 0. Configuración
************************************************************

capture do "C:\Users\jigodoy\Documents\GitHub\Majors\code\config.do"

local top_share 0.20
local min_admitted_year 5


************************************************************
* 1. Cargar base amplia de postulaciones
************************************************************

use "$processed/applications_rd.dta", clear


************************************************************
* 2. Crear variables base y código armonizado
*
* En applications_rd.dta el código del programa es codigo_carrera.
************************************************************

gen year = ao_proceso
gen program_code_original = codigo_carrera

tostring program_code_original, gen(code_str) format(%20.0f) force
replace code_str = strtrim(code_str)

gen str20 program_code_harmonized = code_str

* Armonización pre-2012:
* ejemplo 1414 -> 14014
replace program_code_harmonized = ///
    substr(code_str, 1, 2) + "0" + substr(code_str, 3, .) ///
    if year <= 2011 & length(code_str) == 4

label variable program_code_harmonized ///
    "Program code harmonized using pre/post 2012 zero-insertion rule"


************************************************************
* 3. Crear PSU Lenguaje-Matemática
************************************************************

capture confirm variable psu_lm

if _rc != 0 {

    capture confirm variable lyc_actual
    if _rc != 0 {
        di as error "No existe psu_lm ni lyc_actual."
        exit 111
    }

    capture confirm variable mate_actual
    if _rc != 0 {
        di as error "No existe psu_lm ni mate_actual."
        exit 111
    }

    capture confirm numeric variable lyc_actual
    if _rc == 0 {
        gen double lyc_actual_num = lyc_actual
    }
    else {
        gen double lyc_actual_num = real(lyc_actual)
    }

    capture confirm numeric variable mate_actual
    if _rc == 0 {
        gen double mate_actual_num = mate_actual
    }
    else {
        gen double mate_actual_num = real(mate_actual)
    }

    gen double psu_lm = (lyc_actual_num + mate_actual_num) / 2 ///
        if !missing(lyc_actual_num, mate_actual_num)
}

label variable psu_lm "Average PSU Language-Math"


************************************************************
* 4. Mantener años post-2012 y admitidos
************************************************************

keep if year >= 2012
keep if estado_preferencia == 24
keep if !missing(psu_lm)


************************************************************
* 5. Colapsar a programa-año
************************************************************

collapse ///
    (mean) mean_psu_lm_year = psu_lm ///
    (p50)  p50_psu_lm_year = psu_lm ///
    (count) n_admitted_year = psu_lm ///
    (firstnm) sigla_universidad sede_carrera nombre_carrera, ///
    by(program_code_harmonized year)

drop if n_admitted_year < `min_admitted_year'


************************************************************
* 6. Ranking pooled de todos los programa-años
*
* Aquí NO se rankea por año.
* Todos los programa-años desde 2012 compiten en una sola lista.
************************************************************

gsort -mean_psu_lm_year

gen rank_pooled_post12 = _n
gen n_program_years_post12 = _N
gen top_cutoff_pooled = ceil(n_program_years_post12 * `top_share')

gen selective_pooled_top20_year = rank_pooled_post12 <= top_cutoff_pooled

label variable rank_pooled_post12 ///
    "Rank among all pooled post-2012 program-years"

label variable n_program_years_post12 ///
    "Number of pooled post-2012 program-years"

label variable selective_pooled_top20_year ///
    "Program-year in pooled top 20% post-2012"


************************************************************
* 7. Diagnóstico del top 20% pooled
************************************************************

di as text "=================================================="
di as result "Top 20% pooled de programa-años post-2012"
di as text "=================================================="

count
count if selective_pooled_top20_year == 1

distinct program_code_harmonized
distinct program_code_harmonized if selective_pooled_top20_year == 1

summarize mean_psu_lm_year if selective_pooled_top20_year == 1, detail
summarize mean_psu_lm_year if selective_pooled_top20_year == 0, detail


************************************************************
* 8. Llevar clasificación a nivel programa
*
* Un programa queda selectivo si aparece al menos una vez
* en el top 20% pooled de programa-años post-2012.
************************************************************

collapse ///
    (max) selective_pooled_top20 = selective_pooled_top20_year ///
    (mean) avg_psu_lm_post12_pool = mean_psu_lm_year ///
    (max) max_psu_lm_post12_pool = mean_psu_lm_year ///
    (min) min_psu_lm_post12_pool = mean_psu_lm_year ///
    (count) n_years_obs_post12_pool = year ///
    (sum) n_admitted_post12_pool = n_admitted_year ///
    (firstnm) sigla_universidad sede_carrera nombre_carrera, ///
    by(program_code_harmonized)

label variable selective_pooled_top20 ///
    "Program appears in pooled top 20% post-2012"

label variable avg_psu_lm_post12_pool ///
    "Average PSU L-M across observed post-2012 program-years"

label variable max_psu_lm_post12_pool ///
    "Maximum PSU L-M across observed post-2012 program-years"

label variable min_psu_lm_post12_pool ///
    "Minimum PSU L-M across observed post-2012 program-years"

label variable n_years_obs_post12_pool ///
    "Number of observed post-2012 years"

label variable n_admitted_post12_pool ///
    "Total admitted students with valid PSU L-M post-2012"


************************************************************
* 9. Diagnóstico a nivel programa
************************************************************

di as text "=================================================="
di as result "Programas selectivos según top 20% pooled"
di as text "=================================================="

count
count if selective_pooled_top20 == 1

distinct program_code_harmonized
distinct program_code_harmonized if selective_pooled_top20 == 1

tab selective_pooled_top20, missing


************************************************************
* 10. Guardar clasificación temporal
************************************************************

tempfile selectivity_pooled_top20
save `selectivity_pooled_top20', replace


************************************************************
* 11. Pegar clasificación a analysis_sample
*
* En analysis_sample.dta el código del programa es t_codigo_carrera.
************************************************************

use "$processed/analysis_sample.dta", clear

gen year = ao_proceso
gen program_code_original = t_codigo_carrera

tostring program_code_original, gen(code_str) format(%20.0f) force
replace code_str = strtrim(code_str)

gen str20 program_code_harmonized = code_str

* Armonizar pre-2012 para que matchee con códigos post-2012.
replace program_code_harmonized = ///
    substr(code_str, 1, 2) + "0" + substr(code_str, 3, .) ///
    if year <= 2011 & length(code_str) == 4

label variable program_code_harmonized ///
    "Program code harmonized using pre/post 2012 zero-insertion rule"


************************************************************
* 11.1 Merge con clasificación pooled
************************************************************

merge m:1 program_code_harmonized ///
    using `selectivity_pooled_top20', ///
    keep(master match) nogen

replace selective_pooled_top20 = 0 if missing(selective_pooled_top20)

label variable selective_pooled_top20 ///
    "Program appears in pooled top 20% post-2012"


************************************************************
* 11.2 Asegurar program_year_id para RDD
************************************************************

capture confirm variable program_year_id

if _rc != 0 {
    egen program_year_id = group(ao_proceso t_codigo_carrera)
}


************************************************************
* 12. Diagnóstico final
************************************************************

di as text "=================================================="
di as result "Base final con selectividad pooled top 20%"
di as text "=================================================="

count

distinct program_code_original
distinct program_code_harmonized

distinct program_code_harmonized if selective_pooled_top20 == 1

tab selective_pooled_top20, missing

di as text "=================================================="
di as result "Muestra RDD dentro de bandwidth 25"
di as text "=================================================="

count if abs(score_rd) <= 25

count if abs(score_rd) <= 25 ///
    & selective_pooled_top20 == 1

distinct program_code_harmonized ///
    if abs(score_rd) <= 25 ///
    & selective_pooled_top20 == 1

distinct program_year_id ///
    if abs(score_rd) <= 25 ///
    & selective_pooled_top20 == 1


************************************************************
* 13. Guardar solo base final
************************************************************

save "$processed/analysis_sample_with_selectivity_post2012_pooled_top20.dta", replace

di as text "=================================================="
di as result "Listo. Base final guardada en:"
di as result "$processed/analysis_sample_with_selectivity_post2012_pooled_top20.dta"
di as text "=================================================="











