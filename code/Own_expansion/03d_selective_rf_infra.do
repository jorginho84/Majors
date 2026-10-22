/**********************************************************************
* 03d_selective_rf_infra.do
*
* Design IV, selective vs selective (issue #3): reduced form of the
* selective-competitor exposure on the graduation of the incumbent's
* inframarginal applicants (outcomes of Design I, from 05).
*
*   y_kt = rho cumE^{w,sel}_kt / 10 + d Own_kt + mu_k + a_{f(k),t}
*          [+ g_{r(k),t}] + e_kt
*
* Same exposure, sample, FE and clustering as oe_sel_fs_N_first.tex
* (broad market, Total / Triangular / Gaussian). Outcomes in pct.: program,
* university and HE graduation in 8 years, program graduation in 10 years
* (cohorts <= 2014), First Cohort and Minimum Cohort thresholds.
* The dose event study is in 03c.
*
* Inputs: oe_selective_panel.dta (03), oe_infra_outcomes.dta (05)
* Output: output/own_expansion/tables/oe_sel_rf_infra.tex
**********************************************************************/

do "code/config.do"
do "code/Own_expansion/00_helpers.do"

global oe_out "$output/own_expansion"

use "$processed/oe_selective_panel.dta", clear
merge 1:1 code_h ao_proceso using "$processed/oe_infra_outcomes.dta", ///
    keep(master match) nogen

local yvars g8p_f g8u_f g8h_f g10p_f g8p_m g8u_m g8h_m g10p_m
foreach y of local yvars {
    local lab_`y' : variable label `y'
    foreach fe in b f {
        local abs = cond("`fe'" == "b", "pid ao_proceso", "pid fy_broad")
        foreach w in tot tri gau {
            quietly reghdfe `y' x_`w'_broad, absorb(`abs') cluster(mkt_broad)
            local b_`y'_`w'_`fe'  = _b[x_`w'_broad]
            local se_`y'_`w'_`fe' = _se[x_`w'_broad]
            local p_`y'_`w'_`fe'  = 2 * ttail(e(df_r), abs(_b[x_`w'_broad] / _se[x_`w'_broad]))
            local N_`y'_`w'_`fe'  = e(N)
            local nc_`y'_`w'_`fe' = e(N_clust)
        }
    }
    quietly summarize `y' if g_sel > 0 & ao_proceso < g_sel
    local ym_`y' = r(mean)
    di as text "`y': tri f " as result %6.2f `b_`y'_tri_f' " (" %5.2f `se_`y'_tri_f' ")" ///
        as text "  pre-mean treated " as result %5.1f `ym_`y''
}

file open T using "$oe_out/tables/oe_sel_rf_infra.tex", write replace
file write T "\begin{tabular}{lccccccc}" _n "\toprule" _n
file write T " & & \multicolumn{3}{c}{Program and year FE} & \multicolumn{3}{c}{Program, field \(\times\) year FE} \\" _n
file write T "\cmidrule(lr){3-5}\cmidrule(lr){6-8}" _n
file write T "Outcome & Pre-mean & Total & Triangular & Gaussian & Total & Triangular & Gaussian \\" _n "\midrule" _n
foreach y of local yvars {
    file write T "`lab_`y'' & " %5.1f (`ym_`y'')
    foreach fe in b f {
        foreach w in tot tri gau {
            oe_stars `p_`y'_`w'_`fe''
            file write T " & " %6.2f (`b_`y'_`w'_`fe'') "`r(stars)'"
        }
    }
    file write T " \\" _n " & "
    foreach fe in b f {
        foreach w in tot tri gau {
            file write T " & (" %5.2f (`se_`y'_`w'_`fe'') ")"
        }
    }
    file write T " \\" _n
    if "`y'" == "g10p_f" file write T "\addlinespace" _n
}
file write T "\midrule" _n "Observations (8y, First Cohort) & "
foreach fe in b f {
    foreach w in tot tri gau {
        file write T " & " %6.0fc (`N_g8p_f_`w'_`fe'')
    }
}
file write T " \\" _n "Markets (clusters) & "
foreach fe in b f {
    foreach w in tot tri gau {
        file write T " & " %4.0f (`nc_g8p_f_`w'_`fe'')
    }
}
file write T " \\" _n "\bottomrule" _n "\end{tabular}" _n
file close T

di as result "Selective-vs-selective reduced form on inframarginal graduation written."
