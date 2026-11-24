/**********************************************************************
* 51_design5_balance_rolctrl.do
*
* Deck slides on the balance of the instrument (issue #10), under the
* three candidate main ROL FE (1st preference + set of universities,
* first three preferences, set of programs), with the program-year
* controls and time FE of the results slide (50).
*
*   x_i = g Z_pt/10 + [PSU] + [c_pt] + FE + phi_ROL(i) + u_i
*
*   x  : private-paid, municipal, private-subsidized school, PSU L+M,
*        NEM, BEA, female, applications in the ROL (binary in 0-100);
*        predicted graduation from all of them (yhat) and from all but
*        PSU (yhat_np, with PSU as a control: PSU held fixed)
*   samples: each ROL on its own non-singleton sample (program + year +
*        ROL FE), as in 40
*   specifications on each ROL sample:
*     s1 no controls; s2 program + year FE; s3 + ROL FE (a);
*     s4 (a) + demand in t-1, accreditation and tuition (b);
*     s5 (b) with university x year and field x year FE (c);
*     s3p-s5p: s3-s5 with PSU (linear, missing indicator)
*     s0 no controls, all students
*   c_pt: demand in t-1 (log applicants, log first-preference
*        applicants, log waiting list, mean score of first-preference
*        applicants); accreditation and tuition in t (shares in
*        accredited program and institution, years of institutional
*        accreditation, log median tuition, share in day programs,
*        formal duration); missing -> 0 plus indicator
*   SE : clustered by program-year
*
* Outputs (output/inframarginal/tables/):
*   im_d5_balance_rolctrl.tex      (a)-(c) by ROL           (as 40)
*   im_d5_balance_psu_rolctrl.tex  (a)-(c) by ROL with PSU  (as 40b)
*   im_d5_balance_seq_{top1u,top3,set}.tex  controls one block at a
*                                  time, same students     (as 47)
*   im_d5_balance_rolctrl.csv      every estimate
*
* Inputs: $processed/design5_individual_2007_2016.dta (02_build/16)
*         $processed/program_year_controls_2007_2016.dta (02_build/20)
*         $psu_raw/A_INSCRITOS_PUNTAJES_PSU_YYYY_PRIV_MRUN.csv (BEA)
**********************************************************************/

clear all
set more off
do "code/config.do"

global im_out "$output/inframarginal"
cap mkdir "$im_out/tables"

use grad_year using "$processed/check_06b_titulados_all.dta", clear
quietly summarize grad_year
local last_cohort = r(max) - 8

