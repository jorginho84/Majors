/**********************************************************************
* 14_first_stage_figures_by_delta_groups.do
*
* Objetivo:
*   1. Usar el output del 09:
*        $processed/next_best_all_targets_with_attributes.dta
*
*   2. Pegar next-best y deltas a una base de análisis con outcomes
*      de enrollment y graduation 8y.
*
*   3. Crear manualmente grupos de delta_selectivity:
*        d1: < -10
*        d2: [-10,10)
*        d3: [10,30)
*        d4: [30,50)
*        d5: >= 50
*
*   4. Guardar base canónica:
*        $processed/analysis_sample_delta_groups.dta
*
*   5. Estimar first stages por delta_group para:
*        enrolls_target
*        enrolls_he
*        enrolls_uni
*
*   6. Exportar solo figuras PDF.
*
* Inputs:
*   $processed/next_best_all_targets_with_attributes.dta
*   Una base de análisis que contenga graduation 8y.
*
* Output base necesaria:
*   $processed/analysis_sample_delta_groups.dta
*
* Output figuras:
*   $output/figures/delta_groups/
*
* Figuras:
*   hist_delta_bw25.pdf
*   hist_delta_grad8y_bw25.pdf
*   fs_target.pdf
*   fs_he.pdf
*   fs_uni.pdf
**********************************************************************/

clear all
set more off

do "C:/Users/jigodoy/Documents/GitHub/Majors/code/config.do"

local bw 25

local nextbest "$processed/next_best_all_targets_with_attributes.dta"

capture mkdir "$output/figures"
capture mkdir "$output/figures/delta_groups"


/**********************************************************************
* 1. Definir base de análisis canónica
*
* Esta base viene del 06_build_graduation_outcomes_8y.do.
* Contiene:
*   - outcomes de enrollment
*   - field
*   - graduates_target_8y
*   - graduates_uni_8y
*   - graduates_he_8y
**********************************************************************/

local analysis "$processed/analysis_sample_with_fields_graduation_8y.dta"

capture confirm file "`analysis'"
if _rc != 0 {
    di as error "No existe `analysis'."
    di as error "Corre primero:"
    di as error "  05_build_field.do"
    di as error "  06_build_graduation_outcomes_8y.do"
    exit 601
}

use "`analysis'", clear

foreach v in graduates_target_8y graduates_uni_8y graduates_he_8y field {
    capture confirm variable `v'
    if _rc != 0 {
        di as error "La base `analysis' no contiene `v'."
        exit 111
    }
}

count
di as result "Base de análisis usada en 14: `analysis'"
di as result "N = " r(N)


/**********************************************************************
* 2. Verificar input del 09
**********************************************************************/

capture confirm file "`nextbest'"
if _rc != 0 {
    di as error "No existe `nextbest'. Corre primero el 09 nuevo."
    exit 601
}


/**********************************************************************
* 3. Preparar output del 09 para merge con base de análisis
**********************************************************************/

tempfile nextbest_for_merge

use "`nextbest'", clear

foreach v in ///
    mrun ///
    ao_proceso ///
    target_preferencia ///
    target_codigo_carrera ///
    has_nextbest ///
    nextbest_preferencia ///
    nextbest_codigo_carrera ///
    target_selectivity ///
    nextbest_selectivity ///
    delta_selectivity ///
    target_grad_target_8y ///
    nextbest_grad_target_8y ///
    delta_grad_target_8y {

    capture confirm variable `v'

    if _rc != 0 {
        di as error "Falta variable necesaria en output del 09: `v'"
        exit 111
    }
}

capture confirm numeric variable target_codigo_carrera
if _rc != 0 destring target_codigo_carrera, replace force

capture confirm numeric variable ao_proceso
if _rc != 0 destring ao_proceso, replace force

rename target_preferencia preferencia
rename target_codigo_carrera t_codigo_carrera

keep mrun ao_proceso preferencia t_codigo_carrera ///
     has_nextbest ///
     nextbest_preferencia nextbest_codigo_carrera ///
     target_selectivity nextbest_selectivity delta_selectivity ///
     target_grad_target_8y nextbest_grad_target_8y delta_grad_target_8y

