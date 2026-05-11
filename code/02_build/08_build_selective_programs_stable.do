/**********************************************************************
* 08_build_selective_programs_stable.do
*
* Construye indicadores de selectividad usando un identificador estable
* de programa basado en:
*
*   universidad + sede + nombre de carrera
*
* Esto evita depender solo de t_codigo_carrera, que cambia en el tiempo.
*
* Base inicial:
*   $processed/analysis_sample_with_fields_final.dta
*
* Definición de selectividad:
*   Puntaje promedio PSU Lenguaje-Matemática de los admitidos
*   por programa estable-año.
*
* Modos disponibles:
*   - Top X% dentro de cada año, por ejemplo top 20% o top 10%.
*   - Cuantiles, por ejemplo cuartil superior.
*
* Definición principal de persistencia:
*   Programa observado en el máximo número de años disponible
*   y clasificado como selectivo en todos esos años.
*
* Outputs:
*   $processed/selectivity_program_year_stable.dta
*   $processed/selectivity_program_persistent_stable.dta
*   $processed/analysis_sample_with_selectivity_stable.dta
**********************************************************************/

clear
set more off

************************************************************
* 0. Cargar configuración
************************************************************

do "C:/Users/jigodoy/Documents/GitHub/Majors/code/config.do"

capture mkdir "$output/tables"


************************************************************
* 1. Parámetros modificables
************************************************************

*----------------------------------------------------------*
* Modo de selectividad:
*
* "top"      = top X% de programas dentro de cada año
* "quantile" = cuartiles, quintiles, deciles, etc.
*----------------------------------------------------------*

local mode "top"

* Si mode == "top":
local top_share = 0.20

* Ejemplos:
* local top_share = 0.20   // top 20%
* local top_share = 0.10   // top 10%

* Si mode == "quantile":
local nq = 4
local selected_quantile = 4

* Ejemplo cuartil superior:
* local mode "quantile"
* local nq = 4
* local selected_quantile = 4

* Mínimo de admitidos con puntaje válido por programa estable-año:
local min_admitted = 5

* Parámetros para definición flexible, solo como comparación/robustez.
local min_share_persistent = 1
local min_years_observed = 3


************************************************************
* 2. Variables base
************************************************************

local year_var       ao_proceso
local code_var       t_codigo_carrera
local status_var     estado_preferencia
local admitted_value = 24

local psu_lang_var   lyc_actual
local psu_math_var   mate_actual


************************************************************
* 3. Abrir base inicial
************************************************************

capture confirm file "$processed/analysis_sample_with_fields_final.dta"
if _rc != 0 {
    di as error "No existe la base: $processed/analysis_sample_with_fields_final.dta"
    exit 601
}

di as result "Abriendo base: $processed/analysis_sample_with_fields_final.dta"

use "$processed/analysis_sample_with_fields_final.dta", clear


************************************************************
* 4. Chequeos mínimos de variables
************************************************************

foreach v in `year_var' `code_var' `status_var' ///
             `psu_lang_var' `psu_math_var' ///
             sigla_universidad sede_carrera nombre_carrera {

    capture confirm variable `v'
    if _rc != 0 {
        di as error "No existe la variable `v'."
        exit 111
    }
}


************************************************************
* 5. Crear identificador estable de programa
************************************************************

* Universidad
gen univ_clean = upper(sigla_universidad)
replace univ_clean = strtrim(univ_clean)
replace univ_clean = itrim(univ_clean)

* Sede
gen sede_clean = upper(sede_carrera)
replace sede_clean = strtrim(sede_clean)
replace sede_clean = itrim(sede_clean)

* Carrera
gen carrera_clean = upper(nombre_carrera)
replace carrera_clean = strtrim(carrera_clean)
replace carrera_clean = itrim(carrera_clean)

* Identificador estable:
* mismo programa si coincide universidad + sede + nombre carrera.
egen program_stable_id = group(univ_clean sede_clean carrera_clean)

label variable program_stable_id ///
    "Stable program ID based on university, campus, and program name"

gen year = `year_var'
gen program_code_original = `code_var'

label variable program_code_original "Original DEMRE program code"


************************************************************
* 6. Diagnóstico del identificador estable
************************************************************

preserve

    keep year program_code_original program_stable_id ///
         univ_clean sede_clean carrera_clean

    duplicates drop

    bysort program_stable_id year: gen tag_program_year = _n == 1
    bysort program_stable_id: egen n_years_stable = total(tag_program_year)

    bysort program_stable_id program_code_original: gen tag_code = _n == 1
    bysort program_stable_id: egen n_codes = total(tag_code)

    di as text "=================================================="
    di as result "Diagnóstico de program_stable_id"
    di as text "=================================================="

    tab n_years_stable
    tab n_codes

    count if n_years_stable == 10
    di as result "Stable programs observed 10 years: " r(N)

    count if n_codes > 1
    di as result "Stable program-year rows with more than one historical code: " r(N)

restore


************************************************************
* 7. Crear puntaje promedio PSU Lenguaje-Matemática
************************************************************

