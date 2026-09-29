/**********************************************************************
* 04b_exposure_descriptives.do
*
* Design III — samples and exposure distributions, mirroring the Design II
* descriptive frames. Exposure is summarized at its end-of-period value,
* cumulative exposure in 2016 (one observation per incumbent program).
*
* Tables (output/vacancy_shocks/tables/):
*   vs_samples.tex          Panel A samples by field definition
*   vs_exposure_moments.tex Panel B exposure moments by field def x kernel
*   vs_cos_samples.tex      cosine samples, full and N_pre >= 10
*   vs_cos_moments.tex      cosine exposure moments, both samples
* Figures (output/vacancy_shocks/figures/):
*   vs_exposure_dist_<f>.pdf   Total/Triangular/Gaussian, all and positive
*   vs_q_dist.pdf              conditional similarity Q (broad), all and positive
*   vs_cos_dist_all.pdf, vs_cos_dist_pos.pdf
*
* Input: $processed/vs_panel_exposure.dta
**********************************************************************/

do "code/config.do"

global vs_out "$output/vacancy_shocks"
cap mkdir "$vs_out/tables"
cap mkdir "$vs_out/figures"
set scheme s2color

use "$processed/vs_panel_exposure.dta", clear
keep if est_sample

capture program drop ndist
program define ndist, rclass
    syntax varname [if]
    tempvar t
    quietly egen byte `t' = tag(`varlist') `if'
    quietly count if `t' == 1 & !missing(`varlist')
    return scalar ndistinct = r(N)
end


/**********************************************************************
* 1. Panel A: analytical samples by field definition
**********************************************************************/

file open T using "$vs_out/tables/vs_samples.tex", write replace
file write T "\begin{tabular}{lrrr}" _n "\toprule" _n
file write T "Variable & Broad & ISCED-97 & Generic \\" _n "\midrule" _n

foreach stat in prog obs uni mkt mktshock nshock enr psu {
    local lab = cond("`stat'" == "prog", "Programs", ///
                cond("`stat'" == "obs", "Program-year observations", ///
                cond("`stat'" == "uni", "Incumbent universities", ///
                cond("`stat'" == "mkt", "Markets (field \(\times\) region)", ///
                cond("`stat'" == "mktshock", "Markets with a shock, 2010--2016", ///
                cond("`stat'" == "nshock", "Programs exposed to a market shock", ///
                cond("`stat'" == "enr", "Mean annual enrollment, 2007--2009", ///
                     "Mean PSU score, 2007--2009")))))))
    file write T "`lab'"
    foreach f in broad isced generic {
        preserve
        keep if !missing(mkt_`f')
        if "`stat'" == "prog" {
            quietly ndist pid
            local v = r(ndistinct)
            local fmt %9.0fc
        }
        if "`stat'" == "obs" {
            local v = _N
            local fmt %9.0fc
        }
        if "`stat'" == "uni" {
            quietly ndist sigla_universidad
            local v = r(ndistinct)
            local fmt %9.0fc
        }
        if "`stat'" == "mkt" {
            quietly ndist mkt_`f'
            local v = r(ndistinct)
            local fmt %9.0fc
        }
        if "`stat'" == "mktshock" {
            quietly ndist mkt_`f' if M_`f'_2016 > 0 & !missing(M_`f'_2016)
            local v = r(ndistinct)
            local fmt %9.0fc
        }
        if "`stat'" == "nshock" {
            quietly ndist pid if M_`f'_2016 > 0 & !missing(M_`f'_2016)
            local v = r(ndistinct)
            local fmt %9.0fc
        }
        if inlist("`stat'", "enr", "psu") {
            bys pid: keep if _n == 1
            local vv = cond("`stat'" == "enr", "N_first_pre", "psu_first_pre")
            quietly summarize `vv'
            local v = r(mean)
            local fmt %9.1f
        }
        file write T " & " `fmt' (`v')
        restore
    }
    file write T " \\" _n
}
file write T "\bottomrule" _n "\end{tabular}" _n
file close T


