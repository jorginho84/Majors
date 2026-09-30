/*******************************************************************************
04i_sua_kernelden_first_stage_tables.do

PURPOSE

Deck tables for the SUA first stages with the kernel-weighted denominator
(exposure built in 03d_build_sua_kernel_denominator.do):

                     sum_q k(|S_p-S_q|) N_q
    E_p^{k,KD} =   --------------------------
                     sum_l k(|S_p-S_l|) N_l

where q runs over entrant programs and l over all programs in p's market.

Same sample and specifications as the main first stages
(04_sua_levels_first_stages.do and 04b_sua_log_first_stages.do), so the
tables are directly comparable with them:

    EXPOSURE MEASURES        Triangular KD, Gaussian KD
    FIELD DEFINITIONS        Broad, ISCED-97, Generic
    FIXED EFFECTS            Program + field x year
                             Program + field x year + region x year

MODELS

    Levels:
        N_firstyear_pt = beta [10 x E_p^{k,KD} x Post_t] + FE + error_pt

    Logs:
        log N_firstyear_pt = beta [log_tilde(E_p^{k,KD}) x Post_t]
                           + theta [1(E_p^{k,KD} > 0) x Post_t] + FE + error_pt

Standard errors are clustered by the pre-treatment market.

04g_sua_kernelden_first_stages.do and 04h_sua_kernelden_log_first_stages.do
estimate the region x year specification only and write no tables.

OUTPUTS

    $output/tables/sua_fs_lvl_kd.tex
    $output/tables/sua_fs_log_kd.tex
*******************************************************************************/

clear all
set more off
set varabbrev off

do "code/config.do"

capture which reghdfe
if _rc {
    display as error "reghdfe is not installed."
    exit 199
}


/*******************************************************************************
1. DEFINITIONS
*******************************************************************************/

local market_definitions broad_area cine_subarea generic_area
local field_codes        broad isced generic

local exposure_codes     tri gau
local raw_tri            exp_tri50kd
local raw_gau            exp_gau50kd

local fe_codes           fy ry
local models             lvl log

tempfile results
tempname handle

postfile `handle' ///
    str4 model str8 field str4 exposure str4 fe ///
    double beta double se double F double p ///
    long N long programs long zero long markets ///
    using `results', replace


/*******************************************************************************
2. ESTIMATION
*******************************************************************************/

