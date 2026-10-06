/**********************************************************************
* 29_selectivity_heterogeneity_predetermined.do
*
* Design I heterogeneity by PREDETERMINED program selectivity (issue #4,
* proposal items 1, 2 and 6, approved 2026-10-06).
*
* Selectivity S_p: mean LM PSU of first-year entrants in 2007-2009
* (first three cohorts for programs created later), psu_S from
* Vacancy_shocks/01. Unlike 25_program_selectivity_group.do, it does not
* use 2007-2016 enrollees, whose PSU responds to dZ itself.
*
* Panel and estimator as in 21b (first differences, year FE, SE clustered
* by program), outcome = graduation within 8 years among inframarginal
* applicants. One weight per regression set: avg_N_infra_enter for the
* first stage, reduced form and 2SLS alike, so the first stage reported
* is the first stage of the 2SLS (21b weights its reported first stage by
* avg_N_total_enter instead).
*
* (1) By quartile of S_p and by the deck's fixed PSU cutoffs: FS, RF,
*     2SLS, Kleibergen-Paap F.
*     Joint model: dN x Q_q instrumented by dZ x Q_q, year x Q_q FE, so
*     the four 2SLS coefficients share one VCV: equality test, Holm-
*     adjusted p-values. Continuous version: (dN, dN x S~) by
*     (dZ, dZ x S~), S~ standardized, Sanderson-Windmeijer F.
*     Robustness: university x year FE; wild-cluster bootstrap p-values
*     (boottest) for the RF in each quartile.
* (2) Reduced form reported next to every 2SLS.
* (6) Placebo and dynamics: leads and lags of dZ in the RF and FS,
*     pooled and by quartile.
*
* Inputs:  inframarginal_rank_panel_enrollmentthreshold_allapp_2007_2016_
*          {first,min}_enroll.dta (21b), vs_program_year_2007_2016.dta
* Output:  output/inframarginal/tables/im_sel_*.tex
**********************************************************************/

clear all
set more off
do "code/config.do"

global im_out "$output/inframarginal"
cap mkdir "$im_out"
cap mkdir "$im_out/tables"

* graduation must be observed: 8-year window closes by the last titulados year
use grad_year using "$processed/check_06b_titulados_all.dta", clear
quietly summarize grad_year
local tit_last = r(max)
local last_cohort = `tit_last' - 8
di as result "Titulados through `tit_last': 8-year outcomes valid for cohorts <= `last_cohort'"

