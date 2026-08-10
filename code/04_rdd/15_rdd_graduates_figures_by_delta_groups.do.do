/**********************************************************************
* 15_rdd_graduates_figures_by_delta_groups.do
*
* Objetivo:
*   Estimar RDD por grupos de delta_selectivity para outcomes de
*   graduación a 8 años, usando la base canónica creada por el 14.
*
* Input:
*   $processed/analysis_sample_delta_groups.dta
*
* Outcomes:
*   enrolls_target
*   graduates_target_8y
*   graduates_uni_8y
*   graduates_he_8y
*
* Outputs:
*   Solo figuras PDF en:
*       $output/figures/delta_groups/
*
* Figuras:
*   n_grad8y_groups.pdf
*   rdd_fs_target.pdf
*   rdd_grad_target8y.pdf
*   rdd_grad_uni8y.pdf
*   rdd_grad_he8y.pdf
*
**********************************************************************/

clear all
set more off

do "C:/Users/jigodoy/Documents/GitHub/Majors/code/config.do"

local bw 25

capture mkdir "$output/figures"
capture mkdir "$output/figures/delta_groups"


/**********************************************************************
* 1. Cargar base canónica creada por el 14
**********************************************************************/

use "$processed/analysis_sample_delta_groups.dta", clear


/**********************************************************************
* 2. Verificar variables necesarias
**********************************************************************/

foreach v in ///
    score_rd ///
    above_cutoff ///
    program_year_id ///
    delta_selectivity ///
    has_nextbest ///
    enrolls_target ///
    graduates_target_8y ///
    graduates_uni_8y ///
    graduates_he_8y {

    capture confirm variable `v'

    if _rc != 0 {
        di as error "Falta variable necesaria: `v'"
        di as error "Revisar que el 14 haya creado analysis_sample_delta_groups.dta desde una base con graduación 8y."
        exit 111
    }
}


/**********************************************************************
* 3. Definición manual de grupos de delta_selectivity
*
* IMPORTANTE:
* Este bloque debe ser idéntico en 14, 15 y 18 si se quiere modificar
* manualmente los cortes de forma consistente.
*
* Grupos vigentes:
*   d1: < -10
*   d2: [-10,10)
*   d3: [10,30)
*   d4: [30,50)
*   d5: >= 50
**********************************************************************/

capture drop delta_group
capture drop group_delta_selectivity

gen byte delta_group = .

replace delta_group = 1 if ///
    !missing(delta_selectivity) ///
    & delta_selectivity < -10

replace delta_group = 2 if ///
    !missing(delta_selectivity) ///
    & delta_selectivity >= -10 ///
    & delta_selectivity < 10

replace delta_group = 3 if ///
    !missing(delta_selectivity) ///
    & delta_selectivity >= 10 ///
    & delta_selectivity < 30

replace delta_group = 4 if ///
    !missing(delta_selectivity) ///
    & delta_selectivity >= 30 ///
    & delta_selectivity < 50

replace delta_group = 5 if ///
    !missing(delta_selectivity) ///
    & delta_selectivity >= 50

label define delta_group_lbl ///
    1 "d1: < -10" ///
    2 "d2: [-10,10)" ///
    3 "d3: [10,30)" ///
    4 "d4: [30,50)" ///
    5 "d5: >= 50", replace

label values delta_group delta_group_lbl

* Alias de compatibilidad con códigos previos
gen byte group_delta_selectivity = delta_group
label values group_delta_selectivity delta_group_lbl


/**********************************************************************
* 4. Diagnósticos de consistencia
**********************************************************************/

di as text "=================================================="
di as result "Diagnóstico 15: delta_group dentro de BW"
di as text "=================================================="

tab delta_group if abs(score_rd) <= `bw', missing

di as text "=================================================="
di as result "has_nextbest dentro de BW"
di as text "=================================================="

tab has_nextbest if abs(score_rd) <= `bw', missing

di as text "=================================================="
di as result "delta_group por lado del cutoff"
di as text "=================================================="

tab above_cutoff delta_group if abs(score_rd) <= `bw', missing

di as text "=================================================="
di as result "Distribución delta_selectivity dentro de BW"
di as text "=================================================="

summarize delta_selectivity if abs(score_rd) <= `bw', detail

di as text "=================================================="
di as result "Muestras por outcome dentro de BW"
di as text "=================================================="

foreach y in enrolls_target graduates_target_8y graduates_uni_8y graduates_he_8y {

    di as text "--------------------------------------------------"
    di as result "`y'"

    tab delta_group if abs(score_rd) <= `bw' ///
        & !missing(`y', above_cutoff, score_rd, program_year_id), missing
}


/**********************************************************************
* 5. Figura descriptiva: N por grupo en muestra graduation 8y
**********************************************************************/

preserve

    keep if abs(score_rd) <= `bw'
    keep if !missing(delta_group, graduates_target_8y, above_cutoff, score_rd, program_year_id)

    collapse (count) N = score_rd, by(delta_group)

    graph bar N, ///
        over(delta_group, ///
            relabel(1 "d1" ///
                    2 "d2" ///
                    3 "d3" ///
                    4 "d4" ///
                    5 "d5") ///
            label(labsize(vsmall))) ///
        blabel(bar, format(%12.0fc) size(small)) ///
        yscale(range(0 .)) ///
        ytitle("Number of observations") ///
        title("Observations by delta group") ///
        subtitle("Graduation 8y sample; |score_rd| <= `bw'") ///
        graphregion(color(white)) ///
        plotregion(color(white))

    graph export "$output/figures/delta_groups/n_grad8y_groups.pdf", replace