forvalues i = 1/3 {

    local market_definition : word `i' of `market_definitions'
    local field_code        : word `i' of `field_codes'

    use "$processed/sua_incumbent_panel_kd_`market_definition'_region_2007_2016.dta", clear

    keep if inrange(ao_proceso, 2007, 2016)


    /*
    Common analytical sample, as in 04 and 04b. The KD measures are also
    required to be non-missing.
    */

    drop if missing( ///
        program_id, ao_proceso, field_pre, geo_pre, market_pre, ///
        N_firstyear_incumbent, exp_unw, exp_tri50, exp_gau50, ///
        exp_tri50kd, exp_gau50kd)

    assert N_firstyear_incumbent > 0

    bysort program_id: egen byte has_pre  = max(ao_proceso <= 2011)
    bysort program_id: egen byte has_post = max(ao_proceso >= 2012)
    keep if has_pre == 1 & has_post == 1
    drop has_pre has_post

    isid program_id ao_proceso

    assert post2012 == inrange(ao_proceso, 2012, 2016)

    egen long level_field_year  = group(field_pre ao_proceso)
    egen long level_region_year = group(geo_pre ao_proceso)

    gen double ln_N = ln(N_firstyear_incumbent)

    foreach w of local exposure_codes {

        bysort program_id (ao_proceso): assert `raw_`w'' == `raw_`w''[1]
        assert inrange(`raw_`w'', 0, 1.0000001)

        gen byte   pos_`w'   = `raw_`w'' > 0
        gen double lvl_`w'   = 10 * `raw_`w'' * post2012
        gen double log_`w'   = cond(pos_`w', ln(`raw_`w''), 0) * post2012
        gen byte   Dpost_`w' = pos_`w' * post2012
    }

    foreach model of local models {

        local outcome = cond("`model'" == "lvl", "N_firstyear_incumbent", "ln_N")

        foreach fe of local fe_codes {

            local absorbed = cond("`fe'" == "fy", ///
                "program_id level_field_year", ///
                "program_id level_field_year level_region_year")

            foreach w of local exposure_codes {

                local regressors "`model'_`w'"
                if "`model'" == "log" local regressors "log_`w' Dpost_`w'"

                display ""
                display "=== KD | `model' | `field_code' | `w' | `fe' ==="

                reghdfe `outcome' `regressors', ///
                    absorb(`absorbed') vce(cluster market_pre)

                quietly test `model'_`w'
                local F = r(F)
                local p = r(p)

                tempvar in_sample tag_program tag_zero tag_market

                gen byte `in_sample' = e(sample)

                egen byte `tag_program' = tag(program_id) if `in_sample'
                egen byte `tag_zero'    = tag(program_id) if `in_sample' & pos_`w' == 0
                egen byte `tag_market'  = tag(market_pre) if `in_sample'

                foreach c in program zero market {
                    quietly count if `tag_`c'' == 1
                    local n_`c' = r(N)
                }

                post `handle' ///
                    ("`model'") ("`field_code'") ("`w'") ("`fe'") ///
                    (_b[`model'_`w']) (_se[`model'_`w']) (`F') (`p') ///
                    (e(N)) (`n_program') (`n_zero') (`n_market')

                drop `in_sample' `tag_program' `tag_zero' `tag_market'
            }
        }
    }
}

postclose `handle'


/*******************************************************************************
3. SUMMARY
*******************************************************************************/

use `results', clear

assert _N == 24

format beta se %9.3f
format F %9.2f
format p %9.4f

list model field exposure fe beta se F p N programs zero markets, ///
    sepby(model fe) noobs clean

tempfile all_results
save `all_results'


/*******************************************************************************
4. LATEX TABLES
*******************************************************************************/

capture program drop stars
program define stars
    args p name
    local s ""
    if `p' < 0.10 local s "\sym{*}"
    if `p' < 0.05 local s "\sym{**}"
    if `p' < 0.01 local s "\sym{***}"
    c_local `name' "`s'"
end

foreach model of local models {

    use `all_results', clear
    keep if model == "`model'"
    assert _N == 12

    foreach v in beta se F p N programs zero markets {
        forvalues r = 1/`=_N' {
            local `v'_`=exposure[`r']'_`=fe[`r']'_`=field[`r']' = `v'[`r']
        }
    }

    file open T using "$output/tables/sua_fs_`model'_kd.tex", write replace
    file write T "\begin{tabular}{lcccccc}" _n "\toprule" _n
    file write T " & \multicolumn{3}{c}{Field \(\times\) year FE} & \multicolumn{3}{c}{\(+\) Region \(\times\) year FE} \\" _n
    file write T "\cmidrule(lr){2-4}\cmidrule(lr){5-7}" _n
    file write T "Exposure measure & Broad & ISCED-97 & Generic & Broad & ISCED-97 & Generic \\" _n "\midrule" _n

    foreach w of local exposure_codes {
        local wl = cond("`w'" == "tri", "Triangular KD", "Gaussian KD")
        file write T "\textit{`wl'}"
        foreach fe of local fe_codes {
            foreach f of local field_codes {
                stars `p_`w'_`fe'_`f'' st
                file write T " & " %6.3f (`beta_`w'_`fe'_`f'') "`st'"
            }
        }
        file write T " \\" _n
        foreach fe of local fe_codes {
            foreach f of local field_codes {
                file write T " & (" %5.3f (`se_`w'_`fe'_`f'') ")"
            }
        }
        file write T " \\" _n "\quad Wald \(F\)"
        foreach fe of local fe_codes {
            foreach f of local field_codes {
                file write T " & " %5.2f (`F_`w'_`fe'_`f'')
            }
        }
        file write T " \\" _n "\quad Programs with zero exposure"
        foreach fe of local fe_codes {
            foreach f of local field_codes {
                file write T " & " %9.0fc (`zero_`w'_`fe'_`f'')
            }
        }
        file write T " \\" _n
        if "`w'" != "gau" file write T "\addlinespace" _n
    }

    file write T "\midrule" _n
    foreach s in N programs markets {
        local sl = cond("`s'" == "N", "Observations", ///
            cond("`s'" == "programs", "Programs", "Markets"))
        file write T "`sl'"
        foreach fe of local fe_codes {
            foreach f of local field_codes {
                file write T " & " %9.0fc (``s'_tri_`fe'_`f'')
            }
        }
        file write T " \\" _n
    }
    file write T "Program FE & Yes & Yes & Yes & Yes & Yes & Yes \\" _n
    file write T "Field \(\times\) year FE & Yes & Yes & Yes & Yes & Yes & Yes \\" _n
    file write T "Region \(\times\) year FE & No & No & No & Yes & Yes & Yes \\" _n
    file write T "\bottomrule" _n "\end{tabular}" _n
    file close T

    display "Table written: $output/tables/sua_fs_`model'_kd.tex"
}
