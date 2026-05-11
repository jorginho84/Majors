/**********************************************************************
* 10_rdd_graduation_10y.do
*
* RDD de titulación a 10 años.
*
* Base:
*   $processed/analysis_sample_with_fields_graduation_10y.dta
*
* Outcomes:
*   graduates_he_10y
*   graduates_uni_10y
*   graduates_target_10y
*
* Outputs:
*   $output/tables/rdd_graduation_10y_all.dta
*   $output/tables/rdd_graduation_10y_all.tex
*   $output/tables/rdd_graduation_10y_by_field.dta
*   $output/tables/rdd_graduation_10y_by_field.tex
**********************************************************************/

clear
set more off

************************************************************
* 0. Cargar configuración
************************************************************

do "C:/Users/jigodoy/Documents/GitHub/Majors/code/config.do"

capture mkdir "$output/tables"


************************************************************
* 1. Abrir base de graduación a 10 años
************************************************************

use "$processed/analysis_sample_with_fields_graduation_10y.dta", clear

keep if abs(score_rd) <= $bandwidth

drop if missing(field)
drop if field == ""
drop if field == "Missing"

capture confirm variable program_year_id
if _rc != 0 {
    egen program_year_id = group(ao_proceso t_codigo_carrera)
}

local outcomes graduates_he_10y graduates_uni_10y graduates_target_10y


************************************************************
* 2. Diagnóstico inicial
************************************************************

di as text "=================================================="
di as result "RDD sample: graduation outcomes, 10-year window"
di as text "=================================================="

count
tab ao_proceso
tab above_cutoff, missing
tab graduates_he_10y, missing
tab graduates_uni_10y, missing
tab graduates_target_10y, missing
tab field, missing


************************************************************
* 3. RDD general: todos los campos juntos
************************************************************

tempfile results_all

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
    using `results_all', replace

foreach y of local outcomes {

    di as text "=================================================="
    di as result "RDD general - Outcome: `y'"
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
* 4. Guardar RDD general
************************************************************

use `results_all', clear

gen outcome_label = ""
replace outcome_label = "Graduated HE within 10 years" ///
    if outcome == "graduates_he_10y"
replace outcome_label = "Graduated university within 10 years" ///
    if outcome == "graduates_uni_10y"
replace outcome_label = "Graduated target program within 10 years" ///
    if outcome == "graduates_target_10y"

gen stars = ""
replace stars = "*"   if pval < 0.10
replace stars = "**"  if pval < 0.05
replace stars = "***" if pval < 0.01

gen beta_se = string(beta, "%9.3f") + stars + " (" + string(se, "%9.3f") + ")"

order outcome outcome_label beta se tstat pval ci_low ci_high N clusters stars beta_se

save "$output/tables/rdd_graduation_10y_all.dta", replace


************************************************************
* 5. Exportar RDD general a LaTeX
************************************************************

local texfile "$output/tables/rdd_graduation_10y_all.tex"

capture erase "`texfile'"

file open tex using "`texfile'", write replace

file write tex "\begin{table}[!htbp]\centering" _n
file write tex "\caption{RDD Estimates on Graduation Outcomes: 10-Year Window}" _n
file write tex "\label{tab:rdd_graduation_10y_all}" _n
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
file write tex "\multicolumn{2}{l}{\footnotesize Graduation is measured within ten years of the admission process.} \\" _n
file write tex "\multicolumn{2}{l}{\footnotesize Cohorts: 2007--2014.} \\" _n
file write tex "\multicolumn{2}{l}{\footnotesize * p$<$0.10, ** p$<$0.05, *** p$<$0.01.} \\" _n
file write tex "\hline\hline" _n
file write tex "\end{tabular}" _n
file write tex "\end{table}" _n

file close tex


************************************************************
* 6. Volver a abrir base para RDD por campo
************************************************************

use "$processed/analysis_sample_with_fields_graduation_10y.dta", clear

keep if abs(score_rd) <= $bandwidth

drop if missing(field)
drop if field == ""
drop if field == "Missing"

capture confirm variable program_year_id
if _rc != 0 {
    egen program_year_id = group(ao_proceso t_codigo_carrera)
}

local outcomes graduates_he_10y graduates_uni_10y graduates_target_10y


************************************************************
* 7. RDD por campo
************************************************************

tempfile results_field

