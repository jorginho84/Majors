************************************************************
* 13_rdd_figures_selective.do
*
* Figuras RD con histograma de fondo
* para programas selectivos definidos como:
*
* Programa aparece al menos una vez en el top 20%
* de la lista pooled de programa-años post-2012.
*
* Input:
* $processed/analysis_sample_with_selectivity_post2012_pooled_top20.dta
*

************************************************************

clear all
set more off


************************************************************
* 0. Configuración
************************************************************

capture do "C:\Users\jigodoy\Documents\GitHub\Majors\code\config.do"

global bandwidth 25

use "$processed/analysis_sample_with_selectivity_post2012_pooled_top20.dta", clear


capture mkdir "$output/figures"
capture mkdir "$output/figures/Selective"

************************************************************
* 1. Verificaciones iniciales
************************************************************

describe score_rd above_cutoff program_year_id ///
         selective_pooled_top20 ///
         enrolls_he enrolls_uni enrolls_target

di as text "=================================================="
di as result "Muestra selectiva pooled dentro de bandwidth"
di as text "=================================================="

count if abs(score_rd) <= $bandwidth

count if abs(score_rd) <= $bandwidth ///
    & selective_pooled_top20 == 1

distinct program_code_harmonized ///
    if abs(score_rd) <= $bandwidth ///
    & selective_pooled_top20 == 1

distinct program_year_id ///
    if abs(score_rd) <= $bandwidth ///
    & selective_pooled_top20 == 1


************************************************************
* 2. Programa para figura RD con histograma de fondo
************************************************************

capture program drop make_rd_hist_plot

