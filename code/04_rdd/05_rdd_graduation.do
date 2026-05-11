/**********************************************************************
* 05_rdd_graduation.do
*
* RDD general de titulación a 8 años.
* No divide por campo.
*
* Outcomes:
*   - graduates_he_8y
*   - graduates_uni_8y
*   - graduates_target_8y
*
* Input:
*   - $processed/analysis_sample_with_fields_graduation_8y.dta
*
* Outputs:
*   - $output/tables/rdd_graduation_all.dta
*   - $output/tables/rdd_graduation_all.tex
**********************************************************************/

clear
set more off

************************************************************
* 0. Cargar configuración
************************************************************

do "C:/Users/jigodoy/Documents/GitHub/Majors/code/config.do"


************************************************************
* 1. Abrir base con outcomes de titulación
************************************************************

use "$processed/analysis_sample_with_fields_graduation_8y.dta", clear


************************************************************
* 2. Preparar muestra RDD
************************************************************

keep if abs(score_rd) <= $bandwidth

* Crear program-year id si no existe
capture confirm variable program_year_id
if _rc != 0 {
    egen program_year_id = group(ao_proceso t_codigo_carrera)
}

capture mkdir "$output/tables"


************************************************************
* 3. Diagnóstico de muestra
************************************************************

di as text "=================================================="
di as result "RDD sample: graduation outcomes, all fields"
di as text "=================================================="

count
tab above_cutoff, missing
tab graduates_he_8y, missing
tab graduates_uni_8y, missing
tab graduates_target_8y, missing

tab above_cutoff graduates_he_8y, row
tab above_cutoff graduates_uni_8y, row
tab above_cutoff graduates_target_8y, row


************************************************************
* 4. Estimaciones RDD generales
************************************************************

local outcomes graduates_he_8y graduates_uni_8y graduates_target_8y

tempfile results

postfile handle ///
    str35 outcome ///
    double beta ///
    double se ///
    double tstat ///
    double pval ///
    double ci_low ///
    double ci_high ///
    double N ///
    double clusters ///
    using `results', replace


foreach y of local outcomes {

    di as text "=================================================="
    di as result "Outcome: `y'"
    di as text "=================================================="

    reghdfe `y' ///
        above_cutoff score_rd 1.above_cutoff#c.score_rd, ///
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
* 5. Guardar resultados
************************************************************

use `results', clear

gen outcome_label = ""
replace outcome_label = "Graduated HE within 8 years" ///
    if outcome == "graduates_he_8y"
replace outcome_label = "Graduated university within 8 years" ///
    if outcome == "graduates_uni_8y"
replace outcome_label = "Graduated target program within 8 years" ///
    if outcome == "graduates_target_8y"

gen stars = ""
replace stars = "*"   if pval < 0.10
replace stars = "**"  if pval < 0.05
replace stars = "***" if pval < 0.01

gen beta_se = string(beta, "%9.3f") + stars + " (" + string(se, "%9.3f") + ")"

order outcome outcome_label beta se tstat pval ci_low ci_high N clusters stars beta_se

save "$output/tables/rdd_graduation_all.dta", replace


************************************************************
* 6. Exportar tabla LaTeX
************************************************************

local texfile "$output/tables/rdd_graduation_all.tex"

capture erase "`texfile'"

file open tex using "`texfile'", write replace

file write tex "\begin{table}[!htbp]\centering" _n
file write tex "\caption{RDD Estimates on Graduation Outcomes}" _n
file write tex "\label{tab:rdd_graduation_all}" _n
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
file write tex "\multicolumn{2}{l}{\footnotesize Graduation is measured within eight years of the admission process.} \\" _n
file write tex "\multicolumn{2}{l}{\footnotesize * p$<$0.10, ** p$<$0.05, *** p$<$0.01.} \\" _n
file write tex "\hline\hline" _n
file write tex "\end{tabular}" _n
file write tex "\end{table}" _n

file close tex


************************************************************
* 7. Mostrar resumen
************************************************************

di as text "=================================================="
di as result "RDD graduation all fields"
di as text "=================================================="

list outcome_label beta se pval N clusters, noobs abbreviate(35)

di as result "Resultados guardados en:"
di as result "$output/tables/rdd_graduation_all.dta"
di as result "$output/tables/rdd_graduation_all.tex"