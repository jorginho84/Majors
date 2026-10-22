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

capture log close
log using "$logs/pva_02_estimate_va.log", replace text

local outcomes inc_rank grad_any_8y

/**********************************************************************
* 0. Controls and predicted outcomes
**********************************************************************/

use "$processed/pva_students_2007_2016.dta", clear

* missing scores (ranking exists from 2013 on): zero + indicator
foreach v in psu_lm nem rank {
    gen byte mi_`v' = missing(`v')
    quietly summarize `v'
    gen double z_`v' = (`v' - r(mean)) / r(sd)
    replace z_`v' = 0 if mi_`v'
}
replace female = 2 if missing(female)
replace dep = 9 if missing(dep)

global X c.z_psu_lm##c.z_psu_lm##c.z_psu_lm ///
         c.z_nem##c.z_nem##c.z_nem c.z_rank##c.z_rank##c.z_rank ///
         c.z_psu_lm#c.z_nem mi_psu_lm mi_nem mi_rank i.female i.dep

* covariate-predicted outcomes (MH Fig. 2), cohort FE included
foreach y of local outcomes {
    quietly reg `y' $X i.ao_proceso
    predict double p_`y', xb
}

tempfile base
save `base'

/**********************************************************************
* 1. Helpers
**********************************************************************/

* largest connected set of treatments linked through shared portfolios
* (label propagation on the bipartite program-portfolio graph)
capture program drop connected_set
program define connected_set
    args S P out
    preserve
        keep `S' `P'
        duplicates drop
        gen long comp = `S'
        local changed = 1
        local it = 0
        while `changed' > 0 & `it' < 200 {
            bysort `P': egen long cp = min(comp)
            bysort `S': egen long cs = min(cp)
            count if cs != comp
            local changed = r(N)
            replace comp = cs
            drop cp cs
            local ++it
        }
        bysort `S': keep if _n == 1
        bysort comp: gen long ncomp = _N
        quietly summarize ncomp
        gen byte `out' = ncomp == r(max)
        di as text "connected set: " r(max) " of " _N " treatments (" `it' " iterations)"
        keep `S' `out'
        tempfile cs
        save `cs'
    restore
    merge m:1 `S' using `cs', keep(1 3) nogen
end

* estimate, then centre v on the enrollment-weighted mean with full vcov
* stores results in a program-level frame `fr' with variables v_`tag' se_`tag'
capture program drop va_reg
program define va_reg
    syntax varname, S(varname) tag(string) frame(string) [absorb(string) controls]
    quietly levelsof `s', local(levs)
    * base = largest treatment
    tempvar n
    bysort `s': gen long `n' = _N
    quietly summarize `n'
    quietly levelsof `s' if `n' == r(max), local(b)
    local b : word 1 of `b'
    local ctl = cond("`controls'" != "", "$X", "")
    if "`absorb'" == "" local absorb ao_proceso
    quietly reghdfe `varlist' ib`b'.`s' `ctl', absorb(`absorb') vce(robust)
    di as text "  `tag': N = " e(N) ", R2 = " %6.4f e(r2)

    * collect coefficients in order of levels; omitted -> missing
    tempname B V
    matrix `B' = e(b)
    matrix `V' = e(V)
    mata: va_collect("`B'", "`V'", "`s'", "`levs'")
    * va_collect leaves the coefficients and vcov in Mata externals
    frame `frame' {
        mata: va_store("v_`tag'", "se_`tag'")
    }
end

mata:
void va_collect(string scalar Bn, string scalar Vn, string scalar s, string scalar levs)
{
    real rowvector b
    real matrix V
    string matrix cs
    string rowvector L
    real scalar k, j, K
    external real colvector _idx, _bb
    external real matrix _VV
    b  = st_matrix(Bn)
    V  = st_matrix(Vn)
    cs = st_matrixcolstripe(Bn)
    L  = tokens(levs)
    K  = cols(L)
    _idx = J(K, 1, .)
    for (k = 1; k <= K; k++) {
        for (j = 1; j <= cols(b); j++) {
            if (cs[j, 2] == L[k] + "." + s | cs[j, 2] == L[k] + "b." + s) {
                if (V[j, j] > 0 | strpos(cs[j, 2], "b.")) _idx[k] = j
            }
        }
    }
    _bb = J(K, 1, .)
    _VV = J(K, K, 0)
    for (k = 1; k <= K; k++) {
        if (_idx[k] < .) {
            _bb[k] = b[_idx[k]]
            for (j = 1; j <= K; j++) {
                if (_idx[j] < .) _VV[k, j] = V[_idx[k], _idx[j]]
            }
        }
    }
}

void va_store(string scalar vname, string scalar sename)
{
    real colvector w, ok, v, se
    real matrix M, Vc
    real scalar K
    external real colvector _bb
    external real matrix _VV
    // frame rows are the treatment levels in the same order; weights = n
    w  = st_data(., "n_obs")
    ok = (_bb :< .)
    w  = w :* ok
    w  = w / sum(w)
    K  = rows(_bb)
    v  = editmissing(_bb, 0)
    M  = I(K) - J(K, 1, 1) * w'
    v  = M * v
    Vc = M * _VV * M'
    se = sqrt(diagonal(Vc))
    v  = v  :/ ok
    se = se :/ ok
    (void) st_addvar("double", vname)
    (void) st_addvar("double", sename)
    st_store(., vname, v)
    st_store(., sename, se)
}
end

* dispersion summary (MH Table 3) for one estimate pair
capture program drop va_disp
program define va_disp, rclass
    args v se w
    quietly summarize `v' [aw = `w']
    local var_hat = r(Var) * (r(sum_w) - 1) / r(sum_w)
    tempvar se2
    gen double `se2' = `se'^2
    quietly summarize `se2' [aw = `w']
    local var_e = r(mean)
    return scalar sd_hat    = sqrt(`var_hat')
    return scalar sd_noise  = sqrt(`var_e')
    return scalar sd_signal = sqrt(max(`var_hat' - `var_e', 0))
end

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

    * identifying sample: >= 2 options, >= 2 students, variation in S
    gen int nopt = cond("`version'" == "enr", n_feas_enr, n_feas)
    keep if nopt >= 2
    bysort P: gen long nP = _N
    bysort P S: gen byte tagPS = _n == 1
    bysort P: egen int nS = total(tagPS)
    keep if nP >= 2 & nS >= 2
    drop tagPS

    connected_set S P incs
    keep if incs == 1
    * after dropping, re-impose variation within portfolio
    bysort P S: gen byte tagPS = _n == 1
    bysort P: egen int nS2 = total(tagPS)
    keep if nS2 >= 2
    drop tagPS nS2

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
