/**********************************************************************
* 04_diagnostics_figures.do
*
* Program value-added (issue #9): diagnostics and deck figures.
* Headline VA: version itt (assigned program), program level, outcome
* inc_rank, main specification (portfolio FE + controls).
*
*   A. Program dataset: VA + characteristics + institution
*   B. Balance (MH Fig. 2): university dot plot; program-level densities
*   C. Distribution of VA estimates (histogram)
*   D. Correlates: binned scatter + fitted line (raw mean vs VA)
*   E. Institution share of the VA signal (between-group signal variance)
*   F. Regular vacancies 2007-2025 by VA decile
*   G. Split-sample reliability (odd/even cohorts) and stability
*      (2007-2011 vs 2012-2016); sensitivity to controls
*
* Inputs:  $processed/pva_program_va_correlates.dta, pva_univ_va.dta,
*          pva_students_2007_2016.dta, pva_vacancies_2007_2025.dta
* Output:  output/figures/ProgramVA/ (pdf), output/tables/pva_ (csv)
**********************************************************************/

clear all
set more off
do "code/config.do"
do "code/ProgramVA/00_va_helpers.do"

capture log close
log using "$logs/pva_04_diagnostics_figures.log", replace text

global fig "$output/figures/ProgramVA"
capture mkdir "$fig"
local gopt graphregion(color(white)) plotregion(color(white)) ///
    ylabel(, angle(0) nogrid labsize(small)) xlabel(, labsize(small))

/**********************************************************************
* A. Program dataset
**********************************************************************/

* institution and enrollee composition, from the student file
use S_itt univ_itt S_enr female priv nem using ///
    "$processed/pva_students_2007_2016.dta", clear
preserve
    keep if !missing(S_itt) & univ_itt != ""
    contract S_itt univ_itt, freq(nu)
    gsort S_itt -nu
    bysort S_itt: keep if _n == 1
    rename (S_itt univ_itt) (code_h univ)
    keep code_h univ
    tempfile inst
    save `inst'
restore
keep if !missing(S_enr)
collapse (mean) sh_female = female sh_priv = priv nem_mean = nem, by(S_enr)
rename S_enr code_h
tempfile comp
save `comp'

* vacancies
use "$processed/pva_vacancies_2007_2025.dta", clear
gen double lvac = ln(vac)
preserve
    keep if inrange(ao_proceso, 2007, 2016)
    collapse (mean) lvac_mean = lvac, by(code_h)
    tempfile vm
    save `vm'
restore
keep if inlist(ao_proceso, 2012, 2025)
keep code_h ao_proceso lvac
reshape wide lvac, i(code_h) j(ao_proceso)
gen double dlvac_1225 = lvac2025 - lvac2012
keep code_h dlvac_1225
merge 1:1 code_h using `vm', nogen
tempfile vchar
save `vchar'

use "$processed/pva_program_va_correlates.dta", clear
keep if version == "itt" & !missing(v_inc_main)
merge 1:1 code_h using `inst',  keep(1 3) nogen
merge 1:1 code_h using `comp',  keep(1 3) nogen
merge 1:1 code_h using `vchar', keep(1 3) nogen
quietly summarize mean_inc [aw = n_obs]
gen double mean_inc_c = mean_inc - r(mean)
label var psu_mean   "Average PSU (L-M) of enrollees"
label var nem_mean   "Average NEM of enrollees"
label var sh_priv    "Share of enrollees from private-paid schools"
label var sh_female  "Share of women among enrollees"
label var lvac_mean  "Log regular vacancies (2007-2016 mean)"
label var dlvac_1225 "Log change in regular vacancies, 2012-2025"
save "$processed/pva_program_va_figs.dta", replace

