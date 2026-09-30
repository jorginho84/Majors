/*******************************************************************************
04k_sua_exposure_selectivity_trends.do

PURPOSE

Apply the selectivity-trend test of 04j to the SUA exposure measures.

Weighted exposure is E_p^k = M_m x Q_p^k, and 04j shows that Q_p^k is
mostly a decreasing function of the incumbent's own selectivity S_p. The
negative first stages of the weighted measures with region x year FE may
therefore pick up post-2012 enrollment trends that differ by S_p.

    EXPOSURE MEASURES   Total, Triangular, Gaussian (03b),
                        Triangular KD, Gaussian KD (03d)
    FIELD DEFINITIONS   Broad, ISCED-97, Generic
    SPECIFICATIONS      A  Program + field x year + region x year FE
                           (main first stage, 04 / 04b / 04i)
                        B  A + S_p decile x year FE

Levels (10 percentage-point units) and logs (log_tilde(E) x Post plus
1(E > 0) x Post). Same sample as the main first stage. Event studies in
levels (Broad) report the joint 2007-2010 pretrend p-value and the mean
2012-2016 coefficient under A and B.

S_p is inc_psu_pre, the incumbent's 2009-2011 mean PSU score; deciles are
computed across the programs of each field-definition sample. Standard
errors are clustered by pre-treatment market.

OUTPUTS

    $output/tables/sua_fs_selectivity_trends.tex
    $output/tables/sua_es_selectivity_trends.tex
    $output/sua_es_selectivity_trends.png
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

local exposure_codes     tot tri gau trikd gaukd
local raw_tot            exp_unw
local raw_tri            exp_tri50
local raw_gau            exp_gau50
local raw_trikd          exp_tri50kd
local raw_gaukd          exp_gau50kd

local lab_tot            "Total"
local lab_tri            "Triangular"
local lab_gau            "Gaussian"
local lab_trikd          "Triangular KD"
local lab_gaukd          "Gaussian KD"

tempfile results
tempname handle

postfile `handle' str4 model str8 field str6 exposure str2 spec ///
    double beta double se double p long N long programs ///
    using `results', replace

tempfile es_coefs
tempname es_handle

postfile `es_handle' str6 exposure str2 spec int year ///
    double b double lb double ub using `es_coefs', replace


/*******************************************************************************
2. ESTIMATION
*******************************************************************************/

