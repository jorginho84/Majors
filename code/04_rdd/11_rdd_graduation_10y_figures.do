/**********************************************************************
* 11_rdd_graduation_10y_figures.do
*
* Figuras RDD de titulación a 10 años.
* Incluye:
*   - Figuras generales
*   - Figuras combinadas 2x5 por campo
**********************************************************************/

clear
set more off

************************************************************
* 0. Cargar configuración
************************************************************

do "C:/Users/jigodoy/Documents/GitHub/Majors/code/config.do"


************************************************************
* 1. Abrir base de graduación a 10 años
************************************************************

use "$processed/analysis_sample_with_fields_graduation_10y.dta", clear

keep if abs(score_rd) <= 50

drop if missing(field)
drop if field == ""
drop if field == "Missing"

capture confirm variable program_year_id
if _rc != 0 {
    egen program_year_id = group(ao_proceso t_codigo_carrera)
}

capture mkdir "$output/figures"
capture mkdir "$output/figures/graduation_10y"
capture mkdir "$output/figures/graduation_10y/gph"
capture mkdir "$output/figures/graduation_10y/combined"


************************************************************
* 2. Programa para gráfico RD individual
************************************************************

capture program drop make_rd_grad10
program define make_rd_grad10

    syntax varname, ///
        Ytitle(string) ///
        Title(string) ///
        Saving(string) ///
        [Field(string) Label(string) Gph]

    preserve

        if "`field'" != "" {
            keep if field == "`field'"
        }

        keep if !missing(`varlist', score_rd, above_cutoff)

        count
        if r(N) == 0 {
            di as error "No hay observaciones para outcome = `varlist' field = `field'"
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
        * Bases para histograma, bins y líneas
        ************************************************************

        tempfile main hist bins leftfit rightfit

        save `main', replace


        * Histograma
        use `main', clear

        gen hist_bin = floor(score_rd/5)*5
        collapse (count) freq = score_rd, by(hist_bin)

        rename hist_bin x
        save `hist', replace


        * Bins outcome
        use `main', clear

        gen rd_bin = floor(score_rd/5)*5 + 2.5

        collapse ///
            (mean) y_mean = `varlist' ///
            (count) n = `varlist', ///
            by(rd_bin)

        rename rd_bin x
        save `bins', replace


        * Fit izquierdo
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


        * Fit derecho
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
        * Unir datos
        ************************************************************

        use `hist', clear
        append using `bins'
        append using `leftfit'
        append using `rightfit'


        ************************************************************
        * Posición texto
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

        if "`gph'" != "" {
            graph save "`saving'.gph", replace
        }
        else {
            graph export "`saving'.pdf", replace
        }

    restore

end


************************************************************
* 3. Figuras generales
************************************************************

make_rd_grad10 graduates_he_10y, ///
    ytitle("Graduated from Higher Education within 10 Years") ///
    title("Effect on Graduation from Higher Education") ///
    saving("$output/figures/graduation_10y/rd_graduates_he_10y") ///
    label("RD estimate")


make_rd_grad10 graduates_uni_10y, ///
    ytitle("Graduated from University within 10 Years") ///
    title("Effect on Graduation from University") ///
    saving("$output/figures/graduation_10y/rd_graduates_uni_10y") ///
    label("RD estimate")


make_rd_grad10 graduates_target_10y, ///
    ytitle("Graduated from Target Program within 10 Years") ///
    title("Effect on Graduation from the Target Program") ///
    saving("$output/figures/graduation_10y/rd_graduates_target_10y") ///
    label("RD estimate")


************************************************************
* 4. Programa para combinar 10 campos en 2x5
************************************************************

capture program drop make_combined_grad10
program define make_combined_grad10

    syntax varname, ///
        Ytitle(string) ///
        MAINTITLE(string) ///
        Outname(string) ///
        [Label(string)]

    local fields `" "Agriculture" "Arts and Architecture" "Basic Sciences" "Business" "Education" "Health" "Humanities" "Law" "Social Sciences" "Technology" "'

    local graphlist ""

    foreach f of local fields {

        local f_safe = strtoname("`f'")

        di as text "----------------------------------------"
        di as result "Creando gráfico: `varlist' - `f'"
        di as text "----------------------------------------"

        make_rd_grad10 `varlist', ///
            field("`f'") ///
            ytitle("`ytitle'") ///
            title("`f'") ///
            saving("$output/figures/graduation_10y/gph/rd_`varlist'_`f_safe'") ///
            label("`label'") ///
            gph

        local graphlist `"`graphlist' "$output/figures/graduation_10y/gph/rd_`varlist'_`f_safe'.gph""'
    }

    graph combine `graphlist', ///
        rows(2) ///
        cols(5) ///
        imargin(tiny) ///
        graphregion(color(white)) ///
        title("`maintitle'", size(medsmall)) ///
        xsize(16) ///
        ysize(8)

    graph export "$output/figures/graduation_10y/combined/`outname'.pdf", replace

end


************************************************************
* 5. Figuras combinadas 2x5
************************************************************

make_combined_grad10 graduates_he_10y, ///
    ytitle("Graduated HE within 10 years") ///
    maintitle("RDD: Graduation from Higher Education within 10 Years by Field") ///
    outname("combined_rd_graduates_he_10y_by_field") ///
    label("RD estimate")


make_combined_grad10 graduates_uni_10y, ///
    ytitle("Graduated University within 10 years") ///
    maintitle("RDD: Graduation from University within 10 Years by Field") ///
    outname("combined_rd_graduates_uni_10y_by_field") ///
    label("RD estimate")


make_combined_grad10 graduates_target_10y, ///
    ytitle("Graduated Target Program within 10 years") ///
    maintitle("RDD: Graduation from Target Program within 10 Years by Field") ///
    outname("combined_rd_graduates_target_10y_by_field") ///
    label("RD estimate")


************************************************************
* 6. Fin
************************************************************

di as result "Figuras generales guardadas en:"
di as result "$output/figures/graduation_10y/"

di as result "Figuras combinadas guardadas en:"
di as result "$output/figures/graduation_10y/combined/"