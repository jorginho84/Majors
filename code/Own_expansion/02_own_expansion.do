/**********************************************************************
* 02_own_expansion.do
*
* Design II (new, issue #3) — what happens to a program's own enrollment
* and entering-cohort composition when it suddenly expands its seats.
*
* Treatment: p's own vacancy shock, Design III definition (shock_main:
*   top-20% dlogV among positive changes, sudden, dated 2010-2016).
*   g_p = first shock year; Post_pt = 1{t >= g_p} (absorbing).
*   Sensitivity: p75 and p90 thresholds (shock_p75, shock_p90).
*
* Models:
*   (1) TWFE   y_pt = b Post_pt + mu_p + a_t + e
*   (2) TWFE   y_pt = b Post_pt + mu_p + a_{f(p),t} + g_{r(p),t} + e
*   (3) Event study, dynamic TWFE with (2)'s FE, and Callaway-Sant'Anna
*       (never treated; not yet treated), balanced panel.
*   SE clustered by program.
*
* Samples: incumbent programs (est_sample). Main sample = selective
*   programs, top 20% of pre-period (2007-2009) entrant PSU; all programs
*   for comparison.
*
* Outcomes: vacancies (mechanical), first-year enrollment (level, log),
*   composition of entrants (01_build_composition.do).
*
* Inframarginal outcome: not available (issue #3, blocking item).
*
* Output: output/own_expansion/{figures,tables}/oe_*
**********************************************************************/

do "code/config.do"
do "code/Own_expansion/00_helpers.do"

global oe_out "$output/own_expansion"
cap mkdir "$oe_out"
cap mkdir "$oe_out/tables"
cap mkdir "$oe_out/figures"


/**********************************************************************
* 1. Panel
**********************************************************************/

use "$processed/vs_panel_exposure.dta", clear
merge 1:1 code_h ao_proceso using "$processed/oe_composition_program_year.dta", ///
    keep(master match) nogen
xtset pid ao_proceso

gen double dV = V_dem - L.V_dem
label var dV "Change in regular vacancies"