* signal / noise for the headline VA
va_disp v_inc_main se_inc_main n_obs
local sd_sig = r(sd_signal)
local sd_hat = r(sd_hat)
local sd_nz  = r(sd_noise)
di as result "Headline VA: SD hat " %6.2f `sd_hat' "  SD noise " %6.2f `sd_nz' ///
    "  SD signal " %6.2f `sd_sig'

/**********************************************************************
* B. Balance
**********************************************************************/

* B1. University level, MH Fig. 2 format
use "$processed/pva_univ_va.dta", clear
keep if version == "itt"
decode S, gen(univ)
foreach sp in raw balraw balbase main {
    gen double lo_`sp' = v_inc_`sp' - 1.96 * se_inc_`sp'
    gen double hi_`sp' = v_inc_`sp' + 1.96 * se_inc_`sp'
}
gsort -v_inc_raw
gen int ord = _n
local lab ""
forvalues i = 1/`=_N' {
    local lab `lab' `i' "`=univ[`i']'"
}
gen double ord_a = ord - 0.25
gen double ord_b = ord
gen double ord_c = ord + 0.25
twoway (rcap lo_raw hi_raw ord_a, horizontal lcolor(navy%60)) ///
       (scatter ord_a v_inc_raw, msymbol(D) mcolor(navy) msize(small)) ///
       (rcap lo_balraw hi_balraw ord_b, horizontal lcolor(maroon%60)) ///
       (scatter ord_b v_inc_balraw, msymbol(Dh) mcolor(maroon) msize(small)) ///
       (rcap lo_balbase hi_balbase ord_c, horizontal lcolor(forest_green%60)) ///
       (scatter ord_c v_inc_balbase, msymbol(O) mcolor(forest_green) msize(small)), ///
    yscale(reverse) ylabel(`lab', angle(0) labsize(vsmall) nogrid) ytitle("") ///
    xline(0, lcolor(gs10)) xtitle("Income rank relative to the enrollment-weighted mean", size(small)) ///
    legend(order(2 "Actual outcome" 4 "Covariate-predicted" ///
        6 "Covariate-predicted, portfolio FE") cols(1) size(small)) ///
    graphregion(color(white)) xsize(6.5) ysize(7)
graph export "$fig/pva_balance_univ.pdf", replace

* B2. Program level: densities of program coefficients
use "$processed/pva_program_va_figs.dta", clear
twoway (kdensity v_inc_raw [aw = n_obs], lcolor(navy) lwidth(medthick)) ///
       (kdensity v_inc_balraw [aw = n_obs], lcolor(maroon) lpattern(dash)) ///
       (kdensity v_inc_balbase [aw = n_obs], lcolor(forest_green) lwidth(medthick)), ///
    legend(order(1 "Actual outcome, no controls" 2 "Covariate-predicted, no controls" ///
        3 "Covariate-predicted, portfolio FE") cols(1) size(small) ring(0) pos(1)) ///
    xtitle("Program coefficient (income rank points)", size(small)) ytitle("Density") ///
    `gopt'
graph export "$fig/pva_balance_programs.pdf", replace

/**********************************************************************
* C. Distribution of VA estimates
**********************************************************************/

local s1 = string(`sd_sig', "%4.1f")
local s2 = string(`sd_hat', "%4.1f")
twoway (histogram v_inc_main if abs(v_inc_main) < 60, width(2) fcolor(gs13) lcolor(gs10)) ///
       (histogram v_inc_eb if abs(v_inc_eb) < 60, width(2) fcolor(none) lcolor(navy) lwidth(medthick)), ///
    legend(order(1 "VA estimates" 2 "Empirical Bayes (shrunk)") rows(1) size(small)) ///
    xtitle("Program VA on income rank (points, relative to weighted mean)", size(small)) ///
    ytitle("Density") note("Programs: `=_N'. SD of estimates `s2'; SD of signal `s1' (enrollment weighted)." ///
    "Estimates beyond +/-60 points not shown.", size(vsmall)) `gopt'
graph export "$fig/pva_va_histogram.pdf", replace

/**********************************************************************
* D. Correlates: binned scatter + fitted line
**********************************************************************/

capture program drop binfig
program define binfig
    args x name
    preserve
        keep if !missing(`x', v_inc_main)
        local xl : variable label `x'
        quietly reg v_inc_main `x' [aw = n_obs], robust
        local bv = _b[`x']
        local sv = _se[`x']
        local av = _b[_cons]
        quietly reg mean_inc_c `x' [aw = n_obs], robust
        local br = _b[`x']
        local ar = _b[_cons]
        quietly corr v_inc_main `x' [aw = n_obs]
        local rv = r(rho)
        quietly corr mean_inc_c `x' [aw = n_obs]
        local rr = r(rho)
        local sb : display %6.3f `bv'
        local ss : display %5.3f `sv'
        local sr : display %6.3f `br'
        local cv : display %4.2f `rv'
        local cr : display %4.2f `rr'
        xtile bin = `x' [aw = n_obs], n(20)
        collapse (mean) `x' v_inc_main mean_inc_c [aw = n_obs], by(bin)
        * fitted lines over the range of the bins
        quietly summarize `x'
        local lo = r(min)
        local hi = r(max)
        twoway (scatter mean_inc_c `x', msymbol(Oh) mcolor(gs9)) ///
               (function y = `ar' + `br' * x, range(`lo' `hi') lcolor(gs9) lpattern(dash)) ///
               (scatter v_inc_main `x', msymbol(O) mcolor(navy)) ///
               (function y = `av' + `bv' * x, range(`lo' `hi') lcolor(navy)), ///
            legend(order(1 "Raw income rank" 3 "Value-added") rows(1) size(small)) ///
            xtitle("`xl'", size(small)) ytitle("Income rank points", size(small)) ///
            note("VA: slope `sb' (`ss'), corr `cv'.  Raw: slope `sr', corr `cr'.  20 bins, enrollment weighted.", size(vsmall)) ///
            graphregion(color(white)) ylabel(, angle(0) nogrid labsize(small)) ///
            xlabel(, labsize(small)) name(`name', replace)
    restore
end

use "$processed/pva_program_va_figs.dta", clear
local i = 0
foreach x in psu_mean nem_mean sh_priv sh_female lvac_mean dlvac_1225 {
    local ++i
    binfig `x' g`i'
    graph export "$fig/pva_bin_`x'.pdf", replace
}

/**********************************************************************
* E. Institution share of the VA signal
**********************************************************************/

* between-group signal variance: weighted variance of group means of the
* estimates, minus the expected noise in those means
capture program drop between_share
program define between_share, rclass
    args v se w g
    preserve
        keep if !missing(`v', `se', `g')
        tempvar W SV N2 gm nz
        bysort `g': egen double `W'  = total(`w')
        bysort `g': egen double `SV' = total(`w' * `v')
        bysort `g': egen double `N2' = total((`w' * `se')^2)
        gen double `gm' = `SV' / `W'
        gen double `nz' = `N2' / `W'^2
        bysort `g': keep if _n == 1
        quietly summarize `gm' [aw = `W']
        local vb = r(Var) * (r(sum_w) - 1) / r(sum_w)
        quietly summarize `nz' [aw = `W']
        return scalar between = `vb' - r(mean)
        return scalar ngroups = _N
    restore
end

use "$processed/pva_program_va_figs.dta", clear
egen inst_field = group(univ field)
tempname ps
postfile `ps' str12 measure str14 group double(var_signal var_between share) long G ///
    using "$processed/pva_inst_share.dta", replace
foreach m in main raw {
    va_disp v_inc_`m' se_inc_`m' n_obs
    local vs = r(sd_signal)^2
    foreach g in univ field inst_field {
        between_share v_inc_`m' se_inc_`m' n_obs `g'
        post `ps' ("`m'") ("`g'") (`vs') (r(between)) (r(between) / `vs') (r(ngroups))
    }
}
postclose `ps'
use "$processed/pva_inst_share.dta", clear
format var_* share %9.3f
list, noobs
export delimited using "$output/tables/pva_inst_share.csv", replace

gen str20 gl = cond(group == "univ", "Institution", ///
    cond(group == "field", "Field (11)", "Institution x field"))
gen byte go = cond(group == "univ", 1, cond(group == "field", 2, 3))
graph bar share, over(measure, relabel(1 "VA (main)" 2 "Raw income rank") ///
        label(labsize(small))) over(gl, sort(go) label(labsize(small))) asyvars ///
    bar(1, color(navy)) bar(2, color(gs11)) ///
    ytitle("Share of signal variance between groups", size(small)) ///
    ylabel(0(.2)1, angle(0) nogrid) blabel(bar, format(%4.2f) size(vsmall)) ///
    legend(rows(1) size(small)) graphregion(color(white))
graph export "$fig/pva_inst_share.pdf", replace

/**********************************************************************
* F. Regular vacancies 2007-2025 by VA decile
**********************************************************************/

use "$processed/pva_program_va_figs.dta", clear
xtile dec = v_inc_eb [aw = n_obs], n(10)
keep code_h dec n_obs
tempfile decs
save `decs'

use "$processed/pva_vacancies_2007_2025.dta", clear
merge m:1 code_h using `decs', keep(2 3)
di as result "=== VA programs observed in the Oferta Academica, by year ==="
preserve
    keep if _merge == 3
    tab ao_proceso
restore
keep if _merge == 3
drop _merge

* F1. total regular vacancies by decile, 2012 = 100
preserve
    collapse (sum) vac (count) nprog = vac, by(dec ao_proceso)
    gen double v12_aux = vac if ao_proceso == 2012
    bysort dec: egen double v12 = max(v12_aux)
    gen double idx = 100 * vac / v12
    export delimited dec ao_proceso vac nprog idx ///
        using "$output/tables/pva_vacancies_by_decile.csv", replace
    local plots ""
    forvalues d = 2/9 {
        local plots `plots' (line idx ao_proceso if dec == `d', lcolor(gs12) lwidth(thin))
    }
    twoway `plots' ///
        (connected idx ao_proceso if dec == 1, lcolor(maroon) mcolor(maroon) msize(small)) ///
        (connected idx ao_proceso if dec == 10, lcolor(navy) mcolor(navy) lwidth(thick) msize(small)), ///
        legend(order(10 "Top VA decile" 9 "Bottom VA decile" 1 "Deciles 2-9") rows(1) size(small)) ///
        xline(2012, lcolor(gs10) lpattern(dot)) yline(100, lcolor(gs10)) ///
        xlabel(2007(2)2025, labsize(small)) xtitle("Admission year") ///
        ytitle("Total regular vacancies (2012 = 100)", size(small)) `gopt'
    graph export "$fig/pva_vacancies_decile_total.pdf", replace
restore

* F2. within-program log change relative to 2012, by decile
preserve
    gen double lvac = ln(vac)
    gen double l12_aux = lvac if ao_proceso == 2012
    bysort code_h: egen double l12 = max(l12_aux)
    gen double dl = lvac - l12
    keep if !missing(dl)
    collapse (mean) dl (count) nprog = dl [aw = n_obs], by(dec ao_proceso)
    export delimited using "$output/tables/pva_vacancies_by_decile_within.csv", replace
    local plots ""
    forvalues d = 2/9 {
        local plots `plots' (line dl ao_proceso if dec == `d', lcolor(gs12) lwidth(thin))
    }
    twoway `plots' ///
        (connected dl ao_proceso if dec == 1, lcolor(maroon) mcolor(maroon) msize(small)) ///
        (connected dl ao_proceso if dec == 10, lcolor(navy) mcolor(navy) lwidth(thick) msize(small)), ///
        legend(order(10 "Top VA decile" 9 "Bottom VA decile" 1 "Deciles 2-9") rows(1) size(small)) ///
        xline(2012, lcolor(gs10) lpattern(dot)) yline(0, lcolor(gs10)) ///
        xlabel(2007(2)2025, labsize(small)) xtitle("Admission year") ///
        ytitle("Mean log vacancies relative to 2012", size(small)) `gopt'
    graph export "$fig/pva_vacancies_decile_within.pdf", replace
restore

/**********************************************************************
* G. Split-sample reliability, stability, sensitivity to controls
**********************************************************************/

use "$processed/pva_students_2007_2016.dta", clear
pva_controls
gen long S = S_itt
gen long P = port_bin
keep if !missing(S, P)
gen byte h_oddeven   = mod(ao_proceso, 2)
gen byte h_earlylate = ao_proceso >= 2012
tempfile stud
save `stud'

tempname pr
postfile `pr' str10 split double(sd_sig0 sd_sig1 cov01 corr01 corr_pred) long K ///
    using "$processed/pva_split_sample.dta", replace
foreach split in oddeven earlylate {
    forvalues h = 0/1 {
        use `stud', clear
        keep if h_`split' == `h'
        id_sample n_feas
        capture frame drop fr
        frame put S, into(fr)
        frame fr {
            bysort S: gen long n_obs = _N
            bysort S: keep if _n == 1
            sort S
        }
        va_reg inc_rank, s(S) tag(h) frame(fr) absorb(P) controls
        frame fr {
            rename (v_h se_h n_obs) (v`h' se`h' n`h')
            tempfile r`h'
            save `r`h''
        }
    }
    use `r0', clear
    merge 1:1 S using `r1', keep(3) nogen
    keep if !missing(v0, v1)
    gen double w = min(n0, n1)
    * signal variance in each half from the noise correction, and the
    * cross-half covariance (an estimate of the signal variance that is
    * free of estimation noise if VA is stable)
    va_disp v0 se0 w
    local s0 = r(sd_signal)
    local h0 = r(sd_hat)
    va_disp v1 se1 w
    local s1 = r(sd_signal)
    local h1 = r(sd_hat)
    quietly corr v0 v1 [aw = w], covariance
    local c01 = r(cov_12)
    quietly corr v0 v1 [aw = w]
    local r01 = r(rho)
    * correlation implied by a stable VA: signal over total in each half
    local rp = (`s0' * `s1') / (`h0' * `h1')
    post `pr' ("`split'") (`s0') (`s1') (`c01') (`r01') (`rp') (_N)
    di as result "`split': corr " %5.3f `r01' "  implied by stable VA " %5.3f `rp' ///
        "  cov " %7.2f `c01' "  (signal var halves " %7.2f `s0'^2 ", " %7.2f `s1'^2 ")"

    * binned scatter
    local K = _N
    xtile bin = v0 [aw = w], n(20)
    quietly reg v1 v0 [aw = w], robust
    local b = _b[v0]
    local se = _se[v0]
    local sb : display %4.2f `b'
    local ss : display %4.2f `se'
    local sc : display %4.2f `r01'
    local sp : display %4.2f `rp'
    preserve
        collapse (mean) v0 v1 [aw = w], by(bin)
        local t0 = cond("`split'" == "oddeven", "odd cohorts", "2007-2011")
        local t1 = cond("`split'" == "oddeven", "even cohorts", "2012-2016")
        twoway (scatter v1 v0, mcolor(navy)) (lfit v1 v0, lcolor(navy)) ///
               (function y = x, range(v0) lcolor(gs10) lpattern(dash)), ///
            legend(off) xtitle("VA estimated on `t0'", size(small)) ///
            ytitle("VA estimated on `t1'", size(small)) ///
            note("Programs in both halves: `K' (20 bins). Program-level slope `sb' (`ss'); corr `sc', implied by a stable VA `sp'.", size(vsmall)) `gopt'
        graph export "$fig/pva_split_`split'.pdf", replace
    restore
}
postclose `pr'
use "$processed/pva_split_sample.dta", clear
list, noobs
export delimited using "$output/tables/pva_split_sample.csv", replace

* sensitivity to controls: typical controls and baseline vs main
use "$processed/pva_program_va_figs.dta", clear
xtile bin = v_inc_main [aw = n_obs], n(20)
collapse (mean) v_inc_main v_inc_typ v_inc_base v_inc_raw [aw = n_obs], by(bin)
twoway (scatter v_inc_raw v_inc_main, msymbol(Oh) mcolor(gs9)) ///
       (scatter v_inc_typ v_inc_main, msymbol(Th) mcolor(maroon)) ///
       (scatter v_inc_base v_inc_main, msymbol(O) mcolor(navy)) ///
       (function y = x, range(v_inc_main) lcolor(gs10) lpattern(dash)), ///
    legend(order(1 "No controls" 2 "Typical controls" 3 "Portfolio FE only") ///
        rows(1) size(small)) ///
    xtitle("Main VA (portfolio FE + controls)", size(small)) ///
    ytitle("Alternative estimate", size(small)) ///
    note("20 bins of main VA, enrollment weighted.", size(vsmall)) `gopt'
graph export "$fig/pva_sensitivity_controls.pdf", replace

log close
