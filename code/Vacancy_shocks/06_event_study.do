/**********************************************************************
* 06_event_study.do
*
* Design III — event studies around k's first treatment year g_k.
*
* Treatments (from 03):
*   mkt    first shock at another program in k's broad-field x region market
*   close  first such shock at a program within 50 PSU points of k
*   cos    first shock at one of k's five highest-cosine (PSU bins) programs
*
* Estimators:
*   (A) Dynamic TWFE, never-treated and not-yet-treated units as implicit
*       controls, with field-year and region-year FE and own shocks:
*       y_kt = sum_{l != -1} b_l 1{t - g_k = l} + d own_cumshock
*              + mu_k + a_{f(k),t} + g_{r(k),t} + e
*       Event time binned at <= -5 and >= +4.
*   (B) Callaway & Sant'Anna (csdid), controls = never-treated only.
*   (C) Callaway & Sant'Anna (csdid, notyet), controls = not-yet-treated
*       plus never-treated.
*   (B) and (C) use the balanced panel and cannot absorb field-year or
*   region-year effects.
*
* Outcomes: first-year enrollment (levels) and log first-year enrollment.
*
* Figures: output/vacancy_shocks/figures/vs_es_<outcome>_<treatment>.pdf
* Tables:  output/vacancy_shocks/tables/vs_es_pretrends.tex
*          output/vacancy_shocks/tables/vs_es_cohorts.tex
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

bys pid: gen byte nyrs = _N
gen byte balanced = nyrs == 10


/**********************************************************************
* Cohort sizes
**********************************************************************/

file open T using "$vs_out/tables/vs_es_cohorts.tex", write replace
file write T "\begin{tabular}{lrrr}" _n "\toprule" _n
file write T "First treatment year & Market shock & Close shock & Top-5 cosine shock \\" _n "\midrule" _n
preserve
keep if ao_proceso == 2016
foreach y in 0 2010 2011 2012 2013 2014 2015 2016 {
    local lab = cond(`y' == 0, "Never treated", "`y'")
    file write T "`lab'"
    foreach t in mkt close cos {
        quietly count if g_`t' == `y'
        file write T " & " %6.0fc (r(N))
    }
    file write T " \\" _n
}
file write T "\midrule" _n "Programs"
foreach t in mkt close cos {
    file write T " & " %6.0fc (_N)
}
file write T " \\" _n "\bottomrule" _n "\end{tabular}" _n
file close T
restore


tempname P
postfile `P' str8 treatment str20 outcome str10 est double stat p using ///
    "$vs_out/tables/_pretrends.dta", replace

foreach trt in mkt close cos {

    local tlab = cond("`trt'" == "mkt", "first shock in market", ///
                 cond("`trt'" == "close", "first close-competitor shock", ///
                                          "first shock at a top-5 cosine program"))
    local cl = cond("`trt'" == "cos", "pid", "mkt_broad")

    capture drop ev_*
    gen byte ev_m5 = g_`trt' > 0 & rel_`trt' <= -5
    gen byte ev_m4 = g_`trt' > 0 & rel_`trt' == -4
    gen byte ev_m3 = g_`trt' > 0 & rel_`trt' == -3
    gen byte ev_m2 = g_`trt' > 0 & rel_`trt' == -2
    gen byte ev_p0 = g_`trt' > 0 & rel_`trt' == 0
    gen byte ev_p1 = g_`trt' > 0 & rel_`trt' == 1
    gen byte ev_p2 = g_`trt' > 0 & rel_`trt' == 2
    gen byte ev_p3 = g_`trt' > 0 & rel_`trt' == 3
    gen byte ev_p4 = g_`trt' > 0 & rel_`trt' >= 4 & rel_`trt' < .

