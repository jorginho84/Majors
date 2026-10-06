/**********************************************************************
* 00_helpers.do
*
* Programs shared by the Own_expansion scripts (issue #3).
*
*   oe_stars p        -> local `stars' with the significance stars
*   oe_es             dynamic TWFE + Callaway-Sant'Anna (never / not yet)
*                     event study around a cohort variable, one figure
**********************************************************************/

capture program drop oe_stars
program define oe_stars, rclass
    args p
    local s ""
    if `p' < 0.10 local s "\sym{*}"
    if `p' < 0.05 local s "\sym{**}"
    if `p' < 0.01 local s "\sym{***}"
    return local stars "`s'"
end


/**********************************************************************
* oe_es y, g(cohort var) rel(relative time var) absorb() cluster()
*       controls() ylab() xlab() file() [nocs]
*
* Event time binned at <= -5 and >= +4, t = -1 omitted. CS estimators use
* the balanced panel (variable `balanced' must exist) and no FE beyond
* program and year. Returns r(pTWFE) (joint test of the leads) and
* r(pCSnv) r(pCSny) (test of the CS pre-period average) pretrend p-values
* and r(attCSnv) r(seCSnv) r(attCSny) r(seCSny) the simple ATTs.
**********************************************************************/

capture program drop oe_es
program define oe_es, rclass
    syntax varname, g(varname) rel(varname) absorb(string) cluster(varname) ///
        file(string) [controls(varlist) ylab(string) xlab(string) nocs]

    local y `varlist'
    tempfile esA esCSnv esCSny

    capture drop ev_*
    gen byte ev_m5 = `g' > 0 & `rel' <= -5
    gen byte ev_m4 = `g' > 0 & `rel' == -4
    gen byte ev_m3 = `g' > 0 & `rel' == -3
    gen byte ev_m2 = `g' > 0 & `rel' == -2
    gen byte ev_p0 = `g' > 0 & `rel' == 0
    gen byte ev_p1 = `g' > 0 & `rel' == 1
    gen byte ev_p2 = `g' > 0 & `rel' == 2
    gen byte ev_p3 = `g' > 0 & `rel' == 3
    gen byte ev_p4 = `g' > 0 & `rel' >= 4 & `rel' < .

    quietly reghdfe `y' ev_* `controls', absorb(`absorb') cluster(`cluster')
    quietly test ev_m5 ev_m4 ev_m3 ev_m2
    local pA = r(p)
    estimates store _oe_twfe

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
        estimates restore _oe_twfe
        replace b  = _b[ev_`e'] in `i'
        replace lo = _b[ev_`e'] - 1.96 * _se[ev_`e'] in `i'
        replace hi = _b[ev_`e'] + 1.96 * _se[ev_`e'] in `i'
    }
    gen str6 est = "TWFE"
    save `esA'
    restore

    foreach cg in never notyet {
        local opt = cond("`cg'" == "notyet", "notyet", "")
        local tag = cond("`cg'" == "notyet", "CSny", "CSnv")
        local p`tag' = .
        local att`tag' = .
        local se`tag' = .
        local rc = 1
        if "`cs'" == "" {
            capture noisily csdid `y' if balanced & !missing(`y'), ///
                ivar(pid) time(ao_proceso) gvar(`g') `opt'
            local rc = _rc
        }
        if !`rc' {
            capture estat simple
            if !_rc {
                matrix _bb = r(b)
                matrix _VV = r(V)
                local att`tag' = _bb[1, 1]
                local se`tag'  = sqrt(_VV[1, 1])
            }
            capture estat event, window(-5 4) estore(_oe_cs)
            local rc = _rc
            * pretrend: average of the pre-period event-time effects. The
            * joint test over every pre-period ATT(g,t) (estat pretrend)
            * rejects mechanically when cohorts have one or two treated units.
            if !`rc' {
                estimates restore _oe_cs
                local p`tag' = 2 * normal(-abs(_b[Pre_avg] / _se[Pre_avg]))
            }
        }
        preserve
        clear
        set obs 10
        gen int rel = _n - 6
        gen double b = .
        gen double lo = .
        gen double hi = .
        if !`rc' {
            estimates restore _oe_cs
            local i = 0
            forvalues l = -5/4 {
                local ++i
                local nm = cond(`l' < 0, "Tm" + string(-`l'), "Tp" + string(`l'))
                capture replace b  = _b[`nm'] in `i'
                capture replace lo = _b[`nm'] - 1.96 * _se[`nm'] in `i'
                capture replace hi = _b[`nm'] + 1.96 * _se[`nm'] in `i'
            }
        }
        gen str6 est = "`tag'"
        save `es`tag''
        restore
    }

    preserve
    use `esA', clear
    append using `esCSnv'
    append using `esCSny'
    gen double x = rel + cond(est == "TWFE", -0.18, cond(est == "CSnv", 0, 0.18))
    local pAs = string(`pA', "%5.3f")
    local pBs = string(`pCSnv', "%5.3f")
    local pCs = string(`pCSny', "%5.3f")
    twoway ///
        (rcap lo hi x if est == "TWFE", lcolor(navy)) ///
        (scatter b x if est == "TWFE", mcolor(navy) msymbol(O)) ///
        (rcap lo hi x if est == "CSnv", lcolor(dkorange)) ///
        (scatter b x if est == "CSnv", mcolor(dkorange) msymbol(D)) ///
        (rcap lo hi x if est == "CSny", lcolor(forest_green)) ///
        (scatter b x if est == "CSny", mcolor(forest_green) msymbol(T)), ///
        yline(0, lcolor(gs10)) xline(-0.5, lcolor(cranberry) lpattern(dash)) ///
        xlabel(-5 "{&le}-5" -4(1)3 4 "{&ge}4") ///
        xtitle("`xlab'") ytitle("`ylab'") ///
        legend(order(2 "TWFE" 4 "CS, never treated" 6 "CS, not yet treated") ///
            rows(1) size(small)) ///
        note("Pretrend p-values: TWFE (joint leads) `pAs'; CS pre-period average: never treated `pBs', not yet treated `pCs'.", ///
             size(vsmall)) ///
        graphregion(color(white)) plotregion(color(white))
    graph export "`file'", replace
    restore

    capture drop ev_*
    return scalar pTWFE   = `pA'
    return scalar pCSnv   = `pCSnv'
    return scalar pCSny   = `pCSny'
    return scalar attCSnv = `attCSnv'
    return scalar seCSnv  = `seCSnv'
    return scalar attCSny = `attCSny'
    return scalar seCSny  = `seCSny'
end
