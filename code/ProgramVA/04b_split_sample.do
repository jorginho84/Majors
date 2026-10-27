/**********************************************************************
* 04b_split_sample.do
*
* Program value-added (issue #9): split-sample reliability (odd vs. even
* cohorts), stability (2007-2011 vs. 2012-2016) and sensitivity to
* controls. Slow (about 40 minutes): kept apart from 04.
*
* Inputs:  $processed/pva_students_2007_2016.dta,
*          $processed/pva_program_va_figs.dta (from 04)
* Output:  output/figures/ProgramVA/pva_split_*.pdf,
*          pva_sensitivity_controls.pdf, output/tables/pva_split_sample.csv
**********************************************************************/

clear all
set more off
do "code/config.do"
do "code/ProgramVA/00_va_helpers.do"

capture log close
log using "$logs/pva_04b_split_sample.log", replace text

global fig "$output/figures/ProgramVA"
local gopt graphregion(color(white)) plotregion(color(white)) ///
    ylabel(, angle(0) nogrid labsize(small)) xlabel(, labsize(small))

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
