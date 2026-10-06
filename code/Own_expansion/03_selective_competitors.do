/**********************************************************************
* 03_selective_competitors.do
*
* Design IV (competitor vacancy shocks), selective-vs-selective variant
* (issue #3): when a selective program suddenly expands its seats, what
* happens to its selective competitors?
*
* Same objects as code/Vacancy_shocks/03 and 05, restricted on both sides:
*   incumbents k : selective incumbent programs (est_sample & selective,
*                  top 20% of 2007-2009 entrant PSU, as in 02)
*   sources j    : selective programs (psu_S above the same cutoff; psu_S
*                  uses the first three cohorts for programs created later)
*   shocks       : shock_main (Design III definition)
*
*   E^{w,f}_kt = 100 * sum_{j in m_f(k), j != k, j selective} w(k,j) seats_jt
*                / T^{sel}_{m_f(k)}
*   T^{sel}_m  = pre-period (2007-2009) first-year enrollment of the
*                selective programs in market m
*   cumE       = cumulative sum since 2010
*
* Models (mirror of Design IV model (1) and the event study):
*   N_kt = pi cumE^{w,f}_kt / 10 + d Own_kt + mu_k + a_{f(k),t} [+ g_{r(k),t}] + e
*   SE clustered by market. Event study around the first selective-
*   competitor shock in k's broad market. Outcomes: enrollment and the
*   composition variables of 01.
*
* Inputs:  oe_panel.dta (02), vs_panel_exposure.dta, vs_similarity_pairs.dta
* Output:  output/own_expansion/{tables,figures}/oe_sel_*
**********************************************************************/

do "code/config.do"
do "code/Own_expansion/00_helpers.do"

global oe_out "$output/own_expansion"


/**********************************************************************
* 1. Selective sources and selective market size
**********************************************************************/

use "$processed/oe_panel.dta", clear
preserve
bys pid: keep if _n == 1
_pctile psu_first_pre, p(80)
local sel_cut = r(r1)
restore
di as text "Selective cutoff: " as result %6.1f `sel_cut'

use code_h ao_proceso psu_S N_first_pre seats_main mkt_broad mkt_isced mkt_generic ///
    using "$processed/vs_panel_exposure.dta", clear
gen byte sel_j = psu_S >= `sel_cut' & !missing(psu_S)

