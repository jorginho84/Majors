/**********************************************************************
* 08_design2_income_rank.do
*
* Issue #13: Design II 2SLS (06_design2_2sls.do) with the income rank of
* the program of graduation as the outcome of inframarginal applicants.
*
*   First stage:  N_pt = pi   Post_pt + FE + v
*   Reduced form: y_pt = rho  Post_pt + FE + u
*   2SLS:         y_pt = beta N^_pt   + FE + e,   beta = rho / pi
*
*   y : ir   mean income rank of the program of first title within 8y,
*            any program (0 if no title), rank points (1-100 scale)
*       ga   any title within 8 years (pct.), same title definition
*       irg  income rank among graduates (selected; descriptive)
*       g8p  graduation from the program of first enrollment (pct.),
*            reference: reproduces 06
*   Inframarginal: First Cohort (main), Minimum Cohort
*   FE : (1) program + year; (2) program + university x year
*   Samples: selective programs (main), all incumbent programs
*   Unweighted. SE clustered by program. FS, RF and 2SLS share the
*   program-years with non-missing y.
*
* Inputs:  oe_panel.dta (02), oe_infra_outcomes.dta (05),
*          oe_infra_income_rank.dta (02_build/19)
* Outputs: output/own_expansion/tables/oe_2sls_design2_incrank.tex
*          output/own_expansion/tables/oe_2sls_design2_incrank_first.tex (deck)
*          output/own_expansion/tables/oe_2sls_design2_incrank.csv
*          output/own_expansion/figures/oe_ir_rf_es_ir_f_<fe>.pdf
**********************************************************************/

do "code/config.do"
do "code/Own_expansion/00_helpers.do"

global oe_out "$output/own_expansion"

use "$processed/oe_panel.dta", clear
merge 1:1 code_h ao_proceso using "$processed/oe_infra_outcomes.dta", ///
    keep(master match) keepusing(g8p_f g8p_m) nogen
merge 1:1 code_h ao_proceso using "$processed/oe_infra_income_rank.dta", ///
    keep(master match)
tab _merge if ao_proceso <= 2016
drop _merge

local yrows ir ga irg g8p
local lab_ir  "Income rank of program of graduation (0 if no title)"
local lab_ga  "Any title, 8y (pct.)"
local lab_irg "Income rank among graduates"
local lab_g8p "Graduation from the enrolled program, 8y (pct.)"

local cols "sel_fe1 sel_fe2 all_fe1 all_fe2"

capture postclose R
postfile R str1 def str4 y str8 col double fs fsse rf rfse rfp iv ivse ivp F N ym ///
    using "`c(tmpdir)'/oe_ir.dta", replace

