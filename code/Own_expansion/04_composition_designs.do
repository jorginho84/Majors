/**********************************************************************
* 04_composition_designs.do
*
* Composition effects (issue #3): re-estimate Designs I, III (SUA) and
* IV (competitor shocks) with the mean characteristics of the entering
* cohort as the dependent variable. Design II and the selective-vs-
* selective variant of Design IV are in 02 and 03.
*
* Outcomes (01_build_composition.do): c_psu_mean c_psu_last c_psu_sd
*   c_nem_mean c_female c_priv c_mun. First-year enrollment is repeated
*   as the reference row.
*
* Design I   Composition on vacancy changes (no 2SLS):
*            d y_pt = b d Z_pt + a_t + e, Z = total cupos
*            (program_year_vacancies), in tens, so b = effect of 10 more
*            seats. Reference row: d N (enrolls_target enrollees).
*            Periods 2007-2012 and 2013-2016, as in the deck. SE clustered
*            by program.
* Design III SUA first stage in levels (Sua/04): y_pt = b 10 E_p Post_t
*            + mu_p + a_{f,t} [+ g_{r,t}], broad-area x region markets,
*            Total / Triangular / Gaussian. SE clustered by market.
*            Event study: 10 E^w_p x 1{year = t}, base 2011, w in
*            {Triangular, Gaussian}, program, field-year and region-year FE.
* Design IV  Vacancy_shocks/05 model (1): y_kt = pi cumE^w_kt / 10
*            + d Own_kt + mu_k + a_{f,t} [+ g_{r,t}], broad markets.
*            SE clustered by market. Event study around g_mkt.
*
* Output: output/own_expansion/{tables,figures}/oe_comp_*
**********************************************************************/

do "code/config.do"
do "code/Own_expansion/00_helpers.do"

global oe_out "$output/own_expansion"

local cvars c_psu_mean c_psu_last c_psu_sd c_nem_mean c_female c_priv c_mun

capture program drop harmonize_code
program define harmonize_code
    syntax varname, Generate(name)
    tempvar s
    gen str12 `s' = strtrim(string(`varlist', "%12.0f"))
    gen long `generate' = `varlist'
    replace `generate' = real(substr(`s', 1, 2) + "0" + substr(`s', 3, 2)) ///
        if length(`s') == 4
end

capture program drop oe_coef
program define oe_coef
    * one coefficient into locals <prefix>b, se, p, N
    args x prefix
    c_local `prefix'b  = _b[`x']
    c_local `prefix'se = _se[`x']
    c_local `prefix'p  = 2 * ttail(e(df_r), abs(_b[`x'] / _se[`x']))
    c_local `prefix'N  = e(N)
end

use "$processed/oe_composition_program_year.dta", clear
foreach y of local cvars {
    local lab_`y' : variable label `y'
}
local lab_N "First-year enrollment"


/**********************************************************************
* Design I: composition on d Z
**********************************************************************/

use t_codigo_carrera ao_proceso Z_total_cupos ///
    using "$processed/program_year_vacancies_2007_2016.dta", clear
harmonize_code t_codigo_carrera, generate(code_h)
collapse (sum) Z_total_cupos, by(code_h ao_proceso)
tempfile z
save `z'

* N as in Design I (21b / 28b): distinct enrollees with enrolls_target == 1
use mrun ao_proceso t_codigo_carrera enrolls_target ///
    using "$processed/analysis_sample_with_fields_final.dta", clear
keep if enrolls_target == 1
harmonize_code t_codigo_carrera, generate(code_h)
bys mrun code_h ao_proceso: keep if _n == 1
gen byte one = 1
collapse (sum) N = one, by(code_h ao_proceso)

merge 1:1 code_h ao_proceso using `z', keep(match) nogen
merge 1:1 code_h ao_proceso using "$processed/oe_composition_program_year.dta", ///
    keep(master match) nogen
egen long pid = group(code_h)
xtset pid ao_proceso
* units: Z in tens of seats, so every coefficient is the effect of 10 seats
replace Z_total_cupos = Z_total_cupos / 10
foreach v in N Z_total_cupos `cvars' {
    gen double D_`v' = D.`v'
}

foreach per in a b {
    local cond = cond("`per'" == "a", "inrange(ao_proceso, 2008, 2012)", "inrange(ao_proceso, 2013, 2016)")
    foreach y in N `cvars' {
        quietly reghdfe D_`y' D_Z_total_cupos if `cond', absorb(ao_proceso) cluster(pid)
        oe_coef D_Z_total_cupos rf_`per'_`y'_
    }
}