capture program drop stars
program define stars
    args p name
    c_local `name' = cond(`p' < 0.01, "\sym{***}", cond(`p' < 0.05, "\sym{**}", cond(`p' < 0.10, "\sym{*}", "")))
end

/**********************************************************************
* 1. BEA (as 40b)
**********************************************************************/

tempfile ses
forvalues y = 2007/2016 {
    import delimited "$psu_raw/A_INSCRITOS_PUNTAJES_PSU_`y'_PRIV_MRUN.csv", ///
        delimiter(";") varnames(1) clear encoding(windows-1252) ///
        stringcols(_all)
    rename *, lower
    keep mrun bea
    destring mrun, replace force
    gen int ao_proceso = `y'
    if `y' > 2007 append using `ses'
    save `ses', replace
}
drop if missing(mrun)
duplicates drop mrun ao_proceso, force
gen byte bea_ = strtrim(bea) == "BEA"
drop bea
rename bea_ bea
save `ses', replace

/**********************************************************************
* 2. Sample, outcomes and controls
**********************************************************************/

use "$processed/design5_individual_2007_2016.dta", clear
keep if _m_panel == 3 & ao_proceso <= `last_cohort'
keep if pick_toppref & ao_proceso == first_year_i
duplicates drop mrun, force
merge m:1 mrun ao_proceso using `ses', keep(master match) nogen
merge m:1 codigo_carrera_harmonized ao_proceso ///
    using "$processed/program_year_controls_2007_2016.dta", ///
    keep(master match) gen(_m_ctrl)
tab _m_ctrl

egen long pt         = group(program_id_rank_analysis ao_proceso)
egen long programs   = group(program_id_rank_analysis)
egen long uni_year   = group(sigla_universidad ao_proceso)
egen long field_year = group(field ao_proceso)
gen double y_program = 100 * graduates_enrolled_program_8y
gen double Z10 = Z_total_cupos / 10
gen byte subv  = dep == 3 if !missing(dep)
foreach x in female priv mun subv bea {
    replace `x' = 100 * `x'
}
quietly reg y_program psu_lm nem female priv mun subv bea n_apps
predict double yhat if e(sample)
quietly reg y_program nem female priv mun subv bea n_apps
predict double yhat_np if e(sample)
gen double yhat_npc = yhat_np
gen byte   psu_m = missing(psu_lm)
gen double psu_c = cond(psu_m, 0, psu_lm)

* program-year controls: missing -> 0 plus indicator
local rules1 "w_nem w_rank"
local rules2 "w_nem w_rank w_leng w_mat w_hist w_cien w_min_pond w_min_lm"
foreach v of local rules2 {
    gen byte   mi_`v' = missing(`v')
    replace `v' = 0 if mi_`v'
}
local rules1c "`rules1' mi_w_nem"
local rules2c "`rules2'"
foreach v of local rules2 {
    quietly summarize mi_`v'
    if r(max) > 0 local rules2c "`rules2c' mi_`v'"
}


/**********************************************************************
* 3. Control blocks (missing -> 0 plus indicator)
**********************************************************************/

local b_dem "ld_apps_l1 ld_apps1_l1 ld_wait_l1 d_score1_l1"
local b_acc "m_acred_carr m_acred_inst m_acred_inst_years m_ltuition m_diurno m_duration"
local b_cmp "x_exp_broad x_cumexp_broad x_exp_cos x_cumexp_cos"
local b_fin0 "f_lpc_exp f_lpc_capital f_lpc_acad f_lpc_ovh f_lexp"
local b_fin1 "f_lpc_exp_l1 f_lpc_capital_l1 f_lpc_acad_l1 f_lpc_ovh_l1 f_lexp_l1"
foreach b in dem acc cmp {
    local c_`b' ""
    foreach v of local b_`b' {
        gen byte mi_`v' = missing(`v')
        quietly summarize mi_`v'
        di as text %-22s "`v'" "  missing share " %5.3f r(mean)
        replace `v' = 0 if mi_`v'
        local c_`b' "`c_`b'' `v'"
        if r(max) > 0 local c_`b' "`c_`b'' mi_`v'"
    }
}

/**********************************************************************
* 4. Estimation
**********************************************************************/

