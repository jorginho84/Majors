/**********************************************************************
* 07_binary_pair_exposure.do
*
* Design IV, binary version (issue #6). Program p is treated when its
* exposure to a competitor k in the same market jumps.
*
*   Pair exposure   e_pkt = w(S_p,t-1 , S_k,t-1) * V_kt
*     V_kt   regular vacancies of k (DEMRE)
*     S_.,t-1 mean entrant LM PSU in t-1 (lagged, predetermined for t)
*     w      Gaussian kernel, h = 50 (always > 0, so log e is defined)
*   Market: campus region x broad field (mkt_broad). Competitors k: every
*     other program in p's market, SUA entrants excluded as sources.
*   Shock: dlog e_pkt in the top 20% of positive changes (pooled pairs,
*     2009-2016; 2009 is the first year with S at t-1 and t-2).
*     dlog e = dlog w (similarity) + dlog V_k (seats).
*   Treatment: treat_pt = 1 if any k in p's market has a shock.
*     g_p first treatment year, Post_pt = 1{t >= g_p} (absorbing).
*   Variants: "seats" (dlog V_k only, top 20%) and "sim" (dlog w only).
*
* Models (as Design II), control Own_pt = own_cumshock:
*   (1) y = b Post + d Own + mu_p + l_t
*   (2) y = b Post + d Own + mu_p + l_{f(p)t} + l_{r(p)t}
*   Event study with (2)'s FE; Callaway-Sant'Anna (never / not yet).
*   SE clustered by market.
*
* Inputs:  vs_panel_exposure.dta (03), oe_composition_program_year.dta
* Outputs: output/vacancy_shocks/{tables,figures}/vs_bin_*
**********************************************************************/

do "code/config.do"
do "code/Own_expansion/00_helpers.do"

global vs_out "$output/vacancy_shocks"
cap mkdir "$vs_out/tables"
cap mkdir "$vs_out/figures"

local h = 50


/**********************************************************************
* 1. Program-year inputs
**********************************************************************/

use pid code_h ao_proceso mkt_broad field region V_dem psu_first N_first lnN ///
    own_cumshock est_sample entrant_2012 using "$processed/vs_panel_exposure.dta", clear
xtset pid ao_proceso
gen double S_l1 = L.psu_first
gen double S_l2 = L2.psu_first
gen double V_l1 = L.V_dem
tempfile py
save `py'

* sources k
keep if entrant_2012 != 1 & !missing(mkt_broad)
keep pid ao_proceso mkt_broad V_dem V_l1 S_l1 S_l2
rename (pid V_dem V_l1 S_l1 S_l2) (k Vk Vk_l1 Sk_l1 Sk_l2)
tempfile src
save `src'

* incumbents p
use `py', clear
keep if est_sample == 1 & !missing(mkt_broad)
keep pid ao_proceso mkt_broad S_l1 S_l2
rename (S_l1 S_l2) (Sp_l1 Sp_l2)
joinby mkt_broad ao_proceso using `src'
drop if k == pid


/**********************************************************************
* 2. Pair exposure and shocks
**********************************************************************/

