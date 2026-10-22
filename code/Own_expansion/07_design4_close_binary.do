/**********************************************************************
* 07_design4_close_binary.do
*
* Design IV, binary version (issues #6, #3): what happens to program k
* when a close competitor suddenly expands its seats?
*
* Treatment
*   close shock: a main vacancy shock (shock_main, top 20% of positive
*     dlogV, sudden; dated 2010-2016) at another program j in k's
*     broad-field x region market with |S_k - S_j| < 50 PSU points
*     (triangular-kernel support). g_k = first such year (g_close, built
*     in Vacancy_shocks/03). Post_kt = 1{t >= g_k}, absorbing.
*   Selective vs selective: k selective incumbent, j selective program
*     (same cutoff on psu_S as in 03), same closeness rule.
*
* Models (as Design II)
*   (1) TWFE  y_kt = b Post_kt + mu_k + l_t + e
*   (2) TWFE  y_kt = b Post_kt + mu_k + l_{f(k),t} + e   (broad field x year)
*   Event study with FE (1) and (2), event time binned at <= -5, >= 4.
*   Callaway-Sant'Anna, never treated and not yet treated, balanced
*   panel, program and year only.
*   SE clustered by market (broad field x region).
*
* Outcomes: first-year enrollment (level, log), composition of entrants
*   (01), graduation of inframarginal applicants (05, Design I outcomes).
*
* Inputs:  oe_panel.dta (02), oe_infra_outcomes.dta (05),
*          vs_panel_exposure.dta, vs_similarity_pairs.dta
* Output:  output/own_expansion/{tables,figures}/d4_*
**********************************************************************/

do "code/config.do"
do "code/Own_expansion/00_helpers.do"

global oe_out "$output/own_expansion"

local enr  N_first lnN
local comp c_psu_mean c_psu_last c_psu_sd c_nem_mean c_female c_priv c_mun
local inf  g8p_f g8u_f g8h_f g10p_f g8p_m g8u_m g8h_m g10p_m

local lab_N_first "First-year enrollment"
local lab_lnN     "Log first-year enrollment"
local lab_g8p_f   "Grad. program 8y, First Cohort (pct.)"
local lab_g8u_f   "Grad. university 8y, First Cohort (pct.)"
local lab_g8h_f   "Grad. HE 8y, First Cohort (pct.)"
local lab_g10p_f  "Grad. program 10y, First Cohort (pct.)"
local lab_g8p_m   "Grad. program 8y, Minimum Cohort (pct.)"
local lab_g8u_m   "Grad. university 8y, Minimum Cohort (pct.)"
local lab_g8h_m   "Grad. HE 8y, Minimum Cohort (pct.)"
local lab_g10p_m  "Grad. program 10y, Minimum Cohort (pct.)"


/**********************************************************************
* 1. Selective close shocks: selective source j within 50 PSU of k
**********************************************************************/

use "$processed/oe_panel.dta", clear
preserve
bys pid: keep if _n == 1
_pctile psu_first_pre, p(80)
local sel_cut = r(r1)
restore

use code_h ao_proceso psu_S seats_main using "$processed/vs_panel_exposure.dta", clear
keep if seats_main > 0 & psu_S >= `sel_cut' & !missing(psu_S)
di as text "Main shocks at selective programs: " as result _N
keep code_h ao_proceso
rename code_h j
tempfile selshocks
save `selshocks'

use k j s_tri_broad using "$processed/vs_similarity_pairs.dta", clear
keep if s_tri_broad > 0
joinby j using `selshocks'
gen byte selclose_shock = 1
collapse (max) selclose_shock, by(k ao_proceso)
rename k code_h
tempfile selclose
save `selclose'


/**********************************************************************
* 2. Panel
**********************************************************************/

use "$processed/oe_panel.dta", clear
merge 1:1 code_h ao_proceso using "$processed/oe_infra_outcomes.dta", ///
    keep(master match) nogen
merge 1:1 code_h ao_proceso using `selclose', keep(master match) nogen
replace selclose_shock = 0 if missing(selclose_shock)

* all incumbents: g_close from Vacancy_shocks/03
gen byte post_all = g_close > 0 & ao_proceso >= g_close
gen int  g_all    = g_close
gen int  rel_all  = rel_close

* selective incumbents, selective sources
bys pid: egen int g_sel = min(cond(selclose_shock == 1 & selective, ao_proceso, .))
replace g_sel = 0 if missing(g_sel)
gen int  rel_sel  = ao_proceso - g_sel if g_sel > 0
gen byte post_sel = g_sel > 0 & ao_proceso >= g_sel

foreach y of local comp {
    local lab_`y' : variable label `y'
}


/**********************************************************************
* 3. Cohorts
**********************************************************************/

