/*******************************************************************************
03c_sua_exposure_enrollment_descriptives.do

PURPOSE

1. Verify that pre-treatment entrant enrollment and positive SUA exposure
   occur only in:

       - Valparaiso
       - Biobio
       - La Araucania
       - Metropolitana

2. Describe the analytical samples corresponding to:

       - Broad field
       - ISCED-97 field
       - Generic field

3. Describe Total, Triangular and Gaussian exposure under each field
   definition:

       - Including zero-exposure programs
       - Conditional on positive exposure

4. Describe and graph first-year enrollment in incumbent SUA programs.

OUTPUTS

    sua_exposure_distributions_broad.png
    sua_exposure_distributions_isced.png
    sua_exposure_distributions_generic.png
    sua_firstyear_enrollment_distributions.png

No permanent datasets or spreadsheets are created.
*******************************************************************************/

clear all
set more off
set varabbrev off

do "code/config.do"


/*******************************************************************************
0. DEFINITIONS
*******************************************************************************/

local field_definitions ///
    broad_area ///
    cine_subarea ///
    generic_area

local exposure_measures ///
    total ///
    triangular ///
    gaussian

/*
Regions with positive pre-treatment entrant enrollment:

     5 = Valparaiso
     8 = Biobio
     9 = La Araucania
    13 = Metropolitana
*/

local positive_regions ///
    5 8 9 13


/*******************************************************************************
1. VERIFY THE LOCATION OF ENTRANT PROGRAMS
*******************************************************************************/

local university_panel ///
    "$processed/sua_exposure/sies_university_program_panel_2007_2016.dta"

use "`university_panel'", clear

keep if ///
    sua_entrant_2012 == 1 & ///
    inrange(ao_proceso, 2009, 2011) & ///
    program_year_observed == 1 & ///
    !missing(N_firstyear) & ///
    N_firstyear > 0

drop if missing(id_region)


/*
Entrant enrollment must occur only in the four expected regions.
*/

assert inlist( ///
    id_region, ///
    5, ///
    8, ///
    9, ///
    13 ///
)


/*
Every expected region must contain positive entrant enrollment.
*/

