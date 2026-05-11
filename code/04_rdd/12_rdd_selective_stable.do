/**********************************************************************
* 12_rdd_selective_stable.do
*
* RDD restringido a programas persistentemente selectivos.
*
* Base:
*   $processed/analysis_sample_with_selectivity_stable.dta
*
* Definición de selectividad:
*   Programas observados durante 2007-2016 y ubicados en el top 20%
*   de puntaje promedio PSU Lenguaje-Matemática de admitidos en todos
*   los años, usando program_stable_id.
*
* Especificación RDD:
*   Misma especificación base del RDD principal:
*
*   y = beta * above_cutoff
*       + f(score_rd)
*       + above_cutoff x f(score_rd)
*       + FE programa-año
*
* Outputs:
*   $output/tables/rdd_selective_stable_results.dta
*   $output/tables/rdd_selective_stable_results.tex
**********************************************************************/

clear
set more off

************************************************************
* 0. Cargar configuración
************************************************************

do "C:/Users/jigodoy/Documents/GitHub/Majors/code/config.do"

capture mkdir "$output/tables"


************************************************************
* 1. Abrir base con selectividad estable
************************************************************

capture confirm file "$processed/analysis_sample_with_selectivity_stable.dta"
if _rc != 0 {
    di as error "No existe la base: $processed/analysis_sample_with_selectivity_stable.dta"
    exit 601
}

use "$processed/analysis_sample_with_selectivity_stable.dta", clear


************************************************************
* 2. Chequeos mínimos
************************************************************

foreach v in enrolls_he enrolls_uni enrolls_target ///
             above_cutoff score_rd selective_persistent ///
             program_year_id program_stable_id {
    
    capture confirm variable `v'
    if _rc != 0 {
        di as error "No existe la variable `v'."
        exit 111
    }
}


************************************************************
* 3. Restringir muestra RDD
************************************************************

keep if abs(score_rd) <= $bandwidth
keep if selective_persistent == 1


************************************************************
* 4. Diagnóstico de muestra
************************************************************

di as text "=================================================="
di as result "RDD sample: persistently selective stable programs"
di as text "=================================================="

count

di as text "Número de programas estables:"
distinct program_stable_id

di as text "Número de programa-año originales:"
distinct program_year_id

di as text "Distribución sobre/bajo cutoff:"
tab above_cutoff, missing

di as text "Años:"
tab ao_proceso

di as text "Outcomes:"
summarize enrolls_he enrolls_uni enrolls_target

di as text "Running variable:"
summarize score_rd, detail


************************************************************
* 5. Outcomes principales
************************************************************

local outcomes enrolls_he enrolls_uni enrolls_target


************************************************************
* 6. Estimar RDD y guardar resultados
************************************************************

tempfile results_selective

postfile handle ///
    str40 outcome ///
    double beta ///
    double se ///
    double tstat ///
    double pval ///
    double ci_low ///
    double ci_high ///
    double N ///
    double clusters ///
    using `results_selective', replace


foreach y of local outcomes {

    di as text "=================================================="
    di as result "RDD selective stable programs - Outcome: `y'"
    di as text "=================================================="

    reghdfe `y' ///
        above_cutoff ///
        c.score_rd ///
        1.above_cutoff#c.score_rd, ///
        absorb(program_year_id) ///
        vce(cluster program_year_id)

    local b  = _b[above_cutoff]
    local s  = _se[above_cutoff]
    local t  = `b' / `s'
    local p  = 2 * ttail(e(df_r), abs(`t'))
    local lo = `b' - 1.96 * `s'
    local hi = `b' + 1.96 * `s'
    local N  = e(N)
    local G  = e(N_clust)

    post handle ///
        ("`y'") ///
        (`b') ///
        (`s') ///
        (`t') ///
        (`p') ///
        (`lo') ///
        (`hi') ///
        (`N') ///
        (`G')

    di as result "RD estimate: " %9.4f `b'
    di as result "SE:          " %9.4f `s'
    di as result "p-value:     " %9.4f `p'
    di as result "N:           " %12.0fc `N'
    di as result "Clusters:    " %12.0fc `G'
}

postclose handle


************************************************************
* 7. Guardar resultados
************************************************************

use `results_selective', clear

gen outcome_label = ""
replace outcome_label = "Enrolls in higher education" ///
    if outcome == "enrolls_he"
replace outcome_label = "Enrolls in university" ///
    if outcome == "enrolls_uni"
replace outcome_label = "Enrolls in target program" ///
    if outcome == "enrolls_target"

gen stars = ""
replace stars = "*"   if pval < 0.10
replace stars = "**"  if pval < 0.05
replace stars = "***" if pval < 0.01

gen beta_se = string(beta, "%9.3f") + stars + ///
    " (" + string(se, "%9.3f") + ")"

order outcome outcome_label beta se tstat pval ci_low ci_high N clusters stars beta_se

save "$output/tables/rdd_selective_stable_results.dta", replace


************************************************************
* 8. Exportar tabla LaTeX
************************************************************

local texfile "$output/tables/rdd_selective_stable_results.tex"

capture erase "`texfile'"

file open tex using "`texfile'", write replace

file write tex "\begin{table}[!htbp]\centering" _n
file write tex "\caption{RDD Estimates among Persistently Selective Programs}" _n
file write tex "\label{tab:rdd_selective_stable}" _n
file write tex "\begin{tabular}{lc}" _n
file write tex "\hline\hline" _n
file write tex "Outcome & RD Estimate \\" _n
file write tex "\hline" _n

forvalues i = 1/`=_N' {
    local lab = outcome_label[`i']
    local est = beta_se[`i']

    local lab = subinstr("`lab'", "&", "\&", .)
    local lab = subinstr("`lab'", "_", "\_", .)

    file write tex "`lab' & `est' \\" _n
}

file write tex "\hline" _n
file write tex "\multicolumn{2}{l}{\footnotesize Standard errors clustered at the program-year level in parentheses.} \\" _n
file write tex "\multicolumn{2}{l}{\footnotesize Sample restricted to applicants within $bandwidth points of the admission cutoff.} \\" _n
file write tex "\multicolumn{2}{l}{\footnotesize Persistently selective programs are defined using average PSU Language-Math scores among admitted students.} \\" _n
file write tex "\multicolumn{2}{l}{\footnotesize Selective programs are observed during the full 2007--2016 period and belong to the top 20 percent in all years.} \\" _n
file write tex "\multicolumn{2}{l}{\footnotesize * p$<$0.10, ** p$<$0.05, *** p$<$0.01.} \\" _n
file write tex "\hline\hline" _n
file write tex "\end{tabular}" _n
file write tex "\end{table}" _n

file close tex


************************************************************
* 9. Mostrar resumen final
************************************************************

use "$output/tables/rdd_selective_stable_results.dta", clear

list outcome beta se pval N clusters, noobs abbreviate(35)

di as result "Resultados guardados en:"
di as result "$output/tables/rdd_selective_stable_results.dta"
di as result "$output/tables/rdd_selective_stable_results.tex"