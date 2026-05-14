/**********************************************************************
* 17_rdd_figure_retakes_psu_2y.do
*
* Outcome:
*   retakes_psu_2y
*
* Definición:
*   = 1 si el estudiante vuelve a rendir PSU en t+1 o t+2.
*
* Regresión:
*   |score_rd| <= 25
*
* Figura:
*   eje x hasta ±50
*   bins de 5 puntos
**********************************************************************/

clear all
set more off

do "C:/Users/jigodoy/Documents/GitHub/Majors/code/config.do"

local bw_reg  25
local bw_plot 50
local binw    5

capture mkdir "$output/figures"
capture mkdir "$output/figures/retakes_psu"


/**********************************************************************
* 1. Cargar base
**********************************************************************/

use "$processed/analysis_sample_retakes_psu_2y.dta", clear


/**********************************************************************
* 2. Crear program_year_id si no existe
**********************************************************************/

capture confirm variable program_year_id

if _rc != 0 {
    di as text "program_year_id no existe. Creándolo."
    egen program_year_id = group(ao_proceso t_codigo_carrera)
    label variable program_year_id "Program-year FE: ao_proceso x t_codigo_carrera"
}


/**********************************************************************
* 3. Revisar variables necesarias
**********************************************************************/

foreach v in retakes_psu_2y score_rd above_cutoff program_year_id {
    
    capture confirm variable `v'
    
    if _rc != 0 {
        di as error "Falta variable necesaria: `v'"
        exit 111
    }
}


/**********************************************************************
* 4. Diagnóstico descriptivo
**********************************************************************/

di as text "=================================================="
di as result "Descriptivo retakes_psu_2y |score_rd| <= `bw_reg'"
di as text "=================================================="

tab retakes_psu_2y if abs(score_rd) <= `bw_reg', missing

tab above_cutoff retakes_psu_2y if abs(score_rd) <= `bw_reg', missing

sum retakes_psu_2y if abs(score_rd) <= `bw_reg'


/**********************************************************************
* 5. Estimar RDD
**********************************************************************/

di as text "=================================================="
di as result "RDD: retakes_psu_2y"
di as text "=================================================="

reghdfe retakes_psu_2y ///
    above_cutoff ///
    c.score_rd ///
    1.above_cutoff#c.score_rd ///
    if abs(score_rd) <= `bw_reg', ///
    absorb(program_year_id) ///
    vce(cluster program_year_id)

local beta = _b[above_cutoff]
local se   = _se[above_cutoff]
local N    = e(N)
local G    = e(N_clust)

local beta_txt : display %5.3f `beta'
local se_txt   : display %5.3f `se'

di as text "=================================================="
di as result "RDD estimate: `beta_txt' (`se_txt')"
di as result "N = `N'"
di as result "Clusters = `G'"
di as text "=================================================="


/**********************************************************************
* 6. Crear bins del outcome para figura
**********************************************************************/

tempfile outcome_bins hist_bins

preserve

    keep if abs(score_rd) <= `bw_plot'
    keep if !missing(retakes_psu_2y, score_rd, above_cutoff)

    gen bin = floor(score_rd / `binw') * `binw' + (`binw' / 2)

    collapse ///
        (mean) mean_y = retakes_psu_2y, ///
        by(bin above_cutoff)

    save `outcome_bins', replace

restore


/**********************************************************************
* 7. Crear bins del histograma
**********************************************************************/

preserve

    keep if abs(score_rd) <= `bw_plot'
    keep if !missing(score_rd)

    gen bin = floor(score_rd / `binw') * `binw' + (`binw' / 2)

    collapse ///
        (count) freq = score_rd, ///
        by(bin)

    save `hist_bins', replace

restore


/**********************************************************************
* 8. Graficar
**********************************************************************/

use `outcome_bins', clear

merge m:1 bin using `hist_bins', ///
    keep(master match) nogen

summarize mean_y, meanonly

local y_min = r(min)
local y_max = r(max)

local text_y = 0.215
local text_x = 42

local barw = `binw' * 0.95

twoway ///
    (bar freq bin, ///
        yaxis(1) ///
        barwidth(`barw') ///
        color(eltblue%25) ///
        lcolor(eltblue%0)) ///
    (scatter mean_y bin if above_cutoff == 0, ///
        yaxis(2) ///
        msymbol(O) ///
        msize(small) ///
        color(black)) ///
    (scatter mean_y bin if above_cutoff == 1, ///
        yaxis(2) ///
        msymbol(O) ///
        msize(small) ///
        color(black)) ///
    (lfit mean_y bin if above_cutoff == 0 & abs(bin) <= `bw_reg', ///
        yaxis(2) ///
        lwidth(medthick) ///
        color(black)) ///
    (lfit mean_y bin if above_cutoff == 1 & abs(bin) <= `bw_reg', ///
        yaxis(2) ///
        lwidth(medthick) ///
        color(black)), ///
    xline(0, lpattern(dash) lcolor(gs8)) ///
    xlabel(-50(10)50) ///
    xscale(range(-50 50)) ///
    xtitle("Distance to Admission Cutoff") ///
    ytitle("Frequency", axis(1)) ///
    ytitle("Retakes PSU in t+1 or t+2", axis(2)) ///
    title("Retakes PSU Within Two Years") ///
    text(`text_y' `text_x' "RDD estimate: `beta_txt' (`se_txt')", ///
        yaxis(2) size(small) placement(w)) ///
    note("Regression BW = ±`bw_reg'. Plot range = ±`bw_plot'. FE: program-year. SE clustered by program-year. N=`N', clusters=`G'.", ///
        size(vsmall)) ///
    legend(off) ///
    graphregion(color(white)) ///
    plotregion(color(white))

graph export "$output/figures/retakes_psu/rdd_retakes_psu_2y.pdf", replace


/**********************************************************************
* 9. Guardar resultado puntual en base pequeña
**********************************************************************/

clear
set obs 1

gen outcome = "retakes_psu_2y"
gen beta = `beta'
gen se = `se'
gen N = `N'
gen clusters = `G'
gen bw_reg = `bw_reg'
gen bw_plot = `bw_plot'

save "$processed/rdd_retakes_psu_2y_result.dta", replace


di as text "=================================================="
di as result "Listo."
di as result "Figura:"
di as result "$output/figures/retakes_psu/rdd_retakes_psu_2y.pdf"
di as result "Resultado guardado:"
di as result "$processed/rdd_retakes_psu_2y_result.dta"
di as text "=================================================="