file open T using "$oe_out/tables/oe_comp_design1.tex", write replace
file write T "\begin{tabular}{lcc}" _n "\toprule" _n
file write T "Outcome (\(\Delta\)) & 2007--2012 & 2013--2016 \\" _n "\midrule" _n
foreach y in N `cvars' {
    local ylab = cond("`y'" == "N", "`lab_N'", "`lab_`y''")
    file write T "`ylab'"
    foreach per in a b {
        oe_stars `rf_`per'_`y'_p'
        file write T " & " %7.3f (`rf_`per'_`y'_b') "`r(stars)'"
    }
    file write T " \\" _n
    foreach per in a b {
        file write T " & (" %6.3f (`rf_`per'_`y'_se') ")"
    }
    file write T " \\" _n
    if "`y'" == "N" file write T "\addlinespace" _n
}
file write T "\midrule" _n "Observations (FD)"
foreach per in a b {
    file write T " & " %6.0fc (`rf_`per'_c_psu_mean_N')
}
file write T " \\" _n "\bottomrule" _n "\end{tabular}" _n
file close T


/**********************************************************************
* Design III: SUA, levels first stage with composition outcomes
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
rename N_firstyear_incumbent N
rename demre_code_h code_h
merge 1:1 code_h ao_proceso using "$processed/oe_composition_program_year.dta", ///
    keep(master match) gen(_comp)
di as text "SUA panel rows matched to composition:"
tab _comp

foreach y in N `cvars' {
    foreach e in unw tri50 gau50 {
        foreach fe in f fr {
            local abs = cond("`fe'" == "f", "program_id fy", "program_id fy ry")
            quietly reghdfe `y' fs_`e', absorb(`abs') cluster(market_pre)
            oe_coef fs_`e' sua_`y'_`e'_`fe'_
        }
    }
}

* event studies, PSU-similarity-weighted exposures (Triangular, Gaussian):
* 10 E^w_p x 1{year = t}, base 2011; one regression per kernel, both
* plotted in the same figure
foreach e in tri50 gau50 {
    forvalues t = 2007/2016 {
        gen double ez_`e'_`t' = 10 * exp_`e' * (ao_proceso == `t')
    }
    drop ez_`e'_2011
}
foreach y in N c_psu_mean c_psu_last {
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
            replace b  = _b[ez_`e'_`t'] if year == `t'
            replace lo = _b[ez_`e'_`t'] - 1.96 * _se[ez_`e'_`t'] if year == `t'
            replace hi = _b[ez_`e'_`t'] + 1.96 * _se[ez_`e'_`t'] if year == `t'
        }
        gen str5 k = "`e'"
        save `es_`e''
        restore
    }
    preserve
    use `es_tri50', clear
    append using `es_gau50'
    gen double x = year + cond(k == "tri50", -0.12, 0.12)
    local ylab = cond("`y'" == "N", "`lab_N'", "`lab_`y''")
    twoway (rcap lo hi x if k == "tri50", lcolor(navy)) ///
           (scatter b x if k == "tri50", mcolor(navy) msymbol(O)) ///
           (rcap lo hi x if k == "gau50", lcolor(dkorange)) ///
           (scatter b x if k == "gau50", mcolor(dkorange) msymbol(D)), ///
        yline(0, lcolor(gs10)) xline(2011.5, lcolor(cranberry) lpattern(dash)) ///
        xlabel(2007(1)2016) xtitle("Admission year") ytitle("`ylab'") ///
        legend(order(2 "Triangular" 4 "Gaussian") rows(1) size(small)) ///
        note("Coefficient on 10 x PSU-similarity-weighted SUA exposure x year (2011 omitted); program, field-year and region-year FE." ///
             "Pre-2011 joint test p: Triangular `ptr_tri50', Gaussian `ptr_gau50'. SE clustered by market.", size(vsmall)) ///
        graphregion(color(white)) plotregion(color(white))
    graph export "$oe_out/figures/oe_comp_sua_es_`y'.pdf", replace
    restore
}


/**********************************************************************
* Design IV: competitor shocks, all incumbent programs
**********************************************************************/

use "$processed/oe_panel.dta", clear
foreach w in tot tri gau {
    gen double x_`w' = cumE_`w'_broad / 10
}
foreach y in N_first `cvars' {
    foreach w in tot tri gau {
        foreach fe in f fr {
            local abs = cond("`fe'" == "f", "pid fy", "pid fy ry")
            quietly reghdfe `y' x_`w' own_cumshock, absorb(`abs') cluster(mkt_broad)
            oe_coef x_`w' vs_`y'_`w'_`fe'_
        }
    }
}
foreach y in c_psu_mean c_psu_last {
    oe_es `y', g(g_mkt) rel(rel_mkt) absorb(pid fy ry) cluster(mkt_broad) ///
        controls(own_cumshock) ylab("`lab_`y''") ///
        xlab("Years since first shock in market") ///
        file("$oe_out/figures/oe_comp_vs_es_`y'.pdf")
}


/**********************************************************************
* Tables for III and IV: rows outcomes, columns kernel x FE
**********************************************************************/

foreach d in sua vs {
    if "`d'" == "sua" {
        local ks unw tri50 gau50
        local nrow N
    }
    else {
        local ks tot tri gau
        local nrow N_first
    }
    file open T using "$oe_out/tables/oe_comp_`d'.tex", write replace
    file write T "\begin{tabular}{lcccccc}" _n "\toprule" _n
    file write T " & \multicolumn{3}{c}{Field \(\times\) year FE} & \multicolumn{3}{c}{\(+\) Region \(\times\) year FE} \\" _n
    file write T "\cmidrule(lr){2-4}\cmidrule(lr){5-7}" _n
    file write T "Outcome & Total & Triangular & Gaussian & Total & Triangular & Gaussian \\" _n "\midrule" _n
    foreach y in `nrow' `cvars' {
        local ylab = cond("`y'" == "`nrow'", "`lab_N'", "`lab_`y''")
        file write T "`ylab'"
        foreach fe in f fr {
            foreach k of local ks {
                oe_stars ``d'_`y'_`k'_`fe'_p'
                file write T " & " %7.3f (``d'_`y'_`k'_`fe'_b') "`r(stars)'"
            }
        }
        file write T " \\" _n
        foreach fe in f fr {
            foreach k of local ks {
                file write T " & (" %6.3f (``d'_`y'_`k'_`fe'_se') ")"
            }
        }
        file write T " \\" _n
        if "`y'" == "`nrow'" file write T "\addlinespace" _n
    }
    local k1 : word 1 of `ks'
    file write T "\midrule" _n "Observations"
    foreach fe in f fr {
        foreach k of local ks {
            file write T " & " %6.0fc (``d'_c_psu_mean_`k1'_`fe'_N')
        }
    }
    file write T " \\" _n "\bottomrule" _n "\end{tabular}" _n
    file close T
}

di as result "Composition tables for Designs I, III, IV written."
