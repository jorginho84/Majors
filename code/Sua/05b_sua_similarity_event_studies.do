/*******************************************************************************
05b_sua_similarity_event_studies.do

PURPOSE

Estimate event studies for conditional PSU similarity within exposed SUA
markets, using two functional forms:

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

SAMPLES

Levels:

    - Markets with positive entrant presence
    - Economically meaningful Q = 0 observations are retained

Logs:

    - Markets with positive entrant presence
    - Positive first-year enrollment
    - Positive conditional similarity
    - The sample is defined separately for each similarity measure

SPECIFICATION

    Program fixed effects
    Broad-field x pre-treatment region x year fixed effects
    Standard errors clustered by pre-treatment market
    2011 explicitly omitted

INTERPRETATION

Levels:

    Each coefficient measures the enrollment association corresponding to a
0.10 increase in conditional similarity, relative to 2011.

Logs:

    Each coefficient is the enrollment-similarity elasticity in the indicated
    year, relative to 2011.
*******************************************************************************/

clear all
set more off
set varabbrev off

do "code/config.do"


/*******************************************************************************
1. INPUT AND OUTPUTS
*******************************************************************************/

local input_panel ///
    "$processed/sua_incumbent_panel_w_broad_area_region_2007_2016.dta"

local graph_levels ///
    "$output/sua_similarity_event_study_exposed_markets"

local graph_logs ///
    "$output/sua_similarity_log_event_study"


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


/*
Require each program to appear before and after SUA entry.
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
M_m is the entrant share of total pre-treatment market enrollment.

Q_p^k is defined only when M_m > 0.
*/

gen double entrant_share = ///
    exp_unw

keep if ///
    entrant_share > 0


/*
Conditional similarity measures.
*/

gen double q_tri = ///
    exp_tri50 / entrant_share

gen double q_gau = ///
    exp_gau50 / entrant_share


label variable q_tri ///
    "Triangular similarity conditional on entrants"

label variable q_gau ///
    "Gaussian similarity conditional on entrants"


/*
Validate the range of the similarity measures.
*/

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
Confirm the decomposition:

    E_p^k = M_m * Q_p^k
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
Conditional similarity must be fixed over time within programs.
*/

foreach variable in ///
    q_tri ///
    q_gau {

    tempvar q_min q_max

    bysort program_id: ///
        egen double `q_min' = ///
            min(`variable')

    bysort program_id: ///
        egen double `q_max' = ///
            max(`variable')

    assert abs( ///
        `q_max' - `q_min' ///
    ) < 1e-10

    drop ///
        `q_min' ///
        `q_max'
}

/***********************************************************************
* 3.1 MARKET x YEAR FIXED-EFFECT IDENTIFIER
***********************************************************************/

/*
market_year in the input records the pre-treatment year used to assign
the fixed market. It is not the market x panel-year identifier needed
for the regressions below.
*/

egen long market_year_fe = group( ///
    market_pre ///
    ao_proceso ///
), label

label variable market_year_fe ///
    "Pre-treatment market x admission year FE"

/*
Validate that the identifier maps one-to-one into
pre-treatment market x admission year cells.
*/

bysort market_year_fe: ///
assert market_pre == market_pre[1]

bysort market_year_fe: ///
assert ao_proceso == ao_proceso[1]

egen byte tag_market_year_fe = ///
    tag(market_year_fe)

quietly count if ///
    tag_market_year_fe == 1

display ///
    "Pre-treatment market x year cells = " ///
    %9.0fc r(N)

if r(N) <= 36 {
    display as error ///
        "Invalid market x year FE: too few categories."
    exit 459
}

drop tag_market_year_fe

/*******************************************************************************
4. OUTCOMES AND LOGARITHMIC SIMILARITY
*******************************************************************************/

/*
Log enrollment is defined only for positive enrollment.
*/

gen double ln_enrollment = ///
    ln(N_firstyear_incumbent) ///
    if N_firstyear_incumbent > 0


/*
Log similarity is defined only for positive Q.
*/

gen double ln_q_tri = ///
    ln(q_tri) ///
    if q_tri > 0

gen double ln_q_gau = ///
    ln(q_gau) ///
    if q_gau > 0


/*******************************************************************************
5. ESTIMATION SAMPLES
*******************************************************************************/

/*
The levels sample retains Q = 0.
*/

gen byte sample_levels = 1


/*
The log samples require positive enrollment and positive similarity.

They are defined separately, so no common log sample is imposed.
*/

gen byte sample_log_tri = ///
    N_firstyear_incumbent > 0 & ///
    q_tri > 0

gen byte sample_log_gau = ///
    N_firstyear_incumbent > 0 & ///
    q_gau > 0


/*
Require pre- and post-2012 support within each log sample.
*/

