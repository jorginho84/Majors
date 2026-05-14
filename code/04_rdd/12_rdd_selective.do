************************************************************
* 12_rdd_selective.do
*
* RDD para programas selectivos definidos como:
* programas que aparecen al menos una vez en el top 20%
* de la lista pooled de programa-años post-2012.
*
* Input:
* $processed/analysis_sample_with_selectivity_post2012_pooled_top20.dta
*
* Output:
* $output/tables/rdd_selective_pooled_top20_results.dta
************************************************************

clear all
set more off

************************************************************
* 0. Configuración
************************************************************

capture do "C:\Users\jigodoy\Documents\GitHub\Majors\code\config.do"

global bandwidth 25

use "$processed/analysis_sample_with_selectivity_post2012_pooled_top20.dta", clear

capture mkdir "$output/tables"


************************************************************
* 1. Verificaciones iniciales
************************************************************

describe score_rd above_cutoff program_year_id ///
         selective_pooled_top20 ///
         enrolls_he enrolls_uni enrolls_target

di as text "=================================================="
di as result "Muestra RDD: selectividad pooled top 20%"
di as text "=================================================="

count if abs(score_rd) <= $bandwidth

count if abs(score_rd) <= $bandwidth ///
    & selective_pooled_top20 == 1

distinct program_code_harmonized ///
    if abs(score_rd) <= $bandwidth ///
    & selective_pooled_top20 == 1

distinct program_year_id ///
    if abs(score_rd) <= $bandwidth ///
    & selective_pooled_top20 == 1


************************************************************
* 2. Outcomes
************************************************************

local outcomes enrolls_he enrolls_uni enrolls_target


************************************************************
* 3. Estimar RDD
************************************************************

tempfile rdd_results

postfile handle ///
    str30 outcome ///
    double beta se pvalue ci_low ci_high N clusters mean_y ///
    using `rdd_results', replace

foreach y of local outcomes {

    di as text "=================================================="
    di as result "RDD outcome: `y'"
    di as text "=================================================="

    preserve

        keep if abs(score_rd) <= $bandwidth
        keep if selective_pooled_top20 == 1
        keep if !missing(`y', above_cutoff, score_rd, program_year_id)

        quietly summarize `y'
        local mean_y = r(mean)

        reghdfe `y' ///
            above_cutoff ///
            c.score_rd ///
            1.above_cutoff#c.score_rd, ///
            absorb(program_year_id) ///
            vce(cluster program_year_id)

        local beta = _b[above_cutoff]
        local se   = _se[above_cutoff]
        local t    = _b[above_cutoff] / _se[above_cutoff]
        local p    = 2 * ttail(e(df_r), abs(`t'))
        local cil  = `beta' - invttail(e(df_r), 0.025) * `se'
        local cih  = `beta' + invttail(e(df_r), 0.025) * `se'
        local N    = e(N)
        local cl   = e(N_clust)

        post handle ///
            ("`y'") ///
            (`beta') ///
            (`se') ///
            (`p') ///
            (`cil') ///
            (`cih') ///
            (`N') ///
            (`cl') ///
            (`mean_y')

    restore
}

postclose handle


************************************************************
* 4. Guardar resultados
************************************************************

use `rdd_results', clear

gen beta_se = string(beta, "%9.4f") + " (" + string(se, "%9.4f") + ")"

gen stars = ""
replace stars = "*"   if pvalue < 0.10
replace stars = "**"  if pvalue < 0.05
replace stars = "***" if pvalue < 0.01

gen beta_stars = string(beta, "%9.4f") + stars

order outcome beta se pvalue ci_low ci_high N clusters mean_y beta_se beta_stars

save "$output/tables/rdd_selective_pooled_top20_results.dta", replace

di as text "=================================================="
di as result "Resultados RDD: selectividad pooled top 20%"
di as text "=================================================="

list outcome beta se pvalue N clusters mean_y beta_se, noobs

di as text "=================================================="
di as result "RDD terminado"
di as result "$output/tables/rdd_selective_pooled_top20_results.dta"
di as text "=================================================="


use "$processed/analysis_sample_with_selectivity_post2012_pooled_top20.dta", clear

tab ao_proceso if abs(score_rd) <= 25
tab ao_proceso if abs(score_rd) <= 25 & selective_pooled_top20 == 1

preserve
    keep if abs(score_rd) <= 25
    keep if selective_pooled_top20 == 1
    keep ao_proceso program_year_id
    duplicates drop
    collapse (count) n_clusters = program_year_id, by(ao_proceso)
    list ao_proceso n_clusters, noobs
restore