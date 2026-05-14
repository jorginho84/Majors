/**********************************************************************
* 10_first_stage_figures_by_delta_groups.do
*
* Objetivo:
*   1. Crear grupos manuales de delta_selectivity y delta_grad_target_8y
*      para todas las postulaciones target, no solo admitidos.
*   2. Pegar esos grupos a analysis_sample.dta.
*   3. Estimar first stages por grupo para:
*        - enrolls_target
*        - enrolls_he
*        - enrolls_uni
*   4. Graficar coeficientes con intervalos de confianza.
**********************************************************************/

clear all
set more off

do "C:/Users/jigodoy/Documents/GitHub/Majors/code/config.do"

capture mkdir "$output/figures"

local bw 25

local applications "$processed/applications_rd.dta"
local attrs        "$processed/program_year_attributes_nextbest.dta"
local analysis     "$processed/analysis_sample.dta"


/**********************************************************************
* 1. Preparar lookup corto de atributos
**********************************************************************/

tempfile attrs_short

use "`attrs'", clear

rename selectivity_program_year      selectivity
rename graduation_rate_target_8y     grad_target_8y

keep ao_proceso codigo_carrera selectivity grad_target_8y

duplicates drop ao_proceso codigo_carrera, force

save `attrs_short', replace


/**********************************************************************
* 2. Construir next-best para TODAS las postulaciones target
**********************************************************************/

use "`applications'", clear

************************************************************
* 2.1 Homologar nombres
************************************************************

capture confirm variable t_codigo_carrera
if _rc == 0 {
    rename t_codigo_carrera codigo_carrera
}

capture confirm variable codigo_carrera
if _rc != 0 {
    di as error "No existe t_codigo_carrera ni codigo_carrera."
    exit 111
}

capture confirm variable ao_proceso
if _rc != 0 {
    capture confirm variable año_proceso
    if _rc == 0 rename año_proceso ao_proceso
    else {
        capture confirm variable ano_proceso
        if _rc == 0 rename ano_proceso ao_proceso
        else {
            di as error "No existe ao_proceso."
            exit 111
        }
    }
}

foreach v in mrun ao_proceso preferencia codigo_carrera ///
             application_score cutoff_regular {
    capture confirm variable `v'
    if _rc != 0 {
        di as error "Falta variable necesaria: `v'"
        exit 111
    }
}

capture confirm numeric variable codigo_carrera
if _rc != 0 destring codigo_carrera, replace force

capture confirm numeric variable ao_proceso
if _rc != 0 destring ao_proceso, replace force


************************************************************
* 2.2 Mantener variables necesarias
************************************************************

keep mrun ao_proceso preferencia codigo_carrera ///
     application_score cutoff_regular

drop if missing(mrun, ao_proceso, preferencia, codigo_carrera)

gen double score_rd = application_score - cutoff_regular ///
    if !missing(application_score, cutoff_regular)

gen byte above_cutoff = score_rd >= 0 if !missing(score_rd)

gen byte would_admit = application_score >= cutoff_regular ///
    if !missing(application_score, cutoff_regular)

replace would_admit = 0 if missing(would_admit)


************************************************************
* 2.3 Crear base de targets
************************************************************

tempfile targets candidates nextbest_all

preserve

    rename preferencia        target_preferencia
    rename codigo_carrera     target_codigo_carrera
    rename application_score  target_application_score
    rename cutoff_regular     target_cutoff_regular
    rename score_rd           target_score_rd
    rename above_cutoff       target_above_cutoff
    rename would_admit        target_would_admit

    keep mrun ao_proceso ///
         target_preferencia target_codigo_carrera ///
         target_application_score target_cutoff_regular ///
         target_score_rd target_above_cutoff target_would_admit

    duplicates drop mrun ao_proceso target_preferencia target_codigo_carrera, force

    save `targets', replace

restore


************************************************************
* 2.4 Crear base de candidatas next-best
************************************************************

preserve

    rename preferencia        cand_preferencia
    rename codigo_carrera     cand_codigo_carrera
    rename application_score  cand_application_score
    rename cutoff_regular     cand_cutoff_regular
    rename score_rd           cand_score_rd
    rename above_cutoff       cand_above_cutoff
    rename would_admit        cand_would_admit

    keep mrun ao_proceso ///
         cand_preferencia cand_codigo_carrera ///
         cand_application_score cand_cutoff_regular ///
         cand_score_rd cand_above_cutoff cand_would_admit

    save `candidates', replace

