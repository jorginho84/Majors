/**********************************************************************
* 05_reduced_form_infra.do
*
* Reduced form (issue #3): effect of the slot shocks of Designs II, III
* and IV on the graduation of inframarginal students. No 2SLS.
*
* Outcome panels (program x admission year, inframarginal applicants):
*   8 years, 2007-2016 cohorts: 21b panels
*     inframarginal_rank_panel_enrollmentthreshold_allapp_2007_2016_<def>.dta
*     grad_enrolled_program_rate_8y, grad_uni_rate_8y, grad_he_rate_8y
*   10 years, 2007-2014 cohorts: 28b panels
*     inframarginal_rank_panel_2007_2014_<def>_grad8y10y.dta
*     grad_enrolled_program_rate_10y
*   def in {first_enroll, min_enroll} (First Cohort, Minimum Cohort)
*
* Shocks, same specification, FE and clusters as each design:
*   Design II  own sudden expansion, Post_pt (02_own_expansion.do);
*              TWFE (program + year; + field-year + region-year), SE by
*              program; event study + CS, selective programs.
*   Design III SUA exposure x Post (Total, Triangular, Gaussian), program +
*              field-year [+ region-year], SE by market; event study with
*              the PSU-weighted exposures and region-year FE.
*   Design IV  cumulative competitor exposure / 10 (Total, Triangular,
*              Gaussian, broad markets) + own shocks, program + field-year
*              [+ region-year], SE by market; event study around g_mkt.
*
* Caveat: the outcome is measured on inframarginal applicants, defined by
* a fixed program-level threshold; a shock can still change who is in the
* inframarginal group (selection), so these are reduced-form effects on
* the graduation rate of that group.
*
* Output: output/own_expansion/{tables,figures}/oe_rf_*
**********************************************************************/

do "code/config.do"
do "code/Own_expansion/00_helpers.do"

global oe_out "$output/own_expansion"

* Right-censoring guard (issue #4). Graduation is observed only through
* the last titulados year; a later title is coded as "not graduated".
* A k-year outcome is valid only for cohorts c with c + k <= tit_last.
* With titulados 2007-2016 (the files on the server as of 2026-10-06),
* 8-year outcomes are valid only for the 2007-2008 cohorts, so no shock
* (2010-2016) has a post period. Stop until titulados 2017+ are added.
use grad_year using "$processed/check_06b_titulados_all.dta", clear
quietly summarize grad_year
local tit_last = r(max)
di as text "Last titulados year in the data: " as result `tit_last'
if `tit_last' + 0 < 2012 + 8 {
    di as error "Titulados end in `tit_last': 8-year graduation is censored for" ///
        " cohorts after `=`tit_last' - 8'. Add titulados through 2024 before running."
    exit 459
}