* similarity in t uses PSU of t-1; in t-1 it uses PSU of t-2
gen double lw    = -0.5 * ((Sp_l1 - Sk_l1) / `h')^2
gen double lw_l1 = -0.5 * ((Sp_l2 - Sk_l2) / `h')^2
gen double dlw = lw - lw_l1
gen double dlV = ln(Vk) - ln(Vk_l1)
gen double dle = dlw + dlV
label var dle "dlog pair exposure"

local base "inrange(ao_proceso, 2009, 2016) & !missing(dle)"
foreach v in dle dlV dlw {
    _pctile `v' if `v' > 0 & `base', p(80)
    local thr_`v' = r(r1)
    gen byte sh_`v' = `v' >= `thr_`v'' & `v' > 0 & `base'
    di as text "Top-20% threshold of positive `v': " as result %6.3f `thr_`v''
}

* decomposition of the main shocks: which component dominates
gen byte src_seats = sh_dle & dlV >= dlw
quietly count if sh_dle
local n_pairsh = r(N)
quietly count if sh_dle & src_seats
local sh_seats = r(N) / `n_pairsh'
quietly count if `base'
local n_pairs = r(N)
quietly summarize dlw if sh_dle
local m_dlw = r(mean)
quietly summarize dlV if sh_dle
local m_dlV = r(mean)
di as result "Pair-years: `n_pairs'; shocks: `n_pairsh'; share driven by seats: " %5.3f `sh_seats'

collapse (max) tr_dle = sh_dle tr_dlV = sh_dlV tr_dlw = sh_dlw (count) n_comp = k, by(pid ao_proceso)
tempfile tr
save `tr'


/**********************************************************************
* 3. Program panel with treatment
**********************************************************************/

use `py', clear
keep if est_sample == 1
merge 1:1 pid ao_proceso using `tr', keep(master match) nogen
merge 1:1 code_h ao_proceso using "$processed/oe_composition_program_year.dta", ///
    keepusing(c_psu_mean c_nem_mean c_priv c_mun) keep(master match) nogen
foreach t in dle dlV dlw {
    replace tr_`t' = 0 if missing(tr_`t')
    bys pid: egen int g_`t' = min(cond(tr_`t' == 1, ao_proceso, .))
    replace g_`t' = 0 if missing(g_`t')
    gen int rel_`t' = ao_proceso - g_`t' if g_`t' > 0
    gen byte post_`t' = g_`t' > 0 & ao_proceso >= g_`t'
}
egen long fy = group(field ao_proceso)
egen long ry = group(region ao_proceso)
bys pid: gen byte nyrs = _N
gen byte balanced = nyrs == 10

* share of programs treated: first year and cumulative, by definition
file open T using "$vs_out/tables/vs_bin_treated.tex", write replace
file write T "\begin{tabular}{lccc}" _n "\toprule" _n
file write T "Year & Pair exposure & Seats only & Similarity only \\" _n "\midrule" _n
forvalues t = 2009/2016 {
    file write T "`t'"
    foreach v in dle dlV dlw {
        quietly count if ao_proceso == `t'
        local nt = r(N)
        quietly count if ao_proceso == `t' & post_`v'
        file write T " & " %4.1f (100 * r(N) / `nt') "\%"
    }
    file write T " \\" _n
}
file write T "\midrule" _n "Never treated (programs)"
foreach v in dle dlV dlw {
    quietly count if ao_proceso == 2016
    local n16 = r(N)
    quietly count if ao_proceso == 2016 & g_`v' == 0
    file write T " & " %4.1f (100 * r(N) / `n16') "\%"
}
file write T " \\" _n "Top-20\% threshold (\(\Delta\log\))"
foreach v in dle dlV dlw {
    file write T " & " %5.3f (`thr_`v'')
}
file write T " \\" _n "\bottomrule" _n "\end{tabular}" _n
file close T

file open T using "$vs_out/tables/vs_bin_decomp.tex", write replace
file write T "\begin{tabular}{lr}" _n "\toprule" _n
file write T "Pair-years (incumbent \(p\), competitor \(k\)), 2009--2016 & " %9.0fc (`n_pairs') " \\" _n
file write T "Pair shocks (top 20\% of positive \(\Delta\log e\)) & " %9.0fc (`n_pairsh') " \\" _n
file write T "Share where seats dominate (\(\Delta\log V_k \ge \Delta\log w\)) & " %5.1f (100 * `sh_seats') "\% \\" _n
file write T "Mean \(\Delta\log w\) among shocks & " %6.3f (`m_dlw') " \\" _n
file write T "Mean \(\Delta\log V_k\) among shocks & " %6.3f (`m_dlV') " \\" _n
file write T "\bottomrule" _n "\end{tabular}" _n
file close T

save "$processed/vs_binary_panel.dta", replace


/**********************************************************************
* 4. TWFE and event studies
**********************************************************************/

local ylist N_first lnN c_psu_mean
label var N_first "First-year enrollment"
label var lnN "Log first-year enrollment"
foreach t in dle dlV dlw {
    foreach y of local ylist {
        quietly reghdfe `y' post_`t' own_cumshock, absorb(pid ao_proceso) cluster(mkt_broad)
        oe_stars `=2 * ttail(e(df_r), abs(_b[post_`t'] / _se[post_`t']))'
        local b1_`t'_`y' = string(_b[post_`t'], "%7.3f") + "`r(stars)'"
        local s1_`t'_`y' = "(" + string(_se[post_`t'], "%6.3f") + ")"
        quietly reghdfe `y' post_`t' own_cumshock, absorb(pid fy ry) cluster(mkt_broad)
        oe_stars `=2 * ttail(e(df_r), abs(_b[post_`t'] / _se[post_`t']))'
        local b2_`t'_`y' = string(_b[post_`t'], "%7.3f") + "`r(stars)'"
        local s2_`t'_`y' = "(" + string(_se[post_`t'], "%6.3f") + ")"
        local N_`t'_`y' = e(N)
    }
}

