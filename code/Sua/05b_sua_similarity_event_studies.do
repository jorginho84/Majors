/*******************************************************************************
05b_sua_similarity_event_studies.do

PURPOSE

Estimate event studies for conditional PSU similarity within exposed SUA
markets, using:

    1. Levels
    2. Logarithms


DECOMPOSITION

    E_p^k = M_m * Q_p^k

where:

    M_m   = entrant share of total market enrollment
    Q_p^k = PSU similarity with entrants, conditional on entrant presence


MEASURES

    1. Triangular conditional similarity
    2. Gaussian conditional similarity


SAMPLE

Levels:

    - Markets with positive entrant presence
    - Q = 0 retained
    - First-year enrollment may equal zero

Logs:

    - Markets with positive entrant presence
    - Positive first-year enrollment
    - Q = 0 retained


LOG TRANSFORMATION

    log_tilde(Q_p^k) =
        log(Q_p^k)     if Q_p^k > 0
        0              if Q_p^k = 0

For every event year, the log specification also includes:

    1(Q_p^k > 0) x 1(t = s)

These indicator interactions are controls and are not plotted.


SPECIFICATION

    Program fixed effects
    Broad-field x year fixed effects
    Pre-treatment region x year fixed effects
    Standard errors clustered by pre-treatment market
    2011 explicitly omitted


INTERPRETATION

Levels:

    Each plotted coefficient measures the enrollment association
    corresponding to a 0.10 increase in conditional similarity,
    relative to 2011.

Logs:

    Each plotted coefficient is the enrollment-similarity elasticity
    associated with log similarity in year s relative to 2011,
    while retaining Q = 0 observations through the indicator controls.
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
1. INPUT AND OUTPUTS
*******************************************************************************/

local input_panel ///
    "$processed/sua_incumbent_panel_w_broad_area_region_2007_2016.dta"

local graph_levels ///
    "$output/sua_similarity_event_study_altfe"

local graph_logs ///
    "$output/sua_similarity_log_event_study_altfe"


/*******************************************************************************
2. COMMON PANEL
*******************************************************************************/

use "`input_panel'", clear

keep if ///
    inrange(ao_proceso, 2007, 2016)

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

isid ///
    program_id ///
    ao_proceso

assert ///
    N_firstyear_incumbent >= 0

assert ///
    exp_unw >= 0

assert ///
    exp_tri50 >= 0

assert ///
    exp_gau50 >= 0


/*
Require programs to appear both before and after SUA entry
in the common panel.
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
3. EXPOSED MARKETS AND CONDITIONAL SIMILARITY
*******************************************************************************/

/*
Q is defined only for markets with positive entrant presence.
*/

gen double entrant_share = ///
    exp_unw

keep if ///
    entrant_share > 0


gen double q_tri = ///
    exp_tri50 / entrant_share

gen double q_gau = ///
    exp_gau50 / entrant_share


label variable q_tri ///
    "Triangular similarity conditional on entrants"

label variable q_gau ///
    "Gaussian similarity conditional on entrants"


assert inrange( ///
    q_tri, ///
    0, ///
    1.0000001 ///
)

assert inrange( ///
    q_gau, ///
    0, ///
    1.0000001 ///
)


/*
Verify decomposition.
*/

assert ///
    reldif( ///
        exp_tri50, ///
        entrant_share * q_tri ///
    ) < 1e-8

assert ///
    reldif( ///
        exp_gau50, ///
        entrant_share * q_gau ///
    ) < 1e-8


/*
Q must be fixed over time within program.
*/

foreach q_variable in ///
    q_tri ///
    q_gau {

    tempvar q_min q_max

    bysort program_id: ///
        egen double `q_min' = ///
            min(`q_variable')

    bysort program_id: ///
        egen double `q_max' = ///
            max(`q_variable')

    assert ///
        abs( ///
            `q_max' - ///
            `q_min' ///
        ) < 1e-10

    drop ///
        `q_min' ///
        `q_max'
}


/*******************************************************************************
4. FIXED-EFFECT IDENTIFIERS
*******************************************************************************/

egen long sim_field_year = ///
    group( ///
        field_pre ///
        ao_proceso ///
    )

egen long sim_region_year = ///
    group( ///
        geo_pre ///
        ao_proceso ///
    )


/*******************************************************************************
5. LOG OUTCOME AND ZERO-PRESERVING LOG Q
*******************************************************************************/

/*
Log outcome.
*/

gen double ln_enrollment = ///
    ln(N_firstyear_incumbent) ///
    if N_firstyear_incumbent > 0


