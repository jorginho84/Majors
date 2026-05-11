************************************************************
* 07_rdd_figures_by_field.do
* Figuras RDD por field con formato similar al gráfico base
* Output: solo PDF
************************************************************

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

* Ventana para gráfico: igual que gráfico original, -50 a 50
keep if abs(score_rd) <= 50

* Por seguridad
drop if missing(field)
drop if field == "Missing"
drop if field == ""

capture mkdir "$output/figures"
capture mkdir "$output/figures/by_field"


************************************************************
* 2. Programa para figura RD + histograma
************************************************************

capture program drop make_rd_hist_field
program define make_rd_hist_field

    syntax varname, Field(string) ///
        Ytitle(string) ///
        Title(string) ///
        Saving(string) ///
        [Label(string)]

    preserve

        keep if field == "`field'"
        keep if !missing(`varlist', score_rd, above_cutoff)

        count
        if r(N) == 0 {
            di as error "No hay observaciones para field = `field' y outcome = `varlist'"
            restore
            exit
        }


        ************************************************************
        * Estimación RD con ventana de 25 puntos
        ************************************************************

        reghdfe `varlist' ///
            above_cutoff score_rd 1.above_cutoff#c.score_rd ///
            if abs(score_rd) <= $bandwidth, ///
            absorb(i.ao_proceso#i.t_codigo_carrera) ///
            cluster(i.ao_proceso#i.t_codigo_carrera)

        local beta = _b[above_cutoff]
        local se   = _se[above_cutoff]

        local beta_txt : display %5.3f `beta'
        local se_txt   : display %5.3f `se'

        if "`label'" == "" {
            local label "RD estimate"
        }


        ************************************************************
        * Crear datos para histograma, puntos y líneas
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
        * Ajuste lineal izquierdo usando microdatos
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
        * Ajuste lineal derecho usando microdatos
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
        * Unir bases para graficar
        ************************************************************

        use `hist', clear
        append using `bins'
        append using `leftfit'
        append using `rightfit'


        ************************************************************
        * Posición del texto
        * Usamos coordenadas del eje izquierdo de frecuencia
        * para que text() siempre se muestre.
        ************************************************************

        quietly summarize freq if !missing(freq)
        local maxfreq = r(max)

        local text_x = 15
        local text_y = `maxfreq' * 0.08


        ************************************************************
        * Gráfico
        * OJO: scatter SIN [aw=n], para que los puntos sean pequeños
        * y uniformes, como en el gráfico original.
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
* 3. Loop por field y outcome
************************************************************

levelsof field, local(fields)

foreach f of local fields {

    local f_safe = strtoname("`f'")

    di as text "=================================================="
    di as result "Generando figuras para field: `f'"
    di as text "=================================================="


    ************************************************************
    * Outcome 1: Enrolls in Target Program
    * Este sí corresponde al first stage principal.
    ************************************************************

    make_rd_hist_field enrolls_target, ///
        field("`f'") ///
        ytitle("Enrolls in Target Program") ///
        title("Enroll in the Target Program - `f'") ///
        saving("$output/figures/by_field/rd_enrolls_target_`f_safe'") ///
        label("First Stage")


    ************************************************************
    * Outcome 2: Enrolls in Higher Education
    * Reduced-form effect.
    ************************************************************

    make_rd_hist_field enrolls_he, ///
        field("`f'") ///
        ytitle("Enrolls in Higher Education") ///
        title("Effect on Higher Education Enrollment - `f'") ///
        saving("$output/figures/by_field/rd_enrolls_he_`f_safe'") ///
        label("RD estimate")


    ************************************************************
    * Outcome 3: Enrolls in University
    * Reduced-form effect.
    ************************************************************

    make_rd_hist_field enrolls_uni, ///
        field("`f'") ///
        ytitle("Enrolls in University") ///
        title("Effect on University Enrollment - `f'") ///
        saving("$output/figures/by_field/rd_enrolls_uni_`f_safe'") ///
        label("RD estimate")
}


************************************************************
* 4. Fin
************************************************************

di as result "Figuras guardadas en:"
di as result "$output/figures/by_field/"