foreach measure in ///
    tri ///
    gau {

    tempvar log_has_pre log_has_post

    bysort program_id: ///
        egen byte `log_has_pre' = ///
            max( ///
                sample_log_`measure' == 1 & ///
                ao_proceso <= 2011 ///
            )

    bysort program_id: ///
        egen byte `log_has_post' = ///
            max( ///
                sample_log_`measure' == 1 & ///
                ao_proceso >= 2012 ///
            )

    replace sample_log_`measure' = 0 ///
        if ///
            `log_has_pre' == 0 | ///
            `log_has_post' == 0
}




/*******************************************************************************
7. MANUAL YEAR INTERACTIONS
*
* 2011 is omitted explicitly.
*
* Levels:
*
*     10 * Q_p^k x 1{year = t}
*
* One unit therefore corresponds to a 0.10 increase in Q.
*
* Logs:
*
*     log(Q_p^k) x 1{year = t}
*******************************************************************************/

foreach year in ///
    2007 2008 2009 2010 ///
    2012 2013 2014 2015 2016 {

    /*
    Levels.
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
    Logs.
    */

    gen double es_log_tri_`year' = ///
        ln_q_tri * ///
        (ao_proceso == `year')

    gen double es_log_gau_`year' = ///
        ln_q_gau * ///
        (ao_proceso == `year')
}


/*
Verify that all interactions equal zero outside their corresponding year.
*/

foreach measure in ///
    tri ///
    gau {

    foreach year in ///
        2007 2008 2009 2010 ///
        2012 2013 2014 2015 2016 {

        assert es_lvl_`measure'_`year' == 0 ///
            if ao_proceso != `year'

        assert es_log_`measure'_`year' == 0 ///
            if ///
                sample_log_`measure' == 1 & ///
                ao_proceso != `year'
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
    "Program-year observations in exposed markets = " ///
    %9.0fc r(N)


count if ///
    tag_program == 1

display ///
    "Programs in exposed markets                  = " ///
    %9.0fc r(N)


count if ///
    tag_market == 1

display ///
    "Exposed markets                              = " ///
    %9.0fc r(N)


foreach measure in ///
    tri ///
    gau {

    count if ///
        tag_program == 1 & ///
        q_`measure' > 0

    display ///
        "Programs with positive Q_`measure'        = " ///
        %9.0fc r(N)
}


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
10. ESTIMATE THE FOUR EVENT STUDIES
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
        10.1 MODEL-SPECIFIC VARIABLES
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

            local interpretation ///
                "Effect of a 0.10 increase in conditional similarity"
        }


        if "`form'" == "logs" {

            local outcome ///
                ln_enrollment

            local sample ///
                sample_log_`measure'

            local interaction ///
                es_log

            local form_label ///
                "Logs"

            local interpretation ///
                "Enrollment-similarity elasticity relative to 2011"
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
        Construct the list of annual interaction variables.
        */

        local annual_interactions

        foreach year in ///
            2007 2008 2009 2010 ///
            2012 2013 2014 2015 2016 {

            local annual_interactions ///
                `annual_interactions' ///
                `interaction'_`measure'_`year'
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
			"Fixed effects   = Program + pre-treatment market x year"

        display "============================================================"


        /***********************************************************************
        10.2 EVENT-STUDY REGRESSION
        ***********************************************************************/

        reghdfe ///
            `outcome' ///
            `annual_interactions' ///
            if `sample' == 1, ///
            absorb( ///
                program_id ///
                market_year_fe ///
            ) ///
            vce(cluster market_pre)


        estimates store ///
            es_`form'_`measure'


        /*
        Save the effective estimation sample before subsequent commands.
        */

        tempvar estimation_sample

        gen byte `estimation_sample' = ///
            e(sample)


        /*
        Store residual degrees of freedom for clustered confidence intervals.
        */

        local residual_df = ///
            e(df_r)


        /***********************************************************************
        10.3 EFFECTIVE SAMPLE COUNTS
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
        10.4 JOINT PRETREND TEST
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


        /***********************************************************************
        10.5 CLUSTER-ADJUSTED CRITICAL VALUE
        ***********************************************************************/

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
        10.6 STORE ANNUAL COEFFICIENTS
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
            `tag_estimation_program' ///
            `tag_estimation_market'
    }
}


postclose `results_handle'


/*******************************************************************************
11. PREPARE RESULTS
*******************************************************************************/

use `event_results', clear


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
    year - 0.07 ///
    if measure == "tri"

replace graph_year = ///
    year + 0.07 ///
    if measure == "gau"


/*******************************************************************************
15. CREATE SEPARATE LEVEL AND LOG GRAPHS
*******************************************************************************/

foreach form in ///
    levels ///
    logs {

    /***************************************************************************
    15.1 GRAPH-SPECIFIC LABELS
    ***************************************************************************/

    if "`form'" == "levels" {

        local graph_title ///
            "SUA exposure: similarity within exposed markets"

        local graph_subtitle ///
            "Program FE and Broad-field x region x year FE; 2011 omitted"

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
            "Program FE and Broad-field x region x year FE; 2011 omitted"

        local y_axis_title ///
            "Enrollment-similarity elasticity relative to 2011"

        local y_axis_format ///
            "%4.2f"

        local sample_note ///
            "Positive enrollment and similarity only; samples differ by measure."

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


    /***************************************************************************
    15.4 EVENT-STUDY GRAPH
    ***************************************************************************/

    twoway ///
        (rcap ///
            lower_ci ///
            upper_ci ///
            graph_year ///
            if ///
                form == "`form'" & ///
                measure == "tri", ///
            lcolor(forest_green%60) ///
            lwidth(medthin)) ///
        (rcap ///
            lower_ci ///
            upper_ci ///
            graph_year ///
            if ///
                form == "`form'" & ///
                measure == "gau", ///
            lcolor(maroon%60) ///
            lwidth(medthin)) ///
        (scatter ///
            beta ///
            graph_year ///
            if ///
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