duplicates report mrun ao_proceso preferencia t_codigo_carrera
duplicates drop mrun ao_proceso preferencia t_codigo_carrera, force

save `nextbest_for_merge', replace


/**********************************************************************
* 4. Pegar next-best/deltas a base de análisis
**********************************************************************/

use "`analysis'", clear

capture confirm variable t_codigo_carrera
if _rc != 0 {
    capture confirm variable codigo_carrera
    if _rc == 0 rename codigo_carrera t_codigo_carrera
    else {
        di as error "No existe t_codigo_carrera ni codigo_carrera en la base de análisis."
        exit 111
    }
}

capture confirm numeric variable t_codigo_carrera
if _rc != 0 destring t_codigo_carrera, replace force

capture confirm numeric variable ao_proceso
if _rc != 0 destring ao_proceso, replace force

foreach v in mrun ao_proceso preferencia t_codigo_carrera {
    capture confirm variable `v'
    if _rc != 0 {
        di as error "Falta variable de merge en la base de análisis: `v'"
        exit 111
    }
}

foreach v in ///
    has_nextbest ///
    nextbest_preferencia ///
    nextbest_codigo_carrera ///
    target_selectivity ///
    nextbest_selectivity ///
    delta_selectivity ///
    target_grad_target_8y ///
    nextbest_grad_target_8y ///
    delta_grad_target_8y ///
    delta_group ///
    group_delta_selectivity ///
    delta_grad8y_group ///
    group_delta_grad8y {

    capture drop `v'
}

merge m:1 mrun ao_proceso preferencia t_codigo_carrera ///
    using `nextbest_for_merge', ///
    keep(master match) nogen

replace has_nextbest = 0 if missing(has_nextbest)

label define has_nextbest_lbl ///
    0 "No next-best feasible alternative" ///
    1 "Has next-best feasible alternative", replace

label values has_nextbest has_nextbest_lbl

capture confirm variable program_year_id
if _rc != 0 {
    egen program_year_id = group(ao_proceso t_codigo_carrera)
}


/**********************************************************************
* 5. Verificar outcomes de graduation 8y antes de guardar base canónica
**********************************************************************/

foreach v in graduates_target_8y graduates_uni_8y graduates_he_8y {
    capture confirm variable `v'
    if _rc != 0 {
        di as error "La base final no contiene `v'."
        di as error "El 15 fallará si seguimos. Revisar base usada en el 14."
        exit 111
    }
}


/**********************************************************************
* 6. Definición manual de grupos de delta_selectivity
*
* IMPORTANTE:
* Este bloque debe copiarse igual en 15 y 18 si se quiere modificar
* manualmente los cortes de forma consistente.
**********************************************************************/

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

gen byte group_delta_selectivity = delta_group
label values group_delta_selectivity delta_group_lbl


/************************************************************
* 6.1 Definición secundaria: grupos delta_grad_target_8y
************************************************************/

gen byte delta_grad8y_group = .

replace delta_grad8y_group = 1 if ///
    !missing(delta_grad_target_8y) ///
    & delta_grad_target_8y < -0.10

replace delta_grad8y_group = 2 if ///
    !missing(delta_grad_target_8y) ///
    & delta_grad_target_8y >= -0.10 ///
    & delta_grad_target_8y < -0.02

replace delta_grad8y_group = 3 if ///
    !missing(delta_grad_target_8y) ///
    & delta_grad_target_8y >= -0.02 ///
    & delta_grad_target_8y <= 0.02

replace delta_grad8y_group = 4 if ///
    !missing(delta_grad_target_8y) ///
    & delta_grad_target_8y > 0.02 ///
    & delta_grad_target_8y <= 0.10

replace delta_grad8y_group = 5 if ///
    !missing(delta_grad_target_8y) ///
    & delta_grad_target_8y > 0.10

label define delta_grad8y_group_lbl ///
    1 "g1: < -0.10" ///
    2 "g2: [-0.10,-0.02)" ///
    3 "g3: [-0.02,0.02]" ///
    4 "g4: (0.02,0.10]" ///
    5 "g5: > 0.10", replace

