/*******************************************************************************
07_cosine_event_studies.do

PURPOSE

Compare event-study estimates for three cosine exposure measures:

1. Original Geo-PSU cosine
   - vector: school region × PSU bin

2. PSU cosine, same region × field
   - vector: PSU bin
   - incumbent-entrant pairs restricted to same university region × field

3. Geo-PSU cosine, same region × field
   - vector: school region × PSU bin
   - incumbent-entrant pairs restricted to same university region × field

COMMON SAMPLE:
    All three exposures must be observed.

OUTCOME:
    N_firstyear

UNIT:
    SIES codigo_unico × year

SPECIFICATIONS:

1. Baseline, for all three exposure measures:
       Program FE
       Field × year FE

2. Region-year robustness, for the original Geo-PSU cosine:
       Program FE
       Field × year FE
       Region × year FE

    SE clustered by program in both specifications.

REFERENCE YEAR:
    2011

IMPORTANT:
    Year × exposure interactions are created manually so that
    2011 is genuinely omitted.
*******************************************************************************/

clear all
set more off
set varabbrev off

do "code/config.do"


/*******************************************************************************
0. INPUTS
*******************************************************************************/

local panel ///
    "$processed/sua_exposure/sies_program_year_with_demre_2007_2016.dta"

local roster ///
    "$processed/sua_exposure/sua_university_sies_roster.dta"

local exp_orig ///
    "$processed/cosine_exposure_incumbents_2011_final.dta"

local exp_rf ///
    "$processed/cosine_exposure_incumbents_2011_same_region_field.dta"


/*******************************************************************************
1. NATIVE SIES PROGRAM-YEAR PANEL
*******************************************************************************/

use "`panel'", clear

keep if inrange(ao_proceso, 2007, 2016)

isid codigo_unico ao_proceso


/*******************************************************************************
2. ATTACH SUA ROSTER
*******************************************************************************/

preserve

    use "`roster'", clear

    keep ///
        cod_inst ///
        sigla_universidad ///
        first_sua_year ///
        entrant_2012

    duplicates drop

    isid cod_inst

    tempfile roster_clean
    save `roster_clean', replace

restore


merge m:1 cod_inst ///
    using `roster_clean', ///
    keep(master match) ///
    gen(_m_roster)


keep if _m_roster == 3
drop _m_roster


/*
Keep incumbent SUA universities only.
*/

keep if entrant_2012 == 0


/*******************************************************************************
3. ORIGINAL COSINE EXPOSURE
*******************************************************************************/

preserve

    use "`exp_orig'", clear

    isid codigo_unico_2011

    rename ///
        codigo_unico_2011 ///
        codigo_unico

    keep ///
        codigo_unico ///
        cosine_exposure_std

    rename ///
        cosine_exposure_std ///
        z_exp_orig

    tempfile orig_clean
    save `orig_clean', replace

restore


merge m:1 codigo_unico ///
    using `orig_clean', ///
    gen(_m_orig)

tabulate _m_orig, missing

drop if _m_orig == 2
drop _m_orig


/*******************************************************************************
4. RESTRICTED COSINE EXPOSURES
*******************************************************************************/

preserve

    use "`exp_rf'", clear

    isid codigo_unico_2011

    rename ///
        codigo_unico_2011 ///
        codigo_unico

    keep ///
        codigo_unico ///
        z_exp_psu_rf ///
        z_exp_geo_rf

    tempfile rf_clean
    save `rf_clean', replace

restore


merge m:1 codigo_unico ///
    using `rf_clean', ///
    gen(_m_rf)

tabulate _m_rf, missing

drop if _m_rf == 2
drop _m_rf


/*******************************************************************************
5. COMMON EXPOSURE SAMPLE
*******************************************************************************/

drop if missing( ///
    N_firstyear, ///
    z_exp_orig, ///
    z_exp_psu_rf, ///
    z_exp_geo_rf ///
)


/*
Require programs observed both before and after 2012.
*/

bysort codigo_unico: ///
    egen byte has_pre = ///
        max(ao_proceso <= 2011)

bysort codigo_unico: ///
    egen byte has_post = ///
        max(ao_proceso >= 2012)

keep if ///
    has_pre == 1 & ///
    has_post == 1

drop has_pre has_post


isid codigo_unico ao_proceso


/*******************************************************************************
6. FIX FIELD AND REGION AT 2011
*
* Same construction used in the original cosine first stage.
*******************************************************************************/

gen str56 field_tmp = ///
    area_conocimiento ///
    if ao_proceso == 2011


bysort codigo_unico: ///
    egen str56 field_pre = ///
        mode(field_tmp), ///
        minmode

drop field_tmp


gen double region_tmp = ///
    id_region ///
    if ao_proceso == 2011

bysort codigo_unico: ///
    egen double region_pre = ///
        max(region_tmp)

drop region_tmp


drop if missing(field_pre) | ///
    field_pre == ""

drop if missing(region_pre)