restore


************************************************************
* 2.5 Elegir primera alternativa inferior factible
************************************************************

use `targets', clear

joinby mrun ao_proceso using `candidates'

keep if cand_preferencia > target_preferencia
keep if cand_would_admit == 1

sort mrun ao_proceso target_preferencia target_codigo_carrera cand_preferencia

by mrun ao_proceso target_preferencia target_codigo_carrera: keep if _n == 1

rename cand_preferencia       nextbest_preferencia
rename cand_codigo_carrera    nextbest_codigo_carrera
rename cand_application_score nextbest_application_score
rename cand_cutoff_regular    nextbest_cutoff_regular
rename cand_score_rd          nextbest_score_rd
rename cand_above_cutoff      nextbest_above_cutoff
rename cand_would_admit       nextbest_would_admit

gen byte has_nextbest = 1

save `nextbest_all', replace


/**********************************************************************
* 3. Pegar atributos y crear deltas
**********************************************************************/

use `nextbest_all', clear

************************************************************
* 3.1 Atributos target
************************************************************

gen codigo_carrera = target_codigo_carrera

merge m:1 ao_proceso codigo_carrera using `attrs_short', ///
    keep(master match) nogen

rename selectivity     target_selectivity
rename grad_target_8y  target_grad_target_8y

drop codigo_carrera


************************************************************
* 3.2 Atributos next-best
************************************************************

gen codigo_carrera = nextbest_codigo_carrera

merge m:1 ao_proceso codigo_carrera using `attrs_short', ///
    keep(master match) nogen

rename selectivity     nextbest_selectivity
rename grad_target_8y  nextbest_grad_target_8y

drop codigo_carrera


************************************************************
* 3.3 Deltas
************************************************************

gen double delta_selectivity = ///
    target_selectivity - nextbest_selectivity ///
    if !missing(target_selectivity, nextbest_selectivity)

gen double delta_grad_target_8y = ///
    target_grad_target_8y - nextbest_grad_target_8y ///
    if !missing(target_grad_target_8y, nextbest_grad_target_8y)


/**********************************************************************
* 4. Crear grupos manuales
**********************************************************************/

************************************************************
* 4.1 Grupos delta_selectivity
************************************************************

gen group_delta_selectivity = .

replace group_delta_selectivity = 1 if ///
    delta_selectivity < -25 & !missing(delta_selectivity)

replace group_delta_selectivity = 2 if ///
    delta_selectivity >= -25 & delta_selectivity < -5 & !missing(delta_selectivity)

replace group_delta_selectivity = 3 if ///
    delta_selectivity >= -5 & delta_selectivity <= 5 & !missing(delta_selectivity)

replace group_delta_selectivity = 4 if ///
    delta_selectivity > 5 & delta_selectivity <= 25 & !missing(delta_selectivity)

replace group_delta_selectivity = 5 if ///
    delta_selectivity > 25 & !missing(delta_selectivity)


************************************************************
* 4.2 Grupos delta_grad_target_8y
************************************************************

gen group_delta_grad8y = .

replace group_delta_grad8y = 1 if ///
    delta_grad_target_8y < -0.10 & !missing(delta_grad_target_8y)

replace group_delta_grad8y = 2 if ///
    delta_grad_target_8y >= -0.10 & delta_grad_target_8y < -0.02 ///
    & !missing(delta_grad_target_8y)