file open T using "$oe_out/tables/d4_cohorts.tex", write replace
file write T "\begin{tabular}{lrr}" _n "\toprule" _n
file write T "First treatment year & All incumbents & Selective vs selective \\" _n "\midrule" _n
foreach y in 2010 2011 2012 2013 2014 2015 2016 0 {
    local lab = cond(`y' == 0, "Never treated", "`y'")
    quietly count if ao_proceso == 2016 & g_all == `y'
    local a = r(N)
    quietly count if ao_proceso == 2016 & selective & g_sel == `y'
    local s = r(N)
    file write T "`lab' & " %5.0f (`a') " & " %5.0f (`s') " \\" _n
}
quietly count if ao_proceso == 2016
local na = r(N)
quietly count if ao_proceso == 2016 & selective
local ns = r(N)
file write T "\midrule" _n "Programs & " %5.0f (`na') " & " %5.0f (`ns') " \\" _n
file write T "\bottomrule" _n "\end{tabular}" _n
file close T


/**********************************************************************
* 4. Estimates
**********************************************************************/

tempname P
postfile `P' str4 sample str16 outcome str4 spec double b se p N ymean ///
    using "$oe_out/tables/_d4_results.dta", replace

foreach s in all sel {
    preserve
    if "`s'" == "sel" keep if selective
    local yl `enr' `comp' `inf'
    foreach y of local yl {
        quietly summarize `y' if g_`s' > 0 & ao_proceso < g_`s'
        local ym = r(mean)

        quietly reghdfe `y' post_`s', absorb(pid ao_proceso) cluster(mkt_broad)
        post `P' ("`s'") ("`y'") ("fe1") (_b[post_`s']) (_se[post_`s']) ///
            (2 * ttail(e(df_r), abs(_b[post_`s'] / _se[post_`s']))) (e(N)) (`ym')
        quietly reghdfe `y' post_`s', absorb(pid fy) cluster(mkt_broad)
        post `P' ("`s'") ("`y'") ("fe2") (_b[post_`s']) (_se[post_`s']) ///
            (2 * ttail(e(df_r), abs(_b[post_`s'] / _se[post_`s']))) (e(N)) (`ym')

        local ylab = cond("`lab_`y''" == "", "`y'", "`lab_`y''")
        local xl = cond("`s'" == "all", "Years since first close-competitor shock", ///
            "Years since first selective close-competitor shock")
        oe_es `y', g(g_`s') rel(rel_`s') absorb(pid ao_proceso) cluster(mkt_broad) ///
            ylab("`ylab'") xlab("`xl'") file("$oe_out/figures/d4_es_`s'_`y'_fe1.pdf")
        post `P' ("`s'") ("`y'") ("pfe1") (.) (.) (r(pTWFE)) (.) (.)
        oe_es `y', g(g_`s') rel(rel_`s') absorb(pid fy) cluster(mkt_broad) ///
            ylab("`ylab'") xlab("`xl'") file("$oe_out/figures/d4_es_`s'_`y'_fe2.pdf")
        post `P' ("`s'") ("`y'") ("pfe2") (.) (.) (r(pTWFE)) (.) (.)
        post `P' ("`s'") ("`y'") ("CSnv") (r(attCSnv)) (r(seCSnv)) ///
            (2 * normal(-abs(r(attCSnv) / r(seCSnv)))) (.) (r(pCSnv))
        post `P' ("`s'") ("`y'") ("CSny") (r(attCSny)) (r(seCSny)) ///
            (2 * normal(-abs(r(attCSny) / r(seCSny)))) (.) (r(pCSny))
    }
    restore
}
postclose `P'


/**********************************************************************
* 5. Tables: one per sample x block. Columns: TWFE (1), TWFE (2),
*    CS never treated, CS not yet treated. Below each estimate: SE,
*    and the pre-trend p-value (TWFE joint leads; CS pre-period average).
**********************************************************************/

use "$oe_out/tables/_d4_results.dta", clear
list, clean noobs

capture program drop d4_get
program define d4_get, rclass
    args s y sp v
    quietly summarize `v' if sample == "`s'" & outcome == "`y'" & spec == "`sp'"
    return scalar x = r(mean)
end

foreach s in all sel {
    foreach blk in enr comp inf {
        file open T using "$oe_out/tables/d4_`blk'_`s'.tex", write replace
        file write T "\begin{tabular}{lcccc}" _n "\toprule" _n
        file write T " & TWFE (1) & TWFE (2) & CS & CS \\" _n
        file write T " & program, year & program, field \(\times\) year & never treated & not yet treated \\" _n "\midrule" _n
        foreach y of local `blk' {
            local ylab = cond("`lab_`y''" == "", "`y'", "`lab_`y''")
            file write T "`ylab'"
            foreach sp in fe1 fe2 CSnv CSny {
                d4_get `s' `y' `sp' b
                local bb = r(x)
                d4_get `s' `y' `sp' p
                oe_stars `r(x)'
                file write T " & " %7.3f (`bb') "`r(stars)'"
            }
            file write T " \\" _n
            foreach sp in fe1 fe2 CSnv CSny {
                d4_get `s' `y' `sp' se
                file write T " & (" %6.3f (r(x)) ")"
            }
            file write T " \\" _n "\quad \textit{Pre-trend \(p\)}"
            foreach sp in pfe1 pfe2 {
                d4_get `s' `y' `sp' p
                file write T " & \textit{" %5.3f (r(x)) "}"
            }
            foreach sp in CSnv CSny {
                d4_get `s' `y' `sp' ymean
                file write T " & \textit{" %5.3f (r(x)) "}"
            }
            d4_get `s' `y' fe1 ymean
            local ym = r(x)
            d4_get `s' `y' fe1 N
            file write T " \\" _n "\quad \textit{Pre-mean treated; N} & \multicolumn{4}{c}{\scriptsize " ///
                %7.2f (`ym') "; " %6.0fc (r(x)) "} \\" _n "\addlinespace" _n
        }
        file write T "\bottomrule" _n "\end{tabular}" _n
        file close T
    }
}

save "$processed/d4_results.dta", replace
erase "$oe_out/tables/_d4_results.dta"

di as result "Design IV binary (close-competitor shocks) written."