label values delta_grad8y_group delta_grad8y_group_lbl

gen byte group_delta_grad8y = delta_grad8y_group
label values group_delta_grad8y delta_grad8y_group_lbl


/************************************************************
* 7. Guardar base canónica necesaria para 15, 18 y siguientes RDD
************************************************************/

compress

save "$processed/analysis_sample_delta_groups.dta", replace


/**********************************************************************
* 8. Diagnósticos oficiales
**********************************************************************/

use "$processed/analysis_sample_delta_groups.dta", clear

di as text "=================================================="
di as result "Diagnóstico oficial: analysis_sample_delta_groups"
di as text "=================================================="

count
di as result "Total obs: " r(N)

di as text "--------------------------------------------------"
di as result "Has next-best dentro de BW"
di as text "--------------------------------------------------"
tab has_nextbest if abs(score_rd) <= `bw', missing

di as text "--------------------------------------------------"
di as result "Delta group dentro de BW"
di as text "--------------------------------------------------"
tab delta_group if abs(score_rd) <= `bw', missing

di as text "--------------------------------------------------"
di as result "Delta grad8y group dentro de BW"
di as text "--------------------------------------------------"
tab delta_grad8y_group if abs(score_rd) <= `bw', missing

di as text "--------------------------------------------------"
di as result "Balance above_cutoff x delta_group dentro de BW"
di as text "--------------------------------------------------"
tab above_cutoff delta_group if abs(score_rd) <= `bw', missing

di as text "--------------------------------------------------"
di as result "Distribución delta_selectivity dentro de BW"
di as text "--------------------------------------------------"
summarize delta_selectivity if abs(score_rd) <= `bw', detail

di as text "--------------------------------------------------"
di as result "Distribución delta_grad_target_8y dentro de BW"
di as text "--------------------------------------------------"
summarize delta_grad_target_8y if abs(score_rd) <= `bw', detail

di as text "--------------------------------------------------"
di as result "Muestra enrolls_target x delta_group"
di as text "--------------------------------------------------"
tab delta_group if abs(score_rd) <= `bw' ///
    & !missing(enrolls_target, above_cutoff, score_rd, program_year_id), missing

di as text "--------------------------------------------------"
di as result "Muestra graduates_target_8y x delta_group"
di as text "--------------------------------------------------"
tab delta_group if abs(score_rd) <= `bw' ///
    & !missing(graduates_target_8y, above_cutoff, score_rd, program_year_id), missing


/**********************************************************************
* 9. Histogramas oficiales de delta_selectivity
**********************************************************************/

/************************************************************
* 9.1 Histograma RDD sample oficial
************************************************************/

histogram delta_selectivity ///
    if abs(score_rd) <= `bw' ///
    & !missing(delta_selectivity, delta_group, above_cutoff, score_rd, program_year_id), ///
    percent ///
    width(5) ///
    fcolor(eltblue%45) ///
    lcolor(eltblue%20) ///
    xline(-10 10 30 50, lpattern(dash) lcolor(red)) ///
    title("Delta selectivity: RDD sample") ///
    subtitle("|score_rd| <= `bw'; non-missing delta_group") ///
    xtitle("Delta selectivity: target - next-best") ///
    ytitle("Percent") ///
    graphregion(color(white)) ///
    plotregion(color(white))

graph export "$output/figures/delta_groups/hist_delta_bw25.pdf", replace


/************************************************************
* 9.2 Histograma graduation target sample
************************************************************/

histogram delta_selectivity ///
    if abs(score_rd) <= `bw' ///
    & !missing(delta_selectivity, delta_group, above_cutoff, score_rd, program_year_id, graduates_target_8y), ///
    percent ///
    width(5) ///
    fcolor(eltblue%45) ///
    lcolor(eltblue%20) ///
    xline(-10 10 30 50, lpattern(dash) lcolor(red)) ///
    title("Delta selectivity: graduation target sample") ///
    subtitle("graduates_target_8y; |score_rd| <= `bw'") ///
    xtitle("Delta selectivity: target - next-best") ///
    ytitle("Percent") ///
    graphregion(color(white)) ///
    plotregion(color(white))

