/**********************************************************************
* 16_rdd_figures_enrollment_3y.do
*
* Objetivo:
*   Crear figuras RDD para:
*
*       enrolls_he_3y
*       enrolls_uni_3y
*       enrolls_target_3y
*
* Regresión:
*   |score_rd| <= 25
*
* Figura:
*   eje x hasta ±50
*   bins de 5 puntos
*
* Nota:
*   El texto del RDD se posiciona automáticamente usando el rango
*   de mean_y para que aparezca en todos los gráficos.
**********************************************************************/

clear all
set more off

do "C:/Users/jigodoy/Documents/GitHub/Majors/code/config.do"

local bw_reg  25
local bw_plot 50
local binw    5

capture mkdir "$output/figures"
capture mkdir "$output/figures/enrollment_3y"


/**********************************************************************
* 1. Cargar base construida
**********************************************************************/

use "$processed/analysis_sample_enrollment_3y.dta", clear

describe enrolls_he_3y enrolls_uni_3y enrolls_target_3y

foreach v in score_rd above_cutoff program_year_id ///
             enrolls_he_3y enrolls_uni_3y enrolls_target_3y {

    capture confirm variable `v'

    if _rc != 0 {
        di as error "Falta variable necesaria: `v'"
        exit 111
    }
}


/**********************************************************************
* 2. Programa para figura RDD
**********************************************************************/

capture program drop make_rdd_figure_3y

program define make_rdd_figure_3y

    syntax varname, ///
        OUTNAME(string) ///
        TITLE(string) ///
        YTITLE(string) ///
        [BWREG(integer 25) BWPLOT(integer 50) BINW(real 5)]

    local y "`varlist'"
    local bw_reg  = `bwreg'
    local bw_plot = `bwplot'
    local binw    = `binw'
    local barw    = `binw' * 0.95

    capture confirm variable `y'
    if _rc != 0 {
        di as error "No existe la variable `y'."
        exit 111
    }

    /************************************************************
    * 1. Estimar RDD con bandwidth de regresión
    ************************************************************/

    quietly reghdfe `y' ///
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

    tempfile outcome_bins hist_bins

    /************************************************************
    * 2. Crear bins del outcome
    ************************************************************/

    preserve

        keep if abs(score_rd) <= `bw_plot'
        keep if !missing(`y', score_rd, above_cutoff)

        gen bin = floor(score_rd / `binw') * `binw' + (`binw' / 2)

        collapse ///
            (mean) mean_y = `y', ///
            by(bin above_cutoff)

        save `outcome_bins', replace

    restore


    /************************************************************
    * 3. Crear bins del histograma
    ************************************************************/

    preserve

        keep if abs(score_rd) <= `bw_plot'
        keep if !missing(score_rd)

        gen bin = floor(score_rd / `binw') * `binw' + (`binw' / 2)

        collapse ///
            (count) freq = score_rd, ///
            by(bin)

        save `hist_bins', replace

    restore


    /************************************************************
    * 4. Graficar desde base colapsada, sin perder la base original
    ************************************************************/

    preserve

        use `outcome_bins', clear

        merge m:1 bin using `hist_bins', ///
            keep(master match) nogen

        /********************************************************
        * Posición automática del texto RDD
        ********************************************************/

        summarize mean_y, meanonly

        local y_min = r(min)
        local y_max = r(max)

        local text_y = `y_min' + 0.15 * (`y_max' - `y_min')
        local text_x = 45

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
            ytitle("`ytitle'", axis(2)) ///
            title("`title'") ///
            text(`text_y' `text_x' "RDD estimate: `beta_txt' (`se_txt')", ///
                yaxis(2) size(small) placement(w)) ///
            note("Regression BW = ±`bw_reg'. Plot range = ±`bw_plot'. FE: program-year. SE clustered by program-year. N=`N', clusters=`G'.", ///
                size(vsmall)) ///
            legend(off) ///
            graphregion(color(white)) ///
            plotregion(color(white))

        graph export "$output/figures/enrollment_3y/`outname'.pdf", replace

    restore

end


/**********************************************************************
* 3. Crear figuras
**********************************************************************/

make_rdd_figure_3y enrolls_he_3y, ///
    outname("rdd_enrolls_he_3y") ///
    title("Enroll in Higher Education Within 3 Years") ///
    ytitle("Enrolls in Higher Education") ///
    bwreg(`bw_reg') ///
    bwplot(`bw_plot') /// 
    binw(`binw')

make_rdd_figure_3y enrolls_uni_3y, ///
    outname("rdd_enrolls_uni_3y") ///
    title("Enroll in University Within 3 Years") ///
    ytitle("Enrolls in University") ///
    bwreg(`bw_reg') ///
    bwplot(`bw_plot') ///
    binw(`binw')

make_rdd_figure_3y enrolls_target_3y, ///
    outname("rdd_enrolls_target_3y") ///
    title("Enroll in the Target Program Within 3 Years") ///
    ytitle("Enrolls in Target Program") ///
    bwreg(`bw_reg') ///
    bwplot(`bw_plot') ///
    binw(`binw')


di as text "=================================================="
di as result "Listo. Figuras reemplazadas en:"
di as result "$output/figures/enrollment_3y/"
di as text "=================================================="