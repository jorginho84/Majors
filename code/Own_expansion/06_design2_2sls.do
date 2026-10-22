/**********************************************************************
* 06_design2_2sls.do
*
* Design II, 2SLS (issue #3): effect of the size of the entering cohort
* on inframarginal graduation, with the program's own sudden vacancy
* expansion as the instrument.
*
*   First stage:  N_pt = pi   Post_pt + FE + v
*   Reduced form: y_pt = rho  Post_pt + FE + u
*   2SLS:         y_pt = beta N^_pt   + FE + e,   beta = rho / pi
*
*   N  : first-year enrollment (Formulario D), N_first
*   y  : graduation rate (pct.) of the program-year's inframarginal
*        applicants, as in Design I (21b panels): from the program of
*        first enrollment, any university, any HE; 8 years (10 years for
*        the program outcome, cohorts <= 2014)
*   Inframarginal definitions: First Cohort (main), Minimum Cohort
*   FE : (1) program + year; (2) program + university x year
*   Samples: selective programs (main), all incumbent programs
*   Unweighted, as the reduced form in 05. SE clustered by program.
*   Each regression uses the program-years with a non-missing outcome, so
*   FS, RF and 2SLS share one sample.
*
* Inputs: oe_panel.dta (02), oe_infra_outcomes.dta (05)
* Output: output/own_expansion/tables/oe_2sls_design2.tex
*         output/own_expansion/figures/oe_2sls_rf_es_<y>_<fe>.pdf (reduced-form
*         event studies, selective programs)
**********************************************************************/

do "code/config.do"
do "code/Own_expansion/00_helpers.do"

global oe_out "$output/own_expansion"

use "$processed/oe_panel.dta", clear
merge 1:1 code_h ao_proceso using "$processed/oe_infra_outcomes.dta", ///
    keep(master match) nogen

local yrows g8p g8u g8h g10p
local lab_g8p  "Graduation from the program, 8y"
local lab_g8u  "Graduation from any university, 8y"
local lab_g8h  "Graduation from any HE, 8y"
local lab_g10p "Graduation from the program, 10y"

local cols "sel_fe1 sel_fe2 all_fe1 all_fe2"


/**********************************************************************
* 1. Estimates
**********************************************************************/

foreach d in f m {
    foreach y of local yrows {
        foreach c of local cols {
            local s  = substr("`c'", 1, 3)
            local fe = substr("`c'", 5, 3)
            local abs = cond("`fe'" == "fe1", "pid ao_proceso", "pid uy")
            local if "if !missing(`y'_`d')"
            if "`s'" == "sel" local if "`if' & selective"

            quietly reghdfe N_first post_main `if', absorb(`abs') cluster(pid)
            local `d'_`y'_`c'_fs   = _b[post_main]
            local `d'_`y'_`c'_fsse = _se[post_main]
            local `d'_`y'_`c'_fsp  = 2 * ttail(e(df_r), abs(_b[post_main] / _se[post_main]))

            quietly reghdfe `y'_`d' post_main `if', absorb(`abs') cluster(pid)
            local `d'_`y'_`c'_rf   = _b[post_main]
            local `d'_`y'_`c'_rfse = _se[post_main]
            local `d'_`y'_`c'_rfp  = 2 * ttail(e(df_r), abs(_b[post_main] / _se[post_main]))

            quietly ivreghdfe `y'_`d' (N_first = post_main) `if', absorb(`abs') cluster(pid)
            local `d'_`y'_`c'_iv   = _b[N_first]
            local `d'_`y'_`c'_ivse = _se[N_first]
            local `d'_`y'_`c'_ivp  = 2 * normal(-abs(_b[N_first] / _se[N_first]))
            local `d'_`y'_`c'_F    = e(widstat)
            local `d'_`y'_`c'_N    = e(N)

            * pre-shock mean of the outcome among treated programs
            quietly summarize `y'_`d' `if' & g_main > 0 & post_main == 0
            local `d'_`y'_`c'_ym = r(mean)

            di as text "`d' `y' `c': FS " as result %6.2f ``d'_`y'_`c'_fs' ///
                as text "  RF " as result %6.2f ``d'_`y'_`c'_rf' ///
                as text "  2SLS " as result %7.3f ``d'_`y'_`c'_iv' " (" %6.3f ``d'_`y'_`c'_ivse' ")" ///
                as text "  F " as result %6.1f ``d'_`y'_`c'_F' as text "  N " as result ``d'_`y'_`c'_N'
        }
    }
}


/**********************************************************************
* 2. Table: panels by definition, columns sample x FE
**********************************************************************/

capture program drop oe_row
program define oe_row
    * one coefficient row and its SE row; stat in {fs rf iv}
    args fh lab d y stat fmt cols
    file write `fh' "`lab'"
    foreach c of local cols {
        local b "${S_`d'_`y'_`c'_`stat'}"
        local p "${S_`d'_`y'_`c'_`stat'p}"
        oe_stars `p'
        file write `fh' " & " `fmt' (`b') "`r(stars)'"
    }
    file write `fh' " \\" _n
    foreach c of local cols {
        local se "${S_`d'_`y'_`c'_`stat'se}"
        file write `fh' " & (" `fmt' (`se') ")"
    }
    file write `fh' " \\" _n
end

* pass the locals to oe_row through globals
foreach d in f m {
    foreach y of local yrows {
        foreach c of local cols {
            foreach k in fs fsse fsp rf rfse rfp iv ivse ivp F N ym {
                global S_`d'_`y'_`c'_`k' "``d'_`y'_`c'_`k''"
            }
        }
    }
}

