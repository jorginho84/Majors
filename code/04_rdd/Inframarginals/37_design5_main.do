/**********************************************************************
* 37_design5_main.do
*
* Design V (issue #8): individual-level inframarginal 2SLS with
* application-portfolio (ROL) fixed effects.
*
*   n_pt = a Z_pt + x_i'a2 + psi_p + psi_t + psi_ROL(i) + nu
*   Y_i  = b n_pt + x_i'b2 + phi_p + phi_t + phi_ROL(i) + e   (2SLS)
*
*   unit : one row per inframarginal student (Design I definition,
*          lugar <= T_p first cohort): most preferred inframarginal
*          application in the student's first inframarginal year
*   n    : entering cohort of the program-year (N_total_enter)
*   Z    : vacancies of the program-year (Z_total_cupos)
*   Y    : graduation within 8 years from the enrolled program (main);
*          any university; any higher-education institution
*   x    : PSU language+math, NEM, female, private-paid, municipal
*          (missing values set to 0 with a missing indicator)
*   FE   : program and year always; ROL under seven definitions, from
*          coarse to fine: top1, univ, top2, top1u (main), top3, set, exact
*   SE   : clustered by program-year
*   RF and 2SLS reported x 100 (pp per vacancy / per entrant)
*
* Panel A: full sample (each column keeps its own non-singleton sample).
* Panel B: every column on the common sample retained by the exact-ROL
*          specification, so differences across columns come from the
*          fixed effects and not from a change of sample.
*
* Outputs (output/inframarginal/):
*   tables/im_d5_<y>.tex      y = program, uni, he
*   tables/im_d5_results.csv  every estimate
*
* Input: $processed/design5_individual_2007_2016.dta (02_build/16)
**********************************************************************/

clear all
set more off
do "code/config.do"

global im_out "$output/inframarginal"
cap mkdir "$im_out"
cap mkdir "$im_out/tables"

* 8-year outcomes are observed for cohorts <= last titulados year - 8
use grad_year using "$processed/check_06b_titulados_all.dta", clear
quietly summarize grad_year
local last_cohort = r(max) - 8

capture program drop stars
program define stars
    args p name
    c_local `name' = cond(`p' < 0.01, "\sym{***}", cond(`p' < 0.05, "\sym{**}", cond(`p' < 0.10, "\sym{*}", "")))
end

/**********************************************************************
* 0. Sample
**********************************************************************/

use "$processed/design5_individual_2007_2016.dta", clear
keep if _m_panel == 3 & ao_proceso <= `last_cohort'
keep if pick_toppref & ao_proceso == first_year_i
duplicates report mrun
duplicates drop mrun, force
isid mrun

egen long pt       = group(program_id_rank_analysis ao_proceso)
egen long programs = group(program_id_rank_analysis)

foreach v in program uni he {
    local src = cond("`v'" == "program", "graduates_enrolled_program_8y", "graduates_`v'_8y")
    gen double y_`v' = 100 * `src'
}

local ctrl ""
foreach v in psu_lm nem female priv mun {
    gen byte m_`v' = missing(`v')
    replace `v' = 0 if missing(`v')
    local ctrl "`ctrl' `v' m_`v'"
}

local rols "top1 univ top2 top1u top3 set exact"
local K : word count `rols'
local ncol = `K' + 2

* column c: FE and controls
local fe1 "programs ao_proceso"
local ct1 ""
local fe2 "programs ao_proceso"
local ct2 "`ctrl'"
local c 2
foreach r of local rols {
    local ++c
    local fe`c' "programs ao_proceso rol_`r'"
    local ct`c' "`ctrl'"
    local lab`c' "`r'"
}

* common sample: retained by the exact-ROL specification
quietly reghdfe N_total_enter Z_total_cupos `ctrl', absorb(programs ao_proceso rol_exact)
gen byte common = e(sample)
count if common

* students whose ROL x program group spans >= 2 years (identifying)
foreach r of local rols {
    bysort rol_`r' programs ao_proceso: gen byte f = _n == 1
    bysort rol_`r' programs: egen int ny = total(f)
    gen byte id_`r' = ny >= 2
    drop f ny
}

/**********************************************************************
* 1. Estimation
**********************************************************************/

