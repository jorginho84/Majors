/**********************************************************************
* 33_design1_contdid.do
*
* Design I with the continuous-treatment DiD of Callaway, Goodman-Bacon
* and Sant'Anna (2024) (issue #5). Same panel, outcomes and weights as
* 31_design1_main.do (First Cohort threshold).
*
* Each program-year is a 2x2 comparison of t-1 and t. Dose
* D_pt = dZ_pt (change in vacancies); untreated: programs with dZ = 0.
*   ATT(d)  = E[dY | D=d] - E[dY | D=0]
*             control mean within year (analog of FE (1)) or within
*             university x year (analog of FE (2))
*   ACRT(d) = d ATT(d) / dd, cubic in the dose (B-spline of degree 3,
*             no interior knots, the contdid default); robustness: one
*             interior knot at the weighted median dose
*   ATT^o, ACRT^o: averages over the treated dose distribution
*   per-entrant ratio ACRT^o_RF / ACRT^o_FS vs. the TWFE ratio (2SLS)
* Expansions (dZ > 0) and contractions (dZ < 0, dose |dZ|) separately.
* Doses above 30 seats (about P95 on each side) are dropped.
* Pre-trend: same estimator on dy_{t-1}.
* Inference: bootstrap clustered by program, pointwise and uniform
* (sup-t) 95% bands. Weights avg_N_infra_enter throughout.
*
* Outputs (output/inframarginal/):
*   tables/im_d1_cdid.tex               aggregate parameters
*   figures/im_d1_cdid_{pos,neg}_fe{1,2}.pdf   ATT(d), ACRT(d)
*   figures/im_d1_cdid_dose.pdf          dose distribution
**********************************************************************/

clear all
set more off
do "code/config.do"

global im_out "$output/inframarginal"
cap mkdir "$im_out"
cap mkdir "$im_out/tables"
cap mkdir "$im_out/figures"

local P21b "$processed/inframarginal_rank_panel_enrollmentthreshold_allapp_2007_2016"
local reps 499
global cg_dmax 30

use grad_year using "$processed/check_06b_titulados_all.dta", clear
quietly summarize grad_year
local last_cohort = r(max) - 8

capture program drop stars
program define stars
    args p name
    c_local `name' = cond(`p' < 0.01, "\sym{***}", cond(`p' < 0.05, "\sym{**}", cond(`p' < 0.10, "\sym{*}", "")))
end

* core estimator on the data in memory: dose d >= 0, weight w,
* comparison cell $cg_g, outcomes fs rf rfu pre; knot $cg_knot
capture program drop cg_core
program define cg_core, rclass
    foreach y in fs rf rfu pre {
        tempvar sy sw m0n m0d yt acrt kk acrtk
        quietly {
            gen double `sy' = `y' * w if d == 0 & !missing(`y')
            gen double `sw' = w if d == 0 & !missing(`y')
            bysort $cg_g: egen double `m0n' = total(`sy')
            bysort $cg_g: egen double `m0d' = total(`sw')
            gen double `yt' = `y' - `m0n' / `m0d' if d > 0 & `m0d' > 0 & !missing(`y')

            regress `yt' d d2 d3 [aw = w]
            gen double `acrt' = _b[d] + 2 * _b[d2] * d + 3 * _b[d3] * d2 if !missing(`yt')
            summarize `yt' [aw = w], meanonly
            local v_atto_`y' = r(mean)
            summarize `acrt' [aw = w], meanonly
            local v_acrto_`y' = r(mean)
            if inlist("`y'", "fs", "rf") {
                forvalues k = 1/$cg_dmax {
                    return scalar att_`y'_`k'  = _b[_cons] + _b[d] * `k' + _b[d2] * `k'^2 + _b[d3] * `k'^3
                    return scalar acrt_`y'_`k' = _b[d] + 2 * _b[d2] * `k' + 3 * _b[d3] * `k'^2
                }
            }

            gen double `kk' = max(d - $cg_knot, 0)^3
            regress `yt' d d2 d3 `kk' [aw = w]
            gen double `acrtk' = _b[d] + 2 * _b[d2] * d + 3 * _b[d3] * d2 ///
                + 3 * _b[`kk'] * max(d - $cg_knot, 0)^2 if !missing(`yt')
            summarize `acrtk' [aw = w], meanonly
            local v_acrtk_`y' = r(mean)

            areg `y' d [aw = w] if !missing(`y') & (d == 0 | !missing(`yt')), absorb($cg_g)
            local v_twfe_`y' = _b[d]
        }
    }
    foreach s in atto acrto acrtk twfe {
        foreach y in fs rf rfu pre {
            return scalar `s'_`y' = `v_`s'_`y''
        }
        return scalar r`s'_rf  = `v_`s'_rf'  / `v_`s'_fs'
        return scalar r`s'_rfu = `v_`s'_rfu' / `v_`s'_fs'
    }
    * leave no e(sample): bootstrap must resample all program-years
    ereturn clear