local covs "priv mun subv psu_lm nem bea female n_apps"
local xs "`covs' yhat yhat_np"
foreach r in top1u top3 set {
    quietly reghdfe yhat Z10, absorb(programs ao_proceso rol_`r')
    gen byte s_`r' = e(sample)
}
local fe2 "programs ao_proceso"
local fe3 "programs ao_proceso"
local fe4 "programs ao_proceso"
local fe5 "programs uni_year field_year"
local ct4 "`c_dem' `c_acc'"
local ct5 "`c_dem' `c_acc'"

tempname P
tempfile res
postfile `P' str6 rol str3 spec str8 x double(b se p mean) long N using `res', replace
* s0: no controls, all students
foreach x of local xs {
    if "`x'" == "yhat_np" continue
    quietly regress `x' Z10, vce(cluster pt)
    local b = _b[Z10]
    local se = _se[Z10]
    quietly summarize `x' if e(sample)
    post `P' ("all") ("s0") ("`x'") (`b') (`se') (2 * ttail(e(df_r), abs(`b' / `se'))) (r(mean)) (r(N))
}
foreach r in top1u top3 set {
    foreach s in s1 s2 s3 s4 s5 s3p s4p s5p {
        local c = real(substr("`s'", 2, 1))
        local psu = cond(strpos("`s'", "p"), "psu_c psu_m", "")
        foreach x of local xs {
            * PSU-control specs: covariates other than PSU only (the index
            * without PSU, PSU held fixed, is estimated in s3-s5)
            if "`psu'" != "" & inlist("`x'", "psu_lm", "yhat", "yhat_np") continue
            if inlist("`s'", "s1", "s2") & "`x'" == "yhat_np" continue
            local cx "`psu'"
            if "`x'" == "yhat_np" local cx "psu_c psu_m"
            if `c' == 1 {
                quietly regress `x' Z10 if s_`r', vce(cluster pt)
            }
            else {
                local fe "`fe`c''"
                if `c' >= 3 local fe "`fe' rol_`r'"
                quietly reghdfe `x' Z10 `cx' `ct`c'' if s_`r', absorb(`fe') vce(cluster pt)
            }
            local b = _b[Z10]
            local se = _se[Z10]
            local df = e(df_r)
            local N = e(N)
            quietly summarize `x' if s_`r'
            post `P' ("`r'") ("`s'") ("`x'") (`b') (`se') (2 * ttail(`df', abs(`b' / `se'))) (r(mean)) (`N')
            di as result "`r' `s' `x': " %8.4f `b' " (" %7.4f `se' ")  N=" `N'
        }
    }
}
postclose `P'

use `res', clear
export delimited using "$im_out/tables/im_d5_balance_rolctrl.csv", replace

/**********************************************************************
* 5. Tables
**********************************************************************/

local lab_priv    "Private-paid school (\%)"
local lab_mun     "Municipal school (\%)"
local lab_subv    "Private-subsidized school (\%)"
local lab_psu_lm  "PSU language+math (points)"
local lab_nem     "NEM (points)"
local lab_bea     "BEA, top 10\% of own school (\%)"
local lab_female  "Female (\%)"
local lab_n_apps  "Applications in the ROL (number)"
local lab_yhat    "Predicted graduation, all covariates (\%)"
local lab_yhat_np "Predicted grad., all but PSU, PSU fixed (\%)"

capture program drop putcell
program define putcell
    args h r s x
    quietly count if rol == "`r'" & spec == "`s'" & x == "`x'"
    if r(N) == 0 {
        file write `h' " & "
        exit
    }
    quietly summarize se if rol == "`r'" & spec == "`s'" & x == "`x'"
    if r(mean) == 0 | missing(r(mean)) {
        file write `h' " & --"
        exit
    }
    quietly summarize p if rol == "`r'" & spec == "`s'" & x == "`x'"
    local st = cond(r(mean) < 0.01, "\sym{***}", cond(r(mean) < 0.05, "\sym{**}", cond(r(mean) < 0.10, "\sym{*}", "")))
    quietly summarize b if rol == "`r'" & spec == "`s'" & x == "`x'"
    file write `h' " & " %6.3f (r(mean)) "`st'"
end
capture program drop putse
program define putse
    args h r s x
    quietly summarize se if rol == "`r'" & spec == "`s'" & x == "`x'"
    if r(N) == 0 | r(mean) == 0 | missing(r(mean)) {
        file write `h' " & "
        exit
    }
    file write `h' " & (" %5.3f (r(mean)) ")"
end

* (1) and (2): (a)-(c) by ROL, without and with PSU
foreach tb in bal psu {
    local fn = cond("`tb'" == "bal", "im_d5_balance_rolctrl", "im_d5_balance_psu_rolctrl")
    local sfx = cond("`tb'" == "bal", "", "p")
    local rows = cond("`tb'" == "bal", "`xs'", "priv mun subv nem bea female n_apps yhat_np")
    file open T using "$im_out/tables/`fn'.tex", write replace
    file write T "\begin{tabular}{lc*{9}{c}}" _n "\toprule" _n
    file write T "ROL FE & & \multicolumn{3}{c}{Top 1 + univ. (main)} & \multicolumn{3}{c}{First three pref.} & \multicolumn{3}{c}{Program set} \\" _n
    file write T "\cmidrule(lr){3-5}\cmidrule(lr){6-8}\cmidrule(lr){9-11}" _n " & Mean"
    forvalues k = 1/9 {
        file write T " & (`k')"
    }
    file write T " \\" _n
    if "`tb'" == "psu" file write T "PSU control & " _dup(9) " & Linear" " \\" _n
    file write T "Program-year controls & " _dup(3) " & -- & Yes & Yes" " \\" _n
    file write T "Time FE & " _dup(3) " & Year & Year & U, F \(\times\) yr" " \\" _n "\midrule" _n
    foreach x of local rows {
        if "`x'" == "priv"    file write T "\multicolumn{11}{l}{\textit{Panel A. Socioeconomic proxies}} \\" _n
        if "`x'" == "psu_lm" | ("`x'" == "nem" & "`tb'" == "psu") file write T "\addlinespace" _n "\multicolumn{11}{l}{\textit{Panel B. Achievement and other predetermined}} \\" _n
        if "`x'" == "yhat" | ("`x'" == "yhat_np" & "`tb'" == "psu") file write T "\addlinespace" _n "\multicolumn{11}{l}{\textit{Joint tests}} \\" _n
        quietly summarize mean if rol == "top1u" & spec == "s3" & x == "`x'"
        file write T "`lab_`x''" " & " %6.2f (r(mean))
        local sx = cond("`x'" == "yhat_np", "", "`sfx'")
        foreach r in top1u top3 set {
            foreach s in s3 s4 s5 {
                putcell T `r' `s'`sx' `x'
            }
        }
        file write T " \\" _n " & "
        foreach r in top1u top3 set {
            foreach s in s3 s4 s5 {
                putse T `r' `s'`sx' `x'
            }
        }
        file write T " \\" _n
    }
    file write T "\midrule" _n "Students & "
    foreach r in top1u top3 set {
        foreach s in s3 s4 s5 {
            quietly summarize N if rol == "`r'" & spec == "`s'" & x == "yhat"
            file write T " & " %9.0fc (r(mean))
        }
    }
    file write T " \\" _n "\bottomrule" _n "\end{tabular}" _n
    file close T
}

* (3) controls one block at a time, same students, one table per ROL
foreach r in top1u top3 set {
    file open T using "$im_out/tables/im_d5_balance_seq_`r'.tex", write replace
    file write T "\begin{tabular}{lc*{6}{c}}" _n "\toprule" _n
    file write T " & Mean & (1) & (2) & (3) & (4) & (5) & (6) \\" _n
    file write T "Sample & & All & \multicolumn{5}{c}{ROL FE sample} \\" _n
    file write T "Program FE & & -- & -- & Yes & Yes & Yes & Yes \\" _n
    file write T "Time FE & & -- & -- & Year & Year & Year & U, F \(\times\) yr \\" _n
    file write T "ROL FE & & -- & -- & -- & Yes & Yes & Yes \\" _n
    file write T "Program-year controls & & -- & -- & -- & -- & Yes & Yes \\" _n "\midrule" _n
    foreach x in `covs' yhat yhat_np {
        if "`x'" == "priv"   file write T "\multicolumn{8}{l}{\textit{Panel A. Socioeconomic proxies}} \\" _n
        if "`x'" == "psu_lm" file write T "\addlinespace" _n "\multicolumn{8}{l}{\textit{Panel B. Achievement and other predetermined}} \\" _n
        if "`x'" == "yhat"   file write T "\addlinespace" _n "\multicolumn{8}{l}{\textit{Joint tests}} \\" _n
        quietly summarize mean if rol == "`r'" & spec == "s3" & x == "`x'"
        file write T "`lab_`x''" " & " %6.2f (r(mean))
        putcell T all s0 `x'
        foreach s in s1 s2 s3 s4 s5 {
            putcell T `r' `s' `x'
        }
        file write T " \\" _n " & "
        putse T all s0 `x'
        foreach s in s1 s2 s3 s4 s5 {
            putse T `r' `s' `x'
        }
        file write T " \\" _n
    }
    quietly summarize N if rol == "all" & spec == "s0" & x == "yhat"
    file write T "\midrule" _n "Students & & " %9.0fc (r(mean))
    foreach s in s1 s2 s3 s4 s5 {
        quietly summarize N if rol == "`r'" & spec == "`s'" & x == "yhat"
        file write T " & " %9.0fc (r(mean))
    }
    file write T " \\" _n "\bottomrule" _n "\end{tabular}" _n
    file close T
}

di as result "51_design5_balance_rolctrl.do finished."
