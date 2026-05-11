************************************************************
* 08_combined_rdd_figures_by_field.do
* Combina los RDD de los 10 campos en una sola figura 2x5
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

* Ventana para gráfico
keep if abs(score_rd) <= 50

drop if missing(field)
drop if field == "Missing"
drop if field == ""

capture mkdir "$output/figures"
capture mkdir "$output/figures/by_field"
capture mkdir "$output/figures/by_field/gph"
capture mkdir "$output/figures/by_field/combined"


************************************************************
* 2. Programa para crear un gráfico RD individual en .gph
************************************************************

capture program drop make_rd_hist_field_gph
program define make_rd_hist_field_gph

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
        * Unir bases para graficar
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

        local text_x = 12
        local text_y = `maxfreq' * 0.08


        ************************************************************
        * Gráfico individual
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
            xlabel(-50(25)50, labsize(vsmall)) ///
            xscale(range(-50 50)) ///
            xtitle("Distance to cutoff", size(vsmall)) ///
            ytitle("Frequency", axis(1) size(vsmall)) ///
            ytitle("`ytitle'", axis(2) size(vsmall)) ///
            ylabel(, axis(1) angle(horizontal) labsize(vsmall)) ///
            ylabel(0(.2)1, axis(2) angle(horizontal) labsize(vsmall)) ///
            title("`title'", size(small)) ///
            text(`text_y' `text_x' "`label': `beta_txt' (`se_txt')", ///
                placement(e) size(vsmall) color(black)) ///
            graphregion(color(white)) ///
            plotregion(color(white)) ///
            legend(off)

        graph save "`saving'.gph", replace

    restore

end


************************************************************
* 3. Programa para crear figura combinada 2x5
************************************************************

capture program drop make_combined_field_rdd
program define make_combined_field_rdd

    syntax varname, ///
        Ytitle(string) ///
        MAINTITLE(string) ///
        Outname(string) ///
        [Label(string)]

    * Lista de campos con compound quotes para evitar problemas con espacios
    local fields `" "Agriculture" "Arts and Architecture" "Basic Sciences" "Business" "Education" "Health" "Humanities" "Law" "Social Sciences" "Technology" "'

    local graphlist ""

    foreach f of local fields {

        local f_safe = strtoname("`f'")

        di as text "----------------------------------------"
        di as result "Creando gráfico: `varlist' - `f'"
        di as text "----------------------------------------"

        make_rd_hist_field_gph `varlist', ///
            field("`f'") ///
            ytitle("`ytitle'") ///
            title("`f'") ///
            saving("$output/figures/by_field/gph/rd_`varlist'_`f_safe'") ///
            label("`label'")

        local graphlist `"`graphlist' "$output/figures/by_field/gph/rd_`varlist'_`f_safe'.gph""'
    }

    graph combine `graphlist', ///
        rows(2) ///
        cols(5) ///
        imargin(tiny) ///
        graphregion(color(white)) ///
        title("`maintitle'", size(medsmall)) ///
        xsize(16) ///
        ysize(8)

    graph export "$output/figures/by_field/combined/`outname'.pdf", replace

end


************************************************************
* 4. Crear figuras combinadas por outcome
************************************************************

make_combined_field_rdd enrolls_target, ///
    ytitle("Enrolls in Target Program") ///
    maintitle("RDD: Enroll in the Target Program by Field") ///
    outname("combined_rd_enrolls_target_by_field") ///
    label("First Stage")


make_combined_field_rdd enrolls_he, ///
    ytitle("Enrolls in Higher Education") ///
    maintitle("RDD: Higher Education Enrollment by Field") ///
    outname("combined_rd_enrolls_he_by_field") ///
    label("RD estimate")


make_combined_field_rdd enrolls_uni, ///
    ytitle("Enrolls in University") ///
    maintitle("RDD: University Enrollment by Field") ///
    outname("combined_rd_enrolls_uni_by_field") ///
    label("RD estimate")


************************************************************
* 5. Fin
************************************************************

di as result "Figuras combinadas guardadas en:"
di as result "$output/figures/by_field/combined/"