gen psu_lm = (`psu_lang_var' + `psu_math_var') / 2 ///
    if !missing(`psu_lang_var', `psu_math_var')

label variable psu_lm "Average PSU score: Language and Math"

summarize psu_lm, detail


************************************************************
* 8. Mantener solo admitidos con puntaje válido
************************************************************

keep if `status_var' == `admitted_value'
keep if !missing(psu_lm)


************************************************************
* 9. Calcular selectividad programa estable-año
************************************************************

collapse ///
    (mean) mean_psu_lm_admitted = psu_lm ///
    (count) n_admitted_score = psu_lm ///
    (firstnm) univ_clean sede_clean carrera_clean, ///
    by(program_stable_id year)

label variable mean_psu_lm_admitted ///
    "Mean PSU Language-Math among admitted students"

label variable n_admitted_score ///
    "Number of admitted students with valid PSU score"

drop if n_admitted_score < `min_admitted'


************************************************************
* 10. Rankear programas estables dentro de cada año
************************************************************

gsort year -mean_psu_lm_admitted

by year: gen rank_desc = _n
by year: gen n_programs_year = _N

gen share_rank_desc = rank_desc / n_programs_year

label variable rank_desc ///
    "Rank within year, descending selectivity"

label variable n_programs_year ///
    "Number of stable programs observed in year"

label variable share_rank_desc ///
    "Descending rank divided by number of programs"


************************************************************
* 11. Crear indicador selectivo programa estable-año
************************************************************

gen selective_year = .
label variable selective_year "Stable program-year classified as selective"

if "`mode'" == "top" {

    gen top_cutoff_n = ceil(n_programs_year * `top_share')

    label variable top_cutoff_n ///
        "Number of programs selected under top share rule"

    replace selective_year = rank_desc <= top_cutoff_n

    gen str40 selectivity_definition = ///
        "Top " + string(100 * `top_share') + "%"
}

if "`mode'" == "quantile" {

    gen quantile_selectivity_year = ///
        ceil((n_programs_year - rank_desc + 1) / (n_programs_year / `nq'))

    replace quantile_selectivity_year = 1 if quantile_selectivity_year < 1
    replace quantile_selectivity_year = `nq' if quantile_selectivity_year > `nq'

    label variable quantile_selectivity_year ///
        "Selectivity quantile within year"

    replace selective_year = quantile_selectivity_year == `selected_quantile'

    gen str40 selectivity_definition = ///
        "Quantile " + string(`selected_quantile') + " of " + string(`nq')
}

replace selective_year = 0 if missing(selective_year)


************************************************************
* 12. Diagnóstico programa estable-año
************************************************************

di as text "=================================================="
di as result "Stable program-year selectivity classification"
di as text "=================================================="

tab year selective_year, row

summarize mean_psu_lm_admitted if selective_year == 1
summarize mean_psu_lm_admitted if selective_year == 0

count
count if selective_year == 1
count if selective_year == 0


************************************************************
* 13. Guardar base programa estable-año
************************************************************

save "$processed/selectivity_program_year_stable.dta", replace


************************************************************
* 14. Crear indicador de selectividad persistente estable
************************************************************

collapse ///
    (mean) share_selective = selective_year ///
    (count) n_years_observed = year ///
    (mean) avg_mean_psu_lm_admitted = mean_psu_lm_admitted ///
    (min) min_mean_psu_lm_admitted = mean_psu_lm_admitted ///
    (max) max_mean_psu_lm_admitted = mean_psu_lm_admitted ///
    (firstnm) univ_clean sede_clean carrera_clean, ///
    by(program_stable_id)


************************************************************
* 14.1 Detectar máximo de años observados
************************************************************

summarize n_years_observed, meanonly
local max_years_observed = r(max)

di as text "=================================================="
di as result "Maximum number of observed years by stable program: `max_years_observed'"
di as text "=================================================="


************************************************************
* 14.2 Definiciones de persistencia
************************************************************

* Flexible:
* Selectivo en al menos X% de los años observados,
* con un mínimo de años observados.
gen selective_persistent_flexible = ///
    share_selective >= `min_share_persistent'

replace selective_persistent_flexible = 0 ///
    if n_years_observed < `min_years_observed'


* Estricta:
* Observado en el máximo número de años disponible
* y selectivo en todos esos años.
gen selective_persistent_all_years = ///
    share_selective == 1 & n_years_observed == `max_years_observed'


* Variable principal para RDD selectivo:
gen selective_persistent = selective_persistent_all_years


************************************************************
* 14.3 Labels
************************************************************

label variable share_selective ///
    "Share of observed years classified as selective"

label variable n_years_observed ///
    "Number of years observed"

label variable selective_persistent_flexible ///
    "Persistently selective stable program, flexible definition"

label variable selective_persistent_all_years ///
    "Selective in all available years and observed in max years"

label variable selective_persistent ///
    "Main persistent selectivity indicator"

label variable avg_mean_psu_lm_admitted ///
    "Average stable program selectivity across observed years"

label variable min_mean_psu_lm_admitted ///
    "Minimum stable program selectivity across observed years"

label variable max_mean_psu_lm_admitted ///
    "Maximum stable program selectivity across observed years"


************************************************************
* 15. Diagnóstico persistencia estable
************************************************************

di as text "=================================================="
di as result "Persistent selectivity classification - stable ID"
di as text "=================================================="

tab n_years_observed
tab share_selective

tab selective_persistent_flexible, missing
tab selective_persistent_all_years, missing
tab selective_persistent, missing

count
count if selective_persistent == 1
count if selective_persistent == 0

summarize share_selective n_years_observed avg_mean_psu_lm_admitted ///
    if selective_persistent == 1

summarize share_selective n_years_observed avg_mean_psu_lm_admitted ///
    if selective_persistent == 0

gsort -selective_persistent -avg_mean_psu_lm_admitted

list program_stable_id univ_clean sede_clean carrera_clean ///
     n_years_observed share_selective avg_mean_psu_lm_admitted ///
     if selective_persistent == 1 in 1/50, ///
     noobs abbreviate(35)


************************************************************
* 16. Guardar base persistente estable
************************************************************

save "$processed/selectivity_program_persistent_stable.dta", replace


************************************************************
* 17. Pegar selectividad estable a la base final
************************************************************

use "$processed/analysis_sample_with_fields_final.dta", clear

************************************************************
* 17.1 Recrear el mismo identificador estable
************************************************************

gen univ_clean = upper(sigla_universidad)
replace univ_clean = strtrim(univ_clean)
replace univ_clean = itrim(univ_clean)

gen sede_clean = upper(sede_carrera)
replace sede_clean = strtrim(sede_clean)
replace sede_clean = itrim(sede_clean)

gen carrera_clean = upper(nombre_carrera)
replace carrera_clean = strtrim(carrera_clean)
replace carrera_clean = itrim(carrera_clean)

egen program_stable_id = group(univ_clean sede_clean carrera_clean)

gen year = `year_var'


************************************************************
* 17.2 Merge programa estable-año
************************************************************

merge m:1 program_stable_id year ///
    using "$processed/selectivity_program_year_stable.dta", ///
    keep(master match) nogen


************************************************************
* 17.3 Merge programa estable persistente
************************************************************

merge m:1 program_stable_id ///
    using "$processed/selectivity_program_persistent_stable.dta", ///
    keep(master match) nogen


************************************************************
* 17.4 Reemplazar missing por cero en indicadores
************************************************************

replace selective_year = 0 if missing(selective_year)
replace selective_persistent_flexible = 0 if missing(selective_persistent_flexible)
replace selective_persistent_all_years = 0 if missing(selective_persistent_all_years)
replace selective_persistent = 0 if missing(selective_persistent)


************************************************************
* 18. Crear program_year_id original si no existe
*
* Importante:
* El RDD sigue usando el programa-año original, porque el cutoff
* está definido a nivel t_codigo_carrera x ao_proceso.
************************************************************

capture confirm variable program_year_id
if _rc != 0 {
    egen program_year_id = group(ao_proceso t_codigo_carrera)
}


************************************************************
* 19. Diagnóstico final
************************************************************

di as text "=================================================="
di as result "Analysis sample with stable selectivity indicators"
di as text "=================================================="

count

tab selective_year, missing
tab selective_persistent_flexible, missing
tab selective_persistent_all_years, missing
tab selective_persistent, missing

distinct program_stable_id
distinct program_stable_id if selective_persistent == 1

distinct program_year_id
distinct program_year_id if selective_persistent == 1

count if selective_persistent == 1

count if abs(score_rd) <= $bandwidth
count if abs(score_rd) <= $bandwidth & selective_persistent == 1

tab above_cutoff if abs(score_rd) <= $bandwidth, missing
tab above_cutoff if abs(score_rd) <= $bandwidth & selective_persistent == 1, missing


************************************************************
* 20. Exportar lista de programas selectivos persistentes
************************************************************

preserve

    keep if selective_persistent == 1

    keep program_stable_id univ_clean sede_clean carrera_clean ///
         n_years_observed share_selective avg_mean_psu_lm_admitted ///
         min_mean_psu_lm_admitted max_mean_psu_lm_admitted

    duplicates drop program_stable_id, force

    gsort -avg_mean_psu_lm_admitted

    export excel using "$output/tables/programas_selectivos_persistentes_stable.xlsx", ///
        firstrow(variables) replace

restore


************************************************************
* 21. Guardar analysis sample con selectividad estable
************************************************************

save "$processed/analysis_sample_with_selectivity_stable.dta", replace


************************************************************
* 22. Mostrar resumen final
************************************************************

di as result "Resultados guardados en:"
di as result "$processed/selectivity_program_year_stable.dta"
di as result "$processed/selectivity_program_persistent_stable.dta"
di as result "$processed/analysis_sample_with_selectivity_stable.dta"
di as result "$output/tables/programas_selectivos_persistentes_stable.xlsx"