capture program drop d5_est
program define d5_est
    args yv cond fe ctrl pfx
    quietly reghdfe N_total_enter Z_total_cupos `ctrl' if `cond', absorb(`fe') vce(cluster pt)
    c_local `pfx'fs   = _b[Z_total_cupos]
    c_local `pfx'fsse = _se[Z_total_cupos]
    c_local `pfx'fsp  = 2 * ttail(e(df_r), abs(_b[Z_total_cupos] / _se[Z_total_cupos]))
    quietly reghdfe y_`yv' Z_total_cupos `ctrl' if `cond', absorb(`fe') vce(cluster pt)
    c_local `pfx'rf   = _b[Z_total_cupos]
    c_local `pfx'rfse = _se[Z_total_cupos]
    c_local `pfx'rfp  = 2 * ttail(e(df_r), abs(_b[Z_total_cupos] / _se[Z_total_cupos]))
    quietly ivreghdfe y_`yv' (N_total_enter = Z_total_cupos) `ctrl' if `cond', ///
        absorb(`fe') cluster(pt)
    c_local `pfx'iv   = _b[N_total_enter]
    c_local `pfx'ivse = _se[N_total_enter]
    c_local `pfx'ivp  = 2 * normal(-abs(_b[N_total_enter] / _se[N_total_enter]))
    c_local `pfx'F    = e(widstat)
    c_local `pfx'N    = e(N)
    tempvar s
    gen byte `s' = e(sample)
    quietly summarize y_`yv' if `s'
    c_local `pfx'ym   = r(mean)
    quietly distinct programs if `s'
    c_local `pfx'np   = r(ndistinct)
    quietly distinct pt if `s'
    c_local `pfx'npt  = r(ndistinct)
end

capture postclose R
postfile R str8 outcome str1 panel byte col str8 rol ///
    double fs fsse F rf rfse iv ivse N np npt ym ///
    using "`c(tmpdir)'/d5_results.dta", replace

