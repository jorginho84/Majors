/*******************************************************************************
05_event_studies_exposure_comparison.do

PURPOSE

Create comparable event studies for three non-cosine SUA exposure measures:

    1. Total/unweighted exposure
    2. Selectivity-weighted triangular exposure
    3. Selectivity-weighted Gaussian exposure

SPECIFICATIONS

    baseline:
        Program FE
        Field x year FE

    regionyear:
        Program FE
        Field x year FE
        Region x year FE

COMMON FEATURES

    - Broad area x region exposure
    - Outcome: first-year incumbent enrollment
    - Common input sample across exposure measures
    - Manual exposure x year interactions
    - 2011 explicitly omitted
    - Standard errors clustered by pre-treatment market

OUTPUTS

    - Combined event-study results in .dta
    - Combined event-study and pretrend results in .xlsx
    - Baseline figure in PDF and PNG
    - Region-year figure in PDF and PNG

IMPORTANT

Each exposure is estimated separately. The construction and scaling of the
existing SUA non-cosine exposure variables are preserved.
*******************************************************************************/

clear all
set more off
set varabbrev off

do "code/config.do"


/*******************************************************************************
0. INPUTS AND OUTPUTS
*******************************************************************************/

local sua_panel ///
    "$processed/sua_incumbent_panel_w_broad_area_region_2007_2016.dta"

local results_dta ///
    "$processed/sua_event_study_exposure_comparison.dta"

local results_xlsx ///
    "$output/sua_event_study_exposure_comparison.xlsx"

local figure_baseline ///
    "$output/sua_event_study_exposure_comparison_baseline"

local figure_regionyear ///
    "$output/sua_event_study_exposure_comparison_regionyear"


/*******************************************************************************
1. LOAD MAIN SUA PANEL
*******************************************************************************/

use "`sua_panel'", clear


/*
Keep the common sample across all three exposure measures.

For the broad_area x region panel, geo_pre is the pre-treatment region.
*/

drop if missing( ///
    program_id, ///
    ao_proceso, ///
    field_pre, ///
    geo_pre, ///
    market_pre, ///
    N_firstyear_incumbent, ///
    exp_unw, ///
    exp_tri50, ///
    exp_gau50 ///
)


/*
Require programs observed both before and after SUA entry.
*/

bysort program_id: ///
    egen byte has_pre = ///
        max(ao_proceso <= 2011)

bysort program_id: ///
    egen byte has_post = ///
        max(ao_proceso >= 2012)

keep if ///
    has_pre == 1 & ///
    has_post == 1

drop ///
    has_pre ///
    has_post


/*******************************************************************************
2. SCALE EXPOSURES
*
* One unit equals 10 percentage points of exposure, matching the existing
* SUA first-stage and event-study convention.
*******************************************************************************/

gen double exp_unw10 = ///
    10 * exp_unw

gen double exp_tri10 = ///
    10 * exp_tri50

gen double exp_gau10 = ///
    10 * exp_gau50


/*******************************************************************************
3. CONSTRUCT FIXED-EFFECT IDENTIFIERS
*******************************************************************************/

/*
Field x year FE.
*/

egen long field_year = ///
    group( ///
        field_pre ///
        ao_proceso ///
    )


/*
Region x year FE.

In the broad_area_region panel, geo_pre contains the fixed pre-treatment
region used to define the exposure market.
*/

egen long region_year = ///
    group( ///
        geo_pre ///
        ao_proceso ///
    )


/*******************************************************************************
4. CREATE MANUAL EXPOSURE x YEAR INTERACTIONS
*
* The interactions are created only for:
*
*     2007-2010 and 2012-2016
*
* No interaction is created for 2011, so 2011 is genuinely and explicitly
* omitted from every regression.
*******************************************************************************/

foreach e in unw tri gau {

    if "`e'" == "unw" {
        local x exp_unw10
    }

    if "`e'" == "tri" {
        local x exp_tri10
    }

    if "`e'" == "gau" {
        local x exp_gau10
    }

    foreach y in ///
        2007 2008 2009 2010 ///
        2012 2013 2014 2015 2016 {

        gen double es_`e'_`y' = ///
            `x' * ///
            (ao_proceso == `y')
    }
}


/*******************************************************************************
5. COMMON-SAMPLE COUNTS
*******************************************************************************/

count
local N_common = r(N)


egen byte tag_program = ///
    tag(program_id)

