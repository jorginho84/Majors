/**********************************************************************
* rdd_graduates_figures_by_delta_groups.do
*
* Objetivo:
*   Crear grupos simples de delta_selectivity:
*
*       d1: < -10
*       d2: [-10,0)
*       d3: [0,20)
*       d4: [20,50)
*       d5: >= 50
*
*   Luego estimar RDD por grupo para:
*       - enrolls_target
*       - graduates_target_8y
*       - graduates_uni_8y
*       - graduates_he_8y
*
*   Exporta solo:
*       - bar_N_delta_groups.pdf
*       - rdd_*_delta.pdf
**********************************************************************/

clear all
set more off

do "C:/Users/jigodoy/Documents/GitHub/Majors/code/config.do"

local bw 25

capture mkdir "$output/figures"
capture mkdir "$output/figures/nextbest_graduation"


/**********************************************************************
* 1. Cargar base
**********************************************************************/

use "$processed/analysis_sample_with_delta_groups_manual_graduation.dta", clear


/**********************************************************************
* 2. Revisar variables necesarias
**********************************************************************/

foreach v in score_rd above_cutoff program_year_id ///
             delta_selectivity has_nextbest ///
             enrolls_target ///
             graduates_target_8y graduates_uni_8y graduates_he_8y {

    capture confirm variable `v'

    if _rc != 0 {
        di as error "Falta variable necesaria: `v'"
        exit 111
    }
}


/**********************************************************************
* 3. Crear grupos simples de delta_selectivity
**********************************************************************/

capture drop delta_group

gen delta_group = .

replace delta_group = 1 if ///
    !missing(delta_selectivity) & delta_selectivity < -10

replace delta_group = 2 if ///
    !missing(delta_selectivity) & delta_selectivity >= -10 & delta_selectivity < 0

replace delta_group = 3 if ///
    !missing(delta_selectivity) & delta_selectivity >= 0 & delta_selectivity < 20

replace delta_group = 4 if ///
    !missing(delta_selectivity) & delta_selectivity >= 20 & delta_selectivity < 50

replace delta_group = 5 if ///
    !missing(delta_selectivity) & delta_selectivity >= 50

capture label drop dgrp

label define dgrp ///
    1 "d1: < -10" ///
    2 "d2: [-10,0)" ///
    3 "d3: [0,20)" ///
    4 "d4: [20,50)" ///
    5 "d5: >= 50", replace

label values delta_group dgrp


/**********************************************************************
* 4. Diagnóstico mínimo
**********************************************************************/

di as text "=================================================="
di as result "Frecuencia de delta_group |score_rd| <= `bw'"
di as text "=================================================="

tab delta_group if abs(score_rd) <= `bw', missing


di as text "=================================================="
di as result "delta_group por lado del cutoff"
di as text "=================================================="

tab above_cutoff delta_group if abs(score_rd) <= `bw', missing


di as text "=================================================="
di as result "Rangos reales de delta_selectivity por grupo"
di as text "=================================================="

tabstat delta_selectivity if abs(score_rd) <= `bw', ///
    by(delta_group) ///
    stat(n min p25 median p75 max mean) ///
    columns(statistics)


/**********************************************************************
* 5. Chequeo de missing corregido
*    No usar: tab missing(x) missing(y)
*    Stata no permite expresiones dentro de tab.
**********************************************************************/

capture drop miss_delta_sel miss_delta_group

gen miss_delta_sel   = missing(delta_selectivity)
gen miss_delta_group = missing(delta_group)

capture label drop misslbl

label define misslbl ///
    0 "Observed" ///
    1 "Missing", replace

label values miss_delta_sel misslbl
label values miss_delta_group misslbl

di as text "=================================================="
di as result "Chequeo missing: delta_selectivity vs delta_group"
di as text "=================================================="

tab miss_delta_sel miss_delta_group ///
    if abs(score_rd) <= `bw', missing


di as text "=================================================="
di as result "has_nextbest dentro del bandwidth"
di as text "=================================================="

tab has_nextbest if abs(score_rd) <= `bw', missing

di as text "=================================================="
di as result "has_nextbest por lado del cutoff"
di as text "=================================================="

tab above_cutoff has_nextbest if abs(score_rd) <= `bw', missing


/************************************************************
* Si este chequeo está bien, debería pasar algo así:
*
*   delta_selectivity observed -> delta_group observed
*   delta_selectivity missing  -> delta_group missing
*
* Es decir, los missing NO deberían quedar dentro de d5.
************************************************************/


/**********************************************************************
* 6. Guardar base auxiliar simple
**********************************************************************/

save "$processed/analysis_sample_delta_groups.dta", replace


/**********************************************************************
* 7. Figura descriptiva única: N por grupo
**********************************************************************/

