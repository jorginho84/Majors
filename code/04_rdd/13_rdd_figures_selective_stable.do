/**********************************************************************
* 13_rdd_figures_selective_stable.do
*
* Figuras combinadas RDD + histograma para programas persistentemente
* selectivos.
*
* Crea:
*   - rd_selective_combined_enrolls_he.pdf
*   - rd_selective_combined_enrolls_uni.pdf
*   - rd_selective_combined_enrolls_target.pdf
*
* Base:
*   $processed/analysis_sample_with_selectivity_stable.dta
**********************************************************************/

clear
set more off

************************************************************
* 0. Cargar configuración
************************************************************

do "C:/Users/jigodoy/Documents/GitHub/Majors/code/config.do"

capture mkdir "$output/figures"


************************************************************
* 1. Abrir base
************************************************************

use "$processed/analysis_sample_with_selectivity_stable.dta", clear


************************************************************
* 2. Restringir muestra
************************************************************

keep if abs(score_rd) <= $bandwidth
keep if selective_persistent == 1


************************************************************
* 3. Diagnóstico inicial
************************************************************

di as text "=================================================="
di as result "Combined RDD figures sample: selective stable programs"
di as text "=================================================="

count
distinct program_stable_id
distinct program_year_id
tab above_cutoff
summarize score_rd
summarize enrolls_he enrolls_uni enrolls_target


************************************************************
* 4. Programa para figura combinada
************************************************************

capture program drop make_combined_selective_rd_plot

program define make_combined_selective_rd_plot

    syntax varname, ///
        TITLE(string) ///
        YTITLE(string) ///
        SAVING(string)

    preserve

        ************************************************************
        * 4.1 Estimar RDD principal
        ************************************************************

        reghdfe `varlist' ///
            above_cutoff ///
            c.score_rd ///
            1.above_cutoff#c.score_rd, ///
            absorb(program_year_id) ///
            vce(cluster program_year_id)

        local beta = _b[above_cutoff]
        local se   = _se[above_cutoff]
        local N    = e(N)
        local G    = e(N_clust)

        local beta_txt : display %5.3f `beta'
        local se_txt   : display %5.3f `se'

        ************************************************************
        * 4.2 Crear bins para outcome
        ************************************************************

        gen rd_bin = floor(score_rd)

        collapse ///
            (mean) y_mean = `varlist' ///
            (mean) x_mean = score_rd ///
            (count) n_bin = `varlist', ///
            by(rd_bin above_cutoff)

        tempfile binned
        save `binned', replace

    restore


    preserve

        ************************************************************
        * 4.3 Crear histograma en base original
        ************************************************************

        keep if abs(score_rd) <= $bandwidth
        keep if selective_persistent == 1

        gen rd_bin = floor(score_rd)

        collapse (count) freq = score_rd, by(rd_bin)

        tempfile hist
        save `hist', replace

    restore


    preserve

        ************************************************************
        * 4.4 Combinar bins de outcome con histograma
        ************************************************************

        use `binned', clear

        merge m:1 rd_bin using `hist', ///
            keep(master match) nogen

        replace freq = 0 if missing(freq)


        ************************************************************
        * 4.5 Posición del texto usando eje de frecuencia
        ************************************************************

        summarize freq, meanonly
        local maxfreq = r(max)

        summarize y_mean, meanonly
        local ymin = r(min)
        local ymax = r(max)

        * Texto abajo a la derecha, en escala del eje izquierdo
        local x_text = $bandwidth * 0.35
        local y_text_freq = `maxfreq' * 0.20


        ************************************************************
        * 4.6 Figura combinada
        ************************************************************

        twoway ///
            (bar freq rd_bin, ///
                yaxis(1) ///
                barwidth(1) ///
                fcolor(gs14%35) ///
                lcolor(gs14%20)) ///
            (scatter y_mean x_mean if above_cutoff == 0, ///
                yaxis(2) ///
                msize(small) ///
                msymbol(circle) ///
                mcolor(navy)) ///
            (scatter y_mean x_mean if above_cutoff == 1, ///
                yaxis(2) ///
                msize(small) ///
                msymbol(circle) ///
                mcolor(navy)) ///
            (lfit y_mean x_mean [aw=n_bin] if above_cutoff == 0, ///
                yaxis(2) ///
                lwidth(medthick) ///
                lcolor(navy)) ///
            (lfit y_mean x_mean [aw=n_bin] if above_cutoff == 1, ///
                yaxis(2) ///
                lwidth(medthick) ///
                lcolor(navy)) ///
            , ///
            xline(0, lpattern(dash) lcolor(gs8)) ///
            xlabel(-25(5)25) ///
            xtitle("Distance to Admission Cutoff") ///
            ytitle("Frequency", axis(1)) ///
            ytitle("`ytitle'", axis(2)) ///
            title("`title'") ///
            subtitle("Persistently selective programs") ///
            text(`y_text_freq' `x_text' ///
                "RDD estimate: `beta_txt' (`se_txt')" ///
                "N = `N', clusters = `G'", ///
                placement(e) size(small)) ///
            legend(off) ///
            graphregion(color(white)) ///
            plotregion(color(white))

        graph export "`saving'.pdf", replace

    restore

end


************************************************************
* 5. Crear figuras combinadas
************************************************************

make_combined_selective_rd_plot enrolls_he, ///
    title("Enroll in Higher Education") ///
    ytitle("Enrolls in Higher Education") ///
    saving("$output/figures/rd_selective_combined_enrolls_he")


make_combined_selective_rd_plot enrolls_uni, ///
    title("Enroll in University") ///
    ytitle("Enrolls in University") ///
    saving("$output/figures/rd_selective_combined_enrolls_uni")


make_combined_selective_rd_plot enrolls_target, ///
    title("Enroll in the Target Program") ///
    ytitle("Enrolls in Target Program") ///
    saving("$output/figures/rd_selective_combined_enrolls_target")


************************************************************
* 6. Mensaje final
************************************************************

di as result "Figuras combinadas guardadas en:"
di as result "$output/figures/rd_selective_combined_enrolls_he.pdf"
di as result "$output/figures/rd_selective_combined_enrolls_uni.pdf"
di as result "$output/figures/rd_selective_combined_enrolls_target.pdf"