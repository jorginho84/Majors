/**********************************************************************
* 06b_event_study_dose.do
*
* Design III — event studies that keep the treatment dose.
*
* Distributed-lag event study with binned endpoints (Schmidheiny and
* Siegloch 2023) on the yearly exposure flow E_kt (10 pp units):
*
*   y_kt = b_{-5} sum_{s >= t+5} E_ks + sum_{l=-4..-2} b_l E_{k,t-l}
*        + sum_{l=0..3} b_l E_{k,t-l} + b_{+4} sum_{s <= t-4} E_ks
*        + d own_cumshock + mu_k + a_{f(k),t} [+ g_{r(k),t}] + e_kt
*
* E_{k,t+1} is omitted, so b_l is the cumulative effect at event time l
* of 10 pp of exposure received at event time 0, relative to l = -1.
* Leads beyond 2016 are set to zero, as the binary event studies treat
* programs first shocked after 2016 as never treated. Robustness keeps
* t <= 2012, where every interior lead is observed. Internal gap years
* are filled with zero exposure.
*
* Measures (broad field x region market): Total, Gaussian, Gaussian KD,
* Triangular KD. SE clustered by market.
*
* Figures: output/vacancy_shocks/figures/vs_esd_<outcome>_<fe>.pdf
* Table:   output/vacancy_shocks/tables/vs_esd_summary.tex
*
* Input: $processed/vs_panel_exposure.dta
**********************************************************************/

do "code/config.do"

global vs_out "$output/vacancy_shocks"
cap mkdir "$vs_out/tables"
cap mkdir "$vs_out/figures"

local W tot gau gaukd trikd

use "$processed/vs_panel_exposure.dta", clear
keep if est_sample
keep pid ao_proceso N_first lnN own_cumshock mkt_broad field region ///
    E_tot_broad E_gau_broad E_gaukd_broad E_trikd_broad
gen byte orig = 1