foreach region of local positive_regions {

    quietly count ///
        if id_region == `region'

    assert r(N) > 0
}


levelsof id_region, ///
    local(entrant_regions)


display ""
display "============================================================"
display " REGIONS WITH PRE-TREATMENT ENTRANT ENROLLMENT"
display "============================================================"

display "Observed region codes: `entrant_regions'"
display "Expected region codes: 5 8 9 13"


/*******************************************************************************
2. VERIFY THE ORIGINAL MARKET-LEVEL EXPOSURE
*******************************************************************************/

local market_exposure ///
    "$processed/sua_exposure/sua_exposure_field_region_2009_2011.dta"

use "`market_exposure'", clear


/*
Markets without first-year enrollment have undefined exposure.
*/

assert missing(sua_exposure) ///
    if exposure_defined == 0

assert !missing(sua_exposure) ///
    if exposure_defined == 1


quietly count ///
    if missing(sua_exposure)

local undefined_markets = r(N)


/*
Positive exposure must occur only in the four expected regions.
*/

assert inlist( ///
    id_region, ///
    5, ///
    8, ///
    9, ///
    13 ///
) if ///
    exposure_defined == 1 & ///
    sua_exposure > 0


/*
Every expected region must contain at least one positive-exposure market.
*/

foreach region of local positive_regions {

    quietly count ///
        if ///
        id_region == `region' & ///
        exposure_defined == 1 & ///
        sua_exposure > 0

    assert r(N) > 0
}


levelsof id_region ///
    if ///
    exposure_defined == 1 & ///
    sua_exposure > 0, ///
    local(exposure_regions)


quietly count ///
    if ///
    exposure_defined == 1 & ///
    sua_exposure > 0

local positive_markets = r(N)


display ""
display "============================================================"
display " REGIONS WITH POSITIVE SUA MARKET EXPOSURE"
display "============================================================"

display "Observed region codes:      `exposure_regions'"
display "Expected region codes:      5 8 9 13"

display ///
    "Positive-exposure markets = " ///
    %9.0fc `positive_markets'

display ///
    "Undefined markets         = " ///
    %9.0fc `undefined_markets'


/*******************************************************************************
3. TEMPORARY RESULT FILES
*******************************************************************************/

/*
Analytical-sample results used in Panel A of the Beamer table.
*/

tempfile sample_results
tempname sample_handle

postfile `sample_handle' ///
    str12 field_definition ///
    long observations ///
    long programs ///
    long universities ///
    long markets ///
    double mean_enrollment ///
    double mean_psu ///
    using `sample_results', ///
    replace


/*
Exposure-distribution results used in Panel B and diagnostics.
*/

tempfile exposure_results
tempname exposure_handle

postfile `exposure_handle' ///
    str12 field_definition ///
    str12 exposure_measure ///
    str10 sample ///
    long programs ///
    double mean ///
    double sd ///
    double p25 ///
    double p50 ///
    double p75 ///
    double p90 ///
    double minimum ///
    double maximum ///
    double zero_share ///
    using `exposure_results', ///
    replace


/*
The Broad-field panel is retained temporarily for the enrollment analysis.
*/

tempfile broad_panel


/*******************************************************************************
4. ANALYTICAL SAMPLES AND EXPOSURE DISTRIBUTIONS
*******************************************************************************/

foreach field_definition of local field_definitions {


    /***************************************************************************
    4.1 FIELD LABELS AND INPUT FILE
    ***************************************************************************/

    if "`field_definition'" == "broad_area" {

        local field_code ///
            "broad"

        local field_label ///
            "Broad field"
    }

    if "`field_definition'" == "cine_subarea" {

        local field_code ///
            "isced"

        local field_label ///
            "ISCED-97 field"
    }

    if "`field_definition'" == "generic_area" {

        local field_code ///
            "generic"

        local field_label ///
            "Generic field"
    }


    local input_panel ///
        "$processed/sua_incumbent_panel_w_`field_definition'_region_2007_2016.dta"

    use "`input_panel'", clear


    /***************************************************************************
    4.2 COMMON ANALYTICAL SAMPLE
    *
    * Require the outcome, market identifiers and all three exposure measures.
    ***************************************************************************/

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
    Require each program to appear before and after 2012.
    */

    bysort program_id: ///
        egen byte has_pre_period = ///
            max(ao_proceso <= 2011)

    bysort program_id: ///
        egen byte has_post_period = ///
            max(ao_proceso >= 2012)

    keep if ///
        has_pre_period == 1 & ///
        has_post_period == 1

    drop ///
        has_pre_period ///
        has_post_period


    isid ///
        program_id ///
        ao_proceso
	
		/*
	Pre-treatment PSU is required for the sample table.
	The number of incumbent universities is fixed at 25 by construction.
	*/

	capture confirm variable inc_psu_pre

	if _rc {
		display as error ///
			"Variable inc_psu_pre is required for mean pre-treatment PSU."
		exit 111
	}

	assert !missing(inc_psu_pre)


   

    /***************************************************************************
    4.3 VERIFY THAT EXPOSURES ARE PREDETERMINED
    ***************************************************************************/

    foreach variable in ///
        exp_unw ///
        exp_tri50 ///
        exp_gau50 ///
        inc_psu_pre {

        bysort program_id (ao_proceso): ///
            assert ///
            `variable' == `variable'[1]
    }

    bysort program_id (ao_proceso): ///
        assert ///
        geo_pre == geo_pre[1]

    bysort program_id (ao_proceso): ///
        assert ///
        market_pre == market_pre[1]


	/***************************************************************************
	4.4 ANALYTICAL-SAMPLE STATISTICS
	***************************************************************************/

	local sample_observations = _N


	/*
	Count each program and pre-treatment market once.
	*/

	egen byte tag_program = ///
		tag(program_id)

	egen byte tag_market = ///
		tag(market_pre)


	quietly count ///
		if tag_program == 1

	local sample_programs = r(N)


	quietly count ///
		if tag_market == 1

	local sample_markets = r(N)


	/*
	The analytical panels contain programs from the 25 incumbent SUA
	universities by construction.
	*/

	local sample_universities = 25


	/*
	Program-level mean annual enrollment in 2009-2011.
	*/

	bysort program_id: ///
		egen double mean_enrollment_2009_2011 = ///
			mean( ///
				cond( ///
					inrange(ao_proceso, 2009, 2011), ///
					N_firstyear_incumbent, ///
					. ///
				) ///
			)

	assert !missing(mean_enrollment_2009_2011) ///
		if tag_program == 1


	quietly summarize ///
		mean_enrollment_2009_2011 ///
		if tag_program == 1

	local sample_mean_enrollment = r(mean)


	/*
	Mean pre-treatment PSU across incumbent programs.
	*/

	assert !missing(inc_psu_pre)

	quietly summarize ///
		inc_psu_pre ///
		if tag_program == 1

	local sample_mean_psu = r(mean)


	/*
	Store the analytical-sample statistics.
	*/

	post `sample_handle' ///
		("`field_code'") ///
		(`sample_observations') ///
		(`sample_programs') ///
		(`sample_universities') ///
		(`sample_markets') ///
		(`sample_mean_enrollment') ///
		(`sample_mean_psu')


	drop ///
    tag_program ///
    tag_market ///
    mean_enrollment_2009_2011


	if "`field_definition'" == "broad_area" {

		save `broad_panel', replace
	}


	/***************************************************************************
	4.5 ONE OBSERVATION PER PROGRAM
	***************************************************************************/

	bysort program_id (ao_proceso): ///
		keep if _n == 1


    /***************************************************************************
    4.6 EXPOSURE IN PERCENTAGE POINTS
    ***************************************************************************/

    gen double exposure_total_pct = ///
        100 * exp_unw

    gen double exposure_triangular_pct = ///
        100 * exp_tri50

    gen double exposure_gaussian_pct = ///
        100 * exp_gau50


    label variable exposure_total_pct ///
        "Total exposure"

    label variable exposure_triangular_pct ///
        "Triangular exposure"

    label variable exposure_gaussian_pct ///
        "Gaussian exposure"


    /***************************************************************************
    4.7 VERIFY THE REGIONS WITH POSITIVE EXPOSURE
    ***************************************************************************/

    foreach exposure_measure of local exposure_measures {

        if "`exposure_measure'" == "total" {
            local exposure_variable ///
                exposure_total_pct
        }

        if "`exposure_measure'" == "triangular" {
            local exposure_variable ///
                exposure_triangular_pct
        }

        if "`exposure_measure'" == "gaussian" {
            local exposure_variable ///
                exposure_gaussian_pct
        }


        assert inlist( ///
            geo_pre, ///
            5, ///
            8, ///
            9, ///
            13 ///
        ) if `exposure_variable' > 0


        foreach region of local positive_regions {

            quietly count ///
                if ///
                geo_pre == `region' & ///
                `exposure_variable' > 0

            assert r(N) > 0
        }


        levelsof geo_pre ///
            if `exposure_variable' > 0, ///
            local(positive_regions_`exposure_measure')


        display ""
        display "------------------------------------------------------------"
        display "Field definition = `field_label'"
        display "Exposure measure = `exposure_measure'"

        display ///
            "Positive regions = " ///
            "`positive_regions_`exposure_measure''"
    }


    /***************************************************************************
    4.8 EXPOSURE DESCRIPTIVE STATISTICS
    ***************************************************************************/

    foreach exposure_measure of local exposure_measures {

        if "`exposure_measure'" == "total" {
            local exposure_variable ///
                exposure_total_pct
        }

        if "`exposure_measure'" == "triangular" {
            local exposure_variable ///
                exposure_triangular_pct
        }

        if "`exposure_measure'" == "gaussian" {
            local exposure_variable ///
                exposure_gaussian_pct
        }


        foreach exposure_sample in all positive {

            if "`exposure_sample'" == "all" {
                local sample_condition ///
                    "1"
            }

            if "`exposure_sample'" == "positive" {
                local sample_condition ///
                    "`exposure_variable' > 0"
            }


            quietly summarize ///
                `exposure_variable' ///
                if `sample_condition', ///
                detail


            local exposure_N = r(N)
            local exposure_mean = r(mean)
            local exposure_sd = r(sd)
            local exposure_p25 = r(p25)
            local exposure_p50 = r(p50)
            local exposure_p75 = r(p75)
            local exposure_p90 = r(p90)
            local exposure_minimum = r(min)
            local exposure_maximum = r(max)


            quietly count ///
                if ///
                `sample_condition' & ///
                `exposure_variable' == 0

            local exposure_zeros = r(N)

            local exposure_zero_share = ///
                `exposure_zeros' / ///
                `exposure_N'


            post `exposure_handle' ///
                ("`field_code'") ///
                ("`exposure_measure'") ///
                ("`exposure_sample'") ///
                (`exposure_N') ///
                (`exposure_mean') ///
                (`exposure_sd') ///
                (`exposure_p25') ///
                (`exposure_p50') ///
                (`exposure_p75') ///
                (`exposure_p90') ///
                (`exposure_minimum') ///
                (`exposure_maximum') ///
                (`exposure_zero_share')
        }
    }


    /***************************************************************************
    4.9 COMMON HISTOGRAM SCALE
    ***************************************************************************/

    quietly summarize exposure_total_pct
    local maximum_total = r(max)

    quietly summarize exposure_triangular_pct
    local maximum_triangular = r(max)

    quietly summarize exposure_gaussian_pct
    local maximum_gaussian = r(max)


    local maximum_exposure = ///
        max( ///
            `maximum_total', ///
            `maximum_triangular', ///
            `maximum_gaussian' ///
        )

    local histogram_width = ///
        `maximum_exposure' / 30


    /***************************************************************************
    4.10 EXPOSURE HISTOGRAMS
    ***************************************************************************/

    foreach exposure_measure of local exposure_measures {

        if "`exposure_measure'" == "total" {

            local exposure_variable ///
                exposure_total_pct

            local exposure_title ///
                "Total exposure"
        }

        if "`exposure_measure'" == "triangular" {

            local exposure_variable ///
                exposure_triangular_pct

            local exposure_title ///
                "Triangular exposure"
        }

        if "`exposure_measure'" == "gaussian" {

            local exposure_variable ///
                exposure_gaussian_pct

            local exposure_title ///
                "Gaussian exposure"
        }


        foreach exposure_sample in all positive {

            if "`exposure_sample'" == "all" {

                local graph_condition ///
                    ""

                local graph_subtitle ///
                    "Zeros included"

                local graph_color ///
                    "navy%65"

                local graph_line_color ///
                    "navy"
            }

            if "`exposure_sample'" == "positive" {

                local graph_condition ///
                    "if `exposure_variable' > 0"

                local graph_subtitle ///
                    "Positive exposure only"

                local graph_color ///
                    "forest_green%65"

                local graph_line_color ///
                    "forest_green"
            }


            histogram ///
                `exposure_variable' ///
                `graph_condition', ///
                percent ///
                start(0) ///
                width(`histogram_width') ///
                xscale(range(0 `maximum_exposure')) ///
                color(`graph_color') ///
                lcolor(`graph_line_color') ///
                title( ///
                    "`exposure_title'", ///
                    size(small) ///
                ) ///
                subtitle( ///
                    "`graph_subtitle'", ///
                    size(vsmall) ///
                ) ///
                xtitle( ///
                    "Exposure (percentage points)", ///
                    size(vsmall) ///
                ) ///
                ytitle( ///
                    "Percent of programs", ///
                    size(vsmall) ///
                ) ///
                graphregion(color(white)) ///
                name( ///
                    hist_`exposure_measure'_`exposure_sample'_`field_code', ///
                    replace ///
                )
        }
    }


    /***************************************************************************
    4.11 COMBINE AND EXPORT EXPOSURE HISTOGRAMS
    ***************************************************************************/

    graph combine ///
        hist_total_all_`field_code' ///
        hist_triangular_all_`field_code' ///
        hist_gaussian_all_`field_code' ///
        hist_total_positive_`field_code' ///
        hist_triangular_positive_`field_code' ///
        hist_gaussian_positive_`field_code', ///
        cols(3) ///
        xcommon ///
        title( ///
            "SUA exposure distributions: `field_label'", ///
            size(medium) ///
        ) ///
        subtitle( ///
            "One observation per incumbent program", ///
            size(small) ///
        ) ///
        note( ///
            "Top row includes zeros; bottom row conditions on positive exposure.", ///
            size(vsmall) ///
        ) ///
        graphregion(color(white)) ///
        name( ///
            exposure_distributions_`field_code', ///
            replace ///
        )


    graph export ///
        "$output/sua_exposure_distributions_`field_code'.png", ///
        width(3000) ///
        replace
}


postclose `sample_handle'
postclose `exposure_handle'


/*******************************************************************************
5. DISPLAY ANALYTICAL-SAMPLE STATISTICS
*******************************************************************************/

use `sample_results', clear


/*
Readable field-definition labels.
*/

replace field_definition = ///
    "Broad" ///
    if field_definition == "broad"

replace field_definition = ///
    "ISCED-97" ///
    if field_definition == "isced"

replace field_definition = ///
    "Generic" ///
    if field_definition == "generic"


gen byte field_order = .

replace field_order = 1 ///
    if field_definition == "Broad"

replace field_order = 2 ///
    if field_definition == "ISCED-97"

replace field_order = 3 ///
    if field_definition == "Generic"

sort field_order


format ///
    observations ///
    programs ///
    universities ///
    markets ///
    %9.0fc

format ///
    mean_enrollment ///
    mean_psu ///
    %9.1f


display ""
display "============================================================"
display " SUA ANALYTICAL SAMPLES FOR BEAMER"
display "============================================================"
display ""

list ///
    field_definition ///
    observations ///
    programs ///
    universities ///
    markets ///
    mean_enrollment ///
    mean_psu, ///
    noobs clean


/*******************************************************************************
6. DISPLAY EXPOSURE DESCRIPTIVE STATISTICS
*******************************************************************************/

use `exposure_results', clear


/*
Readable labels.
*/

gen str22 exposure_label = ""

replace exposure_label = ///
    "Total" ///
    if exposure_measure == "total"

replace exposure_label = ///
    "Triangular" ///
    if exposure_measure == "triangular"

replace exposure_label = ///
    "Gaussian" ///
    if exposure_measure == "gaussian"


gen byte field_order = .

replace field_order = 1 ///
    if field_definition == "broad"

replace field_order = 2 ///
    if field_definition == "isced"

replace field_order = 3 ///
    if field_definition == "generic"


gen byte exposure_order = .

replace exposure_order = 1 ///
    if exposure_measure == "total"

replace exposure_order = 2 ///
    if exposure_measure == "triangular"

replace exposure_order = 3 ///
    if exposure_measure == "gaussian"


gen byte sample_order = .

replace sample_order = 1 ///
    if sample == "all"

replace sample_order = 2 ///
    if sample == "positive"


sort ///
    field_order ///
    exposure_order ///
    sample_order


format programs %9.0fc

format ///
    mean ///
    sd ///
    p25 ///
    p50 ///
    p75 ///
    p90 ///
    minimum ///
    maximum ///
    %9.2f

format zero_share %9.3f


display ""
display "============================================================"
display " SUA EXPOSURE DESCRIPTIVE STATISTICS"
display "============================================================"
display "Exposure is expressed in percentage points."
display ""

list ///
    field_definition ///
    exposure_label ///
    sample ///
    programs ///
    mean ///
    sd ///
    p25 ///
    p50 ///
    p75 ///
    p90 ///
    zero_share, ///
    sepby(field_definition exposure_label) ///
    noobs clean


/*******************************************************************************
6.1 COMPACT EXPOSURE TABLE FOR BEAMER
*******************************************************************************/

preserve

    keep if sample == "all"


    replace field_definition = ///
        "Broad" ///
        if field_definition == "broad"

    replace field_definition = ///
        "ISCED-97" ///
        if field_definition == "isced"

    replace field_definition = ///
        "Generic" ///
        if field_definition == "generic"


    gen double zero_percent = ///
        100 * zero_share


    format programs %9.0fc

    format ///
        mean ///
        sd ///
        %9.2f

    format zero_percent %9.1f


    display ""
    display "============================================================"
    display " SUA EXPOSURE STATISTICS FOR BEAMER"
    display "============================================================"
    display ""

    list ///
        field_definition ///
        exposure_label ///
        programs ///
        mean ///
        sd ///
        zero_percent, ///
        sepby(field_definition) ///
        noobs clean

restore


/*******************************************************************************
7. PREPARE ENROLLMENT ANALYSIS
*
* The Broad-field panel is used because enrollment itself does not depend on
* the alternative market definitions.
*******************************************************************************/

use `broad_panel', clear


gen byte positive_exposure = ///
    exp_unw > 0

label define positive_exposure_label ///
    0 "No exposure" ///
    1 "Positive exposure"

label values positive_exposure ///
    positive_exposure_label


label variable N_firstyear_incumbent ///
    "First-year enrollment"


/*
The analytical panel contains positive first-year enrollment.
*/

assert N_firstyear_incumbent > 0


/*
Natural logarithm of first-year enrollment.
*/

gen double log_firstyear_enrollment = ///
    ln(N_firstyear_incumbent)

label variable log_firstyear_enrollment ///
    "Log first-year enrollment"


/*******************************************************************************
8. ENROLLMENT DESCRIPTIVE STATISTICS
*******************************************************************************/

tempfile enrollment_results
tempname enrollment_handle

postfile `enrollment_handle' ///
    str22 sample ///
    long observations ///
    long programs ///
    double mean ///
    double sd ///
    double p25 ///
    double p50 ///
    double p75 ///
    double p90 ///
    double minimum ///
    double maximum ///
    using `enrollment_results', ///
    replace


foreach enrollment_sample in ///
    full_sample ///
    pre_2007_2011 ///
    post_2012_2016 ///
    no_exposure ///
    positive_exposure {


    if "`enrollment_sample'" == "full_sample" {
        local enrollment_condition ///
            "1"
    }

    if "`enrollment_sample'" == "pre_2007_2011" {
        local enrollment_condition ///
            "ao_proceso <= 2011"
    }

    if "`enrollment_sample'" == "post_2012_2016" {
        local enrollment_condition ///
            "ao_proceso >= 2012"
    }

    if "`enrollment_sample'" == "no_exposure" {
        local enrollment_condition ///
            "positive_exposure == 0"
    }

    if "`enrollment_sample'" == "positive_exposure" {
        local enrollment_condition ///
            "positive_exposure == 1"
    }


    quietly summarize ///
        N_firstyear_incumbent ///
        if `enrollment_condition', ///
        detail


    local enrollment_observations = r(N)
    local enrollment_mean = r(mean)
    local enrollment_sd = r(sd)
    local enrollment_p25 = r(p25)
    local enrollment_p50 = r(p50)
    local enrollment_p75 = r(p75)
    local enrollment_p90 = r(p90)
    local enrollment_minimum = r(min)
    local enrollment_maximum = r(max)


    preserve

        keep if `enrollment_condition'

        egen byte tag_enrollment_program = ///
            tag(program_id)

        quietly count ///
            if tag_enrollment_program == 1

        local enrollment_programs = r(N)

    restore


    post `enrollment_handle' ///
        ("`enrollment_sample'") ///
        (`enrollment_observations') ///
        (`enrollment_programs') ///
        (`enrollment_mean') ///
        (`enrollment_sd') ///
        (`enrollment_p25') ///
        (`enrollment_p50') ///
        (`enrollment_p75') ///
        (`enrollment_p90') ///
        (`enrollment_minimum') ///
        (`enrollment_maximum')
}


postclose `enrollment_handle'


/*******************************************************************************
8.1 DISPLAY ENROLLMENT STATISTICS
*******************************************************************************/

preserve

    use `enrollment_results', clear


    gen byte sample_order = .

    replace sample_order = 1 ///
        if sample == "full_sample"

    replace sample_order = 2 ///
        if sample == "pre_2007_2011"

    replace sample_order = 3 ///
        if sample == "post_2012_2016"

    replace sample_order = 4 ///
        if sample == "no_exposure"

    replace sample_order = 5 ///
        if sample == "positive_exposure"


    sort sample_order


    format ///
        observations ///
        programs ///
        %9.0fc

    format ///
        mean ///
        sd ///
        p25 ///
        p50 ///
        p75 ///
        p90 ///
        minimum ///
        maximum ///
        %9.2f


    display ""
    display "============================================================"
    display " FIRST-YEAR ENROLLMENT DESCRIPTIVE STATISTICS"
    display "============================================================"
    display ""

    list ///
        sample ///
        observations ///
        programs ///
        mean ///
        sd ///
        p25 ///
        p50 ///
        p75 ///
        p90 ///
        minimum ///
        maximum, ///
        noobs clean

restore


/*******************************************************************************
9. COMMON HISTOGRAM SCALES
*******************************************************************************/

quietly summarize ///
    N_firstyear_incumbent

local maximum_enrollment = r(max)

local enrollment_width = ///
    `maximum_enrollment' / 40


quietly summarize ///
    log_firstyear_enrollment

local maximum_log_enrollment = r(max)

local log_enrollment_width = ///
    `maximum_log_enrollment' / 30


/*******************************************************************************
10. ENROLLMENT DISTRIBUTIONS IN LEVELS
*******************************************************************************/

histogram ///
    N_firstyear_incumbent ///
    if ao_proceso <= 2011, ///
    percent ///
    start(0) ///
    width(`enrollment_width') ///
    xscale(range(0 `maximum_enrollment')) ///
    color(navy%65) ///
    lcolor(navy) ///
    title( ///
        "A. Enrollment in levels: 2007-2011", ///
        size(small) ///
    ) ///
    xtitle( ///
        "First-year enrollment", ///
        size(vsmall) ///
    ) ///
    ytitle( ///
        "Percent of program-year observations", ///
        size(vsmall) ///
    ) ///
    graphregion(color(white)) ///
    name(enrollment_level_pre, replace)


histogram ///
    N_firstyear_incumbent ///
    if ao_proceso >= 2012, ///
    percent ///
    start(0) ///
    width(`enrollment_width') ///
    xscale(range(0 `maximum_enrollment')) ///
    color(maroon%65) ///
    lcolor(maroon) ///
    title( ///
        "B. Enrollment in levels: 2012-2016", ///
        size(small) ///
    ) ///
    xtitle( ///
        "First-year enrollment", ///
        size(vsmall) ///
    ) ///
    ytitle( ///
        "Percent of program-year observations", ///
        size(vsmall) ///
    ) ///
    graphregion(color(white)) ///
    name(enrollment_level_post, replace)


/*******************************************************************************
11. ENROLLMENT DISTRIBUTIONS IN LOGS
*******************************************************************************/

histogram ///
    log_firstyear_enrollment ///
    if ao_proceso <= 2011, ///
    percent ///
    start(0) ///
    width(`log_enrollment_width') ///
    xscale(range(0 `maximum_log_enrollment')) ///
    color(navy%65) ///
    lcolor(navy) ///
    title( ///
        "C. Log enrollment: 2007-2011", ///
        size(small) ///
    ) ///
    xtitle( ///
        "Natural log of first-year enrollment", ///
        size(vsmall) ///
    ) ///
    ytitle( ///
        "Percent of program-year observations", ///
        size(vsmall) ///
    ) ///
    graphregion(color(white)) ///
    name(enrollment_log_pre, replace)


histogram ///
    log_firstyear_enrollment ///
    if ao_proceso >= 2012, ///
    percent ///
    start(0) ///
    width(`log_enrollment_width') ///
    xscale(range(0 `maximum_log_enrollment')) ///
    color(maroon%65) ///
    lcolor(maroon) ///
    title( ///
        "D. Log enrollment: 2012-2016", ///
        size(small) ///
    ) ///
    xtitle( ///
        "Natural log of first-year enrollment", ///
        size(vsmall) ///
    ) ///
    ytitle( ///
        "Percent of program-year observations", ///
        size(vsmall) ///
    ) ///
    graphregion(color(white)) ///
    name(enrollment_log_post, replace)


/*******************************************************************************
12. COMBINE AND EXPORT ENROLLMENT DISTRIBUTIONS
*******************************************************************************/

graph combine ///
    enrollment_level_pre ///
    enrollment_level_post ///
    enrollment_log_pre ///
    enrollment_log_post, ///
    cols(2) ///
    title( ///
        "First-year enrollment distributions", ///
        size(medium) ///
    ) ///
    subtitle( ///
        "Incumbent SUA programs in the Broad-field analytical sample", ///
        size(small) ///
    ) ///
    note( ///
        "Top row reports enrollment levels; bottom row reports the natural logarithm of enrollment.", ///
        size(vsmall) ///
    ) ///
    graphregion(color(white)) ///
    name(sua_enrollment_distributions, replace)


graph export ///
    "$output/sua_firstyear_enrollment_distributions.png", ///
    width(2800) ///
    replace


display ""
display "============================================================"
display " SUA DESCRIPTIVE ANALYSIS COMPLETED"
display "============================================================"