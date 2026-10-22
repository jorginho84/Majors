/**********************************************************************
* 03c_selective_dose_es.do
*
* Design IV, selective vs selective (issue #3): event-study counterpart
* of the continuous TWFE in oe_sel_fs_N_first.tex.
*
* The TWFE regresses N_kt on the cumulative exposure cumE_kt / 10. Here
* the dose is fixed at each program's end-of-sample cumulative exposure,
* X_k = cumE_k,2016 / 10 (kernels: Total, Triangular, Gaussian; broad
* market), and interacted with year dummies:
*
*   N_kt = sum_{t != 2009} b_t X_k 1{year = t} + d Own_kt + mu_k
*          + a_{f(k),t} [+ g_{r(k),t}] + e_kt
*
* b_t is the enrollment difference per 10 pp of final exposure in year t
* relative to 2009 (the last year before the first shocks, 2010). The
* leads 2007-2008 test pre-trends; the lags show when the effect appears.
* SE clustered by broad market. Two FE sets, as in the TWFE table.
* Outcomes: first-year enrollment, the composition variables of 01
* (oe_sel_composition.tex is the TWFE counterpart), and the 8-year
* graduation of inframarginal applicants (05; reduced form, TWFE
* counterpart in 03d).
*
* Inputs: oe_selective_panel.dta (03), oe_infra_outcomes.dta (05)
* Output: output/own_expansion/figures/oe_sel_dose_es_<y>_{f,fr}.pdf
**********************************************************************/

do "code/config.do"
do "code/Own_expansion/00_helpers.do"

global oe_out "$output/own_expansion"

use "$processed/oe_selective_panel.dta", clear
merge 1:1 code_h ao_proceso using "$processed/oe_infra_outcomes.dta", ///
    keep(master match) nogen

foreach w in tot tri gau {
    bys pid: egen double X_`w' = max(cond(ao_proceso == 2016, x_`w'_broad, .))
    forvalues t = 2007/2016 {
        if `t' == 2009 continue
        gen double xe_`w'_`t' = X_`w' * (ao_proceso == `t')
    }
}

tempname P
postfile `P' str12 y str4 fe str3 w int year double b lo hi double pre using ///
    "$oe_out/tables/_sel_dose_es.dta", replace

local yvars N_first c_psu_mean c_psu_last c_psu_sd c_priv g8p_f g8p_m g8u_f
foreach y of local yvars {
    local ylab_`y' : variable label `y'
}
local ylab_N_first "First-year enrollment"

foreach y of local yvars {
    foreach fe in b f {
        local abs = cond("`fe'" == "b", "pid ao_proceso", "pid fy_broad")
        foreach w in tot tri gau {
            quietly reghdfe `y' xe_`w'_* if !missing(X_`w'), ///
                absorb(`abs') cluster(mkt_broad)
            quietly test xe_`w'_2007 xe_`w'_2008
            local pre = r(p)
            di as text "`y' `fe' `w': leads joint p = " as result %5.3f `pre' ///
                as text "  N = " e(N) "  clusters = " e(N_clust)
            forvalues t = 2007/2016 {
                if `t' == 2009 {
                    post `P' ("`y'") ("`fe'") ("`w'") (`t') (0) (.) (.) (`pre')
                    continue
                }
                local b  = _b[xe_`w'_`t']
                local se = _se[xe_`w'_`t']
                post `P' ("`y'") ("`fe'") ("`w'") (`t') (`b') (`b' - 1.96 * `se') ///
                    (`b' + 1.96 * `se') (`pre')
            }
        }
    }
}
postclose `P'

use "$oe_out/tables/_sel_dose_es.dta", clear
gen double x = year + cond(w == "tot", -0.2, cond(w == "tri", 0, 0.2))

foreach y of local yvars {
    foreach fe in b f {
        local ttl = cond("`fe'" == "b", "Program and year FE", "Program and field x year FE")
        foreach w in tot tri gau {
            quietly summarize pre if y == "`y'" & fe == "`fe'" & w == "`w'"
            local p_`w' = string(r(mean), "%5.3f")
        }
        local c `"y == "`y'" & fe == "`fe'""'
        twoway (rcap lo hi x if `c' & w == "tot", lcolor(gs8)) ///
               (scatter b x if `c' & w == "tot", mcolor(gs8) msymbol(S)) ///
               (rcap lo hi x if `c' & w == "tri", lcolor(navy)) ///
               (scatter b x if `c' & w == "tri", mcolor(navy) msymbol(O)) ///
               (rcap lo hi x if `c' & w == "gau", lcolor(dkorange)) ///
               (scatter b x if `c' & w == "gau", mcolor(dkorange) msymbol(D)), ///
            yline(0, lcolor(gs10)) xline(2009.5, lcolor(cranberry) lpattern(dash)) ///
            xlabel(2007(1)2016) xtitle("Admission year") ///
            ytitle("`ylab_`y''", size(small)) title("`ttl'", size(medsmall)) ///
            legend(order(2 "Total" 4 "Triangular" 6 "Gaussian") rows(1) size(small)) ///
            note("Coefficient per 10 pp of final exposure. Pre-period joint p (2007-08): Total `p_tot', Triangular `p_tri', Gaussian `p_gau'. 2009 omitted. SE clustered by market.", ///
                 size(vsmall)) graphregion(color(white)) plotregion(color(white))
        graph export "$oe_out/figures/oe_sel_dose_es_`y'_`fe'.pdf", replace
    }
}

erase "$oe_out/tables/_sel_dose_es.dta"
di as result "Selective dose event study written."
