/**********************************************************************
* 06_event_study.do
*
* Design III — event studies around k's first treatment year g_k.
* Never-treated programs are controls.
*
* (A) Dynamic TWFE
*     y_kt = sum_{l != -1} b_l 1{t - g_k = l} + d own_cumshock
*            + mu_k + a_{f(k),t} + g_{r(k),t} + e
*     Event time binned at <= -5 and >= +4. SE clustered by program.
*
* (B) Callaway & Sant'Anna (csdid), not-yet-treated controls. It cannot
*     absorb field-year or region-year effects, so it is the check on
*     negative weighting in (A), not a replacement for its controls.
*
* Outcomes: log enrollment (main), entrant PSU, cutoff.
* (B) uses the balanced panel of programs observed in all ten years.
*
* Treatments (from 03): main = exposure above p75; p90; nbr5 = shock at
* one of k's five most ROL-similar programs.
*
* Figures: output/vacancy_shocks/figures/vs_es_<outcome>_<treatment>.pdf
* Tables:  output/vacancy_shocks/tables/vs_es_<outcome>_<treatment>.tex
*          output/vacancy_shocks/tables/vs_es_pretrends.tex (all pretrend tests)
*
* Input: $processed/vs_panel_exposure.dta
**********************************************************************/

do "code/config.do"

global vs_out "$output/vacancy_shocks"
cap mkdir "$vs_out/tables"
cap mkdir "$vs_out/figures"

use "$processed/vs_panel_exposure.dta", clear
keep if est_sample
xtset pid ao_proceso

egen long fy = group(field ao_proceso)
egen long ry = group(region ao_proceso)

* balanced panel flag for csdid
bys pid: gen byte nyrs = _N
gen byte balanced = nyrs == 10 & N_first_pre > 0

