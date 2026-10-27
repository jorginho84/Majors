/**********************************************************************
* 00_va_helpers.do
*
* Program value-added (issue #9): shared programs for 02 and 04.
*   pva_controls   standardized scores + missing indicators; sets $X
*   id_sample      identifying sample (>= 2 options, >= 2 students,
*                  variation in S within portfolio) on the largest
*                  connected set
*   connected_set  largest connected set of treatments via portfolios
*   va_reg         estimate VA, centre on the weighted mean (full vcov)
*   va_disp        signal / noise SD (MH eq. 10)
**********************************************************************/

capture program drop pva_controls
program define pva_controls
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
end

capture program drop id_sample
program define id_sample
    * expects S (treatment), P (portfolio); nopt = number of options
    args nopt
    * identifying sample: >= 2 options, >= 2 students, variation in S
    gen int nopt = `nopt'
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

end

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