forvalues i = 1/3 {

    local market_definition : word `i' of `market_definitions'
    local field_code        : word `i' of `field_codes'

    use "$processed/sua_incumbent_panel_kd_`market_definition'_region_2007_2016.dta", clear

    keep if inrange(ao_proceso, 2007, 2016)

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

    assert !missing(inc_psu_pre)
    bysort program_id (ao_proceso): assert inc_psu_pre == inc_psu_pre[1]

    egen byte tag_program = tag(program_id)
    xtile sel_decile = inc_psu_pre if tag_program, nquantiles(10)
    bysort program_id (sel_decile): replace sel_decile = sel_decile[1]
    assert !missing(sel_decile)

    egen long field_year  = group(field_pre ao_proceso)
    egen long region_year = group(geo_pre ao_proceso)
    egen long decile_year = group(sel_decile ao_proceso)

    local fe_A "program_id field_year region_year"
    local fe_B "program_id field_year region_year decile_year"

    gen double ln_N = ln(N_firstyear_incumbent)

    foreach w of local exposure_codes {

        bysort program_id (ao_proceso): assert `raw_`w'' == `raw_`w''[1]

        gen byte   pos_`w'   = `raw_`w'' > 0
        gen double lvl_`w'   = 10 * `raw_`w'' * post2012
        gen double log_`w'   = cond(pos_`w', ln(`raw_`w''), 0) * post2012
        gen byte   Dpost_`w' = pos_`w' * post2012

        local es_`w' ""
        forvalues y = 2007/2016 {
            if `y' != 2011 {
                gen double es_`w'_`y' = 10 * `raw_`w'' * (ao_proceso == `y')
                local es_`w' "`es_`w'' es_`w'_`y'"
            }
        }
    }


    /***************************************************************************
    2.1 STATIC FIRST STAGES
    ***************************************************************************/

    foreach model in lvl log {

        local outcome = cond("`model'" == "lvl", "N_firstyear_incumbent", "ln_N")

        foreach spec in A B {

            foreach w of local exposure_codes {

                local regressors "lvl_`w'"
                if "`model'" == "log" local regressors "log_`w' Dpost_`w'"

                display ""
                display "=== `model' | `field_code' | `w' | `spec' ==="

                reghdfe `outcome' `regressors', ///
                    absorb(`fe_`spec'') vce(cluster market_pre)

                quietly test `model'_`w'
                local p = r(p)

                quietly levelsof program_id if e(sample), local(pl)
                local np : word count `pl'

                post `handle' ("`model'") ("`field_code'") ("`w'") ("`spec'") ///
                    (_b[`model'_`w']) (_se[`model'_`w']) (`p') (e(N)) (`np')
            }
        }
    }


    /***************************************************************************
    2.2 EVENT STUDIES IN LEVELS (BROAD ONLY)
    ***************************************************************************/

    if "`field_code'" == "broad" {

        foreach spec in A B {

            foreach w of local exposure_codes {

                display ""
                display "=== event study | `w' | `spec' ==="

                reghdfe N_firstyear_incumbent `es_`w'', ///
                    absorb(`fe_`spec'') vce(cluster market_pre)

                test es_`w'_2007 es_`w'_2008 es_`w'_2009 es_`w'_2010
                local p = r(p)

                local post_mean = (_b[es_`w'_2012] + _b[es_`w'_2013] + ///
                    _b[es_`w'_2014] + _b[es_`w'_2015] + _b[es_`w'_2016]) / 5

                post `handle' ("es") ("`field_code'") ("`w'") ("`spec'") ///
                    (`post_mean') (.) (`p') (e(N)) (.)

                local cv = invttail(e(df_r), 0.025)

                forvalues y = 2007/2016 {
                    if `y' == 2011 {
                        post `es_handle' ("`w'") ("`spec'") (`y') (0) (.) (.)
                    }
                    else {
                        post `es_handle' ("`w'") ("`spec'") (`y') ///
                            (_b[es_`w'_`y']) ///
                            (_b[es_`w'_`y'] - `cv' * _se[es_`w'_`y']) ///
                            (_b[es_`w'_`y'] + `cv' * _se[es_`w'_`y'])
                    }
                }
            }
        }
    }
}

postclose `handle'
postclose `es_handle'


/*******************************************************************************
3. SUMMARY
*******************************************************************************/

use `results', clear

assert _N == 2 * 3 * 2 * 5 + 2 * 5

format beta se %9.3f
format p %9.4f

list model field exposure spec beta se p N programs, ///
    sepby(model field spec) noobs clean


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

forvalues r = 1/`=_N' {
    local key = model[`r'] + "_" + field[`r'] + "_" + exposure[`r'] + "_" + spec[`r']
    local b_`key'  = beta[`r']
    local se_`key' = se[`r']
    local p_`key'  = p[`r']
    local N_`key'  = N[`r']
}


/*
First stages: panel A (main specification) and panel B (+ decile x year).
*/

file open T using "$output/tables/sua_fs_selectivity_trends.tex", write replace
file write T "\begin{tabular}{lcccccc}" _n "\toprule" _n
file write T " & \multicolumn{3}{c}{Levels} & \multicolumn{3}{c}{Logs} \\" _n
file write T "\cmidrule(lr){2-4}\cmidrule(lr){5-7}" _n
file write T "Exposure measure & Broad & ISCED-97 & Generic & Broad & ISCED-97 & Generic \\" _n "\midrule" _n

foreach spec in A B {

    if "`spec'" == "A" file write T "\multicolumn{7}{l}{\textit{A. Field \(\times\) year \(+\) region \(\times\) year FE}} \\" _n
    else file write T "\addlinespace" _n "\multicolumn{7}{l}{\textit{B. \(+\) selectivity decile \(\times\) year FE}} \\" _n

    foreach w of local exposure_codes {
        file write T "`lab_`w''"
        foreach model in lvl log {
            foreach f of local field_codes {
                stars `p_`model'_`f'_`w'_`spec'' st
                file write T " & " %6.3f (`b_`model'_`f'_`w'_`spec'') "`st'"
            }
        }
        file write T " \\" _n
        foreach model in lvl log {
            foreach f of local field_codes {
                file write T " & (" %5.3f (`se_`model'_`f'_`w'_`spec'') ")"
            }
        }
        file write T " \\" _n
    }
}

file write T "\midrule" _n "Observations"
foreach model in lvl log {
    foreach f of local field_codes {
        file write T " & " %9.0fc (`N_`model'_`f'_tot_A')
    }
}
file write T " \\" _n "\bottomrule" _n "\end{tabular}" _n
file close T


/*
Event studies (Broad, levels): mean post coefficient and pretrend p-value.
*/

file open T using "$output/tables/sua_es_selectivity_trends.tex", write replace
file write T "\begin{tabular}{lcccc}" _n "\toprule" _n
file write T " & \multicolumn{2}{c}{A. Field \(\times\) year \(+\) region \(\times\) year FE} & \multicolumn{2}{c}{B. \(+\) selectivity decile \(\times\) year FE} \\" _n
file write T "\cmidrule(lr){2-3}\cmidrule(lr){4-5}" _n
file write T "Exposure measure & Mean 2012--16 & Pretrend \(p\) & Mean 2012--16 & Pretrend \(p\) \\" _n "\midrule" _n
foreach w of local exposure_codes {
    file write T "`lab_`w''"
    foreach spec in A B {
        file write T " & " %6.3f (`b_es_broad_`w'_`spec'') " & " %5.3f (`p_es_broad_`w'_`spec'')
    }
    file write T " \\" _n
}
file write T "\bottomrule" _n "\end{tabular}" _n
file close T

display "Tables written."


/*******************************************************************************
5. EVENT-STUDY FIGURE (BROAD, LEVELS): A VS B
*******************************************************************************/

use `es_coefs', clear

gen double x = year + cond(spec == "A", -0.12, 0.12)

local graphs ""

foreach w of local exposure_codes {

    graph twoway ///
        (rcap lb ub x if exposure == "`w'" & spec == "A", lcolor(navy%55)) ///
        (rcap lb ub x if exposure == "`w'" & spec == "B", lcolor(maroon%55)) ///
        (scatter b x if exposure == "`w'" & spec == "A", mcolor(navy) msymbol(O) msize(small)) ///
        (scatter b x if exposure == "`w'" & spec == "B", mcolor(maroon) msymbol(D) msize(small)), ///
        xline(2011, lcolor(gs8) lpattern(dash)) yline(0, lcolor(gs7)) ///
        xlabel(2007(1)2016, labsize(vsmall) angle(45)) ///
        ylabel(, labsize(vsmall) angle(horizontal) grid glcolor(gs14)) ///
        xtitle("") ytitle("") ///
        title("`lab_`w''", size(medsmall) color(black)) ///
        legend(off) ///
        graphregion(color(white)) plotregion(color(white)) scheme(s1color) ///
        name(g_`w', replace)

    local graphs "`graphs' g_`w'"
}

graph combine `graphs', rows(2) ///
    graphregion(color(white)) xsize(12) ysize(6.5) ///
    l1title("Effect of 10 pp of exposure on first-year enrollment", size(small))

graph export "$output/sua_es_selectivity_trends.png", width(2400) replace