replace group_delta_grad8y = 3 if ///
    delta_grad_target_8y >= -0.02 & delta_grad_target_8y <= 0.02 ///
    & !missing(delta_grad_target_8y)

replace group_delta_grad8y = 4 if ///
    delta_grad_target_8y > 0.02 & delta_grad_target_8y <= 0.10 ///
    & !missing(delta_grad_target_8y)

replace group_delta_grad8y = 5 if ///
    delta_grad_target_8y > 0.10 & !missing(delta_grad_target_8y)


************************************************************
* 4.3 Etiquetas
************************************************************

label define delta_group_lbl ///
    1 "Very negative" ///
    2 "Negative" ///
    3 "Close to zero" ///
    4 "Positive" ///
    5 "Very positive", replace

label values group_delta_selectivity delta_group_lbl
label values group_delta_grad8y delta_group_lbl


************************************************************
* 4.4 Diagnóstico de grupos
************************************************************

tab group_delta_selectivity, missing
tab group_delta_grad8y, missing

tabstat delta_selectivity, ///
    by(group_delta_selectivity) ///
    statistics(n mean min p25 median p75 max)

tabstat delta_grad_target_8y, ///
    by(group_delta_grad8y) ///
    statistics(n mean min p25 median p75 max)


************************************************************
* 4.5 Guardar grupos para merge
************************************************************

keep mrun ao_proceso ///
     target_preferencia target_codigo_carrera ///
     has_nextbest ///
     delta_selectivity delta_grad_target_8y ///
     group_delta_selectivity group_delta_grad8y

rename target_preferencia preferencia
rename target_codigo_carrera t_codigo_carrera

save "$processed/next_best_delta_groups_all_applications_manual.dta", replace


/**********************************************************************
* 5. Pegar grupos a analysis_sample
**********************************************************************/

use "`analysis'", clear

capture confirm variable t_codigo_carrera
if _rc != 0 {
    capture confirm variable codigo_carrera
    if _rc == 0 rename codigo_carrera t_codigo_carrera
    else {
        di as error "No existe t_codigo_carrera ni codigo_carrera en analysis_sample."
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
        di as error "Falta variable de merge en analysis_sample: `v'"
        exit 111
    }
}

merge m:1 mrun ao_proceso preferencia t_codigo_carrera ///
    using "$processed/next_best_delta_groups_all_applications_manual.dta", ///
    keep(master match) nogen

************************************************************
* Diagnóstico de disponibilidad de grupos
************************************************************

tab group_delta_selectivity if abs(score_rd) <= `bw', missing
tab group_delta_grad8y if abs(score_rd) <= `bw', missing

tab above_cutoff group_delta_selectivity if abs(score_rd) <= `bw', missing
tab above_cutoff group_delta_grad8y if abs(score_rd) <= `bw', missing

capture confirm variable program_year_id
if _rc != 0 {
    egen program_year_id = group(ao_proceso t_codigo_carrera)
}

save "$processed/analysis_sample_with_delta_groups_manual.dta", replace


/**********************************************************************
* 6. Estimar first stages por grupo
**********************************************************************/

use "$processed/analysis_sample_with_delta_groups_manual.dta", clear

local outcomes enrolls_target enrolls_he enrolls_uni
local groupvars group_delta_selectivity group_delta_grad8y

tempname handle

