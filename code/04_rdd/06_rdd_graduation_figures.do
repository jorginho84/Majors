/**********************************************************************
* 06_rdd_graduation_figures.do
*
* Figuras RDD de titulación a 8 años
* con formato similar a enrollment.
*
* Outcomes:
*   - graduates_he_8y
*   - graduates_uni_8y
*   - graduates_target_8y
*
* Input:
*   - $processed/analysis_sample_with_fields_graduation_8y.dta
*
* Output:
*   - $output/figures/rd_graduates_he_8y.pdf
*   - $output/figures/rd_graduates_uni_8y.pdf
*   - $output/figures/rd_graduates_target_8y.pdf
**********************************************************************/

clear
set more off

************************************************************
* 0. Cargar configuración
************************************************************

do "C:/Users/jigodoy/Documents/GitHub/Majors/code/config.do"


************************************************************
* 1. Abrir base
************************************************************

use "$processed/analysis_sample_with_fields_graduation_8y.dta", clear

* Ventana para gráfico, igual que antes
keep if abs(score_rd) <= 50

* Crear program_year_id si no existe
capture confirm variable program_year_id
if _rc != 0 {
    egen program_year_id = group(ao_proceso t_codigo_carrera)
}

capture mkdir "$output/figures"


************************************************************
* 2. Programa para figura RD + histograma
************************************************************

capture program drop make_rd_hist_grad
program define make_rd_hist_grad

    syntax varname, ///
        Ytitle(string) ///
        Title(string) ///
        Saving(string) ///
        [Label(string)]

    preserve

        keep if !missing(`varlist', score_rd, above_cutoff)

        count
        if r(N) == 0 {
            di as error "No hay observaciones para outcome = `varlist'"
            restore
            exit
        }


        ************************************************************
        * Estimación RD con ventana $bandwidth
        ************************************************************

        reghdfe `varlist' ///
            above_cutoff score_rd 1.above_cutoff#c.score_rd ///
            if abs(score_rd) <= $bandwidth, ///
            absorb(program_year_id) ///
            vce(cluster program_year_id)

        local beta = _b[above_cutoff]
        local se   = _se[above_cutoff]

        local beta_txt : display %5.3f `beta'
        local se_txt   : display %5.3f `se'

        if "`label'" == "" {
            local label "RD estimate"
        }


        ************************************************************
        * Guardar base original
        ************************************************************

        tempfile main hist bins leftfit rightfit
        save `main', replace


        ************************************************************
        * Histograma: bins de 5 puntos
        ************************************************************

        use `main', clear

        gen hist_bin = floor(score_rd/5)*5
        collapse (count) freq = score_rd, by(hist_bin)

        rename hist_bin x
        save `hist', replace


        ************************************************************
        * Puntos RD: promedio por bins de 5 puntos
        ************************************************************

        use `main', clear

        gen rd_bin = floor(score_rd/5)*5 + 2.5

        collapse ///
            (mean) y_mean = `varlist' ///
            (count) n = `varlist', ///
            by(rd_bin)

        rename rd_bin x
        save `bins', replace


        ************************************************************
        * Ajuste lineal izquierdo
        ************************************************************

        use `main', clear

        keep if score_rd < 0 & abs(score_rd) <= $bandwidth

        count
        if r(N) > 0 {
            regress `varlist' score_rd

            clear
            set obs 100
            gen x = -$bandwidth + (_n-1)*($bandwidth/99)
            gen yhat_left = _b[_cons] + _b[score_rd]*x

            save `leftfit', replace
        }
        else {
            clear
            set obs 0
            gen x = .
            gen yhat_left = .
            save `leftfit', replace
        }


        ************************************************************
        * Ajuste lineal derecho
        ************************************************************

        use `main', clear

        keep if score_rd >= 0 & abs(score_rd) <= $bandwidth

        count
        if r(N) > 0 {
            regress `varlist' score_rd

            clear
            set obs 100
            gen x = 0 + (_n-1)*($bandwidth/99)
            gen yhat_right = _b[_cons] + _b[score_rd]*x

            save `rightfit', replace
        }
        else {
            clear
            set obs 0
            gen x = .
            gen yhat_right = .
            save `rightfit', replace
        }


        ************************************************************
        * Unir para graficar
        ************************************************************

        use `hist', clear
        append using `bins'
        append using `leftfit'
        append using `rightfit'


        ************************************************************
        * Posición del texto
        ************************************************************

        quietly summarize freq if !missing(freq)
        local maxfreq = r(max)

        local text_x = 15
        local text_y = `maxfreq' * 0.08


        ************************************************************
        * Gráfico
        ************************************************************

        twoway ///
            (bar freq x, ///
                yaxis(1) ///
                barwidth(5) ///
                fcolor(eltblue%20) ///
                lcolor(eltblue%5)) ///
            (scatter y_mean x, ///
                yaxis(2) ///
                msymbol(circle) ///
                mcolor(black) ///
                mfcolor(black) ///
                mlcolor(black) ///
                msize(tiny)) ///
            (line yhat_left x, ///
                yaxis(2) ///
                lcolor(black) ///
                lwidth(medthick)) ///
            (line yhat_right x, ///
                yaxis(2) ///
                lcolor(black) ///
                lwidth(medthick)) ///
            , ///
            xline(0, lpattern(dash) lcolor(gs8)) ///
            xlabel(-50(10)50) ///
            xscale(range(-50 50)) ///
            xtitle("Distance to Admission Cutoff") ///
            ytitle("Frequency", axis(1)) ///
            ytitle("`ytitle'", axis(2)) ///
            ylabel(, axis(1) angle(horizontal)) ///
            ylabel(0(.1)1, axis(2) angle(horizontal)) ///
            title("`title'") ///
            text(`text_y' `text_x' "`label': `beta_txt' (`se_txt')", ///
                placement(e) size(small) color(black)) ///
            graphregion(color(white)) ///
            plotregion(color(white)) ///
            legend(off)

        graph export "`saving'.pdf", replace

    restore

end


************************************************************
* 3. Crear figuras
************************************************************

make_rd_hist_grad graduates_he_8y, ///
    ytitle("Graduated from Higher Education within 8 Years") ///
    title("Effect on Graduation from Higher Education") ///
    saving("$output/figures/rd_graduates_he_8y") ///
    label("RD estimate")


make_rd_hist_grad graduates_uni_8y, ///
    ytitle("Graduated from University within 8 Years") ///
    title("Effect on Graduation from University") ///
    saving("$output/figures/rd_graduates_uni_8y") ///
    label("RD estimate")


make_rd_hist_grad graduates_target_8y, ///
    ytitle("Graduated from Target Program within 8 Years") ///
    title("Effect on Graduation from the Target Program") ///
    saving("$output/figures/rd_graduates_target_8y") ///
    label("RD estimate")


************************************************************
* 4. Fin
************************************************************

di as result "Figuras guardadas en:"
di as result "$output/figures/"