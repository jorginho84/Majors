/**********************************************************************
* 05_twfe.do
*
* Design III — TWFE regressions of incumbent first-year enrollment on
* cumulative exposure to competitor vacancy shocks, mirroring the
* Design II (SUA entry) first-stage tables.
*
*   N_kt = pi * cumE^{w,f}_kt + delta * own_cumshock_kt
*          + mu_k + alpha_{f(k),t} [+ gamma_{r(k),t}] + e_kt
*
* cumE is the time-varying analogue of E_p x Post_t in Design II. Market
* measures in 10 percentage-point units; cosine in SD units. SE clustered
* by pre-period market (market measures) or program (cosine).
*
* Tables (output/vacancy_shocks/tables/):
*   vs_fs_levels.tex      Total/Triangular/Gaussian x Broad/ISCED/Generic x FE
*   vs_fs_logs.tex        log-log version with zero-exposure indicator
*   vs_fs_q.tex           conditional similarity Q, levels and logs
*   vs_fs_selectivity.tex heterogeneity by incumbent PSU
*   vs_fs_cosine.tex      cosine measures x FE x sample
*   vs_fs_levels_kd.tex   kernel-denominator (KD) measures, levels
*   vs_fs_logs_kd.tex     KD measures, logs
*   vs_fs_kd_trim.tex     KD, excluding the top 1% / 5% of exposure
*   vs_fs_shockdefs.tex   Total, Gaussian and Gaussian KD (Broad) across shock definitions
*
* Input: $processed/vs_panel_exposure.dta
**********************************************************************/

do "code/config.do"

global vs_out "$output/vacancy_shocks"
cap mkdir "$vs_out/tables"

use "$processed/vs_panel_exposure.dta", clear
keep if est_sample
xtset pid ao_proceso

egen long ry = group(region ao_proceso)
egen long yr = group(ao_proceso)
foreach f in broad isced generic {
    local fv = cond("`f'" == "broad", "field", "`f'_field")
    egen long fy_`f' = group(`fv' ao_proceso)
    egen long my_`f' = group(mkt_`f' ao_proceso)
}