postfile handle ///
    str40 field ///
    str40 outcome ///
    double beta ///
    double se ///
    double tstat ///
    double pval ///
    double ci_low ///
    double ci_high ///
    double N ///
    double clusters ///
    using `results_field', replace

levelsof field, local(fields)

foreach f of local fields {

    di _n as text "=================================================="
    di as result "FIELD: `f'"
    di as text "=================================================="

    foreach y of local outcomes {

        di _n as text "=== Outcome: `y' ==="

        preserve

            keep if field == "`f'"

            quietly count
            local N_field = r(N)

            if `N_field' == 0 {
                di as error "No observations for field `f'. Skipping."
                restore
                continue
            }

            capture noisily reghdfe `y' ///
                above_cutoff score_rd 1.above_cutoff#c.score_rd, ///
                absorb(program_year_id) ///
                vce(cluster program_year_id)

            if _rc != 0 {
                di as error "Regression failed for field `f', outcome `y'. Skipping."
                restore
                continue
            }

            local b  = _b[above_cutoff]
            local s  = _se[above_cutoff]
            local t  = `b' / `s'
            local p  = 2 * ttail(e(df_r), abs(`t'))
            local lo = `b' - 1.96 * `s'
            local hi = `b' + 1.96 * `s'
            local N  = e(N)
            local G  = e(N_clust)

            post handle ///
                ("`f'") ///
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

        restore
    }
}

postclose handle


************************************************************
* 8. Guardar resultados por campo
************************************************************

use `results_field', clear

gen outcome_label = ""
replace outcome_label = "Graduated HE within 10 years" ///
    if outcome == "graduates_he_10y"
replace outcome_label = "Graduated university within 10 years" ///
    if outcome == "graduates_uni_10y"
replace outcome_label = "Graduated target program within 10 years" ///
    if outcome == "graduates_target_10y"

gen stars = ""
replace stars = "*"   if pval < 0.10
replace stars = "**"  if pval < 0.05
replace stars = "***" if pval < 0.01

gen beta_se = string(beta, "%9.3f") + stars + " (" + string(se, "%9.3f") + ")"

order field outcome outcome_label beta se tstat pval ci_low ci_high N clusters stars beta_se

sort field outcome

save "$output/tables/rdd_graduation_10y_by_field.dta", replace

************************************************************
* 9. Crear tabla wide para LaTeX por campo
************************************************************

preserve

    keep field outcome beta_se N clusters

    reshape wide beta_se N clusters, i(field) j(outcome) string

    rename beta_segraduates_he_10y      Grad_HE_10y
    rename beta_segraduates_uni_10y     Grad_Uni_10y
    rename beta_segraduates_target_10y  Grad_Target_10y

    rename Ngraduates_he_10y            N_HE_10y
    rename Ngraduates_uni_10y           N_Uni_10y
    rename Ngraduates_target_10y        N_Target_10y

    rename clustersgraduates_he_10y     Clust_HE_10y
    rename clustersgraduates_uni_10y    Clust_Uni_10y
    rename clustersgraduates_target_10y Clust_Target_10y

    sort field

    tempfile wide_field
    save `wide_field', replace

restore
************************************************************
* 10. Exportar tabla LaTeX por campo
************************************************************

use `wide_field', clear

local texfile "$output/tables/rdd_graduation_10y_by_field.tex"

capture erase "`texfile'"

file open tex using "`texfile'", write replace

file write tex "\begin{table}[!htbp]\centering" _n
file write tex "\caption{RDD Estimates on Graduation Outcomes by Field of Study: 10-Year Window}" _n
file write tex "\label{tab:rdd_graduation_10y_by_field}" _n
file write tex "\begin{tabular}{lccc}" _n
file write tex "\hline\hline" _n
file write tex "Field & Graduated HE & Graduated University & Graduated Target Program \\" _n
file write tex "\hline" _n

forvalues i = 1/`=_N' {

    local f  = field[`i']
    local he = Grad_HE_10y[`i']
    local un = Grad_Uni_10y[`i']
    local tg = Grad_Target_10y[`i']

    local f = subinstr("`f'", "&", "\&", .)
    local f = subinstr("`f'", "_", "\_", .)

    file write tex "`f' & `he' & `un' & `tg' \\" _n
}

file write tex "\hline" _n
file write tex "\multicolumn{4}{l}{\footnotesize Standard errors clustered at the program-year level in parentheses.} \\" _n
file write tex "\multicolumn{4}{l}{\footnotesize Sample restricted to applicants within $bandwidth points of the admission cutoff.} \\" _n
file write tex "\multicolumn{4}{l}{\footnotesize Graduation is measured within ten years of the admission process.} \\" _n
file write tex "\multicolumn{4}{l}{\footnotesize Cohorts: 2007--2014.} \\" _n
file write tex "\multicolumn{4}{l}{\footnotesize * p$<$0.10, ** p$<$0.05, *** p$<$0.01.} \\" _n
file write tex "\hline\hline" _n
file write tex "\end{tabular}" _n
file write tex "\end{table}" _n

file close tex

************************************************************
* 11. Mostrar resumen final
************************************************************

use "$output/tables/rdd_graduation_10y_by_field.dta", clear

sort field outcome

list field outcome beta se pval N clusters, ///
    sepby(field) noobs abbreviate(35)

di as result "Resultados guardados en:"
di as result "$output/tables/rdd_graduation_10y_all.dta"
di as result "$output/tables/rdd_graduation_10y_all.tex"
di as result "$output/tables/rdd_graduation_10y_by_field.dta"
di as result "$output/tables/rdd_graduation_10y_by_field.tex"