/*******************************************************************************
7. ESTIMATION IDENTIFIERS
*******************************************************************************/

egen long program_id = ///
    group(codigo_unico)


egen long field_year = ///
    group( ///
        field_pre ///
        ao_proceso ///
    )


egen long region_year = ///
    group( ///
        region_pre ///
        ao_proceso ///
    )


/*******************************************************************************
8. SAMPLE DIAGNOSTICS
*******************************************************************************/

count
local N_obs = r(N)


egen byte tag_prog = ///
    tag(program_id)

count if tag_prog
local N_prog = r(N)


display ""
display "===== COSINE EVENT-STUDY SAMPLE ====="

display ///
    "Program-year observations = " ///
    %9.0fc `N_obs'

display ///
    "Programs = " ///
    %9.0fc `N_prog'


/*
Exposure correlations in common sample.
*/

pwcorr ///
    z_exp_orig ///
    z_exp_psu_rf ///
    z_exp_geo_rf


/*******************************************************************************
9. RESULTS DATASET
*******************************************************************************/

tempfile cos_es

tempname post_cos


postfile `post_cos' ///
    str12 specification ///
    str8 exposure ///
    int year ///
    double beta ///
    double se ///
    double lb ///
    double ub ///
    double pre_F ///
    double pre_p ///
    using `cos_es', ///
    replace


/*******************************************************************************
10. EVENT STUDIES
*
* Manual interactions guarantee that 2011 is genuinely omitted.
*******************************************************************************/