foreach y in N_first c_psu_mean {
    local ylab : variable label `y'
    oe_es `y', g(g_dle) rel(rel_dle) absorb(pid fy ry) cluster(mkt_broad) ///
        controls(own_cumshock) ylab("`ylab'") ///
        xlab("Years since first jump in exposure to a competitor") ///
        file("$vs_out/figures/vs_bin_es_`y'.pdf")
    local csnv_`y' = string(r(attCSnv), "%7.3f")
    local csnvse_`y' = "(" + string(r(seCSnv), "%6.3f") + ")"
    local csny_`y' = string(r(attCSny), "%7.3f")
    local csnyse_`y' = "(" + string(r(seCSny), "%6.3f") + ")"
    local ptw_`y' = string(r(pTWFE), "%5.3f")
}

file open T using "$vs_out/tables/vs_bin_twfe.tex", write replace
file write T "\begin{tabular}{lcccccc}" _n "\toprule" _n
file write T " & \multicolumn{2}{c}{Pair exposure (main)} & \multicolumn{2}{c}{Seats only} & \multicolumn{2}{c}{Similarity only} \\" _n
file write T "\cmidrule(lr){2-3}\cmidrule(lr){4-5}\cmidrule(lr){6-7}" _n
file write T "Outcome & (1) & (2) & (1) & (2) & (1) & (2) \\" _n "\midrule" _n
foreach y of local ylist {
    local ylab : variable label `y'
    file write T "`ylab'"
    foreach t in dle dlV dlw {
        file write T " & `b1_`t'_`y'' & `b2_`t'_`y''"
    }
    file write T " \\" _n
    foreach t in dle dlV dlw {
        file write T " & `s1_`t'_`y'' & `s2_`t'_`y''"
    }
    file write T " \\" _n
}
file write T "\midrule" _n "Observations"
foreach t in dle dlV dlw {
    file write T " & \multicolumn{2}{c}{" %6.0fc (`N_`t'_N_first') "}"
}
file write T " \\" _n "\bottomrule" _n "\end{tabular}" _n
file close T

file open T using "$vs_out/tables/vs_bin_cs.tex", write replace
file write T "\begin{tabular}{lcc}" _n "\toprule" _n
file write T " & First-year enrollment & Mean LM PSU, entrants \\" _n "\midrule" _n
file write T "CS, never treated & `csnv_N_first' & `csnv_c_psu_mean' \\" _n
file write T " & `csnvse_N_first' & `csnvse_c_psu_mean' \\" _n
file write T "CS, not yet treated & `csny_N_first' & `csny_c_psu_mean' \\" _n
file write T " & `csnyse_N_first' & `csnyse_c_psu_mean' \\" _n
file write T "TWFE event study, joint leads \(p\) & `ptw_N_first' & `ptw_c_psu_mean' \\" _n
file write T "\bottomrule" _n "\end{tabular}" _n
file close T

di as result "Design IV binary written."