tempname P
postfile `P' str8 treatment str20 outcome str10 est double stat p using ///
    "$vs_out/tables/_pretrends.dta", replace

* treatment definitions (see 03): p75 of positive exposure (main),
* p90, and a shock at one of k's five most ROL-similar programs
foreach trt in main p90 nbr5 {

    local sfx = cond("`trt'" == "main", "", "_`trt'")
    local tlab = cond("`trt'" == "main", "first year with ROL exposure above p75", ///
                 cond("`trt'" == "p90",  "first year with ROL exposure above p90", ///
                                         "first shock at a top-5 ROL neighbor"))

    capture drop ev_*
    * event-time dummies (never-treated: all zero)
    gen byte ev_m5 = g`sfx' > 0 & rel`sfx' <= -5
    gen byte ev_m4 = g`sfx' > 0 & rel`sfx' == -4
    gen byte ev_m3 = g`sfx' > 0 & rel`sfx' == -3
    gen byte ev_m2 = g`sfx' > 0 & rel`sfx' == -2
    gen byte ev_p0 = g`sfx' > 0 & rel`sfx' == 0
    gen byte ev_p1 = g`sfx' > 0 & rel`sfx' == 1
    gen byte ev_p2 = g`sfx' > 0 & rel`sfx' == 2
    gen byte ev_p3 = g`sfx' > 0 & rel`sfx' == 3
    gen byte ev_p4 = g`sfx' > 0 & rel`sfx' >= 4 & rel`sfx' < .

    di as text _n "Cohorts, treatment `trt':"
    tab g`sfx' if ao_proceso == 2016

foreach y in lnN psu_first cutoff {

    local ylab = cond("`y'" == "lnN", "Log first-year enrollment", ///
                 cond("`y'" == "psu_first", "Mean entrant PSU", "Admission cutoff"))

    /******************************************************************
    * (A) Dynamic TWFE
    ******************************************************************/
    reghdfe `y' ev_* own_cumshock, absorb(pid fy ry) cluster(pid)
    test ev_m5 ev_m4 ev_m3 ev_m2
    local pA = r(p)
    post `P' ("`trt'") ("`y'") ("TWFE") (r(F)) (r(p))
    estimates store twfe

    preserve
    clear
    set obs 10
    gen int rel = _n - 6            // -5 ... 4
    gen double b = .
    gen double lo = .
    gen double hi = .
    local i = 0
    foreach e in m5 m4 m3 m2 m1 p0 p1 p2 p3 p4 {
        local ++i
        if "`e'" == "m1" {
            replace b = 0 in `i'
            continue
        }
        estimates restore twfe
        replace b  = _b[ev_`e'] in `i'
        replace lo = _b[ev_`e'] - 1.96 * _se[ev_`e'] in `i'
        replace hi = _b[ev_`e'] + 1.96 * _se[ev_`e'] in `i'
    }
    gen str4 est = "TWFE"
    tempfile esA
    save `esA'
    restore

    /******************************************************************
    * (B) Callaway & Sant'Anna
    ******************************************************************/
    csdid `y' if balanced & !missing(`y'), ivar(pid) time(ao_proceso) gvar(g`sfx') notyet
    estat pretrend
    local pB = r(pchi2)
    post `P' ("`trt'") ("`y'") ("CS") (r(chi2)) (r(pchi2))
    estat event, window(-5 4) estore(cs)
    local pAs = string(`pA', "%5.3f")
    local pBs = string(`pB', "%5.3f")

    preserve
    clear
    set obs 10
    gen int rel = _n - 6
    gen double b = .
    gen double lo = .
    gen double hi = .
    estimates restore cs
    local i = 0
    forvalues l = -5/4 {
        local ++i
        foreach T in T t {
            local nm = cond(`l' < 0, "`T'm" + string(-`l'), "`T'p" + string(`l'))
            capture replace b  = _b[`nm'] in `i'
            capture replace lo = _b[`nm'] - 1.96 * _se[`nm'] in `i'
            capture replace hi = _b[`nm'] + 1.96 * _se[`nm'] in `i'
        }
    }
    gen str4 est = "CS"
    append using `esA'

    gen double x = rel + cond(est == "TWFE", -0.12, 0.12)
    twoway ///
        (rcap lo hi x if est == "TWFE", lcolor(navy)) ///
        (scatter b x if est == "TWFE", mcolor(navy) msymbol(O)) ///
        (rcap lo hi x if est == "CS", lcolor(dkorange)) ///
        (scatter b x if est == "CS", mcolor(dkorange) msymbol(D)), ///
        yline(0, lcolor(gs10)) xline(-0.5, lcolor(cranberry) lpattern(dash)) ///
        xlabel(-5 "{&le}-5" -4(1)3 4 "{&ge}4") ///
        xtitle("Years since `tlab'") ytitle("`ylab'") ///
        legend(order(2 "TWFE (field-year, region-year FE)" 4 "Callaway & Sant'Anna") ///
            rows(1) size(small)) ///
        note("TWFE omits t = -1; pretrend p = `pAs'." ///
             " CS: not-yet-treated controls, balanced panel; pretrend p = `pBs'.", ///
             size(vsmall)) ///
        graphregion(color(white)) plotregion(color(white))
    graph export "$vs_out/figures/vs_es_`y'_`trt'.pdf", replace

    * side-by-side table of event-time coefficients
    keep rel est b lo hi
    reshape wide b lo hi, i(rel) j(est) string
    sort rel
    file open T using "$vs_out/tables/vs_es_`y'_`trt'.tex", write replace
    file write T "\begin{tabular}{lcc}" _n "\toprule" _n
    file write T "Event time & TWFE & Callaway--Sant'Anna \\" _n "\midrule" _n
    forvalues i = 1/`=_N' {
        local r = rel[`i']
        local lab = cond(`r' == -5, "\(\le -5\)", cond(`r' == 4, "\(\ge 4\)", "`r'"))
        if `r' == -1 {
            file write T "`lab' & \multicolumn{1}{c}{ref.} & " %6.3f (bCS[`i']) " \\" _n
            continue
        }
        file write T "`lab' & " %6.3f (bTWFE[`i']) " & " %6.3f (bCS[`i']) " \\" _n
        file write T " & (" %5.3f ((hiTWFE[`i'] - loTWFE[`i']) / 3.92) ") & (" ///
            %5.3f ((hiCS[`i'] - loCS[`i']) / 3.92) ") \\" _n
    }
    file write T "\midrule" _n "Pretrend test \(p\)-value & " %5.3f (`pA') " & " %5.3f (`pB') " \\" _n
    file write T "\bottomrule" _n "\end{tabular}" _n
    file close T
    restore
}
}

postclose `P'

* pretrend summary across treatments and outcomes
use "$vs_out/tables/_pretrends.dta", clear
list, clean noobs
reshape wide stat p, i(treatment outcome) j(est) string
gen byte ord = cond(treatment == "main", 1, cond(treatment == "p90", 2, 3))
gen byte oy  = cond(outcome == "lnN", 1, cond(outcome == "psu_first", 2, 3))
sort ord oy
file open T using "$vs_out/tables/vs_es_pretrends.tex", write replace
file write T "\begin{tabular}{llcc}" _n "\toprule" _n
file write T "Treatment & Outcome & TWFE \(p\) & Callaway--Sant'Anna \(p\) \\" _n "\midrule" _n
forvalues i = 1/`=_N' {
    local t = cond(ord[`i'] == 1, "Exposure \(>\) p75", cond(ord[`i'] == 2, "Exposure \(>\) p90", "Top-5 neighbor shock"))
    local o = cond(oy[`i'] == 1, "Log enrollment", cond(oy[`i'] == 2, "Entrant PSU", "Cutoff"))
    if oy[`i'] != 1 local t ""
    file write T "`t' & `o' & " %5.3f (pTWFE[`i']) " & " %5.3f (pCS[`i']) " \\" _n
    if oy[`i'] == 3 & ord[`i'] < 3 file write T "\addlinespace" _n
}
file write T "\bottomrule" _n "\end{tabular}" _n
file close T
erase "$vs_out/tables/_pretrends.dta"

di as result "Design III event studies written."
