/*******************************************************************************
05a_sua_log_event_studies.do

PURPOSE

Estimate event studies for the logarithmic SUA first-stage exercise.

EXPOSURE MEASURES

    1. Total
    2. Triangular
    3. Gaussian

FIELD DEFINITION

    Broad field x pre-treatment region.

FIXED-EFFECT SPECIFICATIONS

    1. Baseline:
           Program FE
           Broad-field x year FE

    2. Region-year:
           Program FE
           Broad-field x year FE
           Pre-treatment region x year FE

MODEL

    log(N_firstyear_pt)
        = sum_{year != 2011}
          beta_year,k
          [log(E_p^k) x 1(t = year)]
        + fixed effects
        + error_pt

SAMPLE

Each exposure measure uses its own positive-exposure sample:

    Total:       exp_unw > 0
    Triangular:  exp_tri50 > 0
    Gaussian:    exp_gau50 > 0

Programs with zero exposure are excluded because log(0) is undefined.
Consequently, samples may differ across exposure measures.

INTERPRETATION

beta_year,k is the enrollment-exposure elasticity in the indicated year
relative to 2011, the explicitly omitted year.

INFERENCE

Standard errors are clustered by the Broad-field x pre-treatment-region
market.

OUTPUTS

    1. Baseline event-study figure in PNG and PDF.
    2. Region-year event-study figure in PNG and PDF.

No permanent event-study results dataset or Excel file is created.
*******************************************************************************/

clear all
set more off
set varabbrev off

do "code/config.do"


/*******************************************************************************
0. CHECK REQUIRED COMMAND
*******************************************************************************/

capture which reghdfe

if _rc {

    display as error ///
        "reghdfe is not installed."

    display as error ///
        "Run: ssc install reghdfe, replace"

    exit 199
}


/*******************************************************************************
1. INPUT AND GRAPH OUTPUTS
*******************************************************************************/

local input_panel ///
    "$processed/sua_incumbent_panel_w_broad_area_region_2007_2016.dta"

local graph_baseline ///
    "$output/sua_log_event_study_baseline"

local graph_regionyear ///
    "$output/sua_log_event_study_regionyear"


/*******************************************************************************
2. LOAD BROAD-FIELD PANEL
*******************************************************************************/

use "`input_panel'", clear

keep if ///
    inrange(ao_proceso, 2007, 2016)


/*
Use the same initial analytical sample as the log-log first stages.

Undefined exposure observations are excluded. Economically defined exposure
values equal to zero remain in the initial panel but are excluded separately
from the corresponding logarithmic regression.
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
The logarithmic outcome requires strictly positive enrollment.
*/

keep if ///
    N_firstyear_incumbent > 0

assert ///
    N_firstyear_incumbent > 0

isid ///
    program_id ///
    ao_proceso


/*******************************************************************************
3. REQUIRE PRE- AND POST-2012 OBSERVATIONS
*******************************************************************************/

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

assert _N > 0


/*******************************************************************************
4. VERIFY EXPOSURE VARIABLES
*******************************************************************************/

