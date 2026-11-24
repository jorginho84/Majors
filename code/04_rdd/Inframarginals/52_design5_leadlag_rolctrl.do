/**********************************************************************
* 52_design5_leadlag_rolctrl.do
*
* Deck slide "Design V: all years' seats together (distributed lag)"
* (issue #10), under the three candidate main ROL FE and the program-year
* controls and time FE of the results slide (50). Same regression as 40
* (B2), seats of t-3..t+3 jointly:
*
*   y_i = sum_k gamma_k Z_p,t+k/10 + x_i'd + [c_pt] + phi_p +
*         [phi_t | phi_u(p)t + phi_f(p)t] + phi_ROL(i) + e_i
*
*   ROL FE : 1st preference + set of universities (main), first three
*            preferences, set of programs
*   specifications: (s1) program + year FE; (s2) + demand in t-1,
*            accreditation and tuition (results slide, spec. (b)); (s3) (s2) with
*            university x year and field x year FE (results slide, spec. (c))
*   x      : PSU, NEM, female, private-paid, municipal (as 40)
*   y      : entrants n_pt; graduation from the enrolled program within
*            8 years (pp)
*   Z      : TOTAL_CUPOS from the Oferta Academica 2007-2019 (as 40);
*            cohorts 2010-2016 keep all seven terms
*   SE     : clustered by program-year
*
* Outputs: output/inframarginal/tables/im_d5_leadlag_rolctrl.csv
*          output/inframarginal/figures/im_d5_leadlag_{grad,fs}_s{1,2,3}.pdf
*
* Inputs: as 40 (design5_individual, Oferta Academica 2007-2019);
*         $processed/program_year_controls_2007_2016.dta (02_build/20)
**********************************************************************/

clear all
set more off
do "code/config.do"

global im_out "$output/inframarginal"
cap mkdir "$im_out/tables"
cap mkdir "$im_out/figures"

use grad_year using "$processed/check_06b_titulados_all.dta", clear
quietly summarize grad_year
local last_cohort = r(max) - 8

capture program drop stars
program define stars
    args p name
    c_local `name' = cond(`p' < 0.01, "\sym{***}", cond(`p' < 0.05, "\sym{**}", cond(`p' < 0.10, "\sym{*}", "")))
end

/**********************************************************************
* 2. Instrument leads and lags
**********************************************************************/

* Z extended: TOTAL_CUPOS read directly from the Oferta Academica,
* 2007-2019 (the column exists until 2019; from 2020 only regular
* vacancies are published). Same concept as Z_total_cupos (02_build/13,
* 2007-2016; max over duplicate rows, as there), so cohorts 2010-2016
* have the instrument for t-3..t+3. Code harmonized as in 13/01c.
capture program drop harmonize_code
program define harmonize_code
    args in out
    tempvar s
    gen `s' = strtrim(string(`in', "%12.0f"))
    gen long `out' = `in'
    replace `out' = real(substr(`s', 1, length(`s')-2) + "0" + ///
        substr(`s', length(`s')-1, 2)) if length(`s') == 4
end

tempfile zx
forvalues y = 2007/2019 {
    import excel using "$demre_raw/Postulacion/OfertaAcadémica_Admisión`y'.xlsx", ///
        firstrow clear allstring
    rename *, upper
    capture rename CODIGO_CARRERA CODIGO
    keep CODIGO TOTAL_CUPOS
    destring CODIGO TOTAL_CUPOS, replace force
    drop if missing(CODIGO)
    gen int ao_proceso = `y'
    if `y' > 2007 append using `zx'
    save `zx', replace
}
harmonize_code CODIGO codigo_carrera_harmonized
collapse (max) zx = TOTAL_CUPOS, by(codigo_carrera_harmonized ao_proceso)
replace zx = . if zx <= 0
tabstat zx, by(ao_proceso) stat(n mean)
xtset codigo_carrera_harmonized ao_proceso
gen double X0 = zx / 10
foreach k in 1 2 3 {
    gen double Zm`k' = L`k'.zx / 10
    gen double Zp`k' = F`k'.zx / 10
}
keep codigo_carrera_harmonized ao_proceso X0 Zm? Zp?
tempfile zll
save `zll'

/**********************************************************************
* 3. Sample (as 40), program-year controls
**********************************************************************/

use "$processed/design5_individual_2007_2016.dta", clear
keep if _m_panel == 3 & ao_proceso <= `last_cohort'
keep if pick_toppref & ao_proceso == first_year_i
duplicates drop mrun, force
merge m:1 codigo_carrera_harmonized ao_proceso using `zll', keep(master match) nogen
merge m:1 codigo_carrera_harmonized ao_proceso ///
    using "$processed/program_year_controls_2007_2016.dta", ///
    keep(master match) gen(_m_ctrl)
egen long pt         = group(program_id_rank_analysis ao_proceso)
egen long programs   = group(program_id_rank_analysis)
egen long uni_year   = group(sigla_universidad ao_proceso)
egen long field_year = group(field ao_proceso)
gen double y_program = 100 * graduates_enrolled_program_8y
gen double Z10 = Z_total_cupos / 10

local ctrl ""
foreach v in psu_lm nem female priv mun {
    gen double c_`v' = cond(missing(`v'), 0, `v')
    gen byte   m_`v' = missing(`v')
    local ctrl "`ctrl' c_`v' m_`v'"
}
local b_dem "ld_apps_l1 ld_apps1_l1 ld_wait_l1 d_score1_l1"
local b_acc "m_acred_carr m_acred_inst m_acred_inst_years m_ltuition m_diurno m_duration"
local cpt ""
foreach b in dem acc {
    foreach v of local b_`b' {
        gen byte mi_`v' = missing(`v')
        quietly summarize mi_`v'
        replace `v' = 0 if mi_`v'
        local cpt "`cpt' `v'"
        if r(max) > 0 local cpt "`cpt' mi_`v'"
    }
}

