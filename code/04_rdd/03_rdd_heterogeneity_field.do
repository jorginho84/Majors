/*------------------------------------------------------------------------------
                    RDD estimates by field of study

                    Input:
                        $processed/analysis_sample_with_fields_final.dta

                    Outputs:
                        $output/tables/rdd_enrollment_by_field.dta
                        $output/tables/rdd_enrollment_by_field.csv
                        $output/tables/rdd_enrollment_by_field_wide.csv
------------------------------------------------------------------------------*/

clear
set more off

************************************************************
* 0. Cargar configuración
************************************************************

do "C:/Users/jigodoy/Documents/GitHub/Majors/code/config.do"


************************************************************
* 1. Abrir base final con fields
************************************************************

use "$processed/analysis_sample_with_fields_final.dta", clear


************************************************************
* 2. Preparar muestra RDD
************************************************************

keep if abs(score_rd) <= $bandwidth

drop if missing(field)
drop if field == ""
drop if field == "Missing"

capture mkdir "$output/tables"

di as text "=================================================="
di as text "Muestra RDD por field"
di as text "=================================================="

count
tab field, missing
tab above_cutoff, missing
tab field above_cutoff, missing


************************************************************
* 3. Definir especificación
************************************************************

estimates clear

local fe "i.ao_proceso#i.t_codigo_carrera"
local cluster_var "ao_proceso#t_codigo_carrera"

local outcomes enrolls_he enrolls_uni enrolls_target


************************************************************
* 4. Crear archivo temporal para guardar resultados
************************************************************

tempfile results

postfile handle ///
    str40 field ///
    str30 outcome ///
    double beta ///
    double se ///
    double tstat ///
    double pval ///
    double ci_low ///
    double ci_high ///
    double N ///
    double clusters ///
    using `results', replace


************************************************************
* 5. RDD por field y outcome
************************************************************

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
                absorb(`fe') ///
                cluster(i.`cluster_var')

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


use "$processed/analysis_sample_with_fields_final.dta", clear

keep if abs(score_rd) <= $bandwidth

contract field, freq(n_postulaciones)

gsort -n_postulaciones

list field n_postulaciones, noobs

graph bar n_postulaciones, ///
    over(field, sort(1) descending label(angle(45))) ///
    ytitle("Number of Applications within RD Bandwidth") ///
    title("Applications by Field of Study, RD Sample") ///
    graphregion(color(white)) ///
    plotregion(color(white)) ///
    blabel(bar, format(%9.0fc))

graph export "$output/figures/applications_by_field_rd_sample.pdf", replace

************************************************************
* 6. Guardar resultados y exportar tabla LaTeX
************************************************************

use `results', clear

gen outcome_label = ""
replace outcome_label = "Any higher education" if outcome == "enrolls_he"
replace outcome_label = "University" if outcome == "enrolls_uni"
replace outcome_label = "Target program" if outcome == "enrolls_target"

gen stars = ""
replace stars = "*"   if pval < 0.10
replace stars = "**"  if pval < 0.05
replace stars = "***" if pval < 0.01

gen beta_se = string(beta, "%9.3f") + stars + " (" + string(se, "%9.3f") + ")"

order field outcome outcome_label beta se tstat pval ci_low ci_high N clusters stars beta_se

sort field outcome

* Guardar base de resultados interna
save "$output/tables/rdd_enrollment_by_field.dta", replace


************************************************************
* 7. Crear tabla wide para LaTeX
************************************************************

preserve

    keep field outcome beta_se N clusters

    reshape wide beta_se N clusters, i(field) j(outcome) string

    rename beta_seenrolls_he      Any_HE
    rename beta_seenrolls_uni     University
    rename beta_seenrolls_target  Target_Program

    rename Nenrolls_he            N_Any_HE
    rename Nenrolls_uni           N_University
    rename Nenrolls_target        N_Target_Program

    rename clustersenrolls_he     Clusters_Any_HE
    rename clustersenrolls_uni    Clusters_University
    rename clustersenrolls_target Clusters_Target_Program

    sort field

    tempfile wide_results
    save `wide_results', replace

restore


************************************************************
* 8. Exportar tabla LaTeX manual
************************************************************

use `wide_results', clear

local texfile "$output/tables/rdd_enrollment_by_field.tex"

capture erase "`texfile'"

file open tex using "`texfile'", write replace

file write tex "\begin{table}[!htbp]\centering" _n
file write tex "\caption{RDD Estimates by Field of Study}" _n
file write tex "\label{tab:rdd_by_field}" _n
file write tex "\begin{tabular}{lccc}" _n
file write tex "\hline\hline" _n
file write tex "Field & Any Higher Education & University & Target Program \\" _n
file write tex "\hline" _n

forvalues i = 1/`=_N' {

    local f  = field[`i']
    local he = Any_HE[`i']
    local un = University[`i']
    local tp = Target_Program[`i']

    * Escapar caracteres problemáticos básicos para LaTeX
    local f = subinstr("`f'", "&", "\&", .)
    local f = subinstr("`f'", "_", "\_", .)

    file write tex "`f' & `he' & `un' & `tp' \\" _n
}

file write tex "\hline" _n
file write tex "\multicolumn{4}{l}{\footnotesize Standard errors clustered at the program-year level in parentheses.} \\" _n
file write tex "\multicolumn{4}{l}{\footnotesize Sample restricted to applicants within \$bandwidth points of the admission cutoff.} \\" _n
file write tex "\multicolumn{4}{l}{\footnotesize * p$<$0.10, ** p$<$0.05, *** p$<$0.01.} \\" _n
file write tex "\hline\hline" _n
file write tex "\end{tabular}" _n
file write tex "\end{table}" _n

file close tex

di as result "Tabla LaTeX guardada en:"
di as result "`texfile'"