xtset pid ao_proceso
tsfill, full
foreach v in mkt_broad field region {
    bys pid (`v'): replace `v' = `v'[1] if missing(`v')
}
replace orig = 0 if missing(orig)
count if orig == 0 & inrange(ao_proceso, 2010, 2016)
di as text "Filled program-years with zero exposure (2010-2016): " as result r(N)
xtset pid ao_proceso

foreach w of local W {
    gen double e = cond(missing(E_`w'_broad), 0, E_`w'_broad / 10)
    bys pid (ao_proceso): gen double C = sum(e)
    bys pid (ao_proceso): gen double S = C[_N]

    gen double `w'_m5 = S - cond(missing(F4.C), S, F4.C)
    gen double `w'_m4 = cond(missing(F4.e), 0, F4.e)
    gen double `w'_m3 = cond(missing(F3.e), 0, F3.e)
    gen double `w'_m2 = cond(missing(F2.e), 0, F2.e)
    gen double `w'_p0 = e
    gen double `w'_p1 = cond(missing(L1.e), 0, L1.e)
    gen double `w'_p2 = cond(missing(L2.e), 0, L2.e)
    gen double `w'_p3 = cond(missing(L3.e), 0, L3.e)
    gen double `w'_p4 = cond(missing(L4.C), 0, L4.C)
    drop e C S
}

keep if orig
egen long fy = group(field ao_proceso)
egen long ry = group(region ao_proceso)

local wlab_tot   "Total"
local wlab_gau   "Gaussian"
local wlab_gaukd "Gaussian KD"
local wlab_trikd "Triangular KD"

capture program drop stars
program define stars
    args p name
    c_local `name' = cond(`p' < 0.01, "\sym{***}", cond(`p' < 0.05, "\sym{**}", cond(`p' < 0.10, "\sym{*}", "")))
end

tempname P
postfile `P' str8 w str8 y str3 fe byte smp int rel double b se using ///
    "$vs_out/tables/_esd.dta", replace

foreach smp in 0 1 {
    local ifs = cond(`smp' == 1, "if ao_proceso <= 2012", "")
    foreach y in N_first lnN {
        foreach fe in f fr {
            local abs = cond("`fe'" == "f", "pid fy", "pid fy ry")
            foreach w of local W {
                reghdfe `y' `w'_m5 `w'_m4 `w'_m3 `w'_m2 `w'_p0 `w'_p1 `w'_p2 `w'_p3 `w'_p4 ///
                    own_cumshock `ifs', absorb(`abs') cluster(mkt_broad)
                test `w'_m5 `w'_m4 `w'_m3 `w'_m2
                local pp = r(p)
                lincom (`w'_p0 + `w'_p1 + `w'_p2 + `w'_p3) / 4
                local ab = r(estimate)
                local as = r(se)
                local ap = r(p)
                local N  = e(N)
                local ss = cond(`smp' == 1, "_s", "")
                local r_`y'_`fe'_`w'`ss'_b  = `ab'
                local r_`y'_`fe'_`w'`ss'_se = `as'
                local r_`y'_`fe'_`w'`ss'_p  = `ap'
                local r_`y'_`fe'_`w'`ss'_pp = `pp'
                local r_`y'_`fe'_`w'`ss'_N  = `N'
                foreach e in m5 m4 m3 m2 p0 p1 p2 p3 p4 {
                    local l = cond(substr("`e'", 1, 1) == "m", -real(substr("`e'", 2, 1)), real(substr("`e'", 2, 1)))
                    post `P' ("`w'") ("`y'") ("`fe'") (`smp') (`l') (_b[`w'_`e']) (_se[`w'_`e'])
                }
                post `P' ("`w'") ("`y'") ("`fe'") (`smp') (-1) (0) (0)
            }
        }
    }
}
postclose `P'


/**********************************************************************
* Figures: Total, Gaussian, Gaussian KD; full sample
**********************************************************************/

use "$vs_out/tables/_esd.dta", clear
keep if smp == 0
gen double lo = b - 1.96 * se
gen double hi = b + 1.96 * se
gen double x = rel + cond(w == "tot", -0.2, cond(w == "gau", 0, 0.2))

foreach y in N_first lnN {
    local ylab = cond("`y'" == "lnN", "Log first-year enrollment", "First-year enrollment")
    foreach fe in f fr {
        local felab = cond("`fe'" == "f", "program and field-year FE", "program, field-year and region-year FE")
        local pt  = string(`r_`y'_`fe'_tot_pp', "%5.3f")
        local pg  = string(`r_`y'_`fe'_gau_pp', "%5.3f")
        local pk  = string(`r_`y'_`fe'_gaukd_pp', "%5.3f")
        twoway ///
            (rcap lo hi x if w == "tot"   & y == "`y'" & fe == "`fe'", lcolor(navy)) ///
            (scatter b x  if w == "tot"   & y == "`y'" & fe == "`fe'", mcolor(navy) msymbol(O)) ///
            (rcap lo hi x if w == "gau"   & y == "`y'" & fe == "`fe'", lcolor(dkorange)) ///
            (scatter b x  if w == "gau"   & y == "`y'" & fe == "`fe'", mcolor(dkorange) msymbol(D)) ///
            (rcap lo hi x if w == "gaukd" & y == "`y'" & fe == "`fe'", lcolor(forest_green)) ///
            (scatter b x  if w == "gaukd" & y == "`y'" & fe == "`fe'", mcolor(forest_green) msymbol(T)), ///
            yline(0, lcolor(gs10)) xline(-0.5, lcolor(cranberry) lpattern(dash)) ///
            xlabel(-5 "{&le}-5" -4(1)3 4 "{&ge}4") ///
            xtitle("Years since exposure") ytitle("`ylab' per 10 pp of exposure") ///
            legend(order(2 "Total" 4 "Gaussian" 6 "Gaussian KD") rows(1) size(small)) ///
            note("Pretrend p-values: Total `pt'; Gaussian `pg'; Gaussian KD `pk'." ///
                 "Distributed-lag event study, binned endpoints, t = -1 omitted; `felab', own shocks.", ///
                 size(vsmall)) ///
            graphregion(color(white)) plotregion(color(white))
        graph export "$vs_out/figures/vs_esd_`y'_`fe'.pdf", replace
    }
}
erase "$vs_out/tables/_esd.dta"


/**********************************************************************
* Summary table: average post effect (l = 0..3) and pretrend p-value
**********************************************************************/

file open T using "$vs_out/tables/vs_esd_summary.tex", write replace
file write T "\begin{tabular}{lcccc}" _n "\toprule" _n
file write T " & \multicolumn{2}{c}{Enrollment} & \multicolumn{2}{c}{Log enrollment} \\" _n
file write T "\cmidrule(lr){2-3}\cmidrule(lr){4-5}" _n
file write T " & (1) & (2) & (3) & (4) \\" _n "\midrule" _n
foreach smp in 0 1 {
    local ss = cond(`smp' == 1, "_s", "")
    local ptitle = cond(`smp' == 0, "A. All years (2007--2016)", "B. Years 2007--2012 (all leads observed)")
    file write T "\multicolumn{5}{l}{\textit{`ptitle'}} \\" _n
    foreach w of local W {
        file write T "`wlab_`w''"
        foreach y in N_first lnN {
            foreach fe in f fr {
                stars `r_`y'_`fe'_`w'`ss'_p' s
                local fmt = cond("`y'" == "lnN", "%6.4f", "%6.3f")
                file write T " & " `fmt' (`r_`y'_`fe'_`w'`ss'_b') "`s'"
            }
        }
        file write T " \\" _n
        foreach y in N_first lnN {
            foreach fe in f fr {
                local fmt = cond("`y'" == "lnN", "%6.4f", "%6.3f")
                file write T " & (" `fmt' (`r_`y'_`fe'_`w'`ss'_se') ")"
            }
        }
        file write T " \\" _n
        foreach y in N_first lnN {
            foreach fe in f fr {
                file write T " & [" %5.3f (`r_`y'_`fe'_`w'`ss'_pp') "]"
            }
        }
        file write T " \\" _n
    }
    file write T "Observations"
    foreach y in N_first lnN {
        foreach fe in f fr {
            file write T " & " %9.0fc (`r_`y'_`fe'_tot`ss'_N')
        }
    }
    file write T " \\" _n
    if `smp' == 0 file write T "\midrule" _n
}
file write T "\midrule" _n
file write T "Field-year FE & Yes & Yes & Yes & Yes \\" _n
file write T "Region-year FE & No & Yes & No & Yes \\" _n
file write T "\bottomrule" _n "\end{tabular}" _n
file close T

di as result "Design III dose event studies written."