postfile `handle' ///
    str30 groupvar ///
    str20 outcome ///
    byte group ///
    double beta se ci_low ci_high N clusters ///
    using "$processed/first_stage_by_delta_groups_results.dta", replace

foreach gvar of local groupvars {

    forvalues g = 1/5 {

        foreach y of local outcomes {

            capture confirm variable `y'
            if _rc != 0 {
                di as error "No existe outcome `y'. Se salta."
                continue
            }

            quietly count if abs(score_rd) <= `bw' ///
                & `gvar' == `g' ///
                & !missing(`y', above_cutoff, score_rd, program_year_id)

            local N = r(N)

            quietly levelsof program_year_id if abs(score_rd) <= `bw' ///
                & `gvar' == `g' ///
                & !missing(`y', above_cutoff, score_rd, program_year_id), ///
                local(clustlist)

            local K : word count `clustlist'

            if `N' > 0 & `K' > 1 {

                capture noisily reghdfe `y' ///
                    above_cutoff ///
                    c.score_rd ///
                    1.above_cutoff#c.score_rd ///
                    if abs(score_rd) <= `bw' & `gvar' == `g', ///
                    absorb(program_year_id) ///
                    vce(cluster program_year_id)

                if _rc == 0 {
                    local b  = _b[above_cutoff]
                    local se = _se[above_cutoff]
                    local lo = `b' - 1.96 * `se'
                    local hi = `b' + 1.96 * `se'

                    post `handle' ///
                        ("`gvar'") ///
                        ("`y'") ///
                        (`g') ///
                        (`b') (`se') (`lo') (`hi') (`N') (`K')
                }
            }
        }
    }
}

postclose `handle'



/**********************************************************************
* 7. Graficar coeficientes con intervalos de confianza
*    - Eje X con rangos reales
*    - Coeficiente sobre cada barra
**********************************************************************/

use "$processed/first_stage_by_delta_groups_results.dta", clear

************************************************************
* Crear etiqueta del coeficiente para mostrar sobre cada barra
************************************************************

capture drop beta_label
gen beta_label = string(beta, "%4.3f")


************************************************************
* 7.1 Gráficos por grupo de delta_selectivity
************************************************************

foreach y in enrolls_target enrolls_he enrolls_uni {

    preserve

        keep if groupvar == "group_delta_selectivity" & outcome == "`y'"
        sort group

        twoway ///
            (bar beta group, barwidth(0.65)) ///
            (rcap ci_high ci_low group) ///
            (scatter beta group, ///
                mlabel(beta_label) ///
                mlabposition(12) ///
                msymbol(none)), ///
            yline(0, lpattern(dash)) ///
            xlabel( ///
                1 "< -25" ///
                2 "[-25,-5)" ///
                3 "[-5,5]" ///
                4 "(5,25]" ///
                5 "> 25", ///
                angle(45)) ///
            xtitle("Delta selectivity: target - next-best") ///
            ytitle("RDD coefficient on above_cutoff") ///
            title("First stage: `y' by delta selectivity") ///
            legend(off)

        graph export "$output/figures/fs_`y'_by_delta_selectivity_ranges_labeled.pdf", replace

    restore
}


************************************************************
* 7.2 Gráficos por grupo de delta_grad_target_8y
************************************************************

foreach y in enrolls_target enrolls_he enrolls_uni {

    preserve

        keep if groupvar == "group_delta_grad8y" & outcome == "`y'"
        sort group

        twoway ///
            (bar beta group, barwidth(0.65)) ///
            (rcap ci_high ci_low group) ///
            (scatter beta group, ///
                mlabel(beta_label) ///
                mlabposition(12) ///
                msymbol(none)), ///
            yline(0, lpattern(dash)) ///
            xlabel( ///
                1 "< -0.10" ///
                2 "[-0.10,-0.02)" ///
                3 "[-0.02,0.02]" ///
                4 "(0.02,0.10]" ///
                5 "> 0.10", ///
                angle(45)) ///
            xtitle("Delta graduation rate 8y: target - next-best") ///
            ytitle("RDD coefficient on above_cutoff") ///
            title("First stage: `y' by delta graduation 8y") ///
            legend(off)

        graph export "$output/figures/fs_`y'_by_delta_grad8y_ranges_labeled.pdf", replace

    restore
}



di as text "=================================================="
di as result "Listo. Resultados guardados en:"
di as result "$processed/first_stage_by_delta_groups_results.dta"
di as result "$processed/analysis_sample_with_delta_groups_manual.dta"
di as text "Gráficos guardados en:"
di as result "$output/figures/"
di as text "=================================================="