foreach y in program uni he {
    foreach P in A B {
        local cond = cond("`P'" == "A", "1", "common")
        forvalues c = 1/`ncol' {
            di as text "`y' panel `P' col `c': absorb(`fe`c'')"
            d5_est `y' `cond' "`fe`c''" "`ct`c''" `P'`c'`y'_
            local rl = cond(`c' <= 2, "none", "`lab`c''")
            post R ("`y'") ("`P'") (`c') ("`rl'") ///
                (``P'`c'`y'_fs') (``P'`c'`y'_fsse') (``P'`c'`y'_F') ///
                (``P'`c'`y'_rf') (``P'`c'`y'_rfse') ///
                (``P'`c'`y'_iv') (``P'`c'`y'_ivse') ///
                (``P'`c'`y'_N') (``P'`c'`y'_np') (``P'`c'`y'_npt') (``P'`c'`y'_ym')
            di as result "  FS=" %6.3f ``P'`c'`y'_fs' " RF=" %7.4f ``P'`c'`y'_rf' ///
                " (" %6.4f ``P'`c'`y'_rfse' ")  2SLS=" %7.4f ``P'`c'`y'_iv' ///
                " (" %6.4f ``P'`c'`y'_ivse' ")  F=" %7.1f ``P'`c'`y'_F' "  N=" %9.0fc ``P'`c'`y'_N'
        }
    }
}
postclose R

* share of identifying students, full sample
quietly count
local Nall = r(N)
foreach r of local rols {
    quietly count if id_`r'
    local idsh_`r' = 100 * r(N) / `Nall'
}
local idsh_none = .

/**********************************************************************
* 2. Tables
**********************************************************************/

local ylab_program "Graduation from the enrolled program, 8y"
local ylab_uni     "Graduation from any university, 8y"
local ylab_he      "Graduation from any higher-education institution, 8y"

local rname_top1  "Top 1"
local rname_univ  "Univ.\ set"
local rname_top2  "Top 2"
local rname_top1u "Top 1 + univ."
local rname_top3  "Top 3"
local rname_set   "Prog.\ set"
local rname_exact "Exact"

foreach y in program uni he {
    file open T using "$im_out/tables/im_d5_`y'.tex", write replace
    file write T "\begin{tabular}{l*{`ncol'}{c}}" _n "\toprule" _n
    file write T " "
    forvalues c = 1/`ncol' {
        file write T " & (`c')"
    }
    file write T " \\" _n "ROL FE"
    forvalues c = 1/`ncol' {
        local nm = cond(`c' <= 2, "--", "`rname_`lab`c'''")
        file write T " & `nm'"
    }
    file write T " \\" _n "Controls"
    forvalues c = 1/`ncol' {
        local nm = cond(`c' == 1, "No", "Yes")
        file write T " & `nm'"
    }
    file write T " \\" _n "\midrule" _n

    foreach P in A B {
        local ptitle = cond("`P'" == "A", "Panel A. Full sample", ///
            "Panel B. Common sample (exact-ROL specification)")
        file write T "\multicolumn{`=`ncol'+1'}{l}{\textit{`ptitle'}} \\" _n

        file write T "First stage: \(n_{pt}\) on \(Z_{pt}\)"
        forvalues c = 1/`ncol' {
            stars ``P'`c'`y'_fsp' s
            file write T " & " %6.3f (``P'`c'`y'_fs') "`s'"
        }
        file write T " \\" _n
        forvalues c = 1/`ncol' {
            file write T " & (" %5.3f (``P'`c'`y'_fsse') ")"
        }
        file write T " \\" _n "Kleibergen--Paap F"
        forvalues c = 1/`ncol' {
            file write T " & " %6.0f (``P'`c'`y'_F')
        }
        file write T " \\" _n "\addlinespace" _n
        file write T "\multicolumn{`=`ncol'+1'}{l}{`ylab_`y'' (\(\times 100\))} \\" _n
        foreach e in rf iv {
            local elab = cond("`e'" == "rf", "\quad Reduced form", "\quad \textbf{2SLS}")
            file write T "`elab'"
            forvalues c = 1/`ncol' {
                stars ``P'`c'`y'_`e'p' s
                file write T " & " %7.3f (``P'`c'`y'_`e'') "`s'"
            }
            file write T " \\" _n
            forvalues c = 1/`ncol' {
                file write T " & (" %6.3f (``P'`c'`y'_`e'se') ")"
            }
            file write T " \\" _n
        }
        file write T "Mean of outcome"
        forvalues c = 1/`ncol' {
            file write T " & " %5.1f (``P'`c'`y'_ym')
        }
        file write T " \\" _n "Students"
        forvalues c = 1/`ncol' {
            file write T " & " %9.0fc (``P'`c'`y'_N')
        }
        file write T " \\" _n "Program-years (clusters)"
        forvalues c = 1/`ncol' {
            file write T " & " %6.0fc (``P'`c'`y'_npt')
        }
        file write T " \\" _n
        if "`P'" == "A" {
            file write T "ROL\(\times\)program group spans \(\geq\)2 years (\%)"
            forvalues c = 1/`ncol' {
                if `c' <= 2 file write T " & --"
                else file write T " & " %5.1f (`idsh_`lab`c''')
            }
            file write T " \\" _n
        }
        if "`P'" == "A" file write T "\midrule" _n
    }
    file write T "\bottomrule" _n "\end{tabular}" _n
    file close T
}

* compact table for the deck: program+year, + controls, + top1u ROL (main), + exact ROL
local cc "1 2 6 9"
file open T using "$im_out/tables/im_d5_main.tex", write replace
file write T "\begin{tabular}{lcccc}" _n "\toprule" _n
file write T " & (1) & (2) & (3) & (4) \\" _n
file write T "ROL FE & -- & -- & Top 1 + univ. & Exact \\" _n
file write T "Controls & No & Yes & Yes & Yes \\" _n "\midrule" _n
file write T "First stage: \(n_{pt}\) on \(Z_{pt}\)"
foreach c of local cc {
    stars `A`c'program_fsp' s
    file write T " & " %6.3f (`A`c'program_fs') "`s'"
}
file write T " \\" _n
foreach c of local cc {
    file write T " & (" %5.3f (`A`c'program_fsse') ")"
}
file write T " \\" _n "Kleibergen--Paap F"
foreach c of local cc {
    file write T " & " %6.0f (`A`c'program_F')
}
file write T " \\" _n "\addlinespace" _n
file write T "\multicolumn{5}{l}{2SLS, \(\times 100\)} \\" _n
foreach y in program uni he {
    local yl = cond("`y'" == "program", "Graduation, enrolled program, 8y", cond("`y'" == "uni", "Graduation, any university, 8y", "Graduation, any higher education, 8y"))
    file write T "\quad `yl'"
    foreach c of local cc {
        stars `A`c'`y'_ivp' s
        file write T " & " %6.3f (`A`c'`y'_iv') "`s'"
    }
    file write T " \\" _n
    foreach c of local cc {
        file write T " & (" %5.3f (`A`c'`y'_ivse') ")"
    }
    file write T " \\" _n
}
file write T "\midrule" _n "Students"
foreach c of local cc {
    file write T " & " %9.0fc (`A`c'program_N')
}
file write T " \\" _n "Program-years (clusters)"
foreach c of local cc {
    file write T " & " %6.0fc (`A`c'program_npt')
}
file write T " \\" _n "\bottomrule" _n "\end{tabular}" _n
file close T

use "`c(tmpdir)'/d5_results.dta", clear
export delimited using "$im_out/tables/im_d5_results.csv", replace
list outcome panel col rol fs F rf rfse iv ivse N, sepby(outcome panel) noobs abbreviate(8)

di as result "37_design5_main.do finished."