tempfile shocks tsel
preserve
keep if seats_main > 0 & sel_j
di as text "Main shocks at selective programs: " as result _N
keep code_h ao_proceso seats_main
rename code_h j
save `shocks'
restore

* T^sel_m: pre-period enrollment of selective programs in each market
bys code_h: keep if _n == 1
replace N_first_pre = 0 if missing(N_first_pre)
foreach f in broad isced generic {
    bys mkt_`f': egen double Tsel_`f' = total(N_first_pre * sel_j) if !missing(mkt_`f')
}
keep code_h Tsel_*
save `tsel'


/**********************************************************************
* 2. Exposure of selective incumbents to selective-competitor shocks
**********************************************************************/

use k j s_tot_* s_tri_* s_gau_* using "$processed/vs_similarity_pairs.dta", clear
joinby j using `shocks'
foreach f in broad isced generic {
    foreach w in tot tri gau {
        gen double num_`w'_`f' = s_`w'_`f' * seats_main
    }
}
gen byte selmkt_shock = s_tot_broad > 0 & seats_main > 0
collapse (sum) num_* (max) selmkt_shock, by(k ao_proceso)
rename k code_h
tempfile pairexp
save `pairexp'

use "$processed/oe_panel.dta", clear
keep if selective
* drop the all-source exposure measures inherited from vs_panel_exposure
drop E_* cumE_* Q_* M_* D_mkt_*
merge 1:1 code_h ao_proceso using `pairexp', keep(master match) nogen
merge m:1 code_h using `tsel', keep(master match) nogen
foreach v of varlist num_* selmkt_shock {
    replace `v' = 0 if missing(`v')
}
foreach f in broad isced generic {
    foreach w in tot tri gau {
        gen double E_`w'_`f' = 100 * num_`w'_`f' / Tsel_`f' if Tsel_`f' > 0
        bys pid (ao_proceso): gen double sE_`w'_`f' = sum(E_`w'_`f')
        replace sE_`w'_`f' = . if missing(E_`w'_`f')
        gen double x_`w'_`f' = sE_`w'_`f' / 10
    }
    local fv = cond("`f'" == "broad", "field", "`f'_field")
    egen long fy_`f' = group(`fv' ao_proceso)
}

bys pid: egen int g_sel = min(cond(selmkt_shock == 1, ao_proceso, .))
replace g_sel = 0 if missing(g_sel)
gen int rel_sel = ao_proceso - g_sel if g_sel > 0

di as text _n "Selective incumbents and exposure"
quietly count if ao_proceso == 2016
di as text "  selective incumbents: " as result r(N)
quietly count if ao_proceso == 2016 & sE_tot_broad > 0 & !missing(sE_tot_broad)
di as text "  exposed by 2016 (broad market): " as result r(N)
tab g_sel if ao_proceso == 2016
summarize sE_tot_broad sE_tri_broad sE_gau_broad if ao_proceso == 2016, detail

save "$processed/oe_selective_panel.dta", replace


/**********************************************************************
* 3. Exposure moments table
**********************************************************************/

file open T using "$oe_out/tables/oe_sel_exposure_moments.tex", write replace
file write T "\begin{tabular}{llccccc}" _n "\toprule" _n
file write T "Field & Kernel & Exposed (\%) & Mean & P50 exposed & P90 exposed & Max \\" _n "\midrule" _n
foreach f in broad isced generic {
    local fl = cond("`f'" == "broad", "Broad", cond("`f'" == "isced", "ISCED-97", "Generic"))
    foreach w in tot tri gau {
        local wl = cond("`w'" == "tot", "Total", cond("`w'" == "tri", "Triangular", "Gaussian"))
        quietly count if ao_proceso == 2016 & !missing(sE_`w'_`f')
        local n = r(N)
        quietly count if ao_proceso == 2016 & sE_`w'_`f' > 0 & !missing(sE_`w'_`f')
        local ne = r(N)
        quietly summarize sE_`w'_`f' if ao_proceso == 2016
        local mn = r(mean)
        local mx = r(max)
        quietly _pctile sE_`w'_`f' if ao_proceso == 2016 & sE_`w'_`f' > 0, p(50 90)
        local lab = cond("`w'" == "tot", "`fl'", "")
        file write T "`lab' & `wl' & " %4.1f (100 * `ne' / `n') " & " %5.2f (`mn') ///
            " & " %5.2f (r(r1)) " & " %5.2f (r(r2)) " & " %5.2f (`mx') " \\" _n
    }
}
file write T "\bottomrule" _n "\end{tabular}" _n
file close T


/**********************************************************************
* 4. TWFE: enrollment, 3 kernels x 3 fields x 2 FE sets
**********************************************************************/

capture program drop fsreg
program define fsreg
    syntax varlist [if], x(varname) absorb(string) cluster(varname) [PREfix(string)]
    quietly reghdfe `varlist' `if', absorb(`absorb') cluster(`cluster')
    c_local `prefix'b  = _b[`x']
    c_local `prefix'se = _se[`x']
    c_local `prefix'p  = 2 * ttail(e(df_r), abs(_b[`x'] / _se[`x']))
    c_local `prefix'N  = e(N)
    c_local `prefix'nc = e(N_clust)
end

foreach y in N_first lnN {
    foreach fe in f fr {
        foreach f in broad isced generic {
            local abs = cond("`fe'" == "f", "pid fy_`f'", "pid fy_`f' ry")
            foreach w in tot tri gau {
                fsreg `y' x_`w'_`f' own_cumshock, x(x_`w'_`f') absorb(`abs') ///
                    cluster(mkt_`f') prefix(`y'_`w'_`fe'_`f'_)
            }
        }
    }

    local ylab = cond("`y'" == "lnN", "Log first-year enrollment", "First-year enrollment")
    file open T using "$oe_out/tables/oe_sel_fs_`y'.tex", write replace
    file write T "\begin{tabular}{lcccccc}" _n "\toprule" _n
    file write T " & \multicolumn{3}{c}{Field \(\times\) year FE} & \multicolumn{3}{c}{\(+\) Region \(\times\) year FE} \\" _n
    file write T "\cmidrule(lr){2-4}\cmidrule(lr){5-7}" _n
    file write T "Exposure measure & Broad & ISCED-97 & Generic & Broad & ISCED-97 & Generic \\" _n "\midrule" _n
    foreach w in tot tri gau {
        local wl = cond("`w'" == "tot", "Total", cond("`w'" == "tri", "Triangular", "Gaussian"))
        file write T "\textit{`wl'}"
        foreach fe in f fr {
            foreach f in broad isced generic {
                oe_stars ``y'_`w'_`fe'_`f'_p'
                file write T " & " %7.3f (``y'_`w'_`fe'_`f'_b') "`r(stars)'"
            }
        }
        file write T " \\" _n
        foreach fe in f fr {
            foreach f in broad isced generic {
                file write T " & (" %6.3f (``y'_`w'_`fe'_`f'_se') ")"
            }
        }
        file write T " \\" _n
    }
    file write T "\midrule" _n "Observations"
    foreach fe in f fr {
        foreach f in broad isced generic {
            file write T " & " %6.0fc (``y'_tot_`fe'_`f'_N')
        }
    }
    file write T " \\" _n "Markets (clusters)"
    foreach fe in f fr {
        foreach f in broad isced generic {
            file write T " & " %6.0fc (``y'_tot_`fe'_`f'_nc')
        }
    }
    file write T " \\" _n "\bottomrule" _n "\end{tabular}" _n
    file close T
}


/**********************************************************************
* 5. Composition: Total and Gaussian, broad market, field x year FE
**********************************************************************/

local cvars c_psu_mean c_psu_last c_psu_sd c_nem_mean c_female c_priv c_mun
foreach y of local cvars {
    local lab_`y' : variable label `y'
    foreach w in tot gau {
        foreach fe in f fr {
            local abs = cond("`fe'" == "f", "pid fy_broad", "pid fy_broad ry")
            fsreg `y' x_`w'_broad own_cumshock, x(x_`w'_broad) absorb(`abs') ///
                cluster(mkt_broad) prefix(c_`y'_`w'_`fe'_)
        }
    }
}

file open T using "$oe_out/tables/oe_sel_composition.tex", write replace
file write T "\begin{tabular}{lcccc}" _n "\toprule" _n
file write T " & \multicolumn{2}{c}{Total} & \multicolumn{2}{c}{Gaussian} \\" _n
file write T "\cmidrule(lr){2-3}\cmidrule(lr){4-5}" _n
file write T "Outcome & Field-year & \(+\) Region-year & Field-year & \(+\) Region-year \\" _n "\midrule" _n
foreach y of local cvars {
    file write T "`lab_`y''"
    foreach w in tot gau {
        foreach fe in f fr {
            oe_stars `c_`y'_`w'_`fe'_p'
            file write T " & " %7.3f (`c_`y'_`w'_`fe'_b') "`r(stars)'"
        }
    }
    file write T " \\" _n
    foreach w in tot gau {
        foreach fe in f fr {
            file write T " & (" %6.3f (`c_`y'_`w'_`fe'_se') ")"
        }
    }
    file write T " \\" _n
}
file write T "\bottomrule" _n "\end{tabular}" _n
file close T


/**********************************************************************
* 6. Event studies: first selective-competitor shock in the broad market
**********************************************************************/

foreach y in N_first lnN c_psu_mean {
    local ylab : variable label `y'
    oe_es `y', g(g_sel) rel(rel_sel) absorb(pid fy_broad ry) cluster(mkt_broad) ///
        controls(own_cumshock) ylab("`ylab'") ///
        xlab("Years since first selective-competitor shock in market") ///
        file("$oe_out/figures/oe_sel_es_`y'.pdf")
    di as text "`y': pretrend p TWFE " %5.3f r(pTWFE) ", CS never " %5.3f r(pCSnv) ///
        "; CS ATT never " %7.3f r(attCSnv) " (" %6.3f r(seCSnv) ")" ///
        ", not yet " %7.3f r(attCSny) " (" %6.3f r(seCSny) ")"
}

di as result "Design IV selective-vs-selective written."