capture program drop stars
program define stars
    args p name
    c_local `name' = cond(`p' < 0.01, "\sym{***}", cond(`p' < 0.05, "\sym{**}", cond(`p' < 0.10, "\sym{*}", "")))
end

* predetermined selectivity, one value per harmonized code
use code_h psu_S using "$processed/vs_program_year_2007_2016.dta", clear
bys code_h: keep if _n == 1
rename code_h codigo_carrera_harmonized
tempfile sel
save `sel'


foreach def in first_enroll min_enroll {

    local dlab = cond("`def'" == "first_enroll", "First Cohort", "Minimum Cohort")

    use "$processed/inframarginal_rank_panel_enrollmentthreshold_allapp_2007_2016_`def'.dta", clear
    merge m:1 codigo_carrera_harmonized using `sel', keep(master match) gen(_sel)
    di as text "`dlab': program-years matched to predetermined selectivity"
    tab _sel

    xtset program_id_rank_analysis ao_proceso
    foreach y in grad_enrolled_program_rate_8y grad_uni_rate_8y grad_he_rate_8y {
        * the FD outcome needs both cohorts inside the observed window
        replace D_`y' = . if ao_proceso > `last_cohort'
    }
    gen byte samp = sample_iv == 1 & !missing(psu_S) & ao_proceso <= `last_cohort'

    * program-level quartiles of S (equal number of programs)
    preserve
    keep if samp
    bys program_id_rank_analysis: keep if _n == 1
    xtile Q = psu_S, nq(4)
    keep program_id_rank_analysis Q
    tempfile qq
    save `qq'
    restore
    merge m:1 program_id_rank_analysis using `qq', keep(master match) nogen

    gen byte G = cond(psu_S < 550, 1, cond(psu_S < 600, 2, cond(psu_S < 650, 3, 4))) if !missing(psu_S)
    quietly summarize psu_S if samp
    gen double Sz = (psu_S - r(mean)) / r(sd)
    egen long univ = group(sigla_universidad)

    foreach q in 1 2 3 4 {
        gen double dZq`q' = D_Z_total_cupos * (Q == `q')
        gen double dNq`q' = D_N_total_enter * (Q == `q')
    }
    gen double dZS = D_Z_total_cupos * Sz
    gen double dNS = D_N_total_enter * Sz
    xtset program_id_rank_analysis ao_proceso
    gen double F1dZ = F.D_Z_total_cupos
    gen double L1dZ = L.D_Z_total_cupos

    local W "[aw = avg_N_infra_enter]"

    /******************************************************************
    * (1)+(2) by group: quartiles (Q) and the deck's fixed cutoffs (G)
    ******************************************************************/
    foreach gv in Q G {
        forvalues g = 1/4 {
            local c "samp & `gv' == `g'"
            quietly summarize psu_S if `c'
            local `gv'`g'_psu = r(mean)
            quietly reg D_N_total_enter D_Z_total_cupos i.ao_proceso `W' if `c', ///
                vce(cluster program_id_rank_analysis)
            local `gv'`g'_fs = _b[D_Z_total_cupos]
            local `gv'`g'_fsse = _se[D_Z_total_cupos]
            local `gv'`g'_fsp = 2 * ttail(e(df_r), abs(_b[D_Z_total_cupos] / _se[D_Z_total_cupos]))
            local `gv'`g'_F = (_b[D_Z_total_cupos] / _se[D_Z_total_cupos])^2
            local `gv'`g'_N = e(N)
            quietly distinct program_id_rank_analysis if e(sample)
            local `gv'`g'_np = r(ndistinct)
            foreach y in program uni he {
                local yv = cond("`y'" == "program", "grad_enrolled_program_rate_8y", "grad_`y'_rate_8y")
                quietly reg D_`yv' D_Z_total_cupos i.ao_proceso `W' if `c', ///
                    vce(cluster program_id_rank_analysis)
                local `gv'`g'_rf_`y' = _b[D_Z_total_cupos]
                local `gv'`g'_rfse_`y' = _se[D_Z_total_cupos]
                local `gv'`g'_rfp_`y' = 2 * ttail(e(df_r), abs(_b[D_Z_total_cupos] / _se[D_Z_total_cupos]))
                if "`gv'" == "Q" & "`y'" == "program" {
                    capture boottest D_Z_total_cupos, reps(999) seed(4) nograph
                    local Q`g'_wb = cond(_rc, ., r(p))
                }
                quietly ivregress 2sls D_`yv' i.ao_proceso (D_N_total_enter = D_Z_total_cupos) ///
                    `W' if `c', vce(cluster program_id_rank_analysis)
                local `gv'`g'_iv_`y' = _b[D_N_total_enter]
                local `gv'`g'_ivse_`y' = _se[D_N_total_enter]
                local `gv'`g'_ivp_`y' = 2 * normal(-abs(_b[D_N_total_enter] / _se[D_N_total_enter]))
            }
        }
    }

    * pooled, same weights (reference column)
    quietly reg D_N_total_enter D_Z_total_cupos i.ao_proceso `W' if samp, vce(cluster program_id_rank_analysis)
    local P_fs = _b[D_Z_total_cupos]
    local P_fsse = _se[D_Z_total_cupos]
    local P_F = (_b[D_Z_total_cupos] / _se[D_Z_total_cupos])^2
    local P_N = e(N)
    foreach y in program uni he {
        local yv = cond("`y'" == "program", "grad_enrolled_program_rate_8y", "grad_`y'_rate_8y")
        quietly reg D_`yv' D_Z_total_cupos i.ao_proceso `W' if samp, vce(cluster program_id_rank_analysis)
        local P_rf_`y' = _b[D_Z_total_cupos]
        local P_rfse_`y' = _se[D_Z_total_cupos]
        local P_rfp_`y' = 2 * ttail(e(df_r), abs(_b[D_Z_total_cupos] / _se[D_Z_total_cupos]))
        quietly ivregress 2sls D_`yv' i.ao_proceso (D_N_total_enter = D_Z_total_cupos) `W' if samp, ///
            vce(cluster program_id_rank_analysis)
        local P_iv_`y' = _b[D_N_total_enter]
        local P_ivse_`y' = _se[D_N_total_enter]
        local P_ivp_`y' = 2 * normal(-abs(_b[D_N_total_enter] / _se[D_N_total_enter]))
    }

    /******************************************************************
    * Joint quartile model: shared VCV, equality test, Holm
    ******************************************************************/
    foreach y in program uni he {
        local yv = cond("`y'" == "program", "grad_enrolled_program_rate_8y", "grad_`y'_rate_8y")
        quietly ivreghdfe D_`yv' (dNq1 dNq2 dNq3 dNq4 = dZq1 dZq2 dZq3 dZq4) `W' if samp, ///
            absorb(i.ao_proceso#i.Q) cluster(program_id_rank_analysis)
        quietly test dNq1 = dNq2 = dNq3 = dNq4
        local J_eq_`y' = r(p)
        local J_kp = e(widstat)
        * Holm step-down over the four quartile coefficients
        preserve
        clear
        set obs 4
        gen q = _n
        gen double p = .
        forvalues g = 1/4 {
            replace p = 2 * normal(-abs(_b[dNq`g'] / _se[dNq`g'])) in `g'
        }
        sort p
        gen double ph = min(1, p * (4 - _n + 1))
        replace ph = max(ph, ph[_n - 1]) if _n > 1
        sort q
        forvalues g = 1/4 {
            local J_holm_`y'_`g' = ph[`g']
        }
        restore
        * same test with university x year FE
        quietly ivreghdfe D_`yv' (dNq1 dNq2 dNq3 dNq4 = dZq1 dZq2 dZq3 dZq4) `W' if samp, ///
            absorb(i.ao_proceso#i.Q i.univ#i.ao_proceso) cluster(program_id_rank_analysis)
        forvalues g = 1/4 {
            local U_iv_`y'_`g' = _b[dNq`g']
            local U_ivse_`y'_`g' = _se[dNq`g']
            local U_ivp_`y'_`g' = 2 * normal(-abs(_b[dNq`g'] / _se[dNq`g']))
        }
        quietly test dNq1 = dNq2 = dNq3 = dNq4
        local U_eq_`y' = r(p)
    }

    * continuous interaction, Sanderson-Windmeijer F
    capture drop yr_*
    quietly tab ao_proceso, gen(yr_)
    quietly ivreg2 D_grad_enrolled_program_rate_8y yr_* Sz ///
        (D_N_total_enter dNS = D_Z_total_cupos dZS) `W' if samp, ///
        cluster(program_id_rank_analysis) partial(yr_*) first
    local C_b = _b[D_N_total_enter]
    local C_se = _se[D_N_total_enter]
    local C_p = 2 * normal(-abs(_b[D_N_total_enter] / _se[D_N_total_enter]))
    local C_bS = _b[dNS]
    local C_seS = _se[dNS]
    local C_pS = 2 * normal(-abs(_b[dNS] / _se[dNS]))
    matrix sw = e(first)
    local C_swF1 = sw[rownumb(sw, "SWF"), 1]
    local C_swF2 = sw[rownumb(sw, "SWF"), 2]
    quietly reg D_grad_enrolled_program_rate_8y D_Z_total_cupos dZS Sz i.ao_proceso `W' if samp, ///
        vce(cluster program_id_rank_analysis)
    local C_rfS = _b[dZS]
    local C_rfseS = _se[dZS]
    local C_rfpS = 2 * ttail(e(df_r), abs(_b[dZS] / _se[dZS]))

    /******************************************************************
    * (6) placebo leads and lags of dZ: RF (program graduation) and FS
    ******************************************************************/
    foreach gv in P Q1 Q2 Q3 Q4 {
        local c = cond("`gv'" == "P", "samp", "samp & Q == " + substr("`gv'", 2, 1))
        quietly reg D_grad_enrolled_program_rate_8y F1dZ D_Z_total_cupos L1dZ i.ao_proceso `W' if `c', ///
            vce(cluster program_id_rank_analysis)
        foreach v in F1dZ D_Z_total_cupos L1dZ {
            local D_`gv'_rf_`v' = _b[`v']
            local D_`gv'_rfse_`v' = _se[`v']
            local D_`gv'_rfp_`v' = 2 * ttail(e(df_r), abs(_b[`v'] / _se[`v']))
        }
        local D_`gv'_N = e(N)
        quietly reg D_N_total_enter F1dZ D_Z_total_cupos L1dZ i.ao_proceso `W' if `c', ///
            vce(cluster program_id_rank_analysis)
        foreach v in F1dZ D_Z_total_cupos L1dZ {
            local D_`gv'_fs_`v' = _b[`v']
            local D_`gv'_fsse_`v' = _se[`v']
            local D_`gv'_fsp_`v' = 2 * ttail(e(df_r), abs(_b[`v'] / _se[`v']))
        }
    }

    /******************************************************************
    * Tables
    ******************************************************************/
    local sfx = cond("`def'" == "first_enroll", "first", "min")

    * (a) by quartile and by fixed cutoffs
    foreach gv in Q G {
        file open T using "$im_out/tables/im_sel_`gv'_`sfx'.tex", write replace
        file write T "\begin{tabular}{lccccc}" _n "\toprule" _n
        if "`gv'" == "Q" file write T " & Q1 & Q2 & Q3 & Q4 & Pooled \\" _n
        else file write T " & PSU \(<\)550 & 550--600 & 600--650 & \(\geq\)650 & Pooled \\" _n
        file write T "Mean 2007--09 entrant PSU"
        forvalues g = 1/4 {
            file write T " & " %5.1f (``gv'`g'_psu')
        }
        file write T " & \\" _n "Programs"
        forvalues g = 1/4 {
            file write T " & " %5.0f (``gv'`g'_np')
        }
        file write T " & \\" _n "FD observations"
        forvalues g = 1/4 {
            file write T " & " %6.0fc (``gv'`g'_N')
        }
        file write T " & " %6.0fc (`P_N') " \\" _n "\midrule" _n
        file write T "First stage (\(\Delta N\) on \(\Delta Z\))"
        forvalues g = 1/4 {
            stars ``gv'`g'_fsp' s
            file write T " & " %6.3f (``gv'`g'_fs') "`s'"
        }
        file write T " & " %6.3f (`P_fs') " \\" _n
        forvalues g = 1/4 {
            file write T " & (" %5.3f (``gv'`g'_fsse') ")"
        }
        file write T " & (" %5.3f (`P_fsse') ") \\" _n "F"
        forvalues g = 1/4 {
            file write T " & " %6.1f (``gv'`g'_F')
        }
        file write T " & " %6.1f (`P_F') " \\" _n "\midrule" _n
        foreach y in program uni he {
            local ylab = cond("`y'" == "program", "Program", cond("`y'" == "uni", "Any university", "Any HE"))
            file write T "\multicolumn{6}{l}{\textit{Graduation within 8 years: `ylab'}} \\" _n
            foreach e in rf iv {
                local elab = cond("`e'" == "rf", "\quad Reduced form (\(\times 100\))", "\quad 2SLS (\(\times 100\))")
                file write T "`elab'"
                forvalues g = 1/4 {
                    stars ``gv'`g'_`e'p_`y'' s
                    file write T " & " %7.3f (100 * ``gv'`g'_`e'_`y'') "`s'"
                }
                stars `P_`e'p_`y'' s
                file write T " & " %7.3f (100 * `P_`e'_`y'') "`s'" " \\" _n
                forvalues g = 1/4 {
                    file write T " & (" %6.3f (100 * ``gv'`g'_`e'se_`y'') ")"
                }
                file write T " & (" %6.3f (100 * `P_`e'se_`y'') ") \\" _n
            }
            if "`gv'" == "Q" {
                file write T "\quad Holm-adjusted \(p\) (2SLS)"
                forvalues g = 1/4 {
                    file write T " & " %5.3f (`J_holm_`y'_`g'')
                }
                file write T " & \\" _n "\quad Equality of the four 2SLS (\(p\))" ///
                    " & \multicolumn{4}{c}{" %5.3f (`J_eq_`y'') "} & \\" _n
            }
            file write T "\addlinespace" _n
        }
        if "`gv'" == "Q" {
            file write T "Wild-cluster bootstrap \(p\), RF program"
            forvalues g = 1/4 {
                file write T " & " %5.3f (`Q`g'_wb')
            }
            file write T " & \\" _n
        }
        file write T "\bottomrule" _n "\end{tabular}" _n
        file close T
    }

    * (b) robustness: university x year FE, continuous interaction
    file open T using "$im_out/tables/im_sel_robust_`sfx'.tex", write replace
    file write T "\begin{tabular}{lcccc}" _n "\toprule" _n
    file write T "\multicolumn{5}{l}{\textit{Panel A. Joint quartile 2SLS (\(\times 100\)) with university \(\times\) year FE}} \\" _n
    file write T "Outcome & Q1 & Q2 & Q3 & Q4 \\" _n "\midrule" _n
    foreach y in program uni he {
        local ylab = cond("`y'" == "program", "Program", cond("`y'" == "uni", "Any university", "Any HE"))
        file write T "`ylab'"
        forvalues g = 1/4 {
            stars `U_ivp_`y'_`g'' s
            file write T " & " %7.3f (100 * `U_iv_`y'_`g'') "`s'"
        }
        file write T " \\" _n
        forvalues g = 1/4 {
            file write T " & (" %6.3f (100 * `U_ivse_`y'_`g'') ")"
        }
        file write T " \\" _n "\quad Equality (\(p\)) & \multicolumn{4}{c}{" %5.3f (`U_eq_`y'') "} \\" _n
    }
    file write T "\midrule" _n
    file write T "\multicolumn{5}{l}{\textit{Panel B. Continuous interaction, program graduation (\(\times 100\))}} \\" _n
    stars `C_p' s1
    stars `C_pS' s2
    stars `C_rfpS' s3
    file write T "2SLS: \(\Delta N\) & " %7.3f (100 * `C_b') "`s1'" " & (" %6.3f (100 * `C_se') ") & & \\" _n
    file write T "2SLS: \(\Delta N \times \tilde S\) & " %7.3f (100 * `C_bS') "`s2'" " & (" %6.3f (100 * `C_seS') ") & & \\" _n
    file write T "RF: \(\Delta Z \times \tilde S\) & " %7.3f (100 * `C_rfS') "`s3'" " & (" %6.3f (100 * `C_rfseS') ") & & \\" _n
    file write T "Sanderson--Windmeijer F (\(\Delta N\); \(\Delta N\times\tilde S\)) & " %6.1f (`C_swF1') " & " %6.1f (`C_swF2') " & & \\" _n
    file write T "\bottomrule" _n "\end{tabular}" _n
    file close T

    * (c) placebo leads and lags
    file open T using "$im_out/tables/im_sel_placebo_`sfx'.tex", write replace
    file write T "\begin{tabular}{llccccc}" _n "\toprule" _n
    file write T " & & Pooled & Q1 & Q2 & Q3 & Q4 \\" _n "\midrule" _n
    foreach e in fs rf {
        local elab = cond("`e'" == "fs", "First stage (\(\Delta N\))", "RF, program grad. (\(\times 100\))")
        local m = cond("`e'" == "fs", 1, 100)
        foreach v in F1dZ D_Z_total_cupos L1dZ {
            local vlab = cond("`v'" == "F1dZ", "\(\Delta Z_{t+1}\) (lead)", cond("`v'" == "L1dZ", "\(\Delta Z_{t-1}\) (lag)", "\(\Delta Z_t\)"))
            local lab1 = cond("`v'" == "F1dZ", "`elab'", "")
            file write T "`lab1' & `vlab'"
            foreach gv in P Q1 Q2 Q3 Q4 {
                stars `D_`gv'_`e'p_`v'' s
                file write T " & " %7.3f (`m' * `D_`gv'_`e'_`v'') "`s'"
            }
            file write T " \\" _n " & "
            foreach gv in P Q1 Q2 Q3 Q4 {
                file write T " & (" %6.3f (`m' * `D_`gv'_`e'se_`v'') ")"
            }
            file write T " \\" _n
        }
        file write T "\addlinespace" _n
    }
    file write T "Observations & "
    foreach gv in P Q1 Q2 Q3 Q4 {
        file write T " & " %6.0fc (`D_`gv'_N')
    }
    file write T " \\" _n "\bottomrule" _n "\end{tabular}" _n
    file close T

    di as result "`dlab': selectivity heterogeneity written."
}