end


/**********************************************************************
* 1. Data
**********************************************************************/

use "`P21b'_first_enroll.dta", clear
xtset program_id_rank_analysis ao_proceso
foreach y in grad_enrolled_program_rate_8y grad_uni_rate_8y {
    replace D_`y' = . if ao_proceso > `last_cohort'
}
gen double pre = 100 * L.D_grad_enrolled_program_rate_8y
xtset, clear
keep if sample_iv == 1 & ao_proceso <= `last_cohort'
egen long univ = group(sigla_universidad)
egen long uy = group(univ ao_proceso)
gen double w   = avg_N_infra_enter
gen double fs  = D_N_total_enter
gen double rf  = 100 * D_grad_enrolled_program_rate_8y
gen double rfu = 100 * D_grad_uni_rate_8y
keep program_id_rank_analysis ao_proceso univ uy w fs rf rfu pre D_Z_total_cupos
tempfile base
save `base'

* dose distribution
preserve
keep if inrange(D_Z_total_cupos, -$cg_dmax, $cg_dmax)
histogram D_Z_total_cupos, discrete frequency fcolor(navy%60) lcolor(navy%80) ///
    xline(0, lcolor(dkorange) lpattern(dash)) ///
    xtitle("{&Delta}Z{sub:pt}: change in vacancies (seats)") ytitle("Program-years") ///
    xlabel(-30(5)30) graphregion(color(white)) plotregion(color(white)) xsize(8) ysize(3.5)
graph export "$im_out/figures/im_d1_cdid_dose.pdf", replace
restore


/**********************************************************************
* 2. Estimation: side (pos / neg) x comparison cell (year / univ x year)
**********************************************************************/

local stats ""
foreach y in fs rf rfu pre {
    foreach s in atto acrto acrtk twfe {
        local stats `stats' `s'_`y'=r(`s'_`y')
    }
}
foreach s in atto acrto acrtk twfe {
    local stats `stats' r`s'_rf=r(r`s'_rf) r`s'_rfu=r(r`s'_rfu)
}
foreach y in fs rf {
    forvalues k = 1/$cg_dmax {
        local stats `stats' att_`y'_`k'=r(att_`y'_`k') acrt_`y'_`k'=r(acrt_`y'_`k')
    }
}