file open T using "$oe_out/tables/oe_2sls_design2.tex", write replace
file write T "\begin{tabular}{lcccc}" _n "\toprule" _n
file write T " & \multicolumn{2}{c}{Selective programs} & \multicolumn{2}{c}{All programs} \\" _n
file write T "\cmidrule(lr){2-3}\cmidrule(lr){4-5}" _n
file write T " & (1) & (2) & (1) & (2) \\" _n "\midrule" _n
foreach d in f m {
    local dl = cond("`d'" == "f", "A. First Cohort", "B. Minimum Cohort")
    file write T "\multicolumn{5}{l}{\textit{Panel `dl' threshold}} \\" _n
    oe_row T "First stage: \(N_{pt}\) on \(\text{Treated}_{pt}\)" `d' g8p fs %6.2f "`cols'"
    file write T "Kleibergen--Paap F"
    foreach c of local cols {
        file write T " & " %6.1f (${S_`d'_g8p_`c'_F})
    }
    file write T " \\" _n "\addlinespace" _n
    oe_row T "Reduced form: program graduation, 8y" `d' g8p rf %6.2f "`cols'"
    file write T "\addlinespace" _n "\multicolumn{5}{l}{2SLS: pp of graduation per additional entrant} \\" _n
    foreach y of local yrows {
        oe_row T "\quad `lab_`y''" `d' `y' iv %6.3f "`cols'"
    }
    file write T "\addlinespace" _n "Pre-shock mean, program graduation 8y, treated (\%)"
    foreach c of local cols {
        file write T " & " %5.1f (${S_`d'_g8p_`c'_ym})
    }
    file write T " \\" _n "Program-years (8y)"
    foreach c of local cols {
        file write T " & " %6.0fc (${S_`d'_g8p_`c'_N})
    }
    file write T " \\" _n
    if "`d'" == "f" file write T "\midrule" _n
}
file write T "\midrule" _n
file write T "Program and year FE & \checkmark & & \checkmark & \\" _n
file write T "Program, university \(\times\) year FE & & \checkmark & & \checkmark \\" _n
file write T "\bottomrule" _n "\end{tabular}" _n
file close T

macro drop S_*


/**********************************************************************
* 3. Reduced-form event studies, selective programs
*    Outcome: the second-stage y; event time around g_main (the shock).
*    TWFE with FE (1) or (2), plus CS (never / not yet, program + year).
**********************************************************************/

keep if selective
foreach y in g8p_f g8p_m g8u_f {
    if "`y'" == "g8p_f" local ylab "Program graduation 8y, First Cohort (pct.)"
    if "`y'" == "g8p_m" local ylab "Program graduation 8y, Minimum Cohort (pct.)"
    if "`y'" == "g8u_f" local ylab "University graduation 8y, First Cohort (pct.)"
    foreach fe in fe1 fe2 {
        local abs = cond("`fe'" == "fe1", "pid ao_proceso", "pid uy")
        oe_es `y', g(g_main) rel(rel_main) absorb(`abs') cluster(pid) ///
            ylab("`ylab'") xlab("Years since first own vacancy shock") ///
            file("$oe_out/figures/oe_2sls_rf_es_`y'_`fe'.pdf")
        di as text "`y' `fe': TWFE leads p = " as result %5.3f r(pTWFE) ///
            as text "  CS never Pre_avg p = " as result %5.3f r(pCSnv) ///
            as text "  CS not yet Pre_avg p = " as result %5.3f r(pCSny)
    }
}

di as result "Design II 2SLS written."
