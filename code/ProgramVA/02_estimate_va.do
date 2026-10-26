/**********************************************************************
* 02_estimate_va.do
*
* Program value-added (issue #9), Mountjoy & Hickman (2021) adapted to
* the DEMRE deferred acceptance.
*
*   Y_i = sum_j v_j 1[S_i = j] + phi_{A_i} + g(scores_i) + X_i'b + e_i
*
* Ladder (MH Fig. 3/5), all on the same identifying, connected sample:
*   raw       cohort FE
*   typical   cohort FE + controls
*   baseline  portfolio FE (cohort x unordered feasible set)
*   main      portfolio FE + controls
* Balance (MH Fig. 2): covariate-predicted Y on program dummies, raw and
* with portfolio FE.
*
* Versions:
*   itt  S = assigned program, A = feasible set (port_bin)
*   enr  S = enrolled program (on the ROL), A = feasible set incl. it
*   ter  S = assigned program, A = feasible x infeasible set (port_ter)
* Levels: program (harmonized code) and university.
*
* v_j is reported relative to the enrollment-weighted mean over the
* connected set; the full vcov is carried through the centering.
* Dispersion: signal SD = sqrt(Var(v) - mean(SE^2)), enrollment weighted
* (MH eq. 10). EB: v * s2 / (s2 + SE^2).
*
* Outcomes: inc_rank (main; Mi Futuro income rank of the program the
* student graduates from, 0 if no title, see 01b) and grad_any_8y.
*
* Input:   $processed/pva_students_2007_2016.dta
* Output:  $processed/pva_program_va.dta, $processed/pva_univ_va.dta
*          output/tables/pva_dispersion.csv
**********************************************************************/

clear all
set more off
do "code/config.do"

do "code/ProgramVA/00_va_helpers.do"

capture log close
log using "$logs/pva_02_estimate_va.log", replace text

local outcomes inc_rank grad_any_8y

/**********************************************************************
* 0. Controls and predicted outcomes
**********************************************************************/

use "$processed/pva_students_2007_2016.dta", clear

pva_controls

* covariate-predicted outcomes (MH Fig. 2), cohort FE included
foreach y of local outcomes {
    quietly reg `y' $X i.ao_proceso
    predict double p_`y', xb
}

tempfile base
save `base'

/**********************************************************************
* 2. Ladder by version and level
**********************************************************************/

tempname disp
postfile `disp' str4 version str7 level str16 outcome str10 spec ///
    double(sd_hat sd_noise sd_signal corr_raw) long(N K) ///
    using "$processed/pva_dispersion.dta", replace

foreach version in itt enr ter {
foreach level in program univ {

    use `base', clear
    if "`version'" == "itt" {
        gen long S = S_itt
        gen long P = port_bin
        gen str5 U = univ_itt
    }
    if "`version'" == "enr" {
        gen long S = S_enr if enr_on_rol
        gen long P = port_enr
        gen str5 U = univ_enr if enr_on_rol
    }
    if "`version'" == "ter" {
        gen long S = S_itt
        gen long P = port_ter
        gen str5 U = univ_itt
    }
    if "`level'" == "univ" {
        drop S
        encode U, gen(S)
    }
    keep if !missing(S, P)

    * identifying sample on the largest connected set
    id_sample `=cond("`version'" == "enr", "n_feas_enr", "n_feas")'

    di as result _n "===== version `version', level `level' ====="
    count
    distinct P S

    * program-level frame, one row per treatment level
    capture frame drop fr
    frame put S, into(fr)
    frame fr {
        bysort S: gen long n_obs = _N
        bysort S: keep if _n == 1
        sort S
    }

    foreach y of local outcomes {
        local yy = cond("`y'" == "inc_rank", "inc", "grad")
        frame fr: gen double mean_`yy' = .
        * raw mean by treatment, for reference
        preserve
            collapse (mean) m = `y', by(S)
            tempfile mm
            save `mm'
        restore
        frame fr {
            quietly merge 1:1 S using `mm', nogen
            replace mean_`yy' = m
            drop m
        }

        va_reg `y',      s(S) tag(`yy'_raw)  frame(fr)
        va_reg `y',      s(S) tag(`yy'_typ)  frame(fr) controls
        va_reg `y',      s(S) tag(`yy'_base) frame(fr) absorb(P)
        va_reg `y',      s(S) tag(`yy'_main) frame(fr) absorb(P) controls
        va_reg p_`y',    s(S) tag(`yy'_balraw)  frame(fr)
        va_reg p_`y',    s(S) tag(`yy'_balbase) frame(fr) absorb(P)

        frame fr {
            foreach sp in raw typ base main balraw balbase {
                va_disp v_`yy'_`sp' se_`yy'_`sp' n_obs
                local h  = r(sd_hat)
                local nz = r(sd_noise)
                local s0 = r(sd_signal)
                quietly corr v_`yy'_`sp' v_`yy'_raw [aw = n_obs]
                local cr = r(rho)
                * signal correction (MH fn. 41): raw is precisely measured
                if `s0' > 0 local cr = `cr' * `h' / `s0'
                quietly count if !missing(v_`yy'_`sp')
                local K = r(N)
                quietly summarize n_obs
                post `disp' ("`version'") ("`level'") ("`y'") ("`sp'") ///
                    (`h') (`nz') (`s0') (`cr') (r(sum)) (`K')
                di as text "  `sp': SD hat " %7.4f `h' "  SD signal " %7.4f `s0' ///
                    "  corr w/ raw (signal) " %6.3f `cr'
            }
            * EB-shrunk main VA
            va_disp v_`yy'_main se_`yy'_main n_obs
            local s2 = r(sd_signal)^2
            gen double v_`yy'_eb = v_`yy'_main * `s2' / (`s2' + se_`yy'_main^2)
        }
    }

    frame fr {
        gen str4 version = "`version'"
        if "`level'" == "program" rename S code_h
        tempfile r_`version'_`level'
        save `r_`version'_`level''
    }
}
}
postclose `disp'

* stack versions
foreach level in program univ {
    clear
    foreach version in itt enr ter {
        append using `r_`version'_`level''
    }
    compress
    save "$processed/pva_`level'_va.dta", replace
}

use "$processed/pva_dispersion.dta", clear
format sd_* corr_raw %9.4f
list, noobs sepby(version level outcome) abbrev(10)
export delimited using "$output/tables/pva_dispersion.csv", replace

log close