/**********************************************************************
* 2. Panel B: exposure moments (cumulative exposure in 2016)
**********************************************************************/

preserve
keep if ao_proceso == 2016
file open T using "$vs_out/tables/vs_exposure_moments.tex", write replace
file write T "\begin{tabular}{llrrrr}" _n "\toprule" _n
file write T "Field definition & Exposure measure & Mean & Std. dev. & p90 & Share zero \\" _n "\midrule" _n
foreach f in broad isced generic {
    local fl = cond("`f'" == "broad", "Broad", cond("`f'" == "isced", "ISCED-97", "Generic"))
    foreach w in tot tri gau {
        local wl = cond("`w'" == "tot", "Total", cond("`w'" == "tri", "Triangular", "Gaussian"))
        quietly summarize cumE_`w'_`f', detail
        local m = r(mean)
        local s = r(sd)
        local p = r(p90)
        quietly count if cumE_`w'_`f' == 0
        local z = 100 * r(N) / `=_N'
        local lf = cond("`w'" == "tot", "`fl'", "")
        file write T "`lf' & `wl' & " %6.2f (`m') " & " %6.2f (`s') " & " %6.2f (`p') ///
            " & " %5.1f (`z') "\% \\" _n
    }
    if "`f'" != "generic" file write T "\addlinespace" _n
}
file write T "\bottomrule" _n "\end{tabular}" _n
file close T


/**********************************************************************
* 3. Distribution figures, market measures
**********************************************************************/

foreach f in broad isced generic {
    local gl
    foreach part in all pos {
        foreach w in tot tri gau {
            local wl = cond("`w'" == "tot", "Total", cond("`w'" == "tri", "Triangular", "Gaussian"))
            local ttl = cond("`part'" == "all", "`wl': all programs", "`wl': positive only")
            quietly summarize cumE_`w'_`f', detail
            local top = r(p99)
            local cond = cond("`part'" == "all", "if cumE_`w'_`f' <= `top'", ///
                "if cumE_`w'_`f' > 0 & cumE_`w'_`f' <= `top'")
            histogram cumE_`w'_`f' `cond', fraction ///
                fcolor(navy%60) lcolor(navy%80) ///
                xtitle("Cumulative exposure, 2016 (pp)", size(small)) ytitle("Share of programs", size(small)) ///
                title("`ttl'", size(medsmall)) ///
                graphregion(color(white)) plotregion(color(white)) ///
                name(h_`w'_`part', replace) nodraw
            local gl `gl' h_`w'_`part'
        }
    }
    graph combine `gl', rows(2) cols(3) graphregion(color(white)) ///
        note("Incumbent programs, cumulative exposure in 2016; trimmed at p99. `=cond("`f'"=="broad","Broad",cond("`f'"=="isced","ISCED-97","Generic"))'-field markets.", size(vsmall))
    graph export "$vs_out/figures/vs_exposure_dist_`f'.pdf", replace
}
restore


/**********************************************************************
* 3b. Kernel-denominator exposure: moments and distribution
**********************************************************************/

preserve
keep if ao_proceso == 2016
file open T using "$vs_out/tables/vs_exposure_moments_kd.tex", write replace
file write T "\begin{tabular}{llrrrrrr}" _n "\toprule" _n
file write T "Field definition & Exposure measure & Mean & Std. dev. & p90 & p99 & Max & Share zero \\" _n "\midrule" _n
foreach f in broad isced generic {
    local fl = cond("`f'" == "broad", "Broad", cond("`f'" == "isced", "ISCED-97", "Generic"))
    foreach w in tot trikd gaukd {
        local wl = cond("`w'" == "tot", "Total", cond("`w'" == "trikd", "Triangular KD", "Gaussian KD"))
        quietly summarize cumE_`w'_`f', detail
        local m = r(mean)
        local s = r(sd)
        local p = r(p90)
        local p99 = r(p99)
        local mx = r(max)
        local n = r(N)
        quietly count if cumE_`w'_`f' == 0
        local z = 100 * r(N) / `n'
        local lf = cond("`w'" == "tot", "`fl'", "")
        file write T "`lf' & `wl' & " %6.2f (`m') " & " %6.2f (`s') " & " %6.2f (`p') ///
            " & " %6.2f (`p99') " & " %6.2f (`mx') " & " %5.1f (`z') "\% \\" _n
    }
    if "`f'" != "generic" file write T "\addlinespace" _n
}
file write T "\bottomrule" _n "\end{tabular}" _n
file close T

local gl
foreach part in all pos {
    foreach w in tot trikd gaukd {
        local wl = cond("`w'" == "tot", "Total", cond("`w'" == "trikd", "Triangular KD", "Gaussian KD"))
        local ttl = cond("`part'" == "all", "`wl': all programs", "`wl': positive only")
        quietly summarize cumE_`w'_broad, detail
        local top = r(p99)
        local cond = cond("`part'" == "all", "if cumE_`w'_broad <= `top'", ///
            "if cumE_`w'_broad > 0 & cumE_`w'_broad <= `top'")
        histogram cumE_`w'_broad `cond', fraction ///
            fcolor(navy%60) lcolor(navy%80) ///
            xtitle("Cumulative exposure, 2016 (pp)", size(small)) ytitle("Share of programs", size(small)) ///
            title("`ttl'", size(medsmall)) ///
            graphregion(color(white)) plotregion(color(white)) ///
            name(k_`w'_`part', replace) nodraw
        local gl `gl' k_`w'_`part'
    }
}
graph combine `gl', rows(2) cols(3) graphregion(color(white)) ///
    note("Incumbent programs, cumulative exposure in 2016; trimmed at p99. Broad-field markets. KD: kernel-weighted denominator.", size(vsmall))
graph export "$vs_out/figures/vs_exposure_dist_kd_broad.pdf", replace
restore


/**********************************************************************
* 4. Conditional similarity Q (broad markets with a shock)
**********************************************************************/

preserve
keep if ao_proceso == 2016 & M_broad_2016 > 0 & !missing(M_broad_2016)
local gl
foreach part in all pos {
    foreach w in tri gau {
        local wl = cond("`w'" == "tri", "Triangular", "Gaussian")
        local cond = cond("`part'" == "all", "if !missing(Q_`w'_broad)", "if Q_`w'_broad > 0 & !missing(Q_`w'_broad)")
        local ttl = cond("`part'" == "all", "`wl': exposed programs", "`wl': positive Q only")
        gen double Qp_`w'_`part' = 100 * Q_`w'_broad
        histogram Qp_`w'_`part' `cond', fraction width(5) start(0) ///
            fcolor(navy%60) lcolor(navy%80) ///
            xtitle("Conditional similarity Q (pp)", size(small)) ytitle("Share of programs", size(small)) ///
            title("`ttl'", size(medsmall)) ///
            graphregion(color(white)) plotregion(color(white)) ///
            name(q_`w'_`part', replace) nodraw
        local gl `gl' q_`w'_`part'
    }
}
graph combine `gl', rows(2) cols(2) graphregion(color(white)) ///
    note("Incumbent programs in broad-field markets with at least one shock by 2016; Q in 2016.", size(vsmall))
graph export "$vs_out/figures/vs_q_dist.pdf", replace
restore


/**********************************************************************
* 5. Cosine samples, moments and distributions
**********************************************************************/

file open T using "$vs_out/tables/vs_cos_samples.tex", write replace
file write T "\begin{tabular}{lrr}" _n "\toprule" _n
file write T "Variable & Full sample & \(\bar N^{\mathrm{first}}_{k,2007\text{--}09}\geq10\) \\" _n "\midrule" _n
foreach stat in prog obs uni enr psu {
    local lab = cond("`stat'" == "prog", "Programs", ///
                cond("`stat'" == "obs", "Program-year observations", ///
                cond("`stat'" == "uni", "Incumbent universities", ///
                cond("`stat'" == "enr", "Mean annual enrollment, 2007--2009", ///
                     "Mean PSU score, 2007--2009"))))
    file write T "`lab'"
    foreach s in all m10 {
        preserve
        if "`s'" == "m10" keep if min10
        if "`stat'" == "prog" {
            quietly ndist pid
            local v = r(ndistinct)
            local fmt %9.0fc
        }
        if "`stat'" == "obs" {
            local v = _N
            local fmt %9.0fc
        }
        if "`stat'" == "uni" {
            quietly ndist sigla_universidad
            local v = r(ndistinct)
            local fmt %9.0fc
        }
        if inlist("`stat'", "enr", "psu") {
            bys pid: keep if _n == 1
            local vv = cond("`stat'" == "enr", "N_first_pre", "psu_first_pre")
            quietly summarize `vv'
            local v = r(mean)
            local fmt %9.1f
        }
        file write T " & " `fmt' (`v')
        restore
    }
    file write T " \\" _n
}
file write T "\bottomrule" _n "\end{tabular}" _n
file close T

preserve
keep if ao_proceso == 2016
file open T using "$vs_out/tables/vs_cos_moments.tex", write replace
file write T "\begin{tabular}{lrrrrrr}" _n "\toprule" _n
file write T " & \multicolumn{3}{c}{Full sample} & \multicolumn{3}{c}{\(\bar N^{\mathrm{first}}_{k}\geq10\)} \\" _n
file write T "\cmidrule(lr){2-4}\cmidrule(lr){5-7}" _n
file write T "Exposure measure & Mean & Std. dev. & Share zero & Mean & Std. dev. & Share zero \\" _n "\midrule" _n
foreach d in psu psuR psu_pR psuRF psu_pRF {
    local dl = cond("`d'" == "psu", "PSU bins", ///
               cond("`d'" == "psuR", "PSU bins \(\times\) campus region", ///
               cond("`d'" == "psu_pR", "PSU bins \(+\) campus region", ///
               cond("`d'" == "psuRF", "PSU bins \(\times\) campus region \(\times\) Broad field", ///
                    "PSU bins \(+\) campus region \(+\) Broad field"))))
    file write T "`dl'"
    foreach s in all m10 {
        local c = cond("`s'" == "m10", "if min10", "")
        quietly summarize cumE_cos_`d' `c'
        local m = r(mean)
        local sd = r(sd)
        local n = r(N)
        quietly count if cumE_cos_`d' == 0 `=cond("`s'"=="m10","& min10","")'
        file write T " & " %6.4f (`m') " & " %6.4f (`sd') " & " %5.1f (100 * r(N) / `n') "\%"
    }
    file write T " \\" _n
}
file write T "\bottomrule" _n "\end{tabular}" _n
file close T

foreach part in all pos {
    local gl
    foreach d in psu psuR psu_pR psuRF psu_pRF {
        local dl = cond("`d'" == "psu", "PSU", ///
                   cond("`d'" == "psuR", "PSU x region", ///
                   cond("`d'" == "psu_pR", "PSU + region", ///
                   cond("`d'" == "psuRF", "PSU x region x field", "PSU + region + field"))))
        local cond = cond("`part'" == "all", "", "if cumE_cos_`d' > 0")
        gen double cp_`d' = 100 * cumE_cos_`d'
        histogram cp_`d' `cond', fraction ///
            fcolor(navy%60) lcolor(navy%80) ///
            xtitle("Cumulative cosine exposure, 2016 (pp)", size(small)) ytitle("Share of programs", size(small)) ///
            title("`dl'", size(medsmall)) ///
            graphregion(color(white)) plotregion(color(white)) ///
            name(c_`d', replace) nodraw
        drop cp_`d'
        local gl `gl' c_`d'
    }
    graph combine `gl', rows(2) cols(3) graphregion(color(white)) ///
        note("Incumbent programs, full sample. `=cond("`part'"=="all","All programs.","Programs with positive exposure only.")'", size(vsmall))
    graph export "$vs_out/figures/vs_cos_dist_`part'.pdf", replace
}
restore

di as result "Design III exposure descriptives written."