* shock thresholds, as in 03_build_shocks_exposure.do (pooled positive changes)
foreach p in 75 80 90 {
    _pctile dlogV if dlogV > 0 & !missing(dlogV) & entrant_2012 != 1 ///
        & inrange(ao_proceso, 2008, 2016), p(`p')
    local thr`p' = r(r1)
    di as text "Threshold p`p' of positive dlogV: " as result %6.3f `thr`p''
}

keep if est_sample

* selective: top 20% of pre-period entrant PSU across incumbent programs
preserve
bys pid: keep if _n == 1
_pctile psu_first_pre, p(80)
local sel_cut = r(r1)
restore
gen byte selective = psu_first_pre >= `sel_cut'
label var selective "Top 20% of 2007-2009 entrant PSU"
di as text "Selective cutoff (2007-2009 entrant PSU): " as result %6.1f `sel_cut'

foreach t in main p75 p90 {
    bys pid: egen int g_`t' = min(cond(shock_`t' == 1, ao_proceso, .))
    replace g_`t' = 0 if missing(g_`t')
    gen int rel_`t' = ao_proceso - g_`t' if g_`t' > 0
    gen byte post_`t' = g_`t' > 0 & ao_proceso >= g_`t'
}
label var post_main "Post first own vacancy shock"

egen long fy = group(field ao_proceso)
egen long ry = group(region ao_proceso)
bys pid: gen byte nyrs = _N
gen byte balanced = nyrs == 10

save "$processed/oe_panel.dta", replace


/**********************************************************************
* 2. Distribution of vacancy changes
**********************************************************************/

local l75 = string(`thr75', "%4.2f")
local l80 = string(`thr80', "%4.2f")
local l90 = string(`thr90', "%4.2f")

foreach s in sel all {
    local cond = cond("`s'" == "sel", "& selective", "")
    local stitle = cond("`s'" == "sel", "Selective programs", "All incumbent programs")

    twoway histogram dlogV if dlogV != 0 & inrange(dlogV, -1, 1.5) `cond', ///
        width(0.05) fcolor(navy%60) lcolor(navy) ///
        xline(`thr75', lcolor(gs8) lpattern(shortdash)) ///
        xline(`thr80', lcolor(cranberry) lpattern(dash)) ///
        xline(`thr90', lcolor(dkorange) lpattern(longdash)) ///
        xtitle("{&Delta} log regular vacancies (non-zero changes)") ytitle("Density") ///
        title("`stitle'", size(medium)) ///
        note("Vertical lines: p75 = `l75', p80 (main) = `l80', p90 = `l90' of positive changes, pooled 2008-2016.", ///
             size(vsmall)) ///
        graphregion(color(white)) plotregion(color(white)) name(h1, replace)

    twoway histogram dV if dV != 0 & inrange(dV, -40, 60) `cond', ///
        discrete fcolor(navy%60) lcolor(navy) ///
        xtitle("{&Delta} regular vacancies (seats, non-zero changes)") ytitle("Density") ///
        title("`stitle'", size(medium)) ///
        graphregion(color(white)) plotregion(color(white)) name(h2, replace)

    graph combine h1 h2, rows(1) xsize(10) ysize(4) graphregion(color(white))
    graph export "$oe_out/figures/oe_dV_hist_`s'.pdf", replace
}

* table: thresholds and shocks
file open T using "$oe_out/tables/oe_thresholds.tex", write replace
file write T "\begin{tabular}{lcccccc}" _n "\toprule" _n
file write T " & & & \multicolumn{2}{c}{Shocks, 2010--2016} & \multicolumn{2}{c}{Programs ever treated} \\" _n
file write T "\cmidrule(lr){4-5}\cmidrule(lr){6-7}" _n
file write T "Definition & \(\Delta\log V\) threshold & Increase & All & Selective & All & Selective \\" _n "\midrule" _n
foreach t in p75 main p90 {
    local p = cond("`t'" == "main", 80, real(substr("`t'", 2, 2)))
    local lab = cond("`t'" == "main", "Top 20\% (main)", cond("`t'" == "p75", "Top 25\%", "Top 10\%"))
    quietly count if shock_`t' == 1
    local n1 = r(N)
    quietly count if shock_`t' == 1 & selective
    local n2 = r(N)
    quietly count if g_`t' > 0 & ao_proceso == 2016
    local n3 = r(N)
    quietly count if g_`t' > 0 & ao_proceso == 2016 & selective
    local n4 = r(N)
    file write T "`lab' & " %5.3f (`thr`p'') " & +" %3.0f (100 * (exp(`thr`p'') - 1)) "\% & " ///
        %4.0f (`n1') " & " %4.0f (`n2') " & " %4.0f (`n3') " & " %4.0f (`n4') " \\" _n
}
quietly count if ao_proceso == 2016
local np1 = r(N)
quietly count if ao_proceso == 2016 & selective
local np2 = r(N)
file write T "\midrule" _n "Programs in sample & & & & & " %4.0f (`np1') " & " %4.0f (`np2') " \\" _n
file write T "\bottomrule" _n "\end{tabular}" _n
file close T

di as text _n "Share of program-years with no change / increase (selective)"
gen byte chg = sign(dV) if !missing(dV)
tab chg if selective
tab chg


/**********************************************************************
* 3. TWFE and event studies
**********************************************************************/

local yvars V_dem N_first lnN c_psu_mean c_psu_last c_psu_sd c_nem_mean ///
    c_female c_priv c_mun c_priv_last
label var V_dem "Regular vacancies"
foreach y of local yvars {
    local lab_`y' : variable label `y'
}

tempname P
postfile `P' str4 sample str12 outcome str6 spec double b se p N ymean ///
    using "$oe_out/tables/_oe_results.dta", replace

foreach s in sel all {
    local cond = cond("`s'" == "sel", "if selective", "")
    foreach y of local yvars {
        quietly summarize `y' if post_main == 0 & g_main > 0 `=cond("`s'" == "sel", "& selective", "")'
        local ym = r(mean)

        quietly reghdfe `y' post_main `cond', absorb(pid ao_proceso) cluster(pid)
        post `P' ("`s'") ("`y'") ("fe1") (_b[post_main]) (_se[post_main]) ///
            (2 * ttail(e(df_r), abs(_b[post_main] / _se[post_main]))) (e(N)) (`ym')

        quietly reghdfe `y' post_main `cond', absorb(pid fy ry) cluster(pid)
        post `P' ("`s'") ("`y'") ("fe2") (_b[post_main]) (_se[post_main]) ///
            (2 * ttail(e(df_r), abs(_b[post_main] / _se[post_main]))) (e(N)) (`ym')
    }
}

* sensitivity to the shock threshold, selective sample, full FE
foreach t in p75 p90 {
    foreach y in V_dem N_first lnN c_psu_mean c_psu_last c_priv {
        quietly reghdfe `y' post_`t' if selective, absorb(pid fy ry) cluster(pid)
        post `P' ("sel") ("`y'") ("`t'") (_b[post_`t']) (_se[post_`t']) ///
            (2 * ttail(e(df_r), abs(_b[post_`t'] / _se[post_`t']))) (e(N)) (.)
    }
}

* event studies, selective sample (CS ATTs stored for the tables)
preserve
keep if selective
foreach y in V_dem N_first lnN c_psu_mean c_psu_last c_priv c_nem_mean {
    local ylab : variable label `y'
    oe_es `y', g(g_main) rel(rel_main) absorb(pid fy ry) cluster(pid) ///
        ylab("`ylab'") xlab("Years since first own vacancy shock") ///
        file("$oe_out/figures/oe_es_`y'_sel.pdf")
    post `P' ("sel") ("`y'") ("CSnv") (r(attCSnv)) (r(seCSnv)) ///
        (2 * normal(-abs(r(attCSnv) / r(seCSnv)))) (.) (r(pCSnv))
    post `P' ("sel") ("`y'") ("CSny") (r(attCSny)) (r(seCSny)) ///
        (2 * normal(-abs(r(attCSny) / r(seCSny)))) (.) (r(pCSny))
    post `P' ("sel") ("`y'") ("pTWFE") (.) (.) (r(pTWFE)) (.) (.)
}
restore

* event studies, all programs: enrollment only
foreach y in N_first lnN {
    local ylab : variable label `y'
    oe_es `y', g(g_main) rel(rel_main) absorb(pid fy ry) cluster(pid) ///
        ylab("`ylab'") xlab("Years since first own vacancy shock") ///
        file("$oe_out/figures/oe_es_`y'_all.pdf")
}

postclose `P'


/**********************************************************************
* 4. Tables
**********************************************************************/

use "$oe_out/tables/_oe_results.dta", clear
list sample outcome spec b se p N ymean, clean noobs

capture program drop oe_cell
program define oe_cell, rclass
    * b and se of one (sample, outcome, spec) cell from the results in memory
    args s y sp
    quietly levelsof b if sample == "`s'" & outcome == "`y'" & spec == "`sp'", local(b)
    quietly levelsof se if sample == "`s'" & outcome == "`y'" & spec == "`sp'", local(se)
    quietly levelsof p if sample == "`s'" & outcome == "`y'" & spec == "`sp'", local(p)
    quietly levelsof N if sample == "`s'" & outcome == "`y'" & spec == "`sp'", local(N)
    quietly levelsof ymean if sample == "`s'" & outcome == "`y'" & spec == "`sp'", local(ym)
    return local b "`b'"
    return local se "`se'"
    return local p "`p'"
    return local N "`N'"
    return local ym "`ym'"
end

* (a) enrollment: selective (two FE specs + CS) and all programs (two FE specs)
*     composition: all programs only, two FE specs (issue #5 review)
foreach tab in enroll comp {
    if "`tab'" == "enroll" {
        local rows V_dem N_first lnN
        local cols `""sel fe1" "sel fe2" "sel CSnv" "sel CSny" "all fe1" "all fe2""'
    }
    else {
        local rows c_psu_mean c_psu_sd c_nem_mean c_female c_priv c_mun c_priv_last
        local cols `""all fe1" "all fe2""'
    }
    file open T using "$oe_out/tables/oe_twfe_`tab'.tex", write replace
    if "`tab'" == "enroll" {
        file write T "\begin{tabular}{lcccccc}" _n "\toprule" _n
        file write T " & \multicolumn{4}{c}{Selective programs} & \multicolumn{2}{c}{All programs} \\" _n
        file write T "\cmidrule(lr){2-5}\cmidrule(lr){6-7}" _n
        file write T " & TWFE & TWFE & CS & CS & TWFE & TWFE \\" _n
        file write T " & (1) & (2) & never & not yet & (1) & (2) \\" _n "\midrule" _n
    }
    else {
        file write T "\begin{tabular}{lcc}" _n "\toprule" _n
        file write T " & TWFE (1) & TWFE (2) \\" _n "\midrule" _n
    }
    foreach y of local rows {
        file write T "`lab_`y''"
        foreach c of local cols {
            tokenize `c'
            oe_cell `1' `y' `2'
            if "`r(b)'" == "" | "`r(b)'" == "." {
                file write T " & "
                continue
            }
            local bb = `r(b)'
            oe_stars `r(p)'
            file write T " & " %7.3f (`bb') "`r(stars)'"
        }
        file write T " \\" _n
        foreach c of local cols {
            tokenize `c'
            oe_cell `1' `y' `2'
            if "`r(se)'" == "" | "`r(se)'" == "." {
                file write T " & "
                continue
            }
            file write T " & (" %6.3f (`r(se)') ")"
        }
        file write T " \\" _n
        oe_cell all `y' fe1
        local yma = "`r(ym)'"
        local Na = "`r(N)'"
        if "`tab'" == "enroll" {
            oe_cell sel `y' fe1
            file write T "\quad \textit{Pre-mean treated; N} & \multicolumn{4}{c}{\scriptsize " ///
                %6.2f (`r(ym)') "; " %5.0fc (`r(N)') "} & \multicolumn{2}{c}{\scriptsize " ///
                %6.2f (`yma') "; " %5.0fc (`Na') "} \\" _n "\addlinespace" _n
        }
        else {
            file write T "\quad \textit{Pre-mean treated; N} & \multicolumn{2}{c}{\scriptsize " ///
                %6.2f (`yma') "; " %5.0fc (`Na') "} \\" _n "\addlinespace" _n
        }
    }
    file write T "\bottomrule" _n "\end{tabular}" _n
    file close T
}

* (b) sensitivity to the shock threshold, selective, full FE
file open T using "$oe_out/tables/oe_threshold_sens.tex", write replace
file write T "\begin{tabular}{lccc}" _n "\toprule" _n
file write T "Outcome & Top 25\% & Top 20\% (main) & Top 10\% \\" _n "\midrule" _n
foreach y in V_dem N_first lnN c_psu_mean c_priv {
    file write T "`lab_`y''"
    foreach sp in p75 fe2 p90 {
        oe_cell sel `y' `sp'
        local bb = `r(b)'
        oe_stars `r(p)'
        file write T " & " %7.3f (`bb') "`r(stars)'"
    }
    file write T " \\" _n
    foreach sp in p75 fe2 p90 {
        oe_cell sel `y' `sp'
        file write T " & (" %6.3f (`r(se)') ")"
    }
    file write T " \\" _n
}
file write T "\bottomrule" _n "\end{tabular}" _n
file close T

save "$processed/oe_results_design2.dta", replace
erase "$oe_out/tables/_oe_results.dta"

di as result "Design II (own expansion) written."