foreach side in pos neg {
    foreach k in 1 2 {
        use `base', clear
        if "`side'" == "pos" gen double d = D_Z_total_cupos if D_Z_total_cupos >= 0
        else                 gen double d = -D_Z_total_cupos if D_Z_total_cupos <= 0
        keep if !missing(d) & d <= $cg_dmax
        gen double d2 = d^2
        gen double d3 = d^3
        global cg_g = cond(`k' == 1, "ao_proceso", "uy")

        _pctile d [aw = w] if d > 0, p(50)
        global cg_knot = r(r1)
        bysort $cg_g: egen byte anyT = max(d > 0)
        bysort $cg_g: egen byte anyC = max(d == 0)
        quietly count if d > 0 & anyC & !missing(rf)
        local n_`side'`k'_T = r(N)
        quietly count if d == 0 & anyT & !missing(rf)
        local n_`side'`k'_C = r(N)
        quietly summarize d [aw = w] if d > 0 & anyC & !missing(rf)
        local n_`side'`k'_dbar = r(mean)
        drop anyT anyC

        di as result _n "=== side `side', cell $cg_g, knot $cg_knot, T = `n_`side'`k'_T', C = `n_`side'`k'_C' ==="
        tempfile bf
        bootstrap `stats', reps(`reps') cluster(program_id_rank_analysis) seed(20261013) ///
            saving(`bf', replace) nodrop nodots: cg_core
        matrix b = e(b)
        matrix se = e(se)
        foreach nm of local stats {
            local s = substr("`nm'", 1, strpos("`nm'", "=") - 1)
            local R_`side'`k'_`s'_b  = _b[`s']
            local R_`side'`k'_`s'_se = _se[`s']
            local R_`side'`k'_`s'_p  = 2 * normal(-abs(_b[`s'] / _se[`s']))
        }

        * uniform (sup-t) critical values for the four curves
        preserve
        use `bf', clear
        foreach c in att_fs acrt_fs att_rf acrt_rf {
            gen double tmax = 0
            forvalues j = 1/$cg_dmax {
                replace tmax = max(tmax, abs(`c'_`j' - `R_`side'`k'_`c'_`j'_b') / `R_`side'`k'_`c'_`j'_se')
            }
            _pctile tmax, p(95)
            local U_`side'`k'_`c' = r(r1)
            drop tmax
        }
        restore
        di as result "uniform crit: att_rf `U_`side'`k'_att_rf', acrt_rf `U_`side'`k'_acrt_rf'"

        * figure: ATT(d) and ACRT(d), first stage and program graduation
        preserve
        clear
        set obs $cg_dmax
        gen int x = _n
        foreach c in att_fs acrt_fs att_rf acrt_rf {
            gen double b_`c' = .
            gen double se_`c' = .
            forvalues j = 1/$cg_dmax {
                quietly replace b_`c'  = `R_`side'`k'_`c'_`j'_b'  in `j'
                quietly replace se_`c' = `R_`side'`k'_`c'_`j'_se' in `j'
            }
            gen double plo_`c' = b_`c' - 1.96 * se_`c'
            gen double phi_`c' = b_`c' + 1.96 * se_`c'
            gen double ulo_`c' = b_`c' - `U_`side'`k'_`c'' * se_`c'
            gen double uhi_`c' = b_`c' + `U_`side'`k'_`c'' * se_`c'
        }
        local xt = cond("`side'" == "pos", "Dose: seats added", "Dose: seats cut")
        local gopt "xtitle(`xt', size(small)) xlabel(0(5)30) graphregion(color(white)) plotregion(color(white))"
        foreach y in fs rf {
            local u = cond("`y'" == "fs", "entrants", "pp of program graduation")
            local ao = string(`R_`side'`k'_acrto_`y'_b', "%6.3f")
            local tw = string(`R_`side'`k'_twfe_`y'_b', "%6.3f")
            twoway (rarea ulo_att_`y' uhi_att_`y' x, color(navy%12) lwidth(none)) ///
                   (rarea plo_att_`y' phi_att_`y' x, color(navy%28) lwidth(none)) ///
                   (line b_att_`y' x, lcolor(navy) lwidth(medthick)), ///
                yline(0, lcolor(gs10)) ytitle("`u'", size(small)) legend(off) ///
                title("ATT(d), `=cond("`y'" == "fs", "first stage", "program graduation")'", size(medsmall)) ///
                `gopt' name(a_`y', replace)
            twoway (rarea ulo_acrt_`y' uhi_acrt_`y' x, color(navy%12) lwidth(none)) ///
                   (rarea plo_acrt_`y' phi_acrt_`y' x, color(navy%28) lwidth(none)) ///
                   (line b_acrt_`y' x, lcolor(navy) lwidth(medthick)), ///
                yline(0, lcolor(gs10)) ///
                yline(`R_`side'`k'_acrto_`y'_b', lcolor(navy) lpattern(dash)) ///
                yline(`R_`side'`k'_twfe_`y'_b', lcolor(dkorange) lpattern(shortdash)) ///
                ytitle("`u' per seat", size(small)) ///
                title("ACRT(d), `=cond("`y'" == "fs", "first stage", "program graduation")'", size(medsmall)) ///
                note("Dashed: ACRT{sup:o} = `ao' (navy), TWFE = `tw' (orange)", size(vsmall)) ///
                legend(order(2 "95% pointwise" 1 "95% uniform") rows(1) size(vsmall)) ///
                `gopt' name(c_`y', replace)
        }
        graph combine a_fs c_fs a_rf c_rf, rows(2) graphregion(color(white)) xsize(10) ysize(6.5)
        graph export "$im_out/figures/im_d1_cdid_`side'_fe`k'.pdf", replace
        restore
    }
}


/**********************************************************************
* 3. Table: aggregate parameters
**********************************************************************/

file open T using "$im_out/tables/im_d1_cdid.tex", write replace
file write T "\begin{tabular}{lcccc}" _n "\toprule" _n
file write T " & \multicolumn{2}{c}{Expansions (\(\Delta Z>0\))} & \multicolumn{2}{c}{Contractions (\(\Delta Z<0\))} \\" _n
file write T "\cmidrule(lr){2-3}\cmidrule(lr){4-5}" _n
file write T "Comparison programs (\(\Delta Z=0\)) & Same year & Same univ.\ \(\times\) year & Same year & Same univ.\ \(\times\) year \\" _n "\midrule" _n

local Lfs "\multicolumn{5}{l}{\textit{Panel A. First stage: \(\Delta N\), entrants}} \\"
local Lrf "\multicolumn{5}{l}{\textit{Panel B. Reduced form: program graduation, 8y (pp)}} \\"
local Lr  "\multicolumn{5}{l}{\textit{Panel C. Per entrant: RF / FS (pp of program graduation)}} \\"
local Lru "\multicolumn{5}{l}{\textit{Panel D. Per entrant: graduation from any university (pp)}} \\"
local Lpre "\multicolumn{5}{l}{\textit{Panel E. Pre-trend: same estimator on \(\Delta y_{t-1}\) (pp)}} \\"

foreach blk in fs rf r ru pre {
    file write T "`L`blk''" _n
    if "`blk'" == "fs" | "`blk'" == "rf" {
        local rows "atto acrto acrtk twfe"
    }
    if "`blk'" == "r" local rows "racrto_rf racrtk_rf ratto_rf rtwfe_rf"
    if "`blk'" == "ru" local rows "racrto_rfu rtwfe_rfu"
    if "`blk'" == "pre" local rows "atto acrto twfe"
    foreach r of local rows {
        if inlist("`blk'", "fs", "rf", "pre") local s "`r'_`blk'"
        else local s "`r'"
        local base = cond("`blk'" == "r" | "`blk'" == "ru", substr("`r'", 2, strpos("`r'", "_") - 2), "`r'")
        if "`base'" == "atto"  local lab "\quad \(ATT^o\)"
        if "`base'" == "acrto" local lab "\quad \(ACRT^o\) (per seat)"
        if "`base'" == "acrtk" local lab "\quad \(ACRT^o\), spline with knot at median"
        if "`base'" == "twfe"  local lab "\quad TWFE slope (per seat)"
        if "`blk'" == "r" | "`blk'" == "ru" {
            if "`base'" == "atto"  local lab "\quad \(ATT^o_{RF}/ATT^o_{FS}\)"
            if "`base'" == "acrto" local lab "\quad \(\mathbf{ACRT^o_{RF}/ACRT^o_{FS}}\)"
            if "`base'" == "acrtk" local lab "\quad \(ACRT^o\) ratio, knot at median"
            if "`base'" == "twfe"  local lab "\quad TWFE ratio (= 2SLS on this sample)"
        }
        local fmt = cond("`blk'" == "fs", "%6.3f", "%7.3f")
        file write T "`lab'"
        foreach c in pos1 pos2 neg1 neg2 {
            stars `R_`c'_`s'_p' st
            file write T " & " `fmt' (`R_`c'_`s'_b') "`st'"
        }
        file write T " \\" _n
        foreach c in pos1 pos2 neg1 neg2 {
            file write T " & (" `fmt' (`R_`c'_`s'_se') ")"
        }
        file write T " \\" _n
    }
    file write T "\addlinespace" _n
}
file write T "\midrule" _n "Treated program-years"
foreach c in pos1 pos2 neg1 neg2 {
    file write T " & " %6.0fc (`n_`c'_T')
}
file write T " \\" _n "Comparison program-years"
foreach c in pos1 pos2 neg1 neg2 {
    file write T " & " %6.0fc (`n_`c'_C')
}
file write T " \\" _n "Mean dose (seats)"
foreach c in pos1 pos2 neg1 neg2 {
    file write T " & " %6.1f (`n_`c'_dbar')
}
file write T " \\" _n "\bottomrule" _n "\end{tabular}" _n
file close T

di as result "Design I continuous DiD: table and figures written."