restore


/**********************************************************************
* 6. Estimar RDD por delta_group
*
* Resultados se guardan solo en tempfile.
**********************************************************************/

local outcomes ///
    enrolls_target ///
    graduates_target_8y ///
    graduates_uni_8y ///
    graduates_he_8y

tempfile rdd_delta_results

tempname handle

postfile `handle' ///
    str40 outcome ///
    byte delta_group ///
    double beta se ci_low ci_high N clusters ///
    using `rdd_delta_results', replace

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

        quietly summarize above_cutoff if abs(score_rd) <= `bw' ///
            & delta_group == `g' ///
            & !missing(`y', above_cutoff, score_rd, program_year_id), meanonly

        local min_above = r(min)
        local max_above = r(max)

        if `N' > 0 & `K' > 1 & `min_above' != `max_above' {

            local glabel : label delta_group_lbl `g'

            di as text "=================================================="
            di as result "RDD | outcome=`y' | `glabel'"
            di as result "N=`N', clusters=`K'"
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
* 7. Crear figuras RDD por delta_group
**********************************************************************/

use `rdd_delta_results', clear

capture confirm variable beta
if _rc != 0 {
    di as error "No se generaron resultados RDD."
    exit 111
}

gen beta_label = string(beta, "%5.3f")


capture program drop make_grad_delta_plot

program define make_grad_delta_plot

    syntax, OUTCOME(string) TITLE(string) SAVING(string)

    preserve

        keep if outcome == "`outcome'"
        sort delta_group

        quietly count
        if r(N) == 0 {
            restore
            exit
        }

        /************************************************************
        * Escalas fijas por outcome
        ************************************************************/

        local ymin = 0
        local ymax = 0.10
        local ystep = 0.02

        if "`outcome'" == "enrolls_target" {
            local ymin = 0.45
            local ymax = 0.65
            local ystep = 0.05
        }

        if "`outcome'" == "graduates_target_8y" {
            local ymin = 0.12
            local ymax = 0.30
            local ystep = 0.04
        }

        if inlist("`outcome'", "graduates_uni_8y", "graduates_he_8y") {
            local ymin = -0.02
            local ymax = 0.10
            local ystep = 0.02
        }

        twoway ///
            (bar beta delta_group, ///
                barwidth(0.65) ///
                fcolor(navy%70) ///
                lcolor(navy)) ///
            (rcap ci_high ci_low delta_group, ///
                lwidth(vthin) ///
                lcolor(maroon)) ///
            (scatter beta delta_group, ///
                msymbol(none) ///
                mlabel(beta_label) ///
                mlabposition(12) ///
                mlabsize(small)), ///
            yline(0, lpattern(dash) lcolor(gs8)) ///
            yscale(range(`ymin' `ymax')) ///
            ylabel(`ymin'(`ystep')`ymax', labsize(vsmall)) ///
            xlabel(1 "d1" ///
                   2 "d2" ///
                   3 "d3" ///
                   4 "d4" ///
                   5 "d5", ///
                   labsize(vsmall)) ///
            xscale(range(0.5 5.5)) ///
            xtitle("Delta selectivity group") ///
            ytitle("RDD coefficient on above_cutoff") ///
            title("`title'") ///
            subtitle("d1 < -10; d2 [-10,10); d3 [10,30); d4 [30,50); d5 >= 50") ///
            note("FE: program-year. SE clustered by program-year. BW = ±25.", ///
                size(vsmall)) ///
            legend(off) ///
            graphregion(color(white)) ///
            plotregion(color(white))

        graph export "`saving'.pdf", replace

    restore

end



make_grad_delta_plot, ///
    outcome("graduates_target_8y") ///
    title("Graduation from target program within 8 years") ///
    saving("$output/figures/delta_groups/rdd_grad_target8y")

make_grad_delta_plot, ///
    outcome("graduates_uni_8y") ///
    title("University graduation within 8 years") ///
    saving("$output/figures/delta_groups/rdd_grad_uni8y")

make_grad_delta_plot, ///
    outcome("graduates_he_8y") ///
    title("Higher education graduation within 8 years") ///
    saving("$output/figures/delta_groups/rdd_grad_he8y")


/**********************************************************************
* 8. Mostrar resultados finales
**********************************************************************/

use `rdd_delta_results', clear

sort outcome delta_group

di as text "=================================================="
di as result "Resultados RDD por delta_group"
di as text "=================================================="

list outcome delta_group beta se ci_low ci_high N clusters, ///
    sepby(outcome) abbreviate(24)


di as text "=================================================="
di as result "15 terminado correctamente."
di as result "Input:"
di as result "$processed/analysis_sample_delta_groups.dta"
di as text "Figuras guardadas en:"
di as result "$output/figures/delta_groups/"
di as text "Archivos esperados:"
di as result "  n_grad8y_groups.pdf"
di as result "  rdd_fs_target.pdf"
di as result "  rdd_grad_target8y.pdf"
di as result "  rdd_grad_uni8y.pdf"
di as result "  rdd_grad_he8y.pdf"
di as text "=================================================="