graph export "$output/figures/delta_groups/hist_delta_grad8y_bw25.pdf", replace


/**********************************************************************
* 10. Estimar first stages por delta_group
*
* Resultados se guardan solo como tempfile.
**********************************************************************/

local outcomes enrolls_target enrolls_he enrolls_uni

tempfile first_stage_results

tempname handle

postfile `handle' ///
    str20 outcome ///
    byte delta_group ///
    double beta se ci_low ci_high N clusters ///
    using `first_stage_results', replace

foreach y of local outcomes {

    capture confirm variable `y'
    if _rc != 0 {
        di as error "No existe outcome `y'. Se salta."
        continue
    }

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

            di as text "=================================================="
            di as result "First stage | outcome=`y' | delta_group=`g'"
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
        }
        else {
            di as text "Se salta: outcome=`y' | delta_group=`g' | N=`N', clusters=`K'"
        }
    }
}

postclose `handle'


/**********************************************************************
* 11. Graficar first stages por delta_group
**********************************************************************/

use `first_stage_results', clear

capture confirm variable beta
if _rc != 0 {
    di as error "No se generaron resultados de first stage."
    exit 111
}

gen beta_label = string(beta, "%4.3f")

capture program drop make_fs_delta_plot

program define make_fs_delta_plot

    syntax, OUTCOME(string) TITLE(string) SAVING(string)

    preserve

        keep if outcome == "`outcome'"
        sort delta_group

        quietly count
        if r(N) == 0 {
            restore
            exit
        }

        local ymin = 0
        local ymax = 0.08
        local ystep = 0.02

        if "`outcome'" == "enrolls_target" {
            local ymin = 0.45
            local ymax = 0.65
            local ystep = 0.05
        }

        if inlist("`outcome'", "enrolls_he", "enrolls_uni") {
            local ymin = 0
            local ymax = 0.08
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
                mlabel(beta_label) ///
                mlabposition(12) ///
                mlabsize(small) ///
                msymbol(none)), ///
            yline(0, lpattern(dash) lcolor(gs8)) ///
            yscale(range(`ymin' `ymax')) ///
            ylabel(`ymin'(`ystep')`ymax', labsize(vsmall)) ///
            xlabel( ///
                1 "d1" ///
                2 "d2" ///
                3 "d3" ///
                4 "d4" ///
                5 "d5", ///
                labsize(vsmall)) ///
            xtitle("Delta selectivity group") ///
            ytitle("RDD coefficient on above_cutoff") ///
            title("`title'") ///
            subtitle("d1 < -10; d2 [-10,10); d3 [10,30); d4 [30,50); d5 >= 50") ///
            legend(off) ///
            graphregion(color(white)) ///
            plotregion(color(white))

        graph export "`saving'.pdf", replace

    restore

end


make_fs_delta_plot, ///
    outcome("enrolls_target") ///
    title("First stage: Target enrollment") ///
    saving("$output/figures/delta_groups/fs_target")

make_fs_delta_plot, ///
    outcome("enrolls_he") ///
    title("First stage: Higher education enrollment") ///
    saving("$output/figures/delta_groups/fs_he")

make_fs_delta_plot, ///
    outcome("enrolls_uni") ///
    title("First stage: University enrollment") ///
    saving("$output/figures/delta_groups/fs_uni")


/**********************************************************************
* 12. Final
**********************************************************************/

di as text "=================================================="
di as result "14 terminado correctamente."
di as result "Base canónica guardada en:"
di as result "$processed/analysis_sample_delta_groups.dta"
di as text "Figuras guardadas en:"
di as result "$output/figures/delta_groups/"
di as text "Archivos esperados:"
di as result "  hist_delta_bw25.pdf"
di as result "  hist_delta_grad8y_bw25.pdf"
di as result "  fs_target.pdf"
di as result "  fs_he.pdf"
di as result "  fs_uni.pdf"
di as text "=================================================="