/*
Positive-Q indicators.
*/

gen byte D_q_tri = ///
    q_tri > 0

gen byte D_q_gau = ///
    q_gau > 0


/*
log_tilde(Q).
*/

gen double ln_q_tri = 0

replace ln_q_tri = ///
    ln(q_tri) ///
    if q_tri > 0


gen double ln_q_gau = 0

replace ln_q_gau = ///
    ln(q_gau) ///
    if q_gau > 0


assert ///
    ln_q_tri == 0 ///
    if q_tri == 0

assert ///
    ln_q_gau == 0 ///
    if q_gau == 0


/*******************************************************************************
6. ESTIMATION SAMPLES
*******************************************************************************/

/*
Levels retain all observations in exposed markets.
*/

gen byte sample_levels = 1


/*
Logs require positive enrollment, but Q = 0 is retained.
*/

gen byte sample_logs = ///
    N_firstyear_incumbent > 0


/*
Require pre and post support inside the log-outcome sample.
*/

bysort program_id: ///
    egen byte log_has_pre = ///
        max( ///
            sample_logs == 1 & ///
            ao_proceso <= 2011 ///
        )

bysort program_id: ///
    egen byte log_has_post = ///
        max( ///
            sample_logs == 1 & ///
            ao_proceso >= 2012 ///
        )

replace sample_logs = 0 ///
    if ///
        log_has_pre == 0 | ///
        log_has_post == 0

drop ///
    log_has_pre ///
    log_has_post


/*******************************************************************************
7. MANUAL YEAR INTERACTIONS
*
* 2011 explicitly omitted.
*******************************************************************************/

foreach year in ///
    2007 2008 2009 2010 ///
    2012 2013 2014 2015 2016 {


    /*
    LEVELS

    10 * Q x year

    One unit corresponds to a 0.10 increase in Q.
    */

    gen double es_lvl_tri_`year' = ///
        10 * ///
        q_tri * ///
        (ao_proceso == `year')

    gen double es_lvl_gau_`year' = ///
        10 * ///
        q_gau * ///
        (ao_proceso == `year')


    /*
    LOGS

    log_tilde(Q) x year.
    */

    gen double es_log_tri_`year' = ///
        ln_q_tri * ///
        (ao_proceso == `year')

    gen double es_log_gau_`year' = ///
        ln_q_gau * ///
        (ao_proceso == `year')


    /*
    Positive-Q indicator x year.

    These enter only the log regressions.
    */

    gen byte D_tri_`year' = ///
        D_q_tri * ///
        (ao_proceso == `year')

    gen byte D_gau_`year' = ///
        D_q_gau * ///
        (ao_proceso == `year')
}


/*
Checks.
*/

