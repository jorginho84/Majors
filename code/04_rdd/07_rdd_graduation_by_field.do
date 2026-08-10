/**********************************************************************
* 09_rdd_graduation_by_field.do
*
* RDD de titulación a 8 años por campo de estudio.
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
*   - $output/tables/rdd_graduation_by_field.dta
*   - $output/tables/rdd_graduation_by_field.tex
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

drop if missing(field)
drop if field == ""
drop if field == "Missing"

* Crear program-year id si no existe
capture confirm variable program_year_id
if _rc != 0 {
    egen program_year_id = group(ao_proceso t_codigo_carrera)
}

capture mkdir "$output/tables"


************************************************************
* 3. Diagnóstico
************************************************************

di as text "=================================================="
di as result "RDD sample: graduation outcomes by field"
di as text "=================================================="

count
tab field, missing
tab above_cutoff, missing
tab graduates_he_8y, missing
tab graduates_uni_8y, missing
tab graduates_target_8y, missing
tab field above_cutoff, missing


************************************************************
* 4. Estimaciones RDD
************************************************************

local outcomes graduates_he_8y graduates_uni_8y graduates_target_8y

tempfile results

postfile handle ///
    str40 field ///
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
* 5. Guardar resultados largos
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

order field outcome outcome_label beta se tstat pval ci_low ci_high N clusters stars beta_se

sort field outcome

save "$output/tables/rdd_graduation_by_field.dta", replace


************************************************************
* 6. Crear tabla wide para LaTeX
************************************************************

preserve

    keep field outcome beta_se N clusters

    reshape wide beta_se N clusters, i(field) j(outcome) string

    rename beta_segraduates_he_8y      Graduated_HE_8y
    rename beta_segraduates_uni_8y     Graduated_University_8y
    rename beta_segraduates_target_8y  Graduated_Target_8y

    rename Ngraduates_he_8y            N_Graduated_HE_8y
    rename Ngraduates_uni_8y           N_Graduated_University_8y
    rename Ngraduates_target_8y        N_Graduated_Target_8y

    rename clustersgraduates_he_8y     Clusters_Graduated_HE_8y
    rename clustersgraduates_uni_8y    Clusters_Graduated_University_8y
    rename clustersgraduates_target_8y Clusters_Graduated_Target_8y

    sort field

    tempfile wide_results
    save `wide_results', replace

restore


************************************************************
* 7. Exportar tabla LaTeX
************************************************************

use `wide_results', clear

local texfile "$output/tables/rdd_graduation_by_field.tex"

capture erase "`texfile'"

file open tex using "`texfile'", write replace

file write tex "\begin{table}[!htbp]\centering" _n
file write tex "\caption{RDD Estimates on Graduation Outcomes by Field of Study}" _n
file write tex "\label{tab:rdd_graduation_by_field}" _n
file write tex "\begin{tabular}{lccc}" _n
file write tex "\hline\hline" _n
file write tex "Field & Graduated HE & Graduated University & Graduated Target Program \\" _n
file write tex "\hline" _n

forvalues i = 1/`=_N' {

    local f  = field[`i']
    local he = Graduated_HE_8y[`i']
    local un = Graduated_University_8y[`i']
    local tg = Graduated_Target_8y[`i']

    local f = subinstr("`f'", "&", "\&", .)
    local f = subinstr("`f'", "_", "\_", .)

    file write tex "`f' & `he' & `un' & `tg' \\" _n
}

file write tex "\hline" _n
file write tex "\multicolumn{4}{l}{\footnotesize Standard errors clustered at the program-year level in parentheses.} \\" _n
file write tex "\multicolumn{4}{l}{\footnotesize Sample restricted to applicants within $bandwidth points of the admission cutoff.} \\" _n
file write tex "\multicolumn{4}{l}{\footnotesize Graduation is measured within eight years of the admission process.} \\" _n
file write tex "\multicolumn{4}{l}{\footnotesize * p$<$0.10, ** p$<$0.05, *** p$<$0.01.} \\" _n
file write tex "\hline\hline" _n
file write tex "\end{tabular}" _n
file write tex "\end{table}" _n

file close tex


************************************************************
* 8. Mostrar resumen final
************************************************************

use "$output/tables/rdd_graduation_by_field.dta", clear

sort field outcome

di as text "=================================================="
di as result "RDD graduation by field results"
di as text "=================================================="

list field outcome beta se pval N clusters, ///
    sepby(field) noobs abbreviate(30)

di as result "Resultados guardados en:"
di as result "$output/tables/rdd_graduation_by_field.dta"
di as result "$output/tables/rdd_graduation_by_field.tex"

di as result "RDD graduation by field complete."