foreach raw_exposure in ///
    exp_unw ///
    exp_tri50 ///
    exp_gau50 {

    assert ///
        `raw_exposure' >= 0


    /*
    Exposure must be fixed over time within incumbent programs.
    */

    tempvar minimum_exposure maximum_exposure

    bysort program_id: ///
        egen double `minimum_exposure' = ///
            min(`raw_exposure')

    bysort program_id: ///
        egen double `maximum_exposure' = ///
            max(`raw_exposure')

    assert abs( ///
        `maximum_exposure' - ///
        `minimum_exposure' ///
    ) < 1e-10

    drop ///
        `minimum_exposure' ///
        `maximum_exposure'
}


/*******************************************************************************
5. LOGARITHMIC OUTCOME
*******************************************************************************/

gen double ln_enrollment = ///
    ln(N_firstyear_incumbent)

label variable ln_enrollment ///
    "Log first-year enrollment"

assert ///
    !missing(ln_enrollment)


/*******************************************************************************
6. POSITIVE-EXPOSURE INDICATORS AND LOG EXPOSURES
*******************************************************************************/

/*
Total exposure.
*/

gen byte positive_total = ///
    exp_unw > 0

gen double ln_exp_total = ///
    ln(exp_unw) ///
    if positive_total == 1


/*
Triangular exposure.
*/

gen byte positive_triangular = ///
    exp_tri50 > 0

gen double ln_exp_triangular = ///
    ln(exp_tri50) ///
    if positive_triangular == 1


/*
Gaussian exposure.
*/

gen byte positive_gaussian = ///
    exp_gau50 > 0

gen double ln_exp_gaussian = ///
    ln(exp_gau50) ///
    if positive_gaussian == 1


/*
Validate logarithmic exposures within their corresponding samples.
*/

assert ///
    !missing(ln_exp_total) ///
    if positive_total == 1

assert ///
    !missing(ln_exp_triangular) ///
    if positive_triangular == 1

assert ///
    !missing(ln_exp_gaussian) ///
    if positive_gaussian == 1


/*******************************************************************************
7. FIXED-EFFECT IDENTIFIERS
*******************************************************************************/

egen long log_field_year = ///
    group( ///
        field_pre ///
        ao_proceso ///
    )

egen long log_region_year = ///
    group( ///
        geo_pre ///
        ao_proceso ///
    )


/*******************************************************************************
8. MANUAL LOG EXPOSURE x YEAR INTERACTIONS

Interactions are created for:

    2007-2010
    2012-2016

No interaction is created for 2011. Therefore, 2011 is explicitly omitted.
*******************************************************************************/

foreach year in ///
    2007 2008 2009 2010 ///
    2012 2013 2014 2015 2016 {


    /*
    Total exposure.
    */

    gen double es_total_`year' = ///
        ln_exp_total * ///
        (ao_proceso == `year') ///
        if positive_total == 1


    /*
    Triangular exposure.
    */

    gen double es_triangular_`year' = ///
        ln_exp_triangular * ///
        (ao_proceso == `year') ///
        if positive_triangular == 1


    /*
    Gaussian exposure.
    */

    gen double es_gaussian_`year' = ///
        ln_exp_gaussian * ///
        (ao_proceso == `year') ///
        if positive_gaussian == 1
}


/*
All pre-2011 and post-2011 interactions must equal zero outside their
corresponding year.
*/

foreach exposure_measure in ///
    total ///
    triangular ///
    gaussian {

    foreach year in ///
        2007 2008 2009 2010 ///
        2012 2013 2014 2015 2016 {

        assert ///
            es_`exposure_measure'_`year' == 0 ///
            if ///
            positive_`exposure_measure' == 1 & ///
            ao_proceso != `year'
    }
}


/*******************************************************************************
9. INITIAL SAMPLE DIAGNOSTICS
*******************************************************************************/

egen byte tag_program = ///
    tag(program_id)

display ""
display "============================================================"
display " LOG EVENT-STUDY INITIAL SAMPLE"
display "============================================================"

count

display ///
    "Initial program-year observations = " ///
    %9.0fc r(N)


count if ///
    tag_program == 1

display ///
    "Initial incumbent programs        = " ///
    %9.0fc r(N)


foreach exposure_measure in ///
    total ///
    triangular ///
    gaussian {

    count if ///
        tag_program == 1 & ///
        positive_`exposure_measure' == 1

    display ///
        "Positive `exposure_measure' programs = " ///
        %9.0fc r(N)
}

drop tag_program


/*******************************************************************************
10. TEMPORARY EVENT-STUDY RESULTS
*******************************************************************************/

tempfile event_results
tempname results_handle

postfile `results_handle' ///
    str12 specification ///
    str12 exposure_measure ///
    int year ///
    double beta ///
    double standard_error ///
    double lower_95 ///
    double upper_95 ///
    double pretrend_F ///
    double pretrend_p ///
    long observations ///
    long programs ///
    long markets ///
    using `event_results', ///
    replace


/*******************************************************************************
11. EVENT-STUDY REGRESSIONS

Two FE specifications x three exposure measures = six regressions.
*******************************************************************************/

foreach specification in ///
    baseline ///
    regionyear {


    /***************************************************************************
    11.1 SELECT FIXED EFFECTS
    ***************************************************************************/

    if "`specification'" == "baseline" {

        local absorbed_effects ///
            program_id ///
            log_field_year

        local specification_label ///
            "Program FE + Broad-field x year FE"
    }


    if "`specification'" == "regionyear" {

        local absorbed_effects ///
            program_id ///
            log_field_year ///
            log_region_year

        local specification_label ///
            "Program FE + Broad-field x year FE + region x year FE"
    }


    /***************************************************************************
    11.2 ESTIMATE EACH EXPOSURE MEASURE
    ***************************************************************************/

    foreach exposure_measure in ///
        total ///
        triangular ///
        gaussian {


        if "`exposure_measure'" == "total" {

            local positive_sample ///
                positive_total

            local exposure_label ///
                "Total exposure"
        }


        if "`exposure_measure'" == "triangular" {

            local positive_sample ///
                positive_triangular

            local exposure_label ///
                "Triangular exposure"
        }


        if "`exposure_measure'" == "gaussian" {

            local positive_sample ///
                positive_gaussian

            local exposure_label ///
                "Gaussian exposure"
        }


        display ""
        display "============================================================"
        display " LOG EXPOSURE EVENT STUDY"
        display "============================================================"

        display ///
            "Specification = `specification_label'"

        display ///
            "Exposure      = `exposure_label'"

        display ///
            "Sample        = Positive exposure only"

        display ///
            "Omitted year  = 2011"

        display "============================================================"


        /***********************************************************************
        11.3 EVENT-STUDY REGRESSION
        ***********************************************************************/

        reghdfe ///
            ln_enrollment ///
            es_`exposure_measure'_2007 ///
            es_`exposure_measure'_2008 ///
            es_`exposure_measure'_2009 ///
            es_`exposure_measure'_2010 ///
            es_`exposure_measure'_2012 ///
            es_`exposure_measure'_2013 ///
            es_`exposure_measure'_2014 ///
            es_`exposure_measure'_2015 ///
            es_`exposure_measure'_2016 ///
            if `positive_sample' == 1, ///
            absorb( ///
                `absorbed_effects' ///
            ) ///
            vce(cluster market_pre)


        /*
        Save the effective estimation sample before running additional
        commands.
        */

        tempvar estimation_sample

        gen byte `estimation_sample' = ///
            e(sample)


        /***********************************************************************
        11.4 SAMPLE COUNTS
        ***********************************************************************/

        local observations = ///
            e(N)


        tempvar tag_estimation_program tag_estimation_market

        egen byte `tag_estimation_program' = ///
            tag(program_id) ///
            if `estimation_sample' == 1

        quietly count if ///
            `tag_estimation_program' == 1

        local programs = ///
            r(N)


        egen byte `tag_estimation_market' = ///
            tag(market_pre) ///
            if `estimation_sample' == 1

        quietly count if ///
            `tag_estimation_market' == 1

        local markets = ///
            r(N)


        /***********************************************************************
        11.5 JOINT PRETREND TEST
        ***********************************************************************/

        test ///
            es_`exposure_measure'_2007 ///
            es_`exposure_measure'_2008 ///
            es_`exposure_measure'_2009 ///
            es_`exposure_measure'_2010

        local pretrend_F = ///
            r(F)

        local pretrend_p = ///
            r(p)


        display ///
            "Joint pretrend F = " ///
            %9.4f `pretrend_F'

        display ///
            "Joint pretrend p = " ///
            %9.4f `pretrend_p'

        display ///
            "Observations     = " ///
            %9.0fc `observations'

        display ///
            "Programs         = " ///
            %9.0fc `programs'

        display ///
            "Markets          = " ///
            %9.0fc `markets'


        /***********************************************************************
        11.6 CRITICAL VALUE FOR 95% CONFIDENCE INTERVAL
        ***********************************************************************/

        local critical_value = ///
            invttail( ///
                e(df_r), ///
                0.025 ///
            )


        /***********************************************************************
        11.7 STORE ANNUAL COEFFICIENTS
        ***********************************************************************/

        forvalues year = 2007/2016 {


            /*
            Explicitly store the omitted 2011 coefficient as zero.
            */

            if `year' == 2011 {

                local beta = 0
                local standard_error = 0
                local lower_95 = 0
                local upper_95 = 0
            }


            else {

                local beta = ///
                    _b[es_`exposure_measure'_`year']

                local standard_error = ///
                    _se[es_`exposure_measure'_`year']

                local lower_95 = ///
                    `beta' - ///
                    `critical_value' * ///
                    `standard_error'

                local upper_95 = ///
                    `beta' + ///
                    `critical_value' * ///
                    `standard_error'
            }


            post `results_handle' ///
                ("`specification'") ///
                ("`exposure_measure'") ///
                (`year') ///
                (`beta') ///
                (`standard_error') ///
                (`lower_95') ///
                (`upper_95') ///
                (`pretrend_F') ///
                (`pretrend_p') ///
                (`observations') ///
                (`programs') ///
                (`markets')
        }


        drop ///
            `estimation_sample' ///
            `tag_estimation_program' ///
            `tag_estimation_market'
    }
}

postclose `results_handle'


/*******************************************************************************
12. LOAD AND VALIDATE EVENT-STUDY RESULTS
*******************************************************************************/

use `event_results', clear

count

/*
Two specifications x three exposures x ten years = 60 observations.
*/

assert r(N) == 60

isid ///
    specification ///
    exposure_measure ///
    year


/*******************************************************************************
13. LABEL AND ORDER RESULTS
*******************************************************************************/

gen str24 exposure_label = ""

replace exposure_label = ///
    "Total exposure" ///
    if exposure_measure == "total"

replace exposure_label = ///
    "Triangular" ///
    if exposure_measure == "triangular"

replace exposure_label = ///
    "Gaussian" ///
    if exposure_measure == "gaussian"

assert ///
    exposure_label != ""


gen byte exposure_order = .

replace exposure_order = 1 ///
    if exposure_measure == "total"

replace exposure_order = 2 ///
    if exposure_measure == "triangular"

replace exposure_order = 3 ///
    if exposure_measure == "gaussian"


gen byte specification_order = .

replace specification_order = 1 ///
    if specification == "baseline"

replace specification_order = 2 ///
    if specification == "regionyear"


sort ///
    specification_order ///
    exposure_order ///
    year


format ///
    beta ///
    standard_error ///
    lower_95 ///
    upper_95 ///
    pretrend_F ///
    pretrend_p ///
    %9.4f

format ///
    observations ///
    programs ///
    markets ///
    %12.0fc


/*******************************************************************************
14. DISPLAY ANNUAL COEFFICIENTS
*******************************************************************************/

display ""
display "============================================================"
display " LOG EVENT-STUDY COEFFICIENTS"
display "============================================================"

list ///
    specification ///
    exposure_label ///
    year ///
    beta ///
    standard_error ///
    lower_95 ///
    upper_95, ///
    sepby( ///
        specification ///
        exposure_measure ///
    ) ///
    noobs clean


/*******************************************************************************
15. DISPLAY COMPACT PRETREND SUMMARY
*******************************************************************************/

preserve

    keep ///
        specification ///
        exposure_measure ///
        exposure_label ///
        exposure_order ///
        pretrend_F ///
        pretrend_p ///
        observations ///
        programs ///
        markets

    duplicates drop

    isid ///
        specification ///
        exposure_measure

    count
    assert r(N) == 6

    sort ///
        specification ///
        exposure_order

    format ///
        pretrend_F ///
        %9.3f

    format ///
        pretrend_p ///
        %9.4f

    format ///
        observations ///
        programs ///
        markets ///
        %9.0fc

    display ""
    display "============================================================"
    display " LOG EVENT-STUDY PRETREND SUMMARY"
    display "============================================================"

    list ///
        specification ///
        exposure_label ///
        pretrend_F ///
        pretrend_p ///
        observations ///
        programs ///
        markets, ///
        sepby(specification) ///
        noobs clean

restore

/*******************************************************************************
16. COMMON VERTICAL SCALE
*******************************************************************************/

quietly summarize ///
    lower_95 ///
    if year != 2011, ///
    meanonly

local graph_min = ///
    r(min)


quietly summarize ///
    upper_95 ///
    if year != 2011, ///
    meanonly

local graph_max = ///
    r(max)


local graph_span = ///
    `graph_max' - `graph_min'

if `graph_span' <= 0 {

    local graph_span = 1
}


local graph_min = ///
    `graph_min' - ///
    0.08 * `graph_span'

local graph_max = ///
    `graph_max' + ///
    0.08 * `graph_span'


display ""
display ///
    "Common graph range = " ///
    %9.3f `graph_min' ///
    " to " ///
    %9.3f `graph_max'


/*******************************************************************************
17. HORIZONTAL OFFSETS
*******************************************************************************/

gen double graph_year = ///
    year

replace graph_year = ///
    year - 0.10 ///
    if exposure_measure == "total"

replace graph_year = ///
    year ///
    if exposure_measure == "triangular"

replace graph_year = ///
    year + 0.10 ///
    if exposure_measure == "gaussian"


gen byte plot_observation = ///
    year != 2011 & ///
    !missing( ///
        beta, ///
        lower_95, ///
        upper_95 ///
    )


/*******************************************************************************
18. PAPER-STYLE EVENT-STUDY FIGURES
*******************************************************************************/

foreach specification in ///
    baseline ///
    regionyear {


    /***************************************************************************
    18.1 FIGURE LABELS AND OUTPUT
    ***************************************************************************/

    if "`specification'" == "baseline" {

        local figure_title ///
            "Log exposure: field x year specification"

        local figure_subtitle ///
            "Program FE and Broad-field x year FE; 2011 omitted"

        local figure_output ///
            "`graph_baseline'"
    }


    if "`specification'" == "regionyear" {

        local figure_title ///
            "Log exposure: region x year specification"

        local figure_subtitle ///
            "Program FE, Broad-field x year FE, and region x year FE; 2011 omitted"

        local figure_output ///
            "`graph_regionyear'"
    }


    /***************************************************************************
    18.2 PRETREND P-VALUES FOR FIGURE NOTE
    ***************************************************************************/

    quietly summarize ///
        pretrend_p ///
        if ///
        specification == "`specification'" & ///
        exposure_measure == "total", ///
        meanonly

    local total_p : ///
        display %5.3f r(mean)


    quietly summarize ///
        pretrend_p ///
        if ///
        specification == "`specification'" & ///
        exposure_measure == "triangular", ///
        meanonly

    local triangular_p : ///
        display %5.3f r(mean)


    quietly summarize ///
        pretrend_p ///
        if ///
        specification == "`specification'" & ///
        exposure_measure == "gaussian", ///
        meanonly

    local gaussian_p : ///
        display %5.3f r(mean)


    /***************************************************************************
    18.3 FIGURE
    ***************************************************************************/

    twoway ///
        (rcap ///
            lower_95 ///
            upper_95 ///
            graph_year ///
            if ///
                plot_observation == 1 & ///
                specification == "`specification'" & ///
                exposure_measure == "total", ///
            lcolor(navy%55) ///
            lwidth(thin)) ///
        (rcap ///
            lower_95 ///
            upper_95 ///
            graph_year ///
            if ///
                plot_observation == 1 & ///
                specification == "`specification'" & ///
                exposure_measure == "triangular", ///
            lcolor(forest_green%55) ///
            lwidth(thin)) ///
        (rcap ///
            lower_95 ///
            upper_95 ///
            graph_year ///
            if ///
                plot_observation == 1 & ///
                specification == "`specification'" & ///
                exposure_measure == "gaussian", ///
            lcolor(maroon%55) ///
            lwidth(thin)) ///
        (scatter ///
            beta ///
            graph_year ///
            if ///
                plot_observation == 1 & ///
                specification == "`specification'" & ///
                exposure_measure == "total", ///
            msymbol(O) ///
            msize(medium) ///
            mcolor(navy) ///
            mlcolor(navy)) ///
        (scatter ///
            beta ///
            graph_year ///
            if ///
                plot_observation == 1 & ///
                specification == "`specification'" & ///
                exposure_measure == "triangular", ///
            msymbol(T) ///
            msize(medium) ///
            mcolor(forest_green) ///
            mlcolor(forest_green)) ///
        (scatter ///
            beta ///
            graph_year ///
            if ///
                plot_observation == 1 & ///
                specification == "`specification'" & ///
                exposure_measure == "gaussian", ///
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
            range(`graph_min' `graph_max') ///
        ) ///
        xlabel( ///
            2007(1)2016, ///
            labsize(small) ///
        ) ///
        ylabel( ///
            , ///
            format(%5.2f) ///
            labsize(small) ///
            angle(horizontal) ///
            grid ///
            glcolor(gs14) ///
            glwidth(vthin) ///
        ) ///
        xtitle( ///
            "Admission year", ///
            size(medsmall) ///
        ) ///
        ytitle( ///
            "Enrollment-exposure elasticity relative to 2011", ///
            size(medsmall) ///
        ) ///
        title( ///
            "`figure_title'", ///
            size(medium) ///
            color(black) ///
        ) ///
        subtitle( ///
            "`figure_subtitle'", ///
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
        note( ///
            "Positive enrollment and exposure only; samples differ by exposure measure." ///
            "95% confidence intervals; standard errors clustered by pre-treatment market." ///
            "Joint pretrend p-values: Total = `total_p'; Triangular = `triangular_p'; Gaussian = `gaussian_p'.", ///
            size(vsmall) ///
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


    /***************************************************************************
    18.4 EXPORT FIGURE
    ***************************************************************************/

    graph export ///
        "`figure_output'.png", ///
        width(2400) ///
        replace

    graph export ///
        "`figure_output'.pdf", ///
        replace
}


/*******************************************************************************
19. OUTPUT SUMMARY
*******************************************************************************/

display ""
display "============================================================"
display " LOG EVENT-STUDY OUTPUTS CREATED"
display "============================================================"

display ///
    "Baseline PNG: `graph_baseline'.png"

display ///
    "Baseline PDF: `graph_baseline'.pdf"

display ///
    "Region-year PNG: `graph_regionyear'.png"

display ///
    "Region-year PDF: `graph_regionyear'.pdf"

display ""
display "05a_sua_log_event_studies.do completed successfully."