foreach measure in ///
    tri ///
    gau {

    foreach year in ///
        2007 2008 2009 2010 ///
        2012 2013 2014 2015 2016 {

        assert ///
            es_lvl_`measure'_`year' == 0 ///
            if ao_proceso != `year'

        assert ///
            es_log_`measure'_`year' == 0 ///
            if ao_proceso != `year'

        assert ///
            D_`measure'_`year' == 0 ///
            if ao_proceso != `year'
    }
}


/*******************************************************************************
8. INITIAL SAMPLE DIAGNOSTICS
*******************************************************************************/

egen byte tag_program = ///
    tag(program_id)

egen byte tag_market = ///
    tag(market_pre)


display ""
display "============================================================"
display " CONDITIONAL-SIMILARITY EVENT-STUDY SAMPLE"
display "============================================================"


count

display ///
    "Exposed-market observations = " ///
    %9.0fc r(N)


count if ///
    tag_program == 1

display ///
    "Programs                    = " ///
    %9.0fc r(N)


count if ///
    tag_market == 1

display ///
    "Exposed markets             = " ///
    %9.0fc r(N)


count if ///
    tag_program == 1 & ///
    q_tri == 0

display ///
    "Programs with Q_tri = 0     = " ///
    %9.0fc r(N)


count if ///
    tag_program == 1 & ///
    q_gau == 0

display ///
    "Programs with Q_gau = 0     = " ///
    %9.0fc r(N)


drop ///
    tag_program ///
    tag_market


/*******************************************************************************
9. TEMPORARY EVENT-STUDY RESULTS
*******************************************************************************/

tempfile event_results
tempname results_handle

postfile `results_handle' ///
    str6 form ///
    str3 measure ///
    int year ///
    double beta ///
    double se ///
    double lower_ci ///
    double upper_ci ///
    double pretrend_F ///
    double pretrend_p ///
    long observations ///
    long programs ///
    long markets ///
    using `event_results', ///
    replace


/*******************************************************************************
10. ESTIMATE FOUR EVENT STUDIES
*
*     1. Levels, Triangular
*     2. Levels, Gaussian
*     3. Logs, Triangular
*     4. Logs, Gaussian
*******************************************************************************/

foreach form in ///
    levels ///
    logs {


    foreach measure in ///
        tri ///
        gau {


        /***********************************************************************
        10.1 MODEL-SPECIFIC SETTINGS
        ***********************************************************************/

        if "`form'" == "levels" {

            local outcome ///
                N_firstyear_incumbent

            local sample ///
                sample_levels

            local interaction ///
                es_lvl

            local form_label ///
                "Levels"
        }


        if "`form'" == "logs" {

            local outcome ///
                ln_enrollment

            local sample ///
                sample_logs

            local interaction ///
                es_log

            local form_label ///
                "Logs"
        }


        if "`measure'" == "tri" {

            local measure_label ///
                "Triangular"
        }


        if "`measure'" == "gau" {

            local measure_label ///
                "Gaussian"
        }


        /*
        Main annual interactions.
        */

        local annual_interactions

        foreach year in ///
            2007 2008 2009 2010 ///
            2012 2013 2014 2015 2016 {

            local annual_interactions ///
                `annual_interactions' ///
                `interaction'_`measure'_`year'
        }


        /*
        Positive-Q annual controls for logs.
        */

        local D_interactions

        if "`form'" == "logs" {

            foreach year in ///
                2007 2008 2009 2010 ///
                2012 2013 2014 2015 2016 {

                local D_interactions ///
                    `D_interactions' ///
                    D_`measure'_`year'
            }
        }


        display ""
        display "============================================================"
        display " CONDITIONAL-SIMILARITY EVENT STUDY"
        display "============================================================"

        display ///
            "Functional form = `form_label'"

        display ///
            "Measure         = `measure_label'"

        display ///
            "Omitted year    = 2011"

        display ///
            "Fixed effects   = Program + Broad-field x year + region x year"

        if "`form'" == "logs" {

            display ///
                "Q = 0         = RETAINED"
        }

        display "============================================================"


        /***********************************************************************
        10.2 EVENT-STUDY REGRESSION
        ***********************************************************************/

        reghdfe ///
            `outcome' ///
            `annual_interactions' ///
            `D_interactions' ///
            if `sample' == 1, ///
            absorb( ///
                program_id ///
                sim_field_year ///
                sim_region_year ///
            ) ///
            vce(cluster market_pre)


        /*
        Save estimation sample immediately.
        */

        tempvar estimation_sample

        gen byte `estimation_sample' = ///
            e(sample)


        local residual_df = ///
            e(df_r)

        local observations = ///
            e(N)


        /***********************************************************************
        10.3 EFFECTIVE SAMPLE COUNTS
        ***********************************************************************/

        tempvar tag_est_program tag_est_market

        egen byte `tag_est_program' = ///
            tag(program_id) ///
            if `estimation_sample' == 1

        quietly count if ///
            `tag_est_program' == 1

        local programs = ///
            r(N)


        egen byte `tag_est_market' = ///
            tag(market_pre) ///
            if `estimation_sample' == 1

        quietly count if ///
            `tag_est_market' == 1

        local markets = ///
            r(N)


        /***********************************************************************
        10.4 JOINT PRETREND TEST
        *
        * Test only the plotted Q coefficients.
        *
        * For logs, D x year terms are controls and are not included
        * in the main pretrend test.
        ***********************************************************************/

        test ///
            `interaction'_`measure'_2007 ///
            `interaction'_`measure'_2008 ///
            `interaction'_`measure'_2009 ///
            `interaction'_`measure'_2010

        local pretrend_F = ///
            r(F)

        local pretrend_p = ///
            r(p)


        local critical_value = ///
            invttail( ///
                `residual_df', ///
                0.025 ///
            )


        display ///
            "Joint pretrend F = " ///
            %9.3f `pretrend_F'

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
        10.5 STORE ANNUAL COEFFICIENTS
        ***********************************************************************/

        forvalues year = 2007/2016 {


            if `year' == 2011 {

                local coefficient = 0
                local standard_error = 0
                local lower_bound = 0
                local upper_bound = 0
            }


            else {

                local coefficient = ///
                    _b[`interaction'_`measure'_`year']

                local standard_error = ///
                    _se[`interaction'_`measure'_`year']

                local lower_bound = ///
                    `coefficient' - ///
                    `critical_value' * ///
                    `standard_error'

                local upper_bound = ///
                    `coefficient' + ///
                    `critical_value' * ///
                    `standard_error'
            }


            post `results_handle' ///
                ("`form'") ///
                ("`measure'") ///
                (`year') ///
                (`coefficient') ///
                (`standard_error') ///
                (`lower_bound') ///
                (`upper_bound') ///
                (`pretrend_F') ///
                (`pretrend_p') ///
                (`observations') ///
                (`programs') ///
                (`markets')
        }


        drop ///
            `estimation_sample' ///
            `tag_est_program' ///
            `tag_est_market'
    }
}


postclose `results_handle'


/*******************************************************************************
11. PREPARE RESULTS
*******************************************************************************/

use `event_results', clear

count
assert r(N) == 40

isid ///
    form ///
    measure ///
    year


gen str12 form_label = ""

replace form_label = ///
    "Levels" ///
    if form == "levels"

replace form_label = ///
    "Logs" ///
    if form == "logs"


gen byte form_order = .

replace form_order = 1 ///
    if form == "levels"

replace form_order = 2 ///
    if form == "logs"


gen str12 measure_label = ""

replace measure_label = ///
    "Triangular" ///
    if measure == "tri"

replace measure_label = ///
    "Gaussian" ///
    if measure == "gau"


gen byte measure_order = .

replace measure_order = 1 ///
    if measure == "tri"

replace measure_order = 2 ///
    if measure == "gau"


sort ///
    form_order ///
    measure_order ///
    year


format ///
    beta ///
    se ///
    lower_ci ///
    upper_ci ///
    %9.4f

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
    %12.0fc


/*******************************************************************************
12. DISPLAY ANNUAL COEFFICIENTS
*******************************************************************************/

display ""
display "============================================================"
display " CONDITIONAL-SIMILARITY EVENT-STUDY COEFFICIENTS"
display "============================================================"

list ///
    form_label ///
    measure_label ///
    year ///
    beta ///
    se ///
    lower_ci ///
    upper_ci, ///
    sepby( ///
        form ///
        measure ///
    ) ///
    noobs clean


/*******************************************************************************
13. COMPACT PRETREND SUMMARY
*******************************************************************************/

preserve

    keep ///
        form ///
        form_label ///
        form_order ///
        measure ///
        measure_label ///
        measure_order ///
        pretrend_F ///
        pretrend_p ///
        observations ///
        programs ///
        markets

    duplicates drop

    isid ///
        form ///
        measure

    count
    assert r(N) == 4


    sort ///
        form_order ///
        measure_order


    display ""
    display "============================================================"
    display " CONDITIONAL-SIMILARITY PRETREND SUMMARY"
    display "============================================================"

    list ///
        form_label ///
        measure_label ///
        pretrend_F ///
        pretrend_p ///
        observations ///
        programs ///
        markets, ///
        sepby(form) ///
        noobs clean

restore


/*******************************************************************************
14. GRAPH VARIABLES
*******************************************************************************/

gen double graph_year = ///
    year

replace graph_year = ///
    year - 0.08 ///
    if measure == "tri"

replace graph_year = ///
    year + 0.08 ///
    if measure == "gau"


gen byte plot_observation = ///
    year != 2011


/*******************************************************************************
15. CREATE LEVEL AND LOG GRAPHS
*******************************************************************************/

foreach form in ///
    levels ///
    logs {


    /***************************************************************************
    15.1 GRAPH SETTINGS
    ***************************************************************************/

    if "`form'" == "levels" {

        local graph_title ///
            "SUA exposure: similarity within exposed markets"

        local graph_subtitle ///
            "Program FE, Broad-field x year FE, and region x year FE; 2011 omitted"

        local y_axis_title ///
            "Enrollment coefficient for a 0.10 increase in similarity"

        local y_axis_format ///
            "%4.1f"

        local sample_note ///
            "Exposed markets; economically meaningful zero similarity retained."

        local graph_output ///
            "`graph_levels'"
    }


    if "`form'" == "logs" {

        local graph_title ///
            "Log similarity within exposed SUA markets"

        local graph_subtitle ///
            "Program FE, Broad-field x year FE, and region x year FE; 2011 omitted"

        local y_axis_title ///
            "Enrollment elasticity with respect to similarity"

        local y_axis_format ///
            "%4.2f"

        local sample_note ///
            "Exposed markets; Q = 0 retained; D x year controls included and not plotted."

        local graph_output ///
            "`graph_logs'"
    }


    /***************************************************************************
    15.2 PRETREND P-VALUES
    ***************************************************************************/

    quietly summarize ///
        pretrend_p ///
        if ///
            form == "`form'" & ///
            measure == "tri", ///
        meanonly

    local triangular_p : ///
        display %6.4f r(mean)


    quietly summarize ///
        pretrend_p ///
        if ///
            form == "`form'" & ///
            measure == "gau", ///
        meanonly

    local gaussian_p : ///
        display %6.4f r(mean)


    /***************************************************************************
    15.3 GRAPH RANGE
    ***************************************************************************/

    quietly summarize ///
        lower_ci ///
        if ///
            form == "`form'" & ///
            year != 2011, ///
        meanonly

    local graph_min = ///
        r(min)


    quietly summarize ///
        upper_ci ///
        if ///
            form == "`form'" & ///
            year != 2011, ///
        meanonly

    local graph_max = ///
        r(max)


    local graph_span = ///
        `graph_max' - ///
        `graph_min'

    if `graph_span' <= 0 {

        local graph_span = 1
    }


    local graph_min = ///
        `graph_min' - ///
        0.08 * `graph_span'

    local graph_max = ///
        `graph_max' + ///
        0.08 * `graph_span'


    /***************************************************************************
    15.4 GRAPH
    ***************************************************************************/

    twoway ///
        (rcap ///
            lower_ci ///
            upper_ci ///
            graph_year ///
            if ///
                plot_observation == 1 & ///
                form == "`form'" & ///
                measure == "tri", ///
            lcolor(forest_green%60) ///
            lwidth(medthin)) ///
        (rcap ///
            lower_ci ///
            upper_ci ///
            graph_year ///
            if ///
                plot_observation == 1 & ///
                form == "`form'" & ///
                measure == "gau", ///
            lcolor(maroon%60) ///
            lwidth(medthin)) ///
        (scatter ///
            beta ///
            graph_year ///
            if ///
                plot_observation == 1 & ///
                form == "`form'" & ///
                measure == "tri", ///
            mcolor(forest_green) ///
            mlcolor(forest_green) ///
            msymbol(triangle) ///
            msize(medium)) ///
        (scatter ///
            beta ///
            graph_year ///
            if ///
                plot_observation == 1 & ///
                form == "`form'" & ///
                measure == "gau", ///
            mcolor(maroon) ///
            mlcolor(maroon) ///
            msymbol(diamond) ///
            msize(medium)) ///
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
            format(%4.0f) ///
            labsize(small) ///
        ) ///
        ylabel( ///
            , ///
            format(`y_axis_format') ///
            angle(horizontal) ///
            labsize(small) ///
            grid ///
            glcolor(gs14) ///
            glwidth(vthin) ///
        ) ///
        xtitle( ///
            "Admission year", ///
            size(small) ///
        ) ///
        ytitle( ///
            "`y_axis_title'", ///
            size(small) ///
        ) ///
        title( ///
            "`graph_title'", ///
            size(medsmall) ///
        ) ///
        subtitle( ///
            "`graph_subtitle'", ///
            size(small) ///
        ) ///
        legend( ///
            order( ///
                3 "Triangular" ///
                4 "Gaussian" ///
            ) ///
            rows(1) ///
            position(6) ///
            size(small) ///
            region( ///
                lcolor(none) ///
                fcolor(none) ///
            ) ///
        ) ///
        note( ///
            "`sample_note'" ///
            "95% confidence intervals; standard errors clustered by pre-treatment market." ///
            "Joint pretrend p-values: Triangular = `triangular_p'; Gaussian = `gaussian_p'.", ///
            size(vsmall) ///
        ) ///
        graphregion( ///
            color(white) ///
        ) ///
        plotregion( ///
            color(white) ///
        ) ///
        bgcolor(white) ///
        scheme(s1color) ///
        name( ///
            similarity_`form', ///
            replace ///
        )


    /***************************************************************************
    15.5 EXPORT GRAPH
    ***************************************************************************/

    graph export ///
        "`graph_output'.png", ///
        width(2400) ///
        replace

    graph export ///
        "`graph_output'.pdf", ///
        replace
}


/*******************************************************************************
16. END
*******************************************************************************/

display ""
display "============================================================"
display " CONDITIONAL-SIMILARITY EVENT STUDIES COMPLETED"
display "============================================================"

display ///
    "Levels graph: `graph_levels'.png"

display ///
    "Logs graph:   `graph_logs'.png"

display ""
display "05b_sua_similarity_event_studies.do completed successfully."