foreach d in f m {
    foreach y of local yrows {
        foreach c of local cols {
            local s  = substr("`c'", 1, 3)
            local fe = substr("`c'", 5, 3)
            local abs = cond("`fe'" == "fe1", "pid ao_proceso", "pid uy")
            local if "if !missing(`y'_`d')"
            if "`s'" == "sel" local if "`if' & selective"

            quietly reghdfe N_first post_main `if', absorb(`abs') cluster(pid)
            local fs = _b[post_main]
            local fsse = _se[post_main]
            quietly reghdfe `y'_`d' post_main `if', absorb(`abs') cluster(pid)
            local rf = _b[post_main]
            local rfse = _se[post_main]
            local rfp = 2 * ttail(e(df_r), abs(`rf' / `rfse'))
            quietly ivreghdfe `y'_`d' (N_first = post_main) `if', absorb(`abs') cluster(pid)
            local iv = _b[N_first]
            local ivse = _se[N_first]
            local ivp = 2 * normal(-abs(`iv' / `ivse'))
            local F = e(widstat)
            local N = e(N)
            quietly summarize `y'_`d' `if' & g_main > 0 & post_main == 0
            local ym = r(mean)
            post R ("`d'") ("`y'") ("`c'") (`fs') (`fsse') (`rf') (`rfse') (`rfp') ///
                (`iv') (`ivse') (`ivp') (`F') (`N') (`ym')
            foreach k in fs fsse rf rfse rfp iv ivse ivp F N ym {
                global S_`d'_`y'_`c'_`k' "``k''"
            }
            di as text "`d' `y' `c': FS " as result %6.2f `fs' ///
                as text "  RF " as result %6.2f `rf' " (" %5.2f `rfse' ")" ///
                as text "  2SLS " as result %7.3f `iv' " (" %6.3f `ivse' ")" ///
                as text "  F " as result %6.1f `F' as text "  N " as result `N' ///
                as text "  pre-mean " as result %6.1f `ym'
        }
    }
}
postclose R

/**********************************************************************
* Table
**********************************************************************/

capture program drop ir_row
program define ir_row
    args fh lab d y stat fmt cols
    file write `fh' "`lab'"
    foreach c of local cols {
        local b "${S_`d'_`y'_`c'_`stat'}"
        local p "${S_`d'_`y'_`c'_`stat'p}"
        if "`p'" != "" {
            oe_stars `p'
            local st "`r(stars)'"
        }
        else local st ""
        file write `fh' " & " `fmt' (`b') "`st'"
    }
    file write `fh' " \\" _n
    foreach c of local cols {
        local se "${S_`d'_`y'_`c'_`stat'se}"
        file write `fh' " & (" `fmt' (`se') ")"
    }
    file write `fh' " \\" _n
end

* full table (both thresholds) and deck table (First Cohort only)
foreach tab in full deck {
local defs = cond("`tab'" == "full", "f m", "f")
local tfile = cond("`tab'" == "full", "oe_2sls_design2_incrank", "oe_2sls_design2_incrank_first")
file open T using "$oe_out/tables/`tfile'.tex", write replace
file write T "\begin{tabular}{lcccc}" _n "\toprule" _n
file write T " & \multicolumn{2}{c}{Selective programs} & \multicolumn{2}{c}{All programs} \\" _n
file write T "\cmidrule(lr){2-3}\cmidrule(lr){4-5}" _n
file write T " & (1) & (2) & (1) & (2) \\" _n "\midrule" _n
foreach d of local defs {
    local dl = cond("`d'" == "f", "A. First Cohort", "B. Minimum Cohort")
    file write T "\multicolumn{5}{l}{\textit{Panel `dl' threshold}} \\" _n
    ir_row T "First stage: \(N_{pt}\) on \(\text{Treated}_{pt}\)" `d' ir fs %6.2f "`cols'"
    file write T "Kleibergen--Paap F"
    foreach c of local cols {
        file write T " & " %6.1f (${S_`d'_ir_`c'_F})
    }
    file write T " \\" _n "\addlinespace" _n
    ir_row T "Reduced form: income rank" `d' ir rf %6.2f "`cols'"
    file write T "\addlinespace" _n "\multicolumn{5}{l}{2SLS, per additional entrant} \\" _n
    foreach y of local yrows {
        ir_row T "\quad `lab_`y''" `d' `y' iv %6.3f "`cols'"
    }
    file write T "\addlinespace" _n "Pre-shock mean, income rank, treated"
    foreach c of local cols {
        file write T " & " %5.1f (${S_`d'_ir_`c'_ym})
    }
    file write T " \\" _n "Program-years"
    foreach c of local cols {
        file write T " & " %6.0fc (${S_`d'_ir_`c'_N})
    }
    file write T " \\" _n
    if "`d'" == "f" & "`tab'" == "full" file write T "\midrule" _n
}
file write T "\midrule" _n
file write T "Program and year FE & \checkmark & & \checkmark & \\" _n
file write T "Program, university \(\times\) year FE & & \checkmark & & \checkmark \\" _n
file write T "\bottomrule" _n "\end{tabular}" _n
file close T
}
macro drop S_*

/**********************************************************************
* Reduced-form event study, selective programs, income rank (First Cohort)
**********************************************************************/

keep if selective
foreach fe in fe1 fe2 {
    local abs = cond("`fe'" == "fe1", "pid ao_proceso", "pid uy")
    oe_es ir_f, g(g_main) rel(rel_main) absorb(`abs') cluster(pid) ///
        ylab("Income rank of program of graduation, First Cohort") ///
        xlab("Years since first own vacancy shock") ///
        file("$oe_out/figures/oe_ir_rf_es_ir_f_`fe'.pdf")
    di as text "ir_f `fe': TWFE leads p = " as result %5.3f r(pTWFE) ///
        as text "  CS never Pre_avg p = " as result %5.3f r(pCSnv) ///
        as text "  CS not yet Pre_avg p = " as result %5.3f r(pCSny) ///
        as text "  CS ny ATT = " as result %6.2f r(attCSny) " (" %5.2f r(seCSny) ")"
}

use "`c(tmpdir)'/oe_ir.dta", clear
export delimited using "$oe_out/tables/oe_2sls_design2_incrank.csv", replace
di as result "Design II income rank written."