* regressors in reporting units
foreach f in broad isced generic {
    foreach w in tot tri gau {
        gen double x_`w'_`f' = cumE_`w'_`f' / 10
        gen double lx_`w'_`f' = cond(cumE_`w'_`f' > 0, ln(cumE_`w'_`f'), 0) if !missing(cumE_`w'_`f')
        gen byte   dx_`w'_`f' = cumE_`w'_`f' > 0 if !missing(cumE_`w'_`f')
    }
    foreach w in tri gau {
        gen double q_`w'_`f'  = cond(D_mkt_`f' == 1, Q_`w'_`f' / 0.10, 0) if !missing(D_mkt_`f')
        gen double lq_`w'_`f' = cond(Q_`w'_`f' > 0 & !missing(Q_`w'_`f'), ln(Q_`w'_`f'), 0) if !missing(D_mkt_`f')
        gen byte   dq_`w'_`f' = Q_`w'_`f' > 0 & !missing(Q_`w'_`f') if !missing(D_mkt_`f')
    }
}
foreach d in psu psuR psuRF psu_pR psu_pRF {
    quietly summarize cumE_cos_`d'
    gen double z_cos_`d' = cumE_cos_`d' / r(sd)
    gen double z_cos_`d'_m10 = .
    quietly summarize cumE_cos_`d' if min10
    replace z_cos_`d'_m10 = cumE_cos_`d' / r(sd) if min10
}
foreach f in broad isced generic {
    foreach w in trikd gaukd {
        gen double x_`w'_`f' = cumE_`w'_`f' / 10
        gen double lx_`w'_`f' = cond(cumE_`w'_`f' > 0, ln(cumE_`w'_`f'), 0) if !missing(cumE_`w'_`f')
        gen byte   dx_`w'_`f' = cumE_`w'_`f' > 0 if !missing(cumE_`w'_`f')
    }
}
foreach t in p90 p75 within nosud lev ind adm {
    foreach w in tot gau gaukd {
        gen double x_`w'_broad_`t' = cumE_`w'_broad_`t' / 10
    }
}

* run one regression and return the cell statistics as locals
capture program drop fsreg
program define fsreg
    syntax varlist [if], x(varname) absorb(string) cluster(varname) [PREfix(string)]
    reghdfe `varlist' `if', absorb(`absorb') cluster(`cluster')
    tempvar t
    quietly egen byte `t' = tag(pid) if e(sample)
    quietly count if `t' == 1
    local np = r(N)
    c_local `prefix'b  = _b[`x']
    c_local `prefix'se = _se[`x']
    c_local `prefix'F  = (_b[`x'] / _se[`x'])^2
    c_local `prefix'p  = 2 * ttail(e(df_r), abs(_b[`x'] / _se[`x']))
    c_local `prefix'N  = e(N)
    c_local `prefix'np = `np'
    c_local `prefix'nc = e(N_clust)
end

capture program drop stars
program define stars
    args p name
    c_local `name' = cond(`p' < 0.01, "\sym{***}", cond(`p' < 0.05, "\sym{**}", cond(`p' < 0.10, "\sym{*}", "")))
end


/**********************************************************************
* 1. Levels: 3 kernels x 3 field definitions x 2 FE sets
**********************************************************************/

local cols
foreach fe in f fr {
    foreach f in broad isced generic {
        local abs = cond("`fe'" == "f", "pid fy_`f'", "pid fy_`f' ry")
        foreach w in tot tri gau {
            fsreg N_first x_`w'_`f' own_cumshock, x(x_`w'_`f') absorb(`abs') ///
                cluster(mkt_`f') prefix(`w'_`fe'_`f'_)
        }
    }
}

file open T using "$vs_out/tables/vs_fs_levels.tex", write replace
file write T "\begin{tabular}{lcccccc}" _n "\toprule" _n
file write T " & \multicolumn{3}{c}{Field \(\times\) year FE} & \multicolumn{3}{c}{\(+\) Region \(\times\) year FE} \\" _n
file write T "\cmidrule(lr){2-4}\cmidrule(lr){5-7}" _n
file write T "Exposure measure & Broad & ISCED-97 & Generic & Broad & ISCED-97 & Generic \\" _n "\midrule" _n
foreach w in tot tri gau {
    local wl = cond("`w'" == "tot", "Total", cond("`w'" == "tri", "Triangular", "Gaussian"))
    file write T "\textit{`wl'}"
    foreach fe in f fr {
        foreach f in broad isced generic {
            stars ``w'_`fe'_`f'_p' st
            file write T " & " %6.3f (``w'_`fe'_`f'_b') "`st'"
        }
    }
    file write T " \\" _n
    foreach fe in f fr {
        foreach f in broad isced generic {
            file write T " & (" %5.3f (``w'_`fe'_`f'_se') ")"
        }
    }
    file write T " \\" _n "\quad Wald \(F\)"
    foreach fe in f fr {
        foreach f in broad isced generic {
            file write T " & " %5.2f (``w'_`fe'_`f'_F')
        }
    }
    file write T " \\" _n
    if "`w'" != "gau" file write T "\addlinespace" _n
}
file write T "\midrule" _n
foreach s in N np nc {
    local sl = cond("`s'" == "N", "Observations", cond("`s'" == "np", "Programs", "Markets"))
    file write T "`sl'"
    foreach fe in f fr {
        foreach f in broad isced generic {
            file write T " & " %9.0fc (`tot_`fe'_`f'_`s'')
        }
    }
    file write T " \\" _n
}
file write T "Program FE & Yes & Yes & Yes & Yes & Yes & Yes \\" _n
file write T "Field \(\times\) year FE & Yes & Yes & Yes & Yes & Yes & Yes \\" _n
file write T "Region \(\times\) year FE & No & No & No & Yes & Yes & Yes \\" _n
file write T "\bottomrule" _n "\end{tabular}" _n
file close T


/**********************************************************************
* 2. Logs: log N on log(cumE) with zero-exposure indicator
**********************************************************************/

foreach fe in f fr {
    foreach f in broad isced generic {
        local abs = cond("`fe'" == "f", "pid fy_`f'", "pid fy_`f' ry")
        foreach w in tot tri gau {
            fsreg lnN lx_`w'_`f' dx_`w'_`f' own_cumshock, x(lx_`w'_`f') absorb(`abs') ///
                cluster(mkt_`f') prefix(`w'_`fe'_`f'_)
        }
    }
}

file open T using "$vs_out/tables/vs_fs_logs.tex", write replace
file write T "\begin{tabular}{lcccccc}" _n "\toprule" _n
file write T " & \multicolumn{3}{c}{Field \(\times\) year FE} & \multicolumn{3}{c}{\(+\) Region \(\times\) year FE} \\" _n
file write T "\cmidrule(lr){2-4}\cmidrule(lr){5-7}" _n
file write T "Exposure measure & Broad & ISCED-97 & Generic & Broad & ISCED-97 & Generic \\" _n "\midrule" _n
foreach w in tot tri gau {
    local wl = cond("`w'" == "tot", "Total", cond("`w'" == "tri", "Triangular", "Gaussian"))
    file write T "\textit{`wl'}"
    foreach fe in f fr {
        foreach f in broad isced generic {
            stars ``w'_`fe'_`f'_p' st
            file write T " & " %6.3f (``w'_`fe'_`f'_b') "`st' (" %5.3f (``w'_`fe'_`f'_se') ")"
        }
    }
    file write T " \\" _n "\quad \(F\)"
    foreach fe in f fr {
        foreach f in broad isced generic {
            file write T " & " %5.2f (``w'_`fe'_`f'_F')
        }
    }
    file write T " \\" _n
    if "`w'" != "gau" file write T "\addlinespace" _n
}
file write T "\midrule" _n
foreach s in N np {
    local sl = cond("`s'" == "N", "Observations", "Programs")
    file write T "`sl'"
    foreach fe in f fr {
        foreach f in broad isced generic {
            file write T " & " %9.0fc (`tot_`fe'_`f'_`s'')
        }
    }
    file write T " \\" _n
}
file write T "\bottomrule" _n "\end{tabular}" _n
file close T


/**********************************************************************
* 2b. Kernel-denominator (KD) exposure: levels and logs
**********************************************************************/

foreach spec in lev log {
    foreach fe in f fr {
        foreach f in broad isced generic {
            local abs = cond("`fe'" == "f", "pid fy_`f'", "pid fy_`f' ry")
            foreach w in tot trikd gaukd {
                if "`spec'" == "lev" fsreg N_first x_`w'_`f' own_cumshock, x(x_`w'_`f') ///
                    absorb(`abs') cluster(mkt_`f') prefix(`w'_`fe'_`f'_)
                else fsreg lnN lx_`w'_`f' dx_`w'_`f' own_cumshock, x(lx_`w'_`f') ///
                    absorb(`abs') cluster(mkt_`f') prefix(`w'_`fe'_`f'_)
            }
        }
    }

    file open T using "$vs_out/tables/vs_fs_`=cond("`spec'"=="lev","levels","logs")'_kd.tex", write replace
    file write T "\begin{tabular}{lcccccc}" _n "\toprule" _n
    file write T " & \multicolumn{3}{c}{Field \(\times\) year FE} & \multicolumn{3}{c}{\(+\) Region \(\times\) year FE} \\" _n
    file write T "\cmidrule(lr){2-4}\cmidrule(lr){5-7}" _n
    file write T "Exposure measure & Broad & ISCED-97 & Generic & Broad & ISCED-97 & Generic \\" _n "\midrule" _n
    foreach w in tot trikd gaukd {
        local wl = cond("`w'" == "tot", "Total", cond("`w'" == "trikd", "Triangular KD", "Gaussian KD"))
        file write T "\textit{`wl'}"
        foreach fe in f fr {
            foreach f in broad isced generic {
                stars ``w'_`fe'_`f'_p' st
                file write T " & " %6.3f (``w'_`fe'_`f'_b') "`st'"
            }
        }
        file write T " \\" _n
        foreach fe in f fr {
            foreach f in broad isced generic {
                file write T " & (" %5.3f (``w'_`fe'_`f'_se') ")"
            }
        }
        file write T " \\" _n "\quad Wald \(F\)"
        foreach fe in f fr {
            foreach f in broad isced generic {
                file write T " & " %5.2f (``w'_`fe'_`f'_F')
            }
        }
        file write T " \\" _n
        if "`w'" != "gaukd" file write T "\addlinespace" _n
    }
    file write T "\midrule" _n
    foreach s in N np nc {
        local sl = cond("`s'" == "N", "Observations", cond("`s'" == "np", "Programs", "Markets"))
        file write T "`sl'"
        foreach fe in f fr {
            foreach f in broad isced generic {
                file write T " & " %9.0fc (`gaukd_`fe'_`f'_`s'')
            }
        }
        file write T " \\" _n
    }
    file write T "Region \(\times\) year FE & No & No & No & Yes & Yes & Yes \\" _n
    file write T "\bottomrule" _n "\end{tabular}" _n
    file close T
}

* tails: drop programs whose 2016 KD exposure is above p95 / p99 (Broad, ISCED)
foreach f in broad isced {
    foreach w in trikd gaukd {
        tempvar e16
        bys pid: egen double `e16' = max(cond(ao_proceso == 2016, cumE_`w'_`f', .))
        foreach q in 99 95 {
            quietly _pctile `e16' if ao_proceso == 2016, p(`q')
            local c`q' = r(r1)
        }
        fsreg N_first x_`w'_`f' own_cumshock, x(x_`w'_`f') absorb(pid fy_`f' ry) ///
            cluster(mkt_`f') prefix(t0`w'`f'_)
        fsreg N_first x_`w'_`f' own_cumshock if `e16' <= `c99' | missing(`e16'), x(x_`w'_`f') ///
            absorb(pid fy_`f' ry) cluster(mkt_`f') prefix(t1`w'`f'_)
        fsreg N_first x_`w'_`f' own_cumshock if `e16' <= `c95' | missing(`e16'), x(x_`w'_`f') ///
            absorb(pid fy_`f' ry) cluster(mkt_`f') prefix(t2`w'`f'_)
        drop `e16'
    }
}

file open T using "$vs_out/tables/vs_fs_kd_trim.tex", write replace
file write T "\begin{tabular}{lcccc}" _n "\toprule" _n
file write T " & \multicolumn{2}{c}{Broad} & \multicolumn{2}{c}{ISCED-97} \\" _n
file write T "\cmidrule(lr){2-3}\cmidrule(lr){4-5}" _n
file write T "Sample & Triangular KD & Gaussian KD & Triangular KD & Gaussian KD \\" _n "\midrule" _n
forvalues r = 0/2 {
    local rl = cond(`r' == 0, "All programs", cond(`r' == 1, "Excluding top 1\% of exposure", "Excluding top 5\% of exposure"))
    file write T "`rl'"
    foreach f in broad isced {
        foreach w in trikd gaukd {
            stars `t`r'`w'`f'_p' st
            file write T " & " %6.3f (`t`r'`w'`f'_b') "`st'"
        }
    }
    file write T " \\" _n
    foreach f in broad isced {
        foreach w in trikd gaukd {
            file write T " & (" %5.3f (`t`r'`w'`f'_se') ")"
        }
    }
    file write T " \\" _n " \quad Observations"
    foreach f in broad isced {
        foreach w in trikd gaukd {
            file write T " & " %9.0fc (`t`r'`w'`f'_N')
        }
    }
    file write T " \\" _n
    if `r' < 2 file write T "\addlinespace" _n
}
file write T "\bottomrule" _n "\end{tabular}" _n
file close T


/**********************************************************************
* 3. Conditional similarity Q, markets with a shock (Broad)
**********************************************************************/

local qs "M_broad_2016 > 0 & !missing(M_broad_2016)"
foreach w in tri gau {
    fsreg N_first q_`w'_broad D_mkt_broad own_cumshock if `qs', x(q_`w'_broad) ///
        absorb(pid fy_broad ry) cluster(mkt_broad) prefix(L`w'_)
    fsreg lnN lq_`w'_broad dq_`w'_broad D_mkt_broad own_cumshock if `qs', x(lq_`w'_broad) ///
        absorb(pid fy_broad ry) cluster(mkt_broad) prefix(G`w'_)
}

file open T using "$vs_out/tables/vs_fs_q.tex", write replace
file write T "\begin{tabular}{lcccc}" _n "\toprule" _n
file write T " & \multicolumn{2}{c}{Levels} & \multicolumn{2}{c}{Logs} \\" _n
file write T "\cmidrule(lr){2-3}\cmidrule(lr){4-5}" _n
file write T " & Triangular & Gaussian & Triangular & Gaussian \\" _n "\midrule" _n
file write T "Similarity term"
foreach m in L G {
    foreach w in tri gau {
        stars ``m'`w'_p' st
        file write T " & " %6.3f (``m'`w'_b') "`st'"
    }
}
file write T " \\" _n
foreach m in L G {
    foreach w in tri gau {
        file write T " & (" %5.3f (``m'`w'_se') ")"
    }
}
file write T " \\" _n "Wald \(F\)"
foreach m in L G {
    foreach w in tri gau {
        file write T " & " %5.2f (``m'`w'_F')
    }
}
file write T " \\" _n
foreach s in N np nc {
    local sl = cond("`s'" == "N", "Observations", cond("`s'" == "np", "Programs", "Markets"))
    file write T "`sl'"
    foreach m in L G {
        foreach w in tri gau {
            file write T " & " %9.0fc (``m'`w'_`s'')
        }
    }
    file write T " \\" _n
}
file write T "\bottomrule" _n "\end{tabular}" _n
file close T


/**********************************************************************
* 4. Heterogeneity by incumbent selectivity (Broad)
*    A: exposure, field-year and region-year FE
*    B: Q, market-year FE, markets with a shock
**********************************************************************/

forvalues g = 1/3 {
    foreach w in tri gau {
        fsreg N_first x_`w'_broad own_cumshock if psu_group == `g', x(x_`w'_broad) ///
            absorb(pid fy_broad ry) cluster(mkt_broad) prefix(A`g'`w'_)
        capture noisily fsreg N_first q_`w'_broad own_cumshock if psu_group == `g' & `qs', ///
            x(q_`w'_broad) absorb(pid my_broad) cluster(mkt_broad) prefix(B`g'`w'_)
        if _rc {
            foreach s in b se F p N np nc {
                local B`g'`w'_`s' = .
            }
        }
    }
}

file open T using "$vs_out/tables/vs_fs_selectivity.tex", write replace
file write T "\begin{tabular}{lcccccc}" _n "\toprule" _n
file write T " & \multicolumn{2}{c}{PSU \(<550\)} & \multicolumn{2}{c}{PSU 550--649} & \multicolumn{2}{c}{PSU \(\geq650\)} \\" _n
file write T "\cmidrule(lr){2-3}\cmidrule(lr){4-5}\cmidrule(lr){6-7}" _n
file write T " & Tri. & Gau. & Tri. & Gau. & Tri. & Gau. \\" _n "\midrule" _n
foreach P in A B {
    local pl = cond("`P'" == "A", "Vacancy-shock exposure", "Conditional similarity \(Q\)")
    file write T "\multicolumn{7}{l}{\textit{`pl'}} \\[2pt]" _n "Coefficient"
    forvalues g = 1/3 {
        foreach w in tri gau {
            stars ``P'`g'`w'_p' st
            file write T " & " %6.2f (``P'`g'`w'_b') "`st'"
        }
    }
    file write T " \\" _n
    forvalues g = 1/3 {
        foreach w in tri gau {
            file write T " & (" %5.2f (``P'`g'`w'_se') ")"
        }
    }
    file write T " \\" _n "\(F\)-statistic"
    forvalues g = 1/3 {
        foreach w in tri gau {
            file write T " & " %5.2f (``P'`g'`w'_F')
        }
    }
    file write T " \\" _n
    foreach s in N np nc {
        local sl = cond("`s'" == "N", "Observations", cond("`s'" == "np", "Programs", "Clusters"))
        file write T "`sl'"
        forvalues g = 1/3 {
            file write T " & \multicolumn{2}{c}{" %9.0fc (``P'`g'tri_`s'') "}"
        }
        file write T " \\" _n
    }
    if "`P'" == "A" file write T "\midrule" _n
}
file write T "\bottomrule" _n "\end{tabular}" _n
file close T


/**********************************************************************
* 5. Cosine exposure: 5 measures x 3 FE sets x 2 samples
**********************************************************************/

foreach s in all m10 {
    local sfx = cond("`s'" == "m10", "_m10", "")
    local cnd = cond("`s'" == "m10", "if min10", "")
    foreach d in psu psuR psuRF psu_pR psu_pRF {
        fsreg N_first z_cos_`d'`sfx' own_cumshock `cnd', x(z_cos_`d'`sfx') ///
            absorb(pid ao_proceso) cluster(pid) prefix(c`s'1`d'_)
        fsreg N_first z_cos_`d'`sfx' own_cumshock `cnd', x(z_cos_`d'`sfx') ///
            absorb(pid fy_broad) cluster(pid) prefix(c`s'2`d'_)
        fsreg N_first z_cos_`d'`sfx' own_cumshock `cnd', x(z_cos_`d'`sfx') ///
            absorb(pid fy_broad ry) cluster(pid) prefix(c`s'3`d'_)
    }
}

file open T using "$vs_out/tables/vs_fs_cosine.tex", write replace
file write T "\begin{tabular}{lcccccc}" _n "\toprule" _n
file write T " & \multicolumn{3}{c}{Full sample} & \multicolumn{3}{c}{\(\bar N^{\mathrm{first}}_{k}\geq10\)} \\" _n
file write T "\cmidrule(lr){2-4}\cmidrule(lr){5-7}" _n
file write T "Exposure measure & \shortstack{(1)\\\(+\) year} & \shortstack{(2)\\\(+\) field\(\times\)year} & \shortstack{(3)\\\(+\) region\(\times\)year}"
file write T " & \shortstack{(4)\\\(+\) year} & \shortstack{(5)\\\(+\) field\(\times\)year} & \shortstack{(6)\\\(+\) region\(\times\)year} \\" _n "\midrule" _n
foreach d in psu psuR psuRF psu_pR psu_pRF {
    local dl = cond("`d'" == "psu", "PSU bins", ///
               cond("`d'" == "psuR", "PSU bins \(\times\) region", ///
               cond("`d'" == "psu_pR", "PSU bins \(+\) region", ///
               cond("`d'" == "psuRF", "PSU bins \(\times\) region \(\times\) field", ///
                    "PSU bins \(+\) region \(+\) field"))))
    file write T "`dl'"
    foreach s in all m10 {
        forvalues c = 1/3 {
            stars `c`s'`c'`d'_p' st
            file write T " & " %6.3f (`c`s'`c'`d'_b') "`st'"
        }
    }
    file write T " \\" _n
    foreach s in all m10 {
        forvalues c = 1/3 {
            file write T " & (" %5.3f (`c`s'`c'`d'_se') ")"
        }
    }
    file write T " \\" _n "\quad Wald \(F\)"
    foreach s in all m10 {
        forvalues c = 1/3 {
            file write T " & " %5.2f (`c`s'`c'`d'_F')
        }
    }
    file write T " \\" _n
    if "`d'" == "psu" | "`d'" == "psuRF" file write T "\addlinespace" _n
}
file write T "\midrule" _n
foreach st in N np {
    local sl = cond("`st'" == "N", "Observations", "Programs")
    file write T "`sl'"
    foreach s in all m10 {
        forvalues c = 1/3 {
            file write T " & " %9.0fc (`c`s'`c'psu_`st'')
        }
    }
    file write T " \\" _n
}
file write T "\bottomrule" _n "\end{tabular}" _n
file close T


/**********************************************************************
* 6. Robustness to the shock definition (Broad, both FE)
**********************************************************************/

foreach t in main p90 p75 within nosud lev ind adm {
    local sfx = cond("`t'" == "main", "", "_`t'")
    foreach w in tot gau gaukd {
        fsreg N_first x_`w'_broad`sfx' own_cumshock, x(x_`w'_broad`sfx') ///
            absorb(pid fy_broad ry) cluster(mkt_broad) prefix(r`t'`w'_)
    }
}

file open T using "$vs_out/tables/vs_fs_shockdefs.tex", write replace
file write T "\begin{tabular}{l*{8}{c}}" _n "\toprule" _n
file write T " & Main & Top 10\% & Top 25\% & Within-year & No sudden & Levels & INDICES & Admissions \\" _n "\midrule" _n
foreach w in tot gau gaukd {
    local wl = cond("`w'" == "tot", "Total", cond("`w'" == "gau", "Gaussian", "Gaussian KD"))
    file write T "\textit{`wl'}"
    foreach t in main p90 p75 within nosud lev ind adm {
        stars `r`t'`w'_p' st
        file write T " & " %6.3f (`r`t'`w'_b') "`st'"
    }
    file write T " \\" _n
    foreach t in main p90 p75 within nosud lev ind adm {
        file write T " & (" %5.3f (`r`t'`w'_se') ")"
    }
    file write T " \\" _n
    if "`w'" != "gaukd" file write T "\addlinespace" _n
}
file write T "\midrule" _n "Observations"
foreach t in main p90 p75 within nosud lev ind adm {
    file write T " & " %9.0fc (`r`t'tot_N')
}
file write T " \\" _n "\bottomrule" _n "\end{tabular}" _n
file close T

di as result "Design III TWFE tables written."
