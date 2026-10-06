/**********************************************************************
* 31_design1_main.do
*
* Design I, pooled 2007-2016 (issue #5). One inframarginal definition,
* the deck's "Inframarginal Student Definitions": applicant i is
* inframarginal in program p iff Rank_ipt <= T_p, T_p = enrolled size of
* the first observed cohort (main) or the minimum enrolled cohort over
* 2007-2016 (robustness). T_p is one number per program, so the whole
* panel is estimated at once, with no split by period.
*
*   dN_pt = pi dZ_pt + FE + v
*   dy_pt = beta dN^_pt + FE + e      (2SLS, dN instrumented by dZ)
*
*   y  : graduation from the program within 8 years among inframarginal
*        applicants (main); any university, any HE (secondary)
*   FE : (a) year; (b) year + university x year
*   Weights avg_N_infra_enter in FS, RF and 2SLS alike (as in 29).
*   SE clustered by program. RF and 2SLS reported x 100.
*
* Outputs (output/inframarginal/):
*   tables/im_d1_desc.tex        sample description
*   tables/im_d1_main.tex        FS, RF, 2SLS, both FE
*   tables/im_d1_thresholds.tex  60-100% of First / Minimum cohort
*   tables/im_d1_field.tex       field groups, both FE
*   figures/im_d1_placebo.pdf    lead / contemporaneous / lag of dZ, pooled
*
* Inputs: 21b and 21c panels, program_field_group_mapping.dta (27),
*         check_06b_titulados_all.dta (last titulados year)
**********************************************************************/

clear all
set more off
do "code/config.do"

global im_out "$output/inframarginal"
cap mkdir "$im_out"
cap mkdir "$im_out/tables"
cap mkdir "$im_out/figures"

local P21b "$processed/inframarginal_rank_panel_enrollmentthreshold_allapp_2007_2016"
local P21c "$processed/inframarginal_rank_panel_extended_percentiles_2007_2016"

* 8-year outcomes are observed for cohorts <= last titulados year - 8
use grad_year using "$processed/check_06b_titulados_all.dta", clear
quietly summarize grad_year
local last_cohort = r(max) - 8
di as result "8-year outcomes valid for cohorts <= `last_cohort'"