program define make_rd_hist_plot

    syntax varname, ///
        OUTCOMELABEL(string) ///
        SAVING(string)

    preserve

        keep if abs(score_rd) <= $bandwidth
        keep if selective_pooled_top20 == 1
        keep if !missing(`varlist', above_cutoff, score_rd, program_year_id)

        ********************************************************
        * 2.1 Estimación RDD para anotar en figura
        ********************************************************

        quietly reghdfe `varlist' ///
            above_cutoff ///
            c.score_rd ///
            1.above_cutoff#c.score_rd, ///
            absorb(program_year_id) ///
            vce(cluster program_year_id)

        local beta = _b[above_cutoff]
        local se   = _se[above_cutoff]
        local N    = e(N)
        local cl   = e(N_clust)

        local beta_txt : display %5.3f `beta'
        local se_txt   : display %5.3f `se'
        local N_txt    : display %12.0fc `N'
        local cl_txt   : display %9.0fc `cl'

        local beta_txt = strtrim("`beta_txt'")
        local se_txt   = strtrim("`se_txt'")
        local N_txt    = strtrim("`N_txt'")
        local cl_txt   = strtrim("`cl_txt'")

        local rdd_text "RDD estimate: `beta_txt' (`se_txt')"
        local n_text   "N = `N_txt', clusters = `cl_txt'"


        ********************************************************
        * 2.2 Guardar base filtrada
        ********************************************************

        tempfile base_plot
        save `base_plot', replace


        ********************************************************
        * 2.3 Dataset histograma
        ********************************************************

        use `base_plot', clear

        gen x = floor(score_rd / 1) * 1
        replace x = x + 0.5

        collapse ///
            (count) freq = score_rd, ///
            by(x)

        gen source = "hist"

        tempfile hist_data
        save `hist_data', replace


        ********************************************************
        * 2.4 Dataset medias RD
        ********************************************************

        use `base_plot', clear

        gen x = floor(score_rd / 2.5) * 2.5
        replace x = x + 1.25

        collapse ///
            (mean) y_mean = `varlist' ///
            (count) n = `varlist', ///
            by(x above_cutoff)

        gen source = "rd"

        tempfile rd_data
        save `rd_data', replace


        ********************************************************
        * 2.5 Unir datasets
        ********************************************************

        use `hist_data', clear
        append using `rd_data'


        ********************************************************
        * 2.6 Texto y línea vertical
        ********************************************************

        quietly summarize freq if source == "hist"
        local freq_max = r(max)

        local text_x = 6
        local text_y1 = 0.22 * `freq_max'
        local text_y2 = 0.15 * `freq_max'
        local vline_top = 1.05 * `freq_max'


		********************************************************
        * 2.7 Figura                                           
        ********************************************************

        local ymin = 0
        local ymax = 1
        local ystep = 0.1

        if "`varlist'" == "enrolls_target" {
            local ymin = 0
            local ymax = 0.8
            local ystep = 0.1
        }

        if inlist("`varlist'", "enrolls_uni", "enrolls_he") {
            local ymin = 0
            local ymax = 1
            local ystep = 0.1
        }

        twoway ///
            (bar freq x if source == "hist", ///
                yaxis(1) ///
                barwidth(0.95) ///
                fcolor(eltblue%25) ///
                lcolor(eltblue%10)) ///
            (scatter y_mean x if source == "rd" & x < 0, ///
                yaxis(2) ///
                msymbol(circle) ///
                msize(small) ///
                mcolor(black) ///
                mfcolor(black) ///
                mlcolor(black)) ///
            (scatter y_mean x if source == "rd" & x >= 0, ///
                yaxis(2) ///
                msymbol(circle) ///
                msize(small) ///
                mcolor(black) ///
                mfcolor(black) ///
                mlcolor(black)) ///
            (lfit y_mean x [aw=n] if source == "rd" & x < 0, ///
                yaxis(2) ///
                lcolor(black) ///
                lwidth(medthick)) ///
            (lfit y_mean x [aw=n] if source == "rd" & x >= 0, ///
                yaxis(2) ///
                lcolor(black) ///
                lwidth(medthick)) ///
            (scatteri 0 0 `vline_top' 0, ///
                recast(line) ///
                yaxis(1) ///
                lpattern(dash) ///
                lcolor(gs8) ///
                lwidth(medthick)) ///
            , ///
            xscale(range(-25 25)) ///
            xlabel(-25(5)25, labsize(vsmall)) ///
            xtitle("Distance to Admission Cutoff", size(vsmall)) ///
            ytitle("Frequency", axis(1) size(vsmall)) ///
            ytitle("`outcomelabel'", axis(2) size(vsmall)) ///
            ylabel(, axis(1) angle(horizontal) labsize(vsmall)) ///
            ylabel(`ymin'(`ystep')`ymax', axis(2) angle(horizontal) labsize(vsmall)) ///
            yscale(axis(2) range(`ymin' `ymax')) ///
            title("`outcomelabel'", size(medsmall)) ///
            subtitle("Pooled top 20% program-years", size(small)) ///
            text(`text_y1' `text_x' "`rdd_text'", ///
                size(small) placement(e) color(black)) ///
            text(`text_y2' `text_x' "`n_text'", ///
                size(small) placement(e) color(black)) ///
            legend(off) ///
            graphregion(color(white)) ///
            plotregion(color(white))
        
		graph export "`saving'.pdf", replace

    restore

end
************************************************************
* 3. Crear figuras individuales
************************************************************

************************************************************
* 3.1 Enrolls in Higher Education
************************************************************

make_rd_hist_plot enrolls_he, ///
    outcomelabel("Enrolls in Higher Education") ///
    saving("$output/figures/Selective/rd_hist_enrolls_he_selective_pooled_top20")


************************************************************
* 3.2 Enrolls in University
************************************************************

make_rd_hist_plot enrolls_uni, ///
    outcomelabel("Enrolls in University") ///
    saving("$output/figures/Selective/rd_hist_enrolls_uni_selective_pooled_top20")


************************************************************
* 3.3 Enrolls in Target Program
************************************************************

make_rd_hist_plot enrolls_target, ///
    outcomelabel("Enrolls in Target Program") ///
    saving("$output/figures/Selective/rd_hist_enrolls_target_selective_pooled_top20")


************************************************************
* 4. Final
************************************************************

di as text "=================================================="
di as result "Figuras individuales terminadas"
di as result "$output/figures/selective_pooled_top20/"
di as text "=================================================="