capture program drop oe_coef
program define oe_coef
    args x prefix
    c_local `prefix'b  = _b[`x']
    c_local `prefix'se = _se[`x']
    c_local `prefix'p  = 2 * ttail(e(df_r), abs(_b[`x'] / _se[`x']))
    c_local `prefix'N  = e(N)
end


/**********************************************************************
* 1. Inframarginal outcome panel, keyed by harmonized code x year
**********************************************************************/

tempfile infra
local first = 1
foreach d in first_enroll min_enroll {
    local s = cond("`d'" == "first_enroll", "f", "m")

    use codigo_carrera_harmonized ao_proceso N_infra_enter ///
        grad_enrolled_program_rate_8y grad_uni_rate_8y grad_he_rate_8y ///
        using "$processed/inframarginal_rank_panel_enrollmentthreshold_allapp_2007_2016_`d'.dta", clear
    rename (grad_enrolled_program_rate_8y grad_uni_rate_8y grad_he_rate_8y N_infra_enter) ///
           (g8p_`s' g8u_`s' g8h_`s' ninf_`s')
    * one row per code-year (weighted by the inframarginal count)
    collapse (mean) g8p_`s' g8u_`s' g8h_`s' [aw = ninf_`s'], ///
        by(codigo_carrera_harmonized ao_proceso)
    tempfile p8
    save `p8'

    use codigo_carrera_harmonized ao_proceso grad_enrolled_program_rate_10y N_infra_enter ///
        using "$processed/inframarginal_rank_panel_2007_2014_`d'_grad8y10y.dta", clear
    rename (grad_enrolled_program_rate_10y N_infra_enter) (g10p_`s' n10_`s')
    collapse (mean) g10p_`s' [aw = n10_`s'], by(codigo_carrera_harmonized ao_proceso)
    merge 1:1 codigo_carrera_harmonized ao_proceso using `p8', nogen

    if !`first' merge 1:1 codigo_carrera_harmonized ao_proceso using `infra', nogen
    save `infra', replace
    local first = 0
}
rename codigo_carrera_harmonized code_h
foreach v of varlist g* {
    replace `v' = 100 * `v'
}
* drop cohorts whose graduation window extends past the last titulados year
foreach v of varlist g8* {
    replace `v' = . if ao_proceso + 8 > `tit_last'
}
foreach v of varlist g10* {
    replace `v' = . if ao_proceso + 10 > `tit_last'
}
label var g8p_f  "Grad. program 8y, First Cohort (pct.)"
label var g8u_f  "Grad. university 8y, First Cohort (pct.)"
label var g8h_f  "Grad. HE 8y, First Cohort (pct.)"
label var g10p_f "Grad. program 10y, First Cohort (pct.)"
label var g8p_m  "Grad. program 8y, Minimum Cohort (pct.)"
label var g8u_m  "Grad. university 8y, Minimum Cohort (pct.)"
label var g8h_m  "Grad. HE 8y, Minimum Cohort (pct.)"
label var g10p_m "Grad. program 10y, Minimum Cohort (pct.)"
save `infra', replace

di as text _n "Inframarginal outcome coverage by cohort"
tabstat g8p_f g10p_f g8p_m g10p_m, by(ao_proceso) statistics(n mean) format(%6.1f)

local yvars g8p_f g8u_f g8h_f g10p_f g8p_m g8u_m g8h_m g10p_m
foreach y of local yvars {
    local lab_`y' : variable label `y'
}


/**********************************************************************
* 2. Design II: own sudden expansion
**********************************************************************/

use "$processed/oe_panel.dta", clear
merge 1:1 code_h ao_proceso using `infra', keep(master match) nogen

foreach s in sel all {
    local cond = cond("`s'" == "sel", "if selective", "")
    foreach y of local yvars {
        quietly reghdfe `y' post_main `cond', absorb(pid ao_proceso) cluster(pid)
        oe_coef post_main d2_`s'_`y'_fe1_
        quietly reghdfe `y' post_main `cond', absorb(pid fy ry) cluster(pid)
        oe_coef post_main d2_`s'_`y'_fe2_
    }
}

preserve
keep if selective
foreach y in g8p_f g8p_m {
    oe_es `y', g(g_main) rel(rel_main) absorb(pid fy ry) cluster(pid) ///
        ylab("`lab_`y''") xlab("Years since first own vacancy shock") ///
        file("$oe_out/figures/oe_rf_d2_es_`y'.pdf")
    local d2_cs_`y'_b  = r(attCSny)
    local d2_cs_`y'_se = r(seCSny)
    local d2_cs_`y'_p  = 2 * normal(-abs(r(attCSny) / r(seCSny)))
    local d2_pre_`y'   = r(pTWFE)
}
restore

file open T using "$oe_out/tables/oe_rf_design2.tex", write replace
file write T "\begin{tabular}{lccccc}" _n "\toprule" _n
file write T " & \multicolumn{3}{c}{Selective programs} & \multicolumn{2}{c}{All programs} \\" _n
file write T "\cmidrule(lr){2-4}\cmidrule(lr){5-6}" _n
file write T "Outcome & TWFE (1) & TWFE (2) & CS not yet & TWFE (1) & TWFE (2) \\" _n "\midrule" _n
foreach y of local yvars {
    file write T "`lab_`y''"
    foreach c in "sel fe1" "sel fe2" "cs" "all fe1" "all fe2" {
        tokenize `c'
        if "`1'" == "cs" {
            if "`d2_cs_`y'_b'" == "" {
                file write T " & "
                continue
            }
            oe_stars `d2_cs_`y'_p'
            file write T " & " %6.2f (`d2_cs_`y'_b') "`r(stars)'"
            continue
        }
        oe_stars `d2_`1'_`y'_`2'_p'
        file write T " & " %6.2f (`d2_`1'_`y'_`2'_b') "`r(stars)'"
    }
    file write T " \\" _n
    foreach c in "sel fe1" "sel fe2" "cs" "all fe1" "all fe2" {
        tokenize `c'
        if "`1'" == "cs" {
            if "`d2_cs_`y'_se'" == "" file write T " & "
            else file write T " & (" %5.2f (`d2_cs_`y'_se') ")"
            continue
        }
        file write T " & (" %5.2f (`d2_`1'_`y'_`2'_se') ")"
    }
    file write T " \\" _n
    if "`y'" == "g10p_f" file write T "\addlinespace" _n
}
file write T "\midrule" _n "Observations (8y, First Cohort)"
foreach c in "sel fe1" "sel fe2" "cs" "all fe1" "all fe2" {
    tokenize `c'
    if "`1'" == "cs" file write T " & "
    else file write T " & " %6.0fc (`d2_`1'_g8p_f_`2'_N')
}
file write T " \\" _n "\bottomrule" _n "\end{tabular}" _n
file close T


/**********************************************************************
* 3. Design III: SUA exposure
**********************************************************************/

use "$processed/sua_incumbent_panel_w_broad_area_region_2007_2016.dta", clear
keep if inrange(ao_proceso, 2007, 2016)
drop if missing(program_id, field_pre, geo_pre, market_pre, N_firstyear_incumbent, ///
    exp_unw, exp_tri50, exp_gau50)
bys program_id: egen byte has_pre  = max(ao_proceso <= 2011)
bys program_id: egen byte has_post = max(ao_proceso >= 2012)
keep if has_pre & has_post
gen byte post = inrange(ao_proceso, 2012, 2016)
egen long fy = group(field_pre ao_proceso)
egen long ry = group(geo_pre ao_proceso)
foreach e in unw tri50 gau50 {
    gen double fs_`e' = 10 * exp_`e' * post
}
rename demre_code_h code_h
merge 1:1 code_h ao_proceso using `infra', keep(master match) nogen

foreach y of local yvars {
    foreach e in unw tri50 gau50 {
        foreach fe in f fr {
            local abs = cond("`fe'" == "f", "program_id fy", "program_id fy ry")
            quietly reghdfe `y' fs_`e', absorb(`abs') cluster(market_pre)
            oe_coef fs_`e' sua_`y'_`e'_`fe'_
        }
    }
}

* event study: PSU-weighted exposures, region-year FE
foreach e in tri50 gau50 {
    forvalues t = 2007/2016 {
        gen double ez_`e'_`t' = 10 * exp_`e' * (ao_proceso == `t')
    }
    drop ez_`e'_2011
}
foreach y in g8p_f g8p_m {
    tempfile es_tri50 es_gau50
    foreach e in tri50 gau50 {
        quietly reghdfe `y' ez_`e'_*, absorb(program_id fy ry) cluster(market_pre)
        quietly test ez_`e'_2007 ez_`e'_2008 ez_`e'_2009 ez_`e'_2010
        local ptr_`e' = string(r(p), "%5.3f")
        preserve
        clear
        set obs 10
        gen int year = 2006 + _n
        gen double b = 0
        gen double lo = .
        gen double hi = .
        forvalues t = 2007/2016 {
            if `t' == 2011 continue
            capture replace b  = _b[ez_`e'_`t'] if year == `t'
            capture replace lo = _b[ez_`e'_`t'] - 1.96 * _se[ez_`e'_`t'] if year == `t'
            capture replace hi = _b[ez_`e'_`t'] + 1.96 * _se[ez_`e'_`t'] if year == `t'
        }
        gen str5 k = "`e'"
        save `es_`e''
        restore
    }
    preserve
    use `es_tri50', clear
    append using `es_gau50'
    gen double x = year + cond(k == "tri50", -0.12, 0.12)
    twoway (rcap lo hi x if k == "tri50", lcolor(navy)) ///
           (scatter b x if k == "tri50", mcolor(navy) msymbol(O)) ///
           (rcap lo hi x if k == "gau50", lcolor(dkorange)) ///
           (scatter b x if k == "gau50", mcolor(dkorange) msymbol(D)), ///
        yline(0, lcolor(gs10)) xline(2011.5, lcolor(cranberry) lpattern(dash)) ///
        xlabel(2007(1)2016) xtitle("Admission year") ytitle("`lab_`y''") ///
        legend(order(2 "Triangular" 4 "Gaussian") rows(1) size(small)) ///
        note("Coefficient on 10 x PSU-similarity-weighted SUA exposure x year (2011 omitted); program, field-year and region-year FE." ///
             "Pre-2011 joint test p: Triangular `ptr_tri50', Gaussian `ptr_gau50'. SE clustered by market.", size(vsmall)) ///
        graphregion(color(white)) plotregion(color(white))
    graph export "$oe_out/figures/oe_rf_sua_es_`y'.pdf", replace
    restore
}


/**********************************************************************
* 4. Design IV: competitor shocks
**********************************************************************/

use "$processed/oe_panel.dta", clear
merge 1:1 code_h ao_proceso using `infra', keep(master match) nogen
foreach w in tot tri gau {
    gen double x_`w' = cumE_`w'_broad / 10
}
foreach y of local yvars {
    foreach w in tot tri gau {
        foreach fe in f fr {
            local abs = cond("`fe'" == "f", "pid fy", "pid fy ry")
            quietly reghdfe `y' x_`w' own_cumshock, absorb(`abs') cluster(mkt_broad)
            oe_coef x_`w' vs_`y'_`w'_`fe'_
        }
    }
}
foreach y in g8p_f g8p_m {
    oe_es `y', g(g_mkt) rel(rel_mkt) absorb(pid fy ry) cluster(mkt_broad) ///
        controls(own_cumshock) ylab("`lab_`y''") ///
        xlab("Years since first shock in market") ///
        file("$oe_out/figures/oe_rf_vs_es_`y'.pdf")
}


/**********************************************************************
* 5. Tables for III and IV: rows outcomes, columns kernel x FE
**********************************************************************/

foreach d in sua vs {
    local ks = cond("`d'" == "sua", "unw tri50 gau50", "tot tri gau")
    file open T using "$oe_out/tables/oe_rf_`d'.tex", write replace
    file write T "\begin{tabular}{lcccccc}" _n "\toprule" _n
    file write T " & \multicolumn{3}{c}{Field \(\times\) year FE} & \multicolumn{3}{c}{\(+\) Region \(\times\) year FE} \\" _n
    file write T "\cmidrule(lr){2-4}\cmidrule(lr){5-7}" _n
    file write T "Outcome & Total & Triangular & Gaussian & Total & Triangular & Gaussian \\" _n "\midrule" _n
    foreach y of local yvars {
        file write T "`lab_`y''"
        foreach fe in f fr {
            foreach k of local ks {
                oe_stars ``d'_`y'_`k'_`fe'_p'
                file write T " & " %6.2f (``d'_`y'_`k'_`fe'_b') "`r(stars)'"
            }
        }
        file write T " \\" _n
        foreach fe in f fr {
            foreach k of local ks {
                file write T " & (" %5.2f (``d'_`y'_`k'_`fe'_se') ")"
            }
        }
        file write T " \\" _n
        if "`y'" == "g10p_f" file write T "\addlinespace" _n
    }
    local k1 : word 1 of `ks'
    file write T "\midrule" _n "Observations (8y, First Cohort)"
    foreach fe in f fr {
        foreach k of local ks {
            file write T " & " %6.0fc (``d'_g8p_f_`k1'_`fe'_N')
        }
    }
    file write T " \\" _n "\bottomrule" _n "\end{tabular}" _n
    file close T
}

di as result "Reduced-form effects on inframarginal graduation written."