local fe1 "programs ao_proceso"
local fe2 "programs ao_proceso"
local fe3 "programs uni_year field_year"
local ct1 "`ctrl'"
local ct2 "`ctrl' `cpt'"
local ct3 "`ctrl' `cpt'"

/**********************************************************************
* 4. Distributed lag t-3..t+3
**********************************************************************/

local terms "Zm3 Zm2 Zm1 Z10 Zp1 Zp2 Zp3"
tempname P
tempfile res
postfile `P' str6 rol byte spec str16 dv int k double(b se p) long N using `res', replace
foreach r in top1u top3 set {
    forvalues s = 1/3 {
        foreach dv in N_total_enter y_program {
            quietly reghdfe `dv' `terms' `ct`s'', absorb(`fe`s'' rol_`r') vce(cluster pt)
            local df = e(df_r)
            local N  = e(N)
            local k = -3
            foreach v of local terms {
                post `P' ("`r'") (`s') ("`dv'") (`k') (_b[`v']) (_se[`v']) ///
                    (2 * ttail(`df', abs(_b[`v'] / _se[`v']))) (`N')
                local ++k
            }
            quietly test Zm3 Zm2 Zm1
            post `P' ("`r'") (`s') ("`dv'") (-9) (r(F)) (.) (r(p)) (`N')
            quietly test Zp1 Zp2 Zp3
            post `P' ("`r'") (`s') ("`dv'") (9) (r(F)) (.) (r(p)) (`N')
            di as result "`r' s`s' `dv': t-1 " %7.3f _b[Zm1] " (" %6.3f _se[Zm1] ///
                ")  t " %7.3f _b[Z10] " (" %6.3f _se[Z10] ")  N=" `N'
        }
    }
}
postclose `P'

use `res', clear
export delimited using "$im_out/tables/im_d5_leadlag_rolctrl.csv", replace

/**********************************************************************
* 5. Figures: one per outcome and specification, three ROL FE
**********************************************************************/

keep if inrange(k, -3, 3)
gen double lo = b - 1.96 * se
gen double hi = b + 1.96 * se
gen double kx = k + cond(rol == "top1u", -0.22, cond(rol == "top3", 0, 0.22))
forvalues s = 1/3 {
    foreach dv in y_program N_total_enter {
        local nm = cond("`dv'" == "y_program", "grad", "fs")
        local yt = cond("`dv'" == "y_program", "Change in graduation rate (pp)", "Extra entrants")
        twoway (rcap lo hi kx if dv == "`dv'" & spec == `s' & rol == "top1u", lcolor(navy%70) lwidth(medthick)) ///
               (rcap lo hi kx if dv == "`dv'" & spec == `s' & rol == "top3", lcolor(dkorange%70) lwidth(medthick)) ///
               (rcap lo hi kx if dv == "`dv'" & spec == `s' & rol == "set", lcolor(forest_green%70) lwidth(medthick)) ///
               (scatter b kx if dv == "`dv'" & spec == `s' & rol == "top1u", mcolor(navy) msymbol(circle) msize(large)) ///
               (scatter b kx if dv == "`dv'" & spec == `s' & rol == "top3", mcolor(dkorange) msymbol(diamond) msize(large)) ///
               (scatter b kx if dv == "`dv'" & spec == `s' & rol == "set", mcolor(forest_green) msymbol(triangle) msize(large)), ///
            yline(0, lcolor(gs8) lpattern(dash)) xline(0, lcolor(gs14) lwidth(vthick)) ///
            xlabel(-3 "t-3" -2 "t-2" -1 "t-1" 0 "t (own)" 1 "t+1" 2 "t+2" 3 "t+3", labsize(large)) ///
            xscale(range(-3.5 3.5)) xtitle("Year of the 10 extra seats (relative to entry year t)", size(large)) ///
            ylabel(, labsize(large) angle(0) nogrid) ytitle("`yt'", size(large)) ///
            legend(order(4 "Top 1 + univ. (main)" 5 "First three" 6 "Program set") rows(1) size(medlarge) position(6)) ///
            graphregion(color(white)) plotregion(color(white))
        graph export "$im_out/figures/im_d5_leadlag_`nm'_s`s'.pdf", replace
    }
}

di as result "52_design5_leadlag_rolctrl.do finished."