foreach specification in baseline regionyear {

    if "`specification'" == "baseline" {
        local exposure_list orig psu geo
        local absorbed_fe program_id field_year
    }

    if "`specification'" == "regionyear" {
        local exposure_list orig
        local absorbed_fe program_id field_year region_year
    }

    foreach e of local exposure_list {

    /*
    Select standardized exposure.
    */

    if "`e'" == "orig" {
        local x z_exp_orig
    }

    if "`e'" == "psu" {
        local x z_exp_psu_rf
    }

    if "`e'" == "geo" {
        local x z_exp_geo_rf
    }


    display ""
    display "=========================================="
    display "COSINE EVENT STUDY: `e' - `specification'"
    display "=========================================="


    /*
    Create year-specific interactions.
    2011 is intentionally absent.
    */

    foreach y in ///
        2007 ///
        2008 ///
        2009 ///
        2010 ///
        2012 ///
        2013 ///
        2014 ///
        2015 ///
        2016 {

        capture drop es_`e'_`y'

        gen double es_`e'_`y' = ///
            `x' * ///
            (ao_proceso == `y')
    }


    /*
    Event-study regression.
    */

    reghdfe ///
        N_firstyear ///
        es_`e'_2007 ///
        es_`e'_2008 ///
        es_`e'_2009 ///
        es_`e'_2010 ///
        es_`e'_2012 ///
        es_`e'_2013 ///
        es_`e'_2014 ///
        es_`e'_2015 ///
        es_`e'_2016, ///
        absorb( ///
            `absorbed_fe' ///
        ) ///
        vce(cluster program_id)


    /*
    Joint pre-trend test:
    H0: beta_2007 = ... = beta_2010 = 0
    */

    test ///
        es_`e'_2007 ///
        es_`e'_2008 ///
        es_`e'_2009 ///
        es_`e'_2010


    local pre_F = r(F)
    local pre_p = r(p)


    display ///
        "Pretrend F = " ///
        %8.3f `pre_F'

    display ///
        "Pretrend p = " ///
        %8.4f `pre_p'


    /*
    Store annual estimates.
    */

    forvalues y = 2007/2016 {

        if `y' == 2011 {

            /*
            Genuine reference year.
            */

            local b  = 0
            local se = 0
            local lb = 0
            local ub = 0
        }

        else {

            local b = ///
                _b[es_`e'_`y']

            local se = ///
                _se[es_`e'_`y']

            local crit = ///
                invttail(e(df_r), 0.025)

            local lb = ///
                `b' - `crit' * `se'

            local ub = ///
                `b' + `crit' * `se'
        }


        post `post_cos' ///
            ("`specification'") ///
            ("`e'") ///
            (`y') ///
            (`b') ///
            (`se') ///
            (`lb') ///
            (`ub') ///
            (`pre_F') ///
            (`pre_p')
    }
}

}


/*******************************************************************************
10.1 CLOSE RESULTS FILE
*******************************************************************************/

postclose `post_cos'


/*******************************************************************************
11. LOAD AND VERIFY RESULTS
*******************************************************************************/

use `cos_es', clear


count

display ///
    "Event-study result rows = " ///
    %9.0fc r(N)

/*
Three baseline exposures plus one region-year exposure, each with ten years.
*/

assert r(N) == 40


isid specification exposure year

sort specification exposure year


list ///
    specification ///
    exposure ///
    year ///
    beta ///
    se ///
    lb ///
    ub ///
    pre_F ///
    pre_p, ///
    sepby(specification exposure) ///
    noobs


/*******************************************************************************
12. LABEL EXPOSURES
*******************************************************************************/

gen byte exp_id = .


replace exp_id = 1 ///
    if exposure == "orig"

replace exp_id = 2 ///
    if exposure == "psu"

replace exp_id = 3 ///
    if exposure == "geo"


assert !missing(exp_id)


label define cos_lbl ///
    1 "Original Geo-PSU" ///
    2 "PSU, same region x field" ///
    3 "Geo-PSU, same region x field"

label values exp_id cos_lbl


/*******************************************************************************
13. HORIZONTAL OFFSETS
*******************************************************************************/

gen double year_plot = year


replace year_plot = ///
    year - 0.10 ///
    if exposure == "orig"


replace year_plot = ///
    year ///
    if exposure == "psu"


replace year_plot = ///
    year + 0.10 ///
    if exposure == "geo"


/*******************************************************************************
14. VALID OBSERVATIONS FOR PLOTTING
*******************************************************************************/

gen byte plot_ok = ///
    !missing(beta) & ///
    !missing(lb) & ///
    !missing(ub)


count if plot_ok

display ///
    "Valid graph points = " ///
    %9.0fc r(N)


assert r(N) == 40


/*******************************************************************************
15. FIGURE 2
*
* Same paper-style format as the SUA exposure event-study figure.
*
* 2011 is shown as ONE common black reference point rather than three
* overlapping exposure-specific markers.
*******************************************************************************/

twoway ///
    (rcap lb ub year_plot ///
        if plot_ok & ///
        specification == "baseline" & ///
        year != 2011 & ///
        exposure == "orig", ///
        lcolor(navy%55) ///
        lwidth(thin)) ///
    (rcap lb ub year_plot ///
        if plot_ok & ///
        specification == "baseline" & ///
        year != 2011 & ///
        exposure == "psu", ///
        lcolor(forest_green%55) ///
        lwidth(thin)) ///
    (rcap lb ub year_plot ///
        if plot_ok & ///
        specification == "baseline" & ///
        year != 2011 & ///
        exposure == "geo", ///
        lcolor(maroon%55) ///
        lwidth(thin)) ///
    (scatter beta year_plot ///
        if plot_ok & ///
        specification == "baseline" & ///
        year != 2011 & ///
        exposure == "orig", ///
        msymbol(O) ///
        msize(medlarge) ///
        mcolor(navy) ///
        mlcolor(navy)) ///
    (scatter beta year_plot ///
        if plot_ok & ///
        specification == "baseline" & ///
        year != 2011 & ///
        exposure == "psu", ///
        msymbol(T) ///
        msize(medlarge) ///
        mcolor(forest_green) ///
        mlcolor(forest_green)) ///
    (scatter beta year_plot ///
        if plot_ok & ///
        specification == "baseline" & ///
        year != 2011 & ///
        exposure == "geo", ///
        msymbol(D) ///
        msize(medlarge) ///
        mcolor(maroon) ///
        mlcolor(maroon)) ///
    (scatteri 0 2011, ///
        msymbol(O) ///
        msize(medsmall) ///
        mcolor(black) ///
        mlcolor(black)) ///
    , ///
    xline(2011, ///
        lcolor(gs8) ///
        lpattern(dash) ///
        lwidth(medthin)) ///
    yline(0, ///
        lcolor(gs7) ///
        lpattern(solid) ///
        lwidth(medthin)) ///
    xlabel( ///
        2007(1)2016, ///
        labsize(medsmall) ///
    ) ///
    ylabel(, ///
        format(%9.0f) ///
        labsize(medsmall) ///
        grid ///
        glcolor(gs14) ///
        glwidth(vthin) ///
    ) ///
    xtitle( ///
        "Year", ///
        size(medium) ///
    ) ///
    ytitle( ///
        "Effect on first-year enrollment", ///
        size(medium) ///
    ) ///
    title( ///
        "Event study: cosine exposure and incumbent enrollment", ///
        size(medium) ///
        color(black) ///
    ) ///
    subtitle( ///
        "95% confidence intervals; 2011 omitted", ///
        size(small) ///
        color(gs6) ///
    ) ///
    legend( ///
        order( ///
            4 "Original Geo-PSU" ///
            5 "PSU, same region x field" ///
            6 "Geo-PSU, same region x field" ///
        ) ///
        rows(1) ///
        position(6) ///
        region( ///
            lcolor(none) ///
            fcolor(none) ///
        ) ///
        size(small) ///
    ) ///
    graphregion(color(white)) ///
    plotregion(color(white)) ///
    bgcolor(white)


graph export ///
    "$output/cosine_event_study_three_exposures_revised.pdf", ///
    replace



/*******************************************************************************
17. COMPACT PRE-TREND RESULTS
*******************************************************************************/

display ""
display "===== COSINE PRE-TREND TESTS ====="


preserve

    keep ///
        specification ///
        exposure ///
        pre_F ///
        pre_p

    duplicates drop

    sort specification exposure

    list, ///
        noobs clean

restore