count if tag_program == 1
local programs_common = r(N)


egen byte tag_market = ///
    tag(market_pre)

count if tag_market == 1
local markets_common = r(N)


display ""
display "============================================================"
display " SUA EVENT-STUDY COMMON INPUT SAMPLE"
display "============================================================"

display ///
    "Observations = " ///
    %9.0fc `N_common'

display ///
    "Programs     = " ///
    %9.0fc `programs_common'

display ///
    "Markets      = " ///
    %9.0fc `markets_common'


drop ///
    tag_program ///
    tag_market


/*******************************************************************************
6. RESULTS DATASET
*******************************************************************************/

tempfile eventstudy_results

tempname post_results


postfile `post_results' ///
    str12 specification ///
    str12 exposure ///
    int year ///
    double beta ///
    double se ///
    double lb ///
    double ub ///
    double pre_F ///
    double pre_p ///
    long N ///
    long programs ///
    long markets ///
    using `eventstudy_results', ///
    replace


/*******************************************************************************
7. EVENT-STUDY ESTIMATION
*
* Six regressions:
*
*     baseline   x total/unweighted
*     baseline   x triangular
*     baseline   x gaussian
*     regionyear x total/unweighted
*     regionyear x triangular
*     regionyear x gaussian
*******************************************************************************/

foreach specification in baseline regionyear {

    /*
    Select absorbed fixed effects.
    */

    if "`specification'" == "baseline" {

        local absorbed_fe ///
            program_id ///
            field_year

        local specification_title ///
            "PROGRAM FE + FIELD x YEAR FE"
    }

    if "`specification'" == "regionyear" {

        local absorbed_fe ///
            program_id ///
            field_year ///
            region_year

        local specification_title ///
            "PROGRAM FE + FIELD x YEAR FE + REGION x YEAR FE"
    }


    foreach e in unw tri gau {

        if "`e'" == "unw" {
            local exposure_title ///
                "TOTAL/UNWEIGHTED EXPOSURE"
        }

        if "`e'" == "tri" {
            local exposure_title ///
                "TRIANGULAR EXPOSURE"
        }

        if "`e'" == "gau" {
            local exposure_title ///
                "GAUSSIAN EXPOSURE"
        }


        display ""
        display "============================================================"
        display "`specification_title'"
        display "`exposure_title'"
        display "============================================================"


        /*
        Event-study regression.
        */

        reghdfe ///
            N_firstyear_incumbent ///
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
            vce(cluster market_pre)


        /*
        Record effective estimation-sample counts.
        */

        local N_estimation = e(N)

        quietly levelsof ///
            program_id ///
            if e(sample), ///
            local(sample_programs)

        local N_programs : ///
            word count `sample_programs'


        quietly levelsof ///
            market_pre ///
            if e(sample), ///
            local(sample_markets)

        local N_markets : ///
            word count `sample_markets'


        /*
        Joint test of all four pre-treatment coefficients.
        */

        test ///
            es_`e'_2007 ///
            es_`e'_2008 ///
            es_`e'_2009 ///
            es_`e'_2010

        local pre_F = r(F)
        local pre_p = r(p)


        display ///
            "Joint pretrend F = " ///
            %9.4f `pre_F'

        display ///
            "Joint pretrend p = " ///
            %9.4f `pre_p'

        display ///
            "Estimation N     = " ///
            %9.0fc `N_estimation'

        display ///
            "Programs         = " ///
            %9.0fc `N_programs'

        display ///
            "Markets          = " ///
            %9.0fc `N_markets'


        /*
        Critical value for 95% confidence intervals.
        */

        local critical_value = ///
            invttail(e(df_r), 0.025)


        /*
        Store coefficients for 2007-2016.

        The omitted 2011 coefficient is stored as zero for completeness,
        but it is not plotted with a confidence interval.
        */

        forvalues y = 2007/2016 {

            if `y' == 2011 {

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

                local lb = ///
                    `b' - ///
                    `critical_value' * `se'

                local ub = ///
                    `b' + ///
                    `critical_value' * `se'
            }


            post `post_results' ///
                ("`specification'") ///
                ("`e'") ///
                (`y') ///
                (`b') ///
                (`se') ///
                (`lb') ///
                (`ub') ///
                (`pre_F') ///
                (`pre_p') ///
                (`N_estimation') ///
                (`N_programs') ///
                (`N_markets')
        }
    }
}


postclose `post_results'


/*******************************************************************************
8. LOAD AND VALIDATE COMBINED RESULTS
*******************************************************************************/

use `eventstudy_results', clear


/*
Two specifications x three exposures x ten years = 60 rows.
*/

count

display ///
    "Combined event-study result rows = " ///
    %9.0fc r(N)

assert r(N) == 60


isid ///
    specification ///
    exposure ///
    year


sort ///
    specification ///
    exposure ///
    year


/*******************************************************************************
9. LABEL EXPOSURES
*******************************************************************************/

gen str24 exposure_label = ""

replace exposure_label = ///
    "Total exposure" ///
    if exposure == "unw"

replace exposure_label = ///
    "Triangular" ///
    if exposure == "tri"

replace exposure_label = ///
    "Gaussian" ///
    if exposure == "gau"

assert exposure_label != ""


order ///
    specification ///
    exposure ///
    exposure_label ///
    year ///
    beta ///
    se ///
    lb ///
    ub ///
    pre_F ///
    pre_p ///
    N ///
    programs ///
    markets


format ///
    beta ///
    se ///
    lb ///
    ub ///
    pre_F ///
    pre_p ///
    %9.4f


/*******************************************************************************
10. DISPLAY DETAILED RESULTS
*******************************************************************************/

list ///
    specification ///
    exposure_label ///
    year ///
    beta ///
    se ///
    lb ///
    ub, ///
    sepby( ///
        specification ///
        exposure ///
    ) ///
    noobs


/*******************************************************************************
11. SAVE COMBINED RESULTS
*******************************************************************************/

save ///
    "`results_dta'", ///
    replace


/*
The first Excel sheet contains all 60 event-study rows.
*/

export excel ///
    using "`results_xlsx'", ///
    sheet("event_study") ///
    firstrow(variables) ///
    replace


display ""
display ///
    "Saved combined results: `results_dta'"

display ///
    "Exported combined results: `results_xlsx'"


/*******************************************************************************
12. COMPACT JOINT PRETREND SUMMARY
*
* This produces exactly six rows:
*
*     2 specifications x 3 exposure measures
*******************************************************************************/

preserve

    keep ///
        specification ///
        exposure ///
        exposure_label ///
        pre_F ///
        pre_p ///
        N ///
        programs ///
        markets

    duplicates drop

    isid ///
        specification ///
        exposure

    count
    assert r(N) == 6

    sort ///
        specification ///
        exposure


    display ""
    display "============================================================"
    display " JOINT PRETREND TESTS"
    display "============================================================"


    format ///
        pre_F ///
        pre_p ///
        %9.4f


    list ///
        specification ///
        exposure_label ///
        pre_F ///
        pre_p ///
        N ///
        programs ///
        markets, ///
        sepby(specification) ///
        noobs clean


    /*
    Add the compact six-row summary as a second Excel sheet.
    */

    export excel ///
        using "`results_xlsx'", ///
        sheet("pretrends", replace) ///
        firstrow(variables)

restore


/*******************************************************************************
13. COMMON GRAPH SCALE
*
* Use the same vertical scale for baseline and region-year figures so the
* coefficient paths and confidence intervals are directly comparable.
*******************************************************************************/

quietly summarize ///
    lb ///
    if year != 2011, ///
    meanonly

local y_min = ///
    min(floor(r(min)), 0)


quietly summarize ///
    ub ///
    if year != 2011, ///
    meanonly

local y_max = ///
    max(ceil(r(max)), 0)


local y_span = ///
    `y_max' - `y_min'

local y_step = ///
    ceil(`y_span' / 4)

if `y_step' <= 0 {
    local y_step = 1
}


display ""
display ///
    "Common figure range: " ///
    %9.2f `y_min' ///
    " to " ///
    %9.2f `y_max'


/*******************************************************************************
14. HORIZONTAL OFFSETS FOR FIGURES
*******************************************************************************/

gen double year_plot = year

replace year_plot = ///
    year - 0.10 ///
    if exposure == "unw"

replace year_plot = ///
    year ///
    if exposure == "tri"

replace year_plot = ///
    year + 0.10 ///
    if exposure == "gau"


gen byte plot_ok = ///
    !missing(beta) & ///
    !missing(lb) & ///
    !missing(ub) & ///
    year != 2011


/*******************************************************************************
15. PAPER-STYLE FIGURES
*******************************************************************************/

foreach specification in baseline regionyear {

    if "`specification'" == "baseline" {

        local figure_title ///
            "Baseline specification"

        local figure_subtitle ///
            "Program FE and field x year FE"

        local figure_output ///
            "`figure_baseline'"
    }

    if "`specification'" == "regionyear" {

        local figure_title ///
            "Region x year specification"

        local figure_subtitle ///
            "Program FE, field x year FE, and region x year FE"

        local figure_output ///
            "`figure_regionyear'"
    }


    twoway ///
        (rcap lb ub year_plot ///
            if ///
                plot_ok & ///
                specification == "`specification'" & ///
                exposure == "unw", ///
            lcolor(navy%55) ///
            lwidth(thin)) ///
        (rcap lb ub year_plot ///
            if ///
                plot_ok & ///
                specification == "`specification'" & ///
                exposure == "tri", ///
            lcolor(forest_green%55) ///
            lwidth(thin)) ///
        (rcap lb ub year_plot ///
            if ///
                plot_ok & ///
                specification == "`specification'" & ///
                exposure == "gau", ///
            lcolor(maroon%55) ///
            lwidth(thin)) ///
        (scatter beta year_plot ///
            if ///
                plot_ok & ///
                specification == "`specification'" & ///
                exposure == "unw", ///
            msymbol(O) ///
            msize(medium) ///
            mcolor(navy) ///
            mlcolor(navy)) ///
        (scatter beta year_plot ///
            if ///
                plot_ok & ///
                specification == "`specification'" & ///
                exposure == "tri", ///
            msymbol(T) ///
            msize(medium) ///
            mcolor(forest_green) ///
            mlcolor(forest_green)) ///
        (scatter beta year_plot ///
            if ///
                plot_ok & ///
                specification == "`specification'" & ///
                exposure == "gau", ///
            msymbol(D) ///
            msize(medium) ///
            mcolor(maroon) ///
            mlcolor(maroon)) ///
        , ///
        xline( ///
            2011, ///
            lcolor(gs8) ///
            lpattern(dash) ///
            lwidth(medthin) ///
        ) ///
        yline( ///
            0, ///
            lcolor(gs7) ///
            lpattern(solid) ///
            lwidth(medthin) ///
        ) ///
        xscale( ///
            range(2006.75 2016.25) ///
        ) ///
        yscale( ///
            range(`y_min' `y_max') ///
        ) ///
        xlabel( ///
            2007(1)2016, ///
            labsize(small) ///
        ) ///
       ylabel( ///
			`y_min'(`y_step')`y_max', ///
			format(%9.0f) ///
			labsize(small) ///
			angle(horizontal) ///
			grid ///
			glcolor(gs14) ///
			glwidth(vthin) ///
		) ///
        xtitle( ///
            "Year", ///
            size(medsmall) ///
        ) ///
        ytitle( ///
            "Effect on first-year enrollment", ///
            size(medsmall) ///
        ) ///
        title( ///
            "`figure_title'", ///
            size(medium) ///
            color(black) ///
        ) ///
        subtitle( ///
            "`figure_subtitle'; 2011 omitted", ///
            size(small) ///
            color(gs6) ///
        ) ///
        legend( ///
            order( ///
                4 "Total exposure" ///
                5 "Triangular" ///
                6 "Gaussian" ///
            ) ///
            rows(1) ///
            position(6) ///
            region( ///
                lcolor(none) ///
                fcolor(none) ///
            ) ///
            size(small) ///
        ) ///
        graphregion( ///
            color(white) ///
            margin(medsmall) ///
        ) ///
        plotregion( ///
            color(white) ///
        ) ///
        bgcolor(white) ///
        scheme(s1color)


    graph export ///
        "`figure_output'.pdf", ///
        replace

    graph export ///
        "`figure_output'.png", ///
        width(2400) ///
        replace
}


/*******************************************************************************
16. OUTPUT SUMMARY
*******************************************************************************/

display ""
display "============================================================"
display " OUTPUTS CREATED"
display "============================================================"

display ///
    "Combined DTA: `results_dta'"

display ///
    "Combined XLSX: `results_xlsx'"

display ///
    "Baseline PDF: `figure_baseline'.pdf"

display ///
    "Baseline PNG: `figure_baseline'.png"

display ///
    "Region-year PDF: `figure_regionyear'.pdf"

display ///
    "Region-year PNG: `figure_regionyear'.png"

display ""
display "05_event_studies_exposure_comparison.do completed successfully."