foreach y in N_first lnN {

    local ylab = cond("`y'" == "lnN", "Log first-year enrollment", "First-year enrollment")

    /******************************************************************
    * (A) Dynamic TWFE
    ******************************************************************/
    reghdfe `y' ev_* own_cumshock, absorb(pid fy ry) cluster(`cl')
    test ev_m5 ev_m4 ev_m3 ev_m2
    local pA = r(p)
    post `P' ("`trt'") ("`y'") ("TWFE") (r(F)) (r(p))
    estimates store twfe

    preserve
    clear
    set obs 10
    gen int rel = _n - 6
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
    gen str6 est = "TWFE"
    tempfile esA
    save `esA'
    restore

    /******************************************************************
    * (B) CS never-treated, (C) CS not-yet-treated
    ******************************************************************/
    foreach cg in never notyet {
        local opt = cond("`cg'" == "notyet", "notyet", "")
        local tag = cond("`cg'" == "notyet", "CSny", "CSnv")
        capture noisily csdid `y' if balanced & !missing(`y'), ///
            ivar(pid) time(ao_proceso) gvar(g_`trt') `opt'
        if _rc {
            local p`tag' = .
            post `P' ("`trt'") ("`y'") ("`tag'") (.) (.)
            preserve
            clear
            set obs 10
            gen int rel = _n - 6
            gen double b = .
            gen double lo = .
            gen double hi = .
            gen str6 est = "`tag'"
            tempfile es`tag'
            save `es`tag''
            restore
            continue
        }
        estat pretrend
        local p`tag' = r(pchi2)
        post `P' ("`trt'") ("`y'") ("`tag'") (r(chi2)) (r(pchi2))
        estat event, window(-5 4) estore(cs)

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
        gen str6 est = "`tag'"
        tempfile es`tag'
        save `es`tag''
        restore
    }

    preserve
    use `esA', clear
    append using `esCSnv'
    append using `esCSny'
    gen double x = rel + cond(est == "TWFE", -0.18, cond(est == "CSnv", 0, 0.18))
    local pAs  = string(`pA', "%5.3f")
    local pBs  = string(`pCSnv', "%5.3f")
    local pCs  = string(`pCSny', "%5.3f")
    twoway ///
        (rcap lo hi x if est == "TWFE", lcolor(navy)) ///
        (scatter b x if est == "TWFE", mcolor(navy) msymbol(O)) ///
        (rcap lo hi x if est == "CSnv", lcolor(dkorange)) ///
        (scatter b x if est == "CSnv", mcolor(dkorange) msymbol(D)) ///
        (rcap lo hi x if est == "CSny", lcolor(forest_green)) ///
        (scatter b x if est == "CSny", mcolor(forest_green) msymbol(T)), ///
        yline(0, lcolor(gs10)) xline(-0.5, lcolor(cranberry) lpattern(dash)) ///
        xlabel(-5 "{&le}-5" -4(1)3 4 "{&ge}4") ///
        xtitle("Years since `tlab'") ytitle("`ylab'") ///
        legend(order(2 "TWFE" 4 "CS, never treated" 6 "CS, not yet treated") ///
            rows(1) size(small)) ///
        note("Pretrend p-values: TWFE `pAs'; CS never-treated `pBs'; CS not-yet-treated `pCs'." ///
             "TWFE: program, field-year, region-year FE, own shocks; t = -1 omitted. CS: balanced panel.", ///
             size(vsmall)) ///
        graphregion(color(white)) plotregion(color(white))
    graph export "$vs_out/figures/vs_es_`y'_`trt'.pdf", replace
    restore
}
}

postclose `P'

use "$vs_out/tables/_pretrends.dta", clear
list, clean noobs
reshape wide stat p, i(treatment outcome) j(est) string
gen byte ord = cond(treatment == "mkt", 1, cond(treatment == "close", 2, 3))
gen byte oy  = cond(outcome == "N_first", 1, 2)
sort ord oy
file open T using "$vs_out/tables/vs_es_pretrends.tex", write replace
file write T "\begin{tabular}{llccc}" _n "\toprule" _n
file write T " & & & \multicolumn{2}{c}{Callaway--Sant'Anna} \\" _n "\cmidrule(lr){4-5}" _n
file write T "Treatment & Outcome & TWFE & Never treated & Not yet treated \\" _n "\midrule" _n
forvalues i = 1/`=_N' {
    local t = cond(ord[`i'] == 1, "Market shock", cond(ord[`i'] == 2, "Close-competitor shock", "Top-5 cosine shock"))
    local o = cond(oy[`i'] == 1, "Enrollment", "Log enrollment")
    if oy[`i'] != 1 local t ""
    file write T "`t' & `o' & " %5.3f (pTWFE[`i']) " & " %5.3f (pCSnv[`i']) " & " %5.3f (pCSny[`i']) " \\" _n
    if oy[`i'] == 2 & ord[`i'] < 3 file write T "\addlinespace" _n
}
file write T "\bottomrule" _n "\end{tabular}" _n
file close T
erase "$vs_out/tables/_pretrends.dta"

di as result "Design III event studies written."