capture program drop stars
program define stars
    args p name
    c_local `name' = cond(`p' < 0.01, "\sym{***}", cond(`p' < 0.05, "\sym{**}", cond(`p' < 0.10, "\sym{*}", "")))
end

* prepare one panel: sample flag, university id, leads/lags of dZ
capture program drop d1_prep
program define d1_prep
    args file last
    use "`file'", clear
    xtset program_id_rank_analysis ao_proceso
    foreach y in grad_enrolled_program_rate_8y grad_uni_rate_8y grad_he_rate_8y {
        replace D_`y' = . if ao_proceso > `last'
    }
    gen byte samp = sample_iv == 1 & ao_proceso <= `last'
    egen long univ = group(sigla_universidad)
    gen double F1dZ = F.D_Z_total_cupos
    gen double L1dZ = L.D_Z_total_cupos
end

* FS, RF and 2SLS for one outcome, one condition, one FE set
* locals out: <pfx>fs fsse fsp F N np rf rfse rfp iv ivse ivp
capture program drop d1_est
program define d1_est
    args yv cond fe pfx
    local W "[aw = avg_N_infra_enter]"
    quietly reghdfe D_N_total_enter D_Z_total_cupos `W' if `cond', absorb(`fe') cluster(program_id_rank_analysis)
    c_local `pfx'fs   = _b[D_Z_total_cupos]
    c_local `pfx'fsse = _se[D_Z_total_cupos]
    c_local `pfx'fsp  = 2 * ttail(e(df_r), abs(_b[D_Z_total_cupos] / _se[D_Z_total_cupos]))
    quietly reghdfe D_`yv' D_Z_total_cupos `W' if `cond', absorb(`fe') cluster(program_id_rank_analysis)
    c_local `pfx'rf   = _b[D_Z_total_cupos]
    c_local `pfx'rfse = _se[D_Z_total_cupos]
    c_local `pfx'rfp  = 2 * ttail(e(df_r), abs(_b[D_Z_total_cupos] / _se[D_Z_total_cupos]))
    quietly ivreghdfe D_`yv' (D_N_total_enter = D_Z_total_cupos) `W' if `cond', ///
        absorb(`fe') cluster(program_id_rank_analysis)
    c_local `pfx'iv   = _b[D_N_total_enter]
    c_local `pfx'ivse = _se[D_N_total_enter]
    c_local `pfx'ivp  = 2 * normal(-abs(_b[D_N_total_enter] / _se[D_N_total_enter]))
    c_local `pfx'F    = e(widstat)
    c_local `pfx'N    = e(N)
    quietly distinct program_id_rank_analysis if e(sample)
    c_local `pfx'np   = r(ndistinct)
end

local fe1 "ao_proceso"
local fe2 "ao_proceso univ#ao_proceso"
local yprog "grad_enrolled_program_rate_8y"


/**********************************************************************
* 1. Sample description (First Cohort)
**********************************************************************/

d1_prep "`P21b'_first_enroll.dta" `last_cohort'
quietly count
local d_py = r(N)
quietly distinct program_id_rank_analysis
local d_np = r(ndistinct)
quietly distinct sigla_universidad
local d_nu = r(ndistinct)
quietly count if samp & !missing(D_`yprog')
local d_fd = r(N)
foreach v in N_total_enter N_infra_enter Z_total_cupos grad_enrolled_program_rate_8y grad_uni_rate_8y {
    quietly summarize `v' if ao_proceso <= `last_cohort'
    local m_`v' = r(mean)
    local s_`v' = r(sd)
}
quietly summarize D_Z_total_cupos if samp
local s_dZ = r(sd)
quietly summarize D_N_total_enter if samp
local s_dN = r(sd)
quietly summarize N_infra_enter if ao_proceso <= `last_cohort'
local tot_infra = r(sum)

file open T using "$im_out/tables/im_d1_desc.tex", write replace
file write T "\begin{tabular}{lrr}" _n "\toprule" _n " & Mean & SD \\" _n "\midrule" _n
file write T "Entering cohort, \(N_{pt}\) & " %6.1f (`m_N_total_enter') " & " %6.1f (`s_N_total_enter') " \\" _n
file write T "Vacancies, \(Z_{pt}\) & " %6.1f (`m_Z_total_cupos') " & " %6.1f (`s_Z_total_cupos') " \\" _n
file write T "Inframarginal applicants per program-year & " %6.1f (`m_N_infra_enter') " & " %6.1f (`s_N_infra_enter') " \\" _n
file write T "\(\Delta Z_{pt}\) & & " %6.1f (`s_dZ') " \\" _n
file write T "\(\Delta N_{pt}\) & & " %6.1f (`s_dN') " \\" _n
file write T "Graduation from the program, 8y (\%) & " %6.1f (100 * `m_grad_enrolled_program_rate_8y') " & " ///
    %6.1f (100 * `s_grad_enrolled_program_rate_8y') " \\" _n
file write T "Graduation from any university, 8y (\%) & " %6.1f (100 * `m_grad_uni_rate_8y') " & " ///
    %6.1f (100 * `s_grad_uni_rate_8y') " \\" _n
file write T "\midrule" _n
file write T "Universities & \multicolumn{2}{r}{" %6.0fc (`d_nu') "} \\" _n
file write T "Programs & \multicolumn{2}{r}{" %6.0fc (`d_np') "} \\" _n
file write T "Program-years, 2007--`last_cohort' & \multicolumn{2}{r}{" %6.0fc (`d_py') "} \\" _n
file write T "Inframarginal applicants & \multicolumn{2}{r}{" %9.0fc (`tot_infra') "} \\" _n
file write T "First-difference observations & \multicolumn{2}{r}{" %6.0fc (`d_fd') "} \\" _n
file write T "\bottomrule" _n "\end{tabular}" _n
file close T


/**********************************************************************
* 2. Main results, both FE, First Cohort (Panel A) and Minimum (Panel B)
**********************************************************************/

foreach k in 1 2 {
    foreach y in program uni he {
        local yv = cond("`y'" == "program", "`yprog'", "grad_`y'_rate_8y")
        d1_est `yv' samp "`fe`k''" A`k'`y'_
    }
    quietly summarize `yprog' if samp [aw = avg_N_infra_enter]
    local ymean = r(mean)
}

* placebo regressions on the main sample (used in section 4)
foreach k in 1 2 {
    foreach e in fs rf {
        local dv = cond("`e'" == "fs", "D_N_total_enter", "D_`yprog'")
        quietly reghdfe `dv' F1dZ D_Z_total_cupos L1dZ [aw = avg_N_infra_enter] if samp, ///
            absorb(`fe`k'') cluster(program_id_rank_analysis)
        foreach v in F1dZ D_Z_total_cupos L1dZ {
            local pl_`e'_`k'_`v'_b  = _b[`v']
            local pl_`e'_`k'_`v'_se = _se[`v']
        }
        local pl_`e'_`k'_N = e(N)
        quietly test F1dZ
        local pl_`e'_`k'_plead = r(p)
    }
}

d1_prep "`P21b'_min_enroll.dta" `last_cohort'
foreach k in 1 2 {
    d1_est `yprog' samp "`fe`k''" B`k'program_
}

file open T using "$im_out/tables/im_d1_main.tex", write replace
file write T "\begin{tabular}{lcc}" _n "\toprule" _n
file write T " & (1) & (2) \\" _n "\midrule" _n
file write T "\multicolumn{3}{l}{\textit{Panel A. First Cohort threshold}} \\" _n
file write T "First stage: \(\Delta N\) on \(\Delta Z\)"
foreach k in 1 2 {
    stars `A`k'program_fsp' s
    file write T " & " %6.3f (`A`k'program_fs') "`s'"
}
file write T " \\" _n
foreach k in 1 2 {
    file write T " & (" %5.3f (`A`k'program_fsse') ")"
}
file write T " \\" _n "Kleibergen--Paap F"
foreach k in 1 2 {
    file write T " & " %6.1f (`A`k'program_F')
}
file write T " \\" _n "\addlinespace" _n
file write T "\multicolumn{3}{l}{Graduation from the program, 8y (\(\times 100\))} \\" _n
foreach e in rf iv {
    local elab = cond("`e'" == "rf", "\quad Reduced form", "\quad \textbf{2SLS}")
    file write T "`elab'"
    foreach k in 1 2 {
        stars `A`k'program_`e'p' s
        file write T " & " %7.3f (100 * `A`k'program_`e'') "`s'"
    }
    file write T " \\" _n
    foreach k in 1 2 {
        file write T " & (" %6.3f (100 * `A`k'program_`e'se') ")"
    }
    file write T " \\" _n
}
file write T "\addlinespace" _n
file write T "\multicolumn{3}{l}{Secondary outcomes, 2SLS (\(\times 100\))} \\" _n
foreach y in uni he {
    local ylab = cond("`y'" == "uni", "\quad Graduation from any university, 8y", "\quad Graduation from any HE, 8y")
    file write T "`ylab'"
    foreach k in 1 2 {
        stars `A`k'`y'_ivp' s
        file write T " & " %7.3f (100 * `A`k'`y'_iv') "`s'"
    }
    file write T " \\" _n
    foreach k in 1 2 {
        file write T " & (" %6.3f (100 * `A`k'`y'_ivse') ")"
    }
    file write T " \\" _n
}
file write T "\addlinespace" _n "FD observations"
foreach k in 1 2 {
    file write T " & " %6.0fc (`A`k'program_N')
}
file write T " \\" _n "Programs"
foreach k in 1 2 {
    file write T " & " %6.0fc (`A`k'program_np')
}
file write T " \\" _n "Mean program graduation, 8y (\%) & \multicolumn{2}{c}{" %5.1f (100 * `ymean') "} \\" _n
file write T "\midrule" _n
file write T "\multicolumn{3}{l}{\textit{Panel B. Minimum Cohort threshold}} \\" _n
file write T "First stage"
foreach k in 1 2 {
    stars `B`k'program_fsp' s
    file write T " & " %6.3f (`B`k'program_fs') "`s'"
}
file write T " \\" _n
foreach k in 1 2 {
    file write T " & (" %5.3f (`B`k'program_fsse') ")"
}
file write T " \\" _n "\textbf{2SLS}, graduation from the program (\(\times 100\))"
foreach k in 1 2 {
    stars `B`k'program_ivp' s
    file write T " & " %7.3f (100 * `B`k'program_iv') "`s'"
}
file write T " \\" _n
foreach k in 1 2 {
    file write T " & (" %6.3f (100 * `B`k'program_ivse') ")"
}
file write T " \\" _n "\midrule" _n
file write T "Year FE & \checkmark & \checkmark \\" _n
file write T "University \(\times\) year FE & & \checkmark \\" _n
file write T "\bottomrule" _n "\end{tabular}" _n
file close T


/**********************************************************************
* 3. Threshold robustness: 100, 90, 80, 70, 60% of the threshold
**********************************************************************/

foreach d in first min {
    foreach pc in 100 90 80 70 60 {
        local sfx = cond(`pc' == 100, "", "`pc'")
        d1_prep "`P21c'_`d'_enroll`sfx'.dta" `last_cohort'
        foreach k in 1 2 {
            d1_est `yprog' samp "`fe`k''" T`d'`pc'`k'_
        }
    }
}

file open T using "$im_out/tables/im_d1_thresholds.tex", write replace
file write T "\begin{tabular}{lcccc}" _n "\toprule" _n
file write T " & \multicolumn{2}{c}{First Cohort} & \multicolumn{2}{c}{Minimum Cohort} \\" _n
file write T "\cmidrule(lr){2-3}\cmidrule(lr){4-5}" _n
file write T "Share of threshold & (1) & (2) & (1) & (2) \\" _n "\midrule" _n
foreach pc in 100 90 80 70 60 {
    file write T "`pc'\%"
    foreach d in first min {
        foreach k in 1 2 {
            stars `T`d'`pc'`k'_ivp' s
            file write T " & " %7.3f (100 * `T`d'`pc'`k'_iv') "`s'"
        }
    }
    file write T " \\" _n
    foreach d in first min {
        foreach k in 1 2 {
            file write T " & (" %6.3f (100 * `T`d'`pc'`k'_ivse') ")"
        }
    }
    file write T " \\" _n
}
file write T "\midrule" _n
file write T "University \(\times\) year FE & & \checkmark & & \checkmark \\" _n
file write T "\bottomrule" _n "\end{tabular}" _n
file close T


/**********************************************************************
* 4. Placebo figure: coefficients on dZ_{t+1}, dZ_t, dZ_{t-1}, pooled
**********************************************************************/

preserve
clear
set obs 12
gen byte e = cond(_n <= 6, 1, 2)
gen byte k = cond(mod(_n - 1, 6) < 3, 1, 2)
gen byte j = mod(_n - 1, 3) + 1
gen double b = .
gen double se = .
forvalues i = 1/12 {
    local ee = cond(e[`i'] == 1, "fs", "rf")
    local kk = k[`i']
    local vv = cond(j[`i'] == 1, "F1dZ", cond(j[`i'] == 2, "D_Z_total_cupos", "L1dZ"))
    local m = cond("`ee'" == "rf", 100, 1)
    replace b  = `m' * `pl_`ee'_`kk'_`vv'_b'  in `i'
    replace se = `m' * `pl_`ee'_`kk'_`vv'_se' in `i'
}
gen double lo = b - 1.96 * se
gen double hi = b + 1.96 * se
gen double x = j + cond(k == 1, -0.08, 0.08)
local xl `"xlabel(1 "Lead {&Delta}Z{sub:t+1}" 2 "{&Delta}Z{sub:t}" 3 "Lag {&Delta}Z{sub:t-1}", noticks) xscale(range(0.6 3.4))"'
local plf1 = string(`pl_fs_1_plead', "%5.3f")
local plf2 = string(`pl_fs_2_plead', "%5.3f")
local plr1 = string(`pl_rf_1_plead', "%5.3f")
local plr2 = string(`pl_rf_2_plead', "%5.3f")
twoway (rcap lo hi x if e == 1 & k == 1, lcolor(navy)) ///
       (scatter b x if e == 1 & k == 1, mcolor(navy) msymbol(O) msize(medlarge)) ///
       (rcap lo hi x if e == 1 & k == 2, lcolor(dkorange)) ///
       (scatter b x if e == 1 & k == 2, mcolor(dkorange) msymbol(D) msize(medlarge)), ///
    yline(0, lcolor(gs11)) `xl' xtitle("") ytitle("{&Delta}N, entrants per seat") ///
    title("First stage", size(medium)) ///
    note("Lead p: year FE `plf1'; + univ.×year FE `plf2'", size(small)) ///
    legend(order(2 "Year FE" 4 "+ University × year FE") rows(1) size(small)) ///
    graphregion(color(white)) plotregion(color(white)) name(g1, replace)
twoway (rcap lo hi x if e == 2 & k == 1, lcolor(navy)) ///
       (scatter b x if e == 2 & k == 1, mcolor(navy) msymbol(O) msize(medlarge)) ///
       (rcap lo hi x if e == 2 & k == 2, lcolor(dkorange)) ///
       (scatter b x if e == 2 & k == 2, mcolor(dkorange) msymbol(D) msize(medlarge)), ///
    yline(0, lcolor(gs11)) `xl' xtitle("") ytitle("Program graduation, pp per seat") ///
    title("Reduced form: graduation from the program, 8y", size(medium)) ///
    note("Lead p: year FE `plr1'; + univ.×year FE `plr2'", size(small)) ///
    legend(order(2 "Year FE" 4 "+ University × year FE") rows(1) size(small)) ///
    graphregion(color(white)) plotregion(color(white)) name(g2, replace)
graph combine g1 g2, rows(1) graphregion(color(white)) xsize(10) ysize(4.5)
graph export "$im_out/figures/im_d1_placebo.pdf", replace
restore
di as result "Placebo sample: FS N = `pl_fs_1_N', RF N = `pl_rf_1_N'"


/**********************************************************************
* 5. Field heterogeneity, both FE (First Cohort)
**********************************************************************/

d1_prep "`P21b'_first_enroll.dta" `last_cohort'
merge m:1 sigla_universidad codigo_carrera_harmonized using ///
    "$processed/program_field_group_mapping.dta", keepusing(field_group) keep(master match) gen(_fg)
tab _fg if samp
local flab1 "Business and Law"
local flab2 "Health"
local flab3 "STEM"
local flab4 "Education and Humanities"
local flab5 "Arts, Agriculture and Other"
forvalues f = 1/5 {
    foreach k in 1 2 {
        d1_est `yprog' "samp & field_group == `f'" "`fe`k''" F`f'`k'_
    }
}

file open T using "$im_out/tables/im_d1_field.tex", write replace
file write T "\begin{tabular}{lcccccc}" _n "\toprule" _n
file write T " & & & \multicolumn{2}{c}{(1) Year FE} & \multicolumn{2}{c}{(2) \(+\) Univ. \(\times\) year FE} \\" _n
file write T "\cmidrule(lr){4-5}\cmidrule(lr){6-7}" _n
file write T "Field & Programs & FD obs. & First stage & 2SLS & First stage & 2SLS \\" _n "\midrule" _n
forvalues f = 1/5 {
    file write T "`flab`f'' & " %5.0f (`F`f'1_np') " & " %6.0fc (`F`f'1_N')
    foreach k in 1 2 {
        stars `F`f'`k'_fsp' s1
        stars `F`f'`k'_ivp' s2
        file write T " & " %6.3f (`F`f'`k'_fs') "`s1'" " & " %7.3f (100 * `F`f'`k'_iv') "`s2'"
    }
    file write T " \\" _n " & & "
    foreach k in 1 2 {
        file write T " & (" %5.3f (`F`f'`k'_fsse') ") & (" %6.3f (100 * `F`f'`k'_ivse') ")"
    }
    file write T " \\" _n
}
file write T "\bottomrule" _n "\end{tabular}" _n
file close T

/**********************************************************************
* 6. Horizon: graduation within 8 vs 10 years, common 2007-2014 sample
*    (28b panel: same inframarginal students observed at both horizons)
**********************************************************************/

file open T using "$im_out/tables/im_d1_horizon.tex", write replace
file write T "\begin{tabular}{llcc}" _n "\toprule" _n
file write T "Threshold & Horizon & (1) & (2) \\" _n "\midrule" _n
foreach d in first min {
    use "$processed/inframarginal_rank_panel_2007_2014_`d'_enroll_grad8y10y.dta", clear
    gen byte samp = sample_iv_common == 1
    gen double avg_N_infra_enter = avg_N_infra_common
    egen long univ = group(sigla_universidad)
    foreach h in 8 10 {
        foreach k in 1 2 {
            d1_est grad_enrolled_program_rate_`h'y samp "`fe`k''" H`d'`h'`k'_
        }
        local dlab = cond(`h' == 8, cond("`d'" == "first", "First Cohort", "Minimum Cohort"), "")
        file write T "`dlab' & `h' years"
        foreach k in 1 2 {
            stars `H`d'`h'`k'_ivp' s
            file write T " & " %7.3f (100 * `H`d'`h'`k'_iv') "`s'"
        }
        file write T " \\" _n " & "
        foreach k in 1 2 {
            file write T " & (" %6.3f (100 * `H`d'`h'`k'_ivse') ")"
        }
        file write T " \\" _n
    }
    file write T "\addlinespace" _n
}
file write T "\midrule" _n "First stage & "
foreach k in 1 2 {
    stars `Hfirst8`k'_fsp' s
    file write T " & " %6.3f (`Hfirst8`k'_fs') "`s'"
}
file write T " \\" _n "FD observations & "
foreach k in 1 2 {
    file write T " & " %6.0fc (`Hfirst8`k'_N')
}
file write T " \\" _n "University \(\times\) year FE & & & \checkmark \\" _n
file write T "\bottomrule" _n "\end{tabular}" _n
file close T

di as result "Design I main tables and placebo figure written."