preserve

    keep if abs(score_rd) <= `bw'
    keep if !missing(delta_group)

    collapse (count) N = score_rd, by(delta_group)

    graph bar N, ///
        over(delta_group, ///
            relabel(1 "d1" ///
                    2 "d2" ///
                    3 "d3" ///
                    4 "d4" ///
                    5 "d5")) ///
        blabel(bar, format(%12.0fc) size(small)) ///
        title("Observations by delta group") ///
        subtitle("d1 < -10; d2 [-10,0); d3 [0,20); d4 [20,50); d5 >= 50") ///
        ytitle("Number of observations") ///
        graphregion(color(white)) ///
        plotregion(color(white))

    graph export "$output/figures/nextbest_graduation/bar_N_delta_groups.pdf", replace

restore


/**********************************************************************
* 8. Estimar RDD por grupo
**********************************************************************/

use "$processed/analysis_sample_delta_groups.dta", clear

local outcomes ///
    enrolls_target ///
    graduates_target_8y ///
    graduates_uni_8y ///
    graduates_he_8y

tempname handle

postfile `handle' ///
    str40 outcome ///
    byte delta_group ///
    double beta se ci_low ci_high N clusters ///
    using "$processed/rdd_delta_results.dta", replace


foreach y of local outcomes {

    forvalues g = 1/5 {

        quietly count if abs(score_rd) <= `bw' ///
            & delta_group == `g' ///
            & !missing(`y', above_cutoff, score_rd, program_year_id)

        local N = r(N)

        quietly levelsof program_year_id if abs(score_rd) <= `bw' ///
            & delta_group == `g' ///
            & !missing(`y', above_cutoff, score_rd, program_year_id), ///
            local(clustlist)

        local K : word count `clustlist'

        if `N' > 0 & `K' > 1 {

            local glabel : label dgrp `g'

            di as text "=================================================="
            di as result "Outcome: `y' | `glabel'"
            di as text "=================================================="

            capture noisily reghdfe `y' ///
                above_cutoff ///
                c.score_rd ///
                1.above_cutoff#c.score_rd ///
                if abs(score_rd) <= `bw' ///
                & delta_group == `g', ///
                absorb(program_year_id) ///
                vce(cluster program_year_id)

            if _rc == 0 {

                local b  = _b[above_cutoff]
                local se = _se[above_cutoff]
                local lo = `b' - 1.96 * `se'
                local hi = `b' + 1.96 * `se'

                post `handle' ///
                    ("`y'") ///
                    (`g') ///
                    (`b') (`se') (`lo') (`hi') (`N') (`K')
            }
            else {
                di as error "RDD falló para outcome `y', grupo `g'"
            }
        }
        else {
            di as text "Se salta `y', grupo `g': N=`N', clusters=`K'"
        }
    }
}

postclose `handle'

/**********************************************************************
* 9. Crear figuras RDD como BARRAS con intervalos de confianza
**********************************************************************/

use "$processed/rdd_delta_results.dta", clear

gen beta_label = string(beta, "%5.3f")


foreach y in enrolls_target graduates_target_8y graduates_uni_8y graduates_he_8y {

    preserve

        keep if outcome == "`y'"
        sort delta_group

        local mytitle ""

        if "`y'" == "enrolls_target" {
            local mytitle "First stage: enrolls_target"
        }

        if "`y'" == "graduates_target_8y" {
            local mytitle "Graduation from target program within 8 years"
        }

        if "`y'" == "graduates_uni_8y" {
            local mytitle "University graduation within 8 years"
        }

        if "`y'" == "graduates_he_8y" {
            local mytitle "Higher education graduation within 8 years"
        }

        twoway ///
            (bar beta delta_group, barwidth(0.65)) ///
            (rcap ci_high ci_low delta_group, lwidth(medthin)) ///
            (scatter beta delta_group, ///
                msymbol(none) ///
                mlabel(beta_label) ///
                mlabposition(12) ///
                mlabsize(small)), ///
            yline(0, lpattern(dash)) ///
            xlabel(1 "d1" ///
                   2 "d2" ///
                   3 "d3" ///
                   4 "d4" ///
                   5 "d5", ///
                   labsize(small)) ///
            xscale(range(0.5 5.5)) ///
            xtitle("Delta selectivity group") ///
            ytitle("RDD coefficient on above_cutoff") ///
            title("`mytitle'") ///
            subtitle("d1 < -10; d2 [-10,0); d3 [0,20); d4 [20,50); d5 >= 50") ///
            note("Sample restricted to observed delta selectivity. FE: program-year. SE clustered by program-year.", ///
                size(vsmall)) ///
            legend(off) ///
            graphregion(color(white)) ///
            plotregion(color(white))

        graph export "$output/figures/nextbest_graduation/rdd_`y'_delta_bar.pdf", replace

    restore
}
/**********************************************************************
* 10. Mostrar resultados finales
**********************************************************************/

use "$processed/rdd_delta_results.dta", clear

sort outcome delta_group

di as text "=================================================="
di as result "Resultados RDD por delta_group"
di as text "=================================================="

list outcome delta_group beta se ci_low ci_high N clusters, ///
    sepby(outcome) abbreviate(24)


di as text "=================================================="
di as result "Listo."
di as result "Base auxiliar:"
di as result "$processed/analysis_sample_delta_groups.dta"
di as result "Resultados:"
di as result "$processed/rdd_delta_results.dta"
di as result "Figuras:"
di as result "$output/figures/nextbest_graduation/bar_N_delta_groups.pdf"
di as result "$output/figures/nextbest_graduation/rdd_*_delta.pdf"
di as text "=================================================="