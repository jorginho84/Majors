/**********************************************************************
* 40_design5_placebo.do
*
* Design V (issues #8, #10): placebo checks agreed on 2026-10-27.
* Extends 38 (balance on PSU/NEM, Z_t+1 lead) in two directions.
*
*   (A) Balance: x_i = g Z_pt + FE + u, reported in two groups
*       SES proxies (no income variable exists): private-paid school,
*           municipal school, technical-professional track
*           (RAMA_EDUCACIONAL "T*")
*       Achievement and other predetermined: PSU L+M, NEM, BEA (top
*           10% of own school, i.e. relative achievement), female,
*           ROL length
*       plus predicted graduation from all of them (joint test), and
*       panel C: Z_pt and Z_p,t+1 together (the placebo of 38). A-B and
*       C replace 38's im_d5_balance.tex in the deck (one slide).
*
*   (B1) Leads and lags of the instrument, own series:
*        y = b0 Z_pt + bk Z_p,t+k + FE + e,   k = -3..-1, +1..+3,
*        one regression per k (each on the cohorts where Z_p,t+k is
*        observed; Z_total_cupos exists 2007-2016 only). If Z shifts
*        cohort size and nothing else, bk should be ~0 for every k.
*
*   (B2) Distributed lag, t-3..t+3 jointly, with DEMRE Oferta Academica
*        regular vacancies (pva_vacancies_2007_2025, ProgramVA/01c),
*        which cover 2007-2025, so cohorts 2010-2016 keep all seven
*        terms. This series is not Z_total_cupos (regular seats only,
*        ~19 fewer on average, corr 0.96), so B2 complements B1.
*
*   y   : first stage n_pt (N_total_enter) and graduation from the
*         enrolled program within 8 years (x100)
*   FE  : program + year (1); program + year + ROL top1u (2, main)
*   SE  : clustered by program-year
*   Sample: as 37/38 (most preferred inframarginal application in the
*         student's first inframarginal year). Z scaled per 10 seats.
*
* Inputs:  $processed/design5_individual_2007_2016.dta (02_build/16)
*          $processed/inframarginal_rank_panel_enrollmentthreshold_allapp_2007_2016_first_enroll.dta
*          $processed/pva_vacancies_2007_2025.dta (ProgramVA/01c)
*          $psu_raw/A_INSCRITOS_PUNTAJES_PSU_YYYY_PRIV_MRUN.csv
* Outputs: output/inframarginal/tables/im_d5_placebo_balance.tex (A, B)
*          output/inframarginal/tables/im_d5_placebo_tplus1.tex (C)
*          output/inframarginal/tables/im_d5_placebo_leadlag.tex
*          output/inframarginal/figures/im_d5_leadlag_{grad,fs}.pdf
*          output/inframarginal/tables/im_d5_placebo.csv (every estimate)
**********************************************************************/

clear all
set more off
do "code/config.do"

global im_out "$output/inframarginal"
cap mkdir "$im_out/tables"
cap mkdir "$im_out/figures"

use grad_year using "$processed/check_06b_titulados_all.dta", clear
quietly summarize grad_year
local last_cohort = r(max) - 8

capture program drop stars
program define stars
    args p name
    c_local `name' = cond(`p' < 0.01, "\sym{***}", cond(`p' < 0.05, "\sym{**}", cond(`p' < 0.10, "\sym{*}", "")))
end

/**********************************************************************
* 1. Extra SES proxies from Formulario A
**********************************************************************/

tempfile ses
forvalues y = 2007/2016 {
    import delimited "$psu_raw/A_INSCRITOS_PUNTAJES_PSU_`y'_PRIV_MRUN.csv", ///
        delimiter(";") varnames(1) clear encoding(windows-1252) ///
        stringcols(_all)
    rename *, lower
    keep mrun rama_educacional bea
    destring mrun, replace force
    gen int ao_proceso = `y'
    if `y' > 2007 append using `ses'
    save `ses', replace
}
drop if missing(mrun)
duplicates drop mrun ao_proceso, force
gen byte tp  = substr(strtrim(rama_educacional), 1, 1) == "T" ///
    if inlist(substr(strtrim(rama_educacional), 1, 1), "H", "T")
gen byte bea_ = strtrim(bea) == "BEA"
drop rama_educacional bea
rename bea_ bea
save `ses', replace

/**********************************************************************
* 2. Instrument leads and lags
**********************************************************************/

* (B1) own series, 2007-2016
use program_id_rank_analysis ao_proceso Z_total_cupos using ///
    "$processed/inframarginal_rank_panel_enrollmentthreshold_allapp_2007_2016_first_enroll.dta", clear
xtset program_id_rank_analysis ao_proceso
foreach k in 1 2 3 {
    gen double Zm`k' = L`k'.Z_total_cupos / 10
    gen double Zp`k' = F`k'.Z_total_cupos / 10
}
keep program_id_rank_analysis ao_proceso Zm? Zp?
tempfile zll
save `zll'

* (B2) Oferta Academica regular vacancies, 2007-2025
use "$processed/pva_vacancies_2007_2025.dta", clear
xtset code_h ao_proceso
gen double V0 = vac / 10
foreach k in 1 2 3 {
    gen double Vm`k' = L`k'.vac / 10
    gen double Vp`k' = F`k'.vac / 10
}
keep code_h ao_proceso V0 Vm? Vp?
rename code_h codigo_carrera_harmonized
tempfile vll
save `vll'

/**********************************************************************
* 3. Sample (as 37/38)
**********************************************************************/

use "$processed/design5_individual_2007_2016.dta", clear
keep if _m_panel == 3 & ao_proceso <= `last_cohort'
keep if pick_toppref & ao_proceso == first_year_i
duplicates drop mrun, force
merge m:1 mrun ao_proceso using `ses', keep(master match) nogen
merge m:1 program_id_rank_analysis ao_proceso using `zll', keep(master match) nogen
merge m:1 codigo_carrera_harmonized ao_proceso using `vll', keep(master match) nogen
egen long pt       = group(program_id_rank_analysis ao_proceso)
egen long programs = group(program_id_rank_analysis)
gen double y_program = 100 * graduates_enrolled_program_8y
gen double Z10 = Z_total_cupos / 10

local fe1 "programs ao_proceso"
local fe2 "programs ao_proceso rol_top1u"

di as result "Students: " _N
tab ao_proceso
summarize tp bea

tempname P
postfile `P' str10 panel str16 dv str8 term int k byte fe double(b se p) long N ///
    using "$processed/im_d5_placebo_results.dta", replace

/**********************************************************************
* 4. (A) Balance
**********************************************************************/

local xs "psu_lm nem female priv mun tp bea n_apps"
* binary covariates in percent, so coefficients read as pp per ten seats
foreach x in female priv mun tp bea {
    replace `x' = 100 * `x'
}
quietly reg y_program `xs'
predict double yhat if e(sample)

foreach x in `xs' yhat {
    quietly summarize `x'
    local m_`x' = r(mean)
    foreach f in 1 2 {
        quietly reghdfe `x' Z10, absorb(`fe`f'') vce(cluster pt)
        local b_`x'_`f'  = _b[Z10]
        local se_`x'_`f' = _se[Z10]
        local p_`x'_`f'  = 2 * ttail(e(df_r), abs(_b[Z10] / _se[Z10]))
        local N_`x'_`f'  = e(N)
        post `P' ("A") ("`x'") ("Z_t") (0) (`f') (`b_`x'_`f'') (`se_`x'_`f'') (`p_`x'_`f'') (e(N))
        di as result "`x' fe`f': " %8.4f `b_`x'_`f'' " (" %7.4f `se_`x'_`f'' ")  p=" %5.3f `p_`x'_`f''
    }
}

* Panel C of the same table: next year's seats (as 38, panel B), so one
* slide carries balance and the t+1 placebo; t+-k in general is in B1.
foreach dv in N_total_enter y_program {
    foreach f in 1 2 {
        quietly reghdfe `dv' Z10 Zp1, absorb(`fe`f'') vce(cluster pt)
        foreach t in Z10 Zp1 {
            local C_`dv'_`t'_`f'_b  = _b[`t']
            local C_`dv'_`t'_`f'_se = _se[`t']
            local C_`dv'_`t'_`f'_p  = 2 * ttail(e(df_r), abs(_b[`t'] / _se[`t']))
        }
        local C_N_`f' = e(N)
    }
}

local lab_psu_lm "PSU language+math (points)"
local lab_nem    "NEM (points)"
local lab_female "Female (\%)"
local lab_priv   "Private-paid school (\%)"
local lab_mun    "Municipal school (\%)"
local lab_tp     "Technical-professional track (\%)"
local lab_bea    "BEA, top 10\% of own school (\%)"
local lab_n_apps "Applications in the ROL (number)"
local lab_yhat   "Predicted graduation, program, 8y (\%)"

file open T using "$im_out/tables/im_d5_placebo_balance.tex", write replace
file write T "\begin{tabular}{lccc}" _n "\toprule" _n
file write T " & Mean & (1) & (2) \\" _n
file write T " & level & \multicolumn{2}{c}{per 10 seats} \\" _n "\midrule" _n
foreach x in priv mun tp psu_lm nem bea female n_apps yhat {
    if "`x'" == "priv"   file write T "\multicolumn{4}{l}{\textit{Panel A. Socioeconomic proxies}} \\" _n
    if "`x'" == "psu_lm" file write T "\addlinespace" _n "\multicolumn{4}{l}{\textit{Panel B. Achievement and other predetermined}} \\" _n
    if "`x'" == "yhat"   file write T "\addlinespace" _n "\multicolumn{4}{l}{\textit{Joint test: all covariates above}} \\" _n
    file write T "`lab_`x''" " & " %6.2f (`m_`x'')
    foreach f in 1 2 {
        stars `p_`x'_`f'' s
        file write T " & " %7.3f (`b_`x'_`f'') "`s'"
    }
    file write T " \\" _n " &"
    foreach f in 1 2 {
        file write T " & (" %6.3f (`se_`x'_`f'') ")"
    }
    file write T " \\" _n
}
file write T "\midrule" _n
file write T "Students & & " %9.0fc (`N_psu_lm_1') " & " %9.0fc (`N_psu_lm_2') " \\" _n
file write T "Program FE & & Yes & Yes \\" _n
file write T "Year FE & & Yes & Yes \\" _n
file write T "ROL FE (top 1 + univ.) & & No & Yes \\" _n
file write T "\bottomrule" _n "\end{tabular}" _n
file close T

* Panel C, separate fragment so the deck can place it beside A-B
local lab_N_total_enter "First stage, \(n_{pt}\) (entrants per 10 seats)"
local lab_y_program     "Graduation, program, 8y (pp per 10 seats)"
local lab_Z10 "\quad \(Z_{pt}\)"
local lab_Zp1 "\quad \(Z_{p,t+1}\)"
file open T using "$im_out/tables/im_d5_placebo_tplus1.tex", write replace
file write T "\begin{tabular}{lcc}" _n "\toprule" _n
file write T "\multicolumn{3}{l}{\textit{Panel C. Placebo: \(Z_{pt}\) and \(Z_{p,t+1}\) together}} \\" _n
file write T " & (1) & (2) \\" _n "\midrule" _n
foreach dv in N_total_enter y_program {
    file write T "\multicolumn{3}{l}{`lab_`dv''} \\" _n
    foreach t in Z10 Zp1 {
        file write T "`lab_`t''"
        foreach f in 1 2 {
            stars `C_`dv'_`t'_`f'_p' s
            file write T " & " %7.3f (`C_`dv'_`t'_`f'_b') "`s'"
        }
        file write T " \\" _n
        foreach f in 1 2 {
            file write T " & (" %6.3f (`C_`dv'_`t'_`f'_se') ")"
        }
        file write T " \\" _n
    }
}
file write T "\midrule" _n
file write T "Students & " %9.0fc (`C_N_1') " & " %9.0fc (`C_N_2') " \\" _n
file write T "\bottomrule" _n "\end{tabular}" _n
file close T

/**********************************************************************
* 5. (B1) Z_t and Z_t+k, own series, one regression per k
**********************************************************************/

local klist "-3 -2 -1 1 2 3"
foreach dv in N_total_enter y_program {
    foreach k of local klist {
        local v = cond(`k' < 0, "Zm" + string(abs(`k')), "Zp" + string(`k'))
        foreach f in 1 2 {
            quietly reghdfe `dv' Z10 `v', absorb(`fe`f'') vce(cluster pt)
            local df = e(df_r)
            local N  = e(N)
            local c0 = _b[Z10]
            local s0 = _se[Z10]
            local ck = _b[`v']
            local sk = _se[`v']
            local p0 = 2 * ttail(`df', abs(`c0' / `s0'))
            local pk = 2 * ttail(`df', abs(`ck' / `sk'))
            post `P' ("B1") ("`dv'") ("Z_t") (`k') (`f') (`c0') (`s0') (`p0') (`N')
            post `P' ("B1") ("`dv'") ("Z_t+k") (`k') (`f') (`ck') (`sk') (`pk') (`N')
            local B1_`dv'_`f'_0_`v'  = `c0'
            local B1_`dv'_`f'_0s_`v' = `s0'
            local B1_`dv'_`f'_0p_`v' = `p0'
            local B1_`dv'_`f'_k_`v'  = `ck'
            local B1_`dv'_`f'_ks_`v' = `sk'
            local B1_`dv'_`f'_kp_`v' = `pk'
            local B1_`dv'_`f'_N_`v'  = `N'
            di as result "`dv' fe`f' k=`k': Z_t " %8.3f `c0' " (" %6.3f `s0' ")  Z_t+k " ///
                %8.3f `ck' " (" %6.3f `sk' ")  N=" `N'
        }
    }
}

* table: main FE (2); FE (1) is in the csv
local f 2
file open T using "$im_out/tables/im_d5_placebo_leadlag.tex", write replace
file write T "\begin{tabular}{l*{6}{c}}" _n "\toprule" _n
file write T " & \(k=-3\) & \(k=-2\) & \(k=-1\) & \(k=+1\) & \(k=+2\) & \(k=+3\) \\" _n "\midrule" _n
foreach dv in N_total_enter y_program {
    local dl = cond("`dv'" == "N_total_enter", "First stage, \(n_{pt}\) (entrants per 10 seats)", "Graduation from the program, 8y (pp per 10 seats)")
    file write T "\multicolumn{7}{l}{\textit{`dl'}} \\" _n
    foreach t in 0 k {
        local tl = cond("`t'" == "0", "\quad \(Z_{pt}\)", "\quad \(Z_{p,t+k}\)")
        file write T "`tl'"
        foreach k of local klist {
            local v = cond(`k' < 0, "Zm" + string(abs(`k')), "Zp" + string(`k'))
            stars `B1_`dv'_`f'_`t'p_`v'' s
            file write T " & " %7.3f (`B1_`dv'_`f'_`t'_`v'') "`s'"
        }
        file write T " \\" _n
        foreach k of local klist {
            local v = cond(`k' < 0, "Zm" + string(abs(`k')), "Zp" + string(`k'))
            file write T " & (" %6.3f (`B1_`dv'_`f'_`t's_`v'') ")"
        }
        file write T " \\" _n
    }
    file write T "\quad Students"
    foreach k of local klist {
        local v = cond(`k' < 0, "Zm" + string(abs(`k')), "Zp" + string(`k'))
        file write T " & " %9.0fc (`B1_`dv'_`f'_N_`v'')
    }
    file write T " \\" _n "\addlinespace" _n
}
file write T "\midrule" _n
file write T "\multicolumn{7}{l}{Program, year and ROL (top 1 + univ.) FE; SE clustered by program-year; per 10 seats.} \\" _n
file write T "\bottomrule" _n "\end{tabular}" _n
file close T

/**********************************************************************
* 6. (B2) Distributed lag t-3..t+3, Oferta Academica regular vacancies
**********************************************************************/

local terms "Vm3 Vm2 Vm1 V0 Vp1 Vp2 Vp3"
foreach dv in N_total_enter y_program {
    foreach f in 1 2 {
        quietly reghdfe `dv' `terms', absorb(`fe`f'') vce(cluster pt)
        local df = e(df_r)
        local N  = e(N)
        di as result _n "`dv' fe`f', distributed lag, N=" `N'
        local k = -3
        foreach v of local terms {
            local p = 2 * ttail(`df', abs(_b[`v'] / _se[`v']))
            post `P' ("B2") ("`dv'") ("V_t+k") (`k') (`f') (_b[`v']) (_se[`v']) (`p') (`N')
            di as text "  k=" %2.0f `k' ": " %8.3f _b[`v'] " (" %6.3f _se[`v'] ")"
            local ++k
        }
        quietly test Vm3 Vm2 Vm1
        di as text "  joint lags p = " %5.3f r(p)
        post `P' ("B2") ("`dv'") ("lags_F") (-9) (`f') (r(F)) (.) (r(p)) (`N')
        quietly test Vp1 Vp2 Vp3
        di as text "  joint leads p = " %5.3f r(p)
        post `P' ("B2") ("`dv'") ("leads_F") (9) (`f') (r(F)) (.) (r(p)) (`N')
    }
}
postclose `P'

* figures: main FE (2)
use "$processed/im_d5_placebo_results.dta", clear
export delimited using "$im_out/tables/im_d5_placebo.csv", replace
keep if panel == "B2" & term == "V_t+k" & fe == 2
gen double lo = b - 1.96 * se
gen double hi = b + 1.96 * se
foreach dv in y_program N_total_enter {
    local nm = cond("`dv'" == "y_program", "grad", "fs")
    local yt = cond("`dv'" == "y_program", "Graduation, program, 8y (pp per 10 vacancies)", "Entering cohort n (entrants per 10 vacancies)")
    quietly summarize N if dv == "`dv'"
    local Nn : di %9.0fc r(mean)
    twoway (rcap lo hi k if dv == "`dv'", lcolor(navy)) ///
           (scatter b k if dv == "`dv'", mcolor(navy) msymbol(circle)), ///
        yline(0, lcolor(gs10) lpattern(dash)) xline(0, lcolor(gs13)) ///
        xlabel(-3(1)3) xtitle("k (vacancies in year t+k, per 10)") ///
        ytitle("`yt'") legend(off) ///
        note("Program, year and ROL (top 1 + univ.) FE. 95% CI, SE clustered by program-year." ///
             "Oferta Academica regular vacancies; cohorts 2010-2016; N = `=strtrim("`Nn'")'.") ///
        graphregion(color(white)) plotregion(color(white))
    graph export "$im_out/figures/im_d5_leadlag_`nm'.pdf", replace
}

di as result "40_design5_placebo.do finished."
