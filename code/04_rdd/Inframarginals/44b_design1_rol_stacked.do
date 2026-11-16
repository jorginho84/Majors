/**********************************************************************
* 44b_design1_rol_stacked.do
*
* Design I (31) with ROL fixed effects, keeping its first difference
* (2026-11-12 meeting with Jorge). Stacked first differences at the
* applicant level: every Design I first difference (p, t-1 -> t) is a
* block g = (p, t) holding the inframarginal applicants of p in t-1
* (post = 0) and in t (post = 1). With a block FE and two periods per
* block, the within-block comparison is the first difference of 31.
*
*   N_pst = pi Z_pst + phi_g + gamma_t(g) x post + [lambda_ROL] + v
*   Y_ipst = beta N_pst + phi_g + gamma_t(g) x post + [lambda_ROL] + e
*                                                    (2SLS, N by Z)
*   unit : inframarginal application (Design I definition, lugar <= T_p
*          first cohort, all applications), one copy per block it
*          belongs to (a program-year enters the blocks ending in t and
*          t+1)
*   y    : graduation within 8 years from the enrolled program (main);
*          any university; any higher education
*   FE   : block g (= the first difference); end year x post (= year FE
*          of 31); (b) adds university x end year x post (= univ x year)
*          ROL: none; top1u (main); set; exact; top1u x block (same ROL
*          within the same block only)
*   Weights: each period of a block weighs avg_N_infra_enter / 2 in
*          total (applicant weight avg_N_infra_enter / (2 N_infra_pst)),
*          so without ROL FE beta equals 31 exactly.
*   SE   : clustered by program (as 31).
*   Coefficients x 100: pp per additional entrant.
*   Each ROL column is paired with the same regression without ROL FE
*   on its non-singleton sample, so the change comes from the FE alone
*   (csv only; the .tex shows the replication and the ROL FE columns).
*
* Outputs (output/inframarginal/):
*   tables/im_d1_rol_stacked.tex   program graduation, both FE
*   tables/im_d1_rol_stacked.csv   every estimate (uni, he if run)
*
* Inputs: $processed/design5_individual_2007_2016.dta (02_build/16)
*         21b panel (first cohort), check_06b_titulados_all.dta
**********************************************************************/

clear all
set more off
do "code/config.do"

global im_out "$output/inframarginal"
cap mkdir "$im_out"
cap mkdir "$im_out/tables"

local P21b "$processed/inframarginal_rank_panel_enrollmentthreshold_allapp_2007_2016_first_enroll.dta"

use grad_year using "$processed/check_06b_titulados_all.dta", clear
quietly summarize grad_year
local last_cohort = r(max) - 8

capture program drop stars
program define stars
    args p name
    c_local `name' = cond(`p' < 0.01, "\sym{***}", cond(`p' < 0.05, "\sym{**}", cond(`p' < 0.10, "\sym{*}", "")))
end

/**********************************************************************
* 1. Blocks: the Design I first differences
**********************************************************************/

use "`P21b'", clear
gen byte samp = sample_iv == 1 & ao_proceso <= `last_cohort'
keep program_id_rank_analysis ao_proceso N_total_enter Z_total_cupos ///
    N_infra_enter avg_N_infra_enter sigla_universidad samp
tempfile pan blocks
save `pan'
keep if samp
keep program_id_rank_analysis ao_proceso avg_N_infra_enter
rename ao_proceso tend
save `blocks'

/**********************************************************************
* 2. Stacked applicant file
**********************************************************************/

use "$processed/design5_individual_2007_2016.dta", clear
keep if _m_panel == 3 & ao_proceso <= `last_cohort'
gen double y_program = 100 * graduates_enrolled_program_8y
gen double y_uni     = 100 * graduates_uni_8y
gen double y_he      = 100 * graduates_he_8y
keep mrun program_id_rank_analysis ao_proceso y_* rol_top1u rol_set rol_exact
merge m:1 program_id_rank_analysis ao_proceso using `pan', ///
    keep(match) nogen keepusing(N_total_enter Z_total_cupos N_infra_enter sigla_universidad)
tempfile base stk
save `base'

forvalues post = 0/1 {
    use `base', clear
    gen int tend = ao_proceso + (1 - `post')
    merge m:1 program_id_rank_analysis tend using `blocks', keep(match) nogen
    gen byte post = `post'
    if `post' == 1 append using `stk'
    save `stk', replace
}

egen long g     = group(program_id_rank_analysis tend)
egen long univ  = group(sigla_universidad)
egen long rolg  = group(rol_top1u g)
gen double w    = avg_N_infra_enter / (2 * N_infra_enter)
quietly count
di as result "Stacked rows: " %12.0fc r(N)
quietly distinct g
di as result "Blocks (= Design I first differences): " %9.0fc r(ndistinct)
compress

/**********************************************************************
* 3. Estimation
**********************************************************************/

local feb1 "g tend#post"
local feb2 "g univ#tend#post"
* ROL FE sets: label -> absorb term
local rl "top1u set exact top1ug"
local ra_top1u  "rol_top1u"
local ra_set    "rol_set"
local ra_exact  "rol_exact"
local ra_top1ug "rolg"

tempname P
tempfile res
postfile `P' str7 y byte fe str7 rol byte withrol double(b se p fs fsse F) ///
    long(N nb) using `res', replace

* outcomes: program graduation only by default (~25 min in Stata SE);
* set ys "program uni he" for the secondary outcomes (~1 h)
local ys "program"
foreach y of local ys {
    forvalues k = 1/2 {
        * Design I replication (no ROL FE, full stacked sample)
        quietly ivreghdfe y_`y' (N_total_enter = Z_total_cupos) [aw = w], ///
            absorb(`feb`k'') cluster(program_id_rank_analysis)
        local b = _b[N_total_enter]
        local se = _se[N_total_enter]
        local F = e(widstat)
        local N = e(N)
        tempvar s
        gen byte `s' = e(sample)
        quietly distinct g if `s'
        local nb = r(ndistinct)
        quietly reghdfe N_total_enter Z_total_cupos [aw = w] if `s', ///
            absorb(`feb`k'') cluster(program_id_rank_analysis)
        post `P' ("`y'") (`k') ("none") (0) (`b') (`se') (2 * normal(-abs(`b' / `se'))) ///
            (_b[Z_total_cupos]) (_se[Z_total_cupos]) (`F') (`N') (`nb')
        drop `s'
        foreach r of local rl {
            * with ROL FE (non-singleton sample), then without on that sample
            quietly ivreghdfe y_`y' (N_total_enter = Z_total_cupos) [aw = w], ///
                absorb(`feb`k'' `ra_`r'') cluster(program_id_rank_analysis)
            local b = _b[N_total_enter]
            local se = _se[N_total_enter]
            local F = e(widstat)
            local N = e(N)
            gen byte es = e(sample)
            quietly distinct g if es
            local nb = r(ndistinct)
            quietly reghdfe N_total_enter Z_total_cupos [aw = w] if es, ///
                absorb(`feb`k'' `ra_`r'') cluster(program_id_rank_analysis)
            post `P' ("`y'") (`k') ("`r'") (1) (`b') (`se') (2 * normal(-abs(`b' / `se'))) ///
                (_b[Z_total_cupos]) (_se[Z_total_cupos]) (`F') (`N') (`nb')
            quietly ivreghdfe y_`y' (N_total_enter = Z_total_cupos) [aw = w] if es, ///
                absorb(`feb`k'') cluster(program_id_rank_analysis)
            local b = _b[N_total_enter]
            local se = _se[N_total_enter]
            local F = e(widstat)
            local N = e(N)
            quietly reghdfe N_total_enter Z_total_cupos [aw = w] if es, ///
                absorb(`feb`k'') cluster(program_id_rank_analysis)
            post `P' ("`y'") (`k') ("`r'") (0) (`b') (`se') (2 * normal(-abs(`b' / `se'))) ///
                (_b[Z_total_cupos]) (_se[Z_total_cupos]) (`F') (`N') (`nb')
            drop es
        }
    }
}
postclose `P'

use `res', clear
export delimited using "$im_out/tables/im_d1_rol_stacked.csv", replace
format b se fs fsse %8.4f
format F %7.1f
list y fe rol withrol b se p fs F N nb, noobs sepby(y fe) abbrev(8)

/**********************************************************************
* 4. Table: program graduation
**********************************************************************/

keep if y == "program"
gen str9 col = rol + string(withrol)
replace col = "none" if rol == "none"
* deck table: Design I replication + the columns with ROL FE (the
* paired regressions without ROL FE on each sample stay in the csv)
local cols "none top1u1 set1 exact1 top1ug1"
foreach c of local cols {
    forvalues k = 1/2 {
        foreach v in b se p fs fsse F N nb {
            quietly summarize `v' if col == "`c'" & fe == `k'
            local `v'_`c'`k' = r(mean)
        }
    }
}
local nc : word count `cols'

file open T using "$im_out/tables/im_d1_rol_stacked.tex", write replace
file write T "\begin{tabular}{l*{`nc'}{c}}" _n "\toprule" _n
file write T " & Design I & Main ROL & Program-set ROL & Exact ROL & Main ROL \\" _n
file write T " & (replication) & (1st pref. + set of univ.) & (set of programs) & (ordered list) & \(\times\) block \\" _n
file write T "\cmidrule(lr){2-2}\cmidrule(lr){3-6}" _n
file write T " & (1) & (2) & (3) & (4) & (5) \\" _n
file write T "ROL fixed effects & No & Yes & Yes & Yes & Yes \\" _n
file write T "\midrule" _n
forvalues k = 1/2 {
    local pl = cond(`k' == 1, "Panel A. FE: block + year", "Panel B. FE: block + university \(\times\) year")
    file write T "\multicolumn{`=`nc'+1'}{l}{\textit{`pl'}} \\" _n
    file write T "2SLS, graduation from the program (pp per entrant)"
    foreach c of local cols {
        stars `p_`c'`k'' st
        file write T " & " %7.3f (`b_`c'`k'') "`st'"
    }
    file write T " \\" _n
    foreach c of local cols {
        file write T " & (" %5.3f (`se_`c'`k'') ")"
    }
    file write T " \\" _n "First stage"
    foreach c of local cols {
        file write T " & " %6.3f (`fs_`c'`k'')
    }
    file write T " \\" _n "Kleibergen--Paap F"
    foreach c of local cols {
        file write T " & " %6.1f (`F_`c'`k'')
    }
    file write T " \\" _n "Applicant-block rows"
    foreach c of local cols {
        file write T " & " %10.0fc (`N_`c'`k'')
    }
    file write T " \\" _n "Blocks (first differences)"
    foreach c of local cols {
        file write T " & " %6.0fc (`nb_`c'`k'')
    }
    file write T " \\" _n
    if `k' == 1 file write T "\addlinespace" _n
}
file write T "\bottomrule" _n "\end{tabular}" _n
file close T

di as result "44b_design1_rol_stacked.do finished."
