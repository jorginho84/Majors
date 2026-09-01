/*******************************************************************************
07_cosine_event_studies.do

PURPOSE

Estimate event studies for the five cosine-exposure definitions:

    1. PSU only
    2. PSU x campus region
    3. PSU + campus region
    4. PSU x campus region x Broad field
    5. PSU + campus region + Broad field

SAMPLES

    1. Full analytical sample
    2. Programs with at least 10 first-year students in 2011

SPECIFICATIONS

    1. Program FE + Broad-field x year FE
    2. Program FE + Broad-field x year FE
       + campus-region x year FE

The code estimates all 20 combinations but exports only two figures for the
full analytical sample. Each figure displays the five exposure definitions.

Exposure is divided by its original cross-program SD without subtracting its
mean. Economically meaningful zero exposure therefore remains equal to zero.

2011 is explicitly omitted.
Standard errors are clustered by program.
*******************************************************************************/

clear all
set more off
set varabbrev off

do "code/config.do"


/*******************************************************************************
1. INPUTS AND OUTPUTS
*******************************************************************************/

local panel ///
    "$processed/sua_exposure/sies_program_year_with_demre_2007_2016.dta"

local roster ///
    "$processed/sua_exposure/sua_university_sies_roster.dta"

local exposure ///
    "$processed/cosine_exposure_incumbents_2011_psu_campus_region.dta"

local graph_baseline ///
    "$output/cosine_event_studies_baseline"

local graph_regionyear ///
    "$output/cosine_event_studies_regionyear"


/*******************************************************************************
2. ANALYTICAL PANEL OF INCUMBENT PROGRAMS
*******************************************************************************/

use "`panel'", clear

keep if ///
    inrange(ao_proceso, 2007, 2016)

isid ///
    codigo_unico ///
    ao_proceso


/*
Identify incumbent and entrant universities.
*/

preserve

    use "`roster'", clear

    keep ///
        cod_inst ///
        entrant_2012

    duplicates drop

    isid cod_inst

    tempfile roster_clean
    save `roster_clean', replace

restore


merge m:1 cod_inst ///
    using `roster_clean', ///
    keep(match) ///
    nogen

keep if ///
    entrant_2012 == 0


/*******************************************************************************
3. MERGE THE FIVE COSINE-EXPOSURE MEASURES
*******************************************************************************/

preserve

    use "`exposure'", clear

    rename codigo_unico_2011 ///
        codigo_unico

    keep ///
        codigo_unico ///
        exp_psu ///
        exp_psu_region ///
        exp_psu_plus_region ///
        exp_psu_region_field ///
        exp_psu_plus_region_field ///
        sd_exp_psu ///
        sd_exp_psu_region ///
        sd_exp_psu_plus_region ///
        sd_exp_psu_region_field ///
        sd_exp_psu_plus_region_field


    /*
    Short names for raw exposure measures.
    */

    rename exp_psu_region ///
        exp_psu_reg

    rename exp_psu_plus_region ///
        exp_psu_addreg

    rename exp_psu_region_field ///
        exp_psu_regfld

    rename exp_psu_plus_region_field ///
        exp_psu_addregfld


    /*
    Exposure measured in original cross-program SD units.
    */

    rename sd_exp_psu ///
        exp_psu_sd

    rename sd_exp_psu_region ///
        exp_psu_reg_sd

    rename sd_exp_psu_plus_region ///
        exp_psu_addreg_sd

    rename sd_exp_psu_region_field ///
        exp_psu_regfld_sd

    rename sd_exp_psu_plus_region_field ///
        exp_psu_addregfld_sd


    isid codigo_unico

    tempfile exposure_clean
    save `exposure_clean', replace

restore


merge m:1 codigo_unico ///
    using `exposure_clean', ///
    keep(match) ///
    nogen


/*******************************************************************************
4. REQUIRE PRE- AND POST-2012 OBSERVATIONS
*******************************************************************************/

bysort codigo_unico: ///
    egen byte has_pre = ///
        max(ao_proceso <= 2011)

bysort codigo_unico: ///
    egen byte has_post = ///
        max(ao_proceso >= 2012)

keep if ///
    has_pre == 1 & ///
    has_post == 1

drop ///
    has_pre ///
    has_post


/*******************************************************************************
5. FIX PROGRAM CHARACTERISTICS IN 2011
*******************************************************************************/

preserve

    keep if ///
        ao_proceso == 2011

    keep ///
        codigo_unico ///
        area_conocimiento ///
        id_region ///
        N_firstyear

    drop if missing( ///
        codigo_unico, ///
        area_conocimiento, ///
        id_region, ///
        N_firstyear ///
    )

    isid codigo_unico

    rename area_conocimiento ///
        field_2011

    rename id_region ///
        region_2011

    rename N_firstyear ///
        enroll_2011

    tempfile characteristics_2011
    save `characteristics_2011', replace

restore


merge m:1 codigo_unico ///
    using `characteristics_2011', ///
    keep(match) ///
    nogen

drop if ///
    missing(N_firstyear)

assert ///
    N_firstyear >= 0

isid ///
    codigo_unico ///
    ao_proceso


/*******************************************************************************
6. ANALYTICAL SAMPLES
*******************************************************************************/

local min_enroll 10

gen byte sample_min10 = ///
    enroll_2011 >= `min_enroll'

label variable sample_min10 ///
    "At least 10 first-year students in 2011"

bysort codigo_unico: ///
    assert sample_min10 == sample_min10[1]


/*******************************************************************************
7. VALIDATE EXPOSURE MEASURES
*******************************************************************************/

foreach variable in ///
    exp_psu ///
    exp_psu_reg ///
    exp_psu_addreg ///
    exp_psu_regfld ///
    exp_psu_addregfld ///
    exp_psu_sd ///
    exp_psu_reg_sd ///
    exp_psu_addreg_sd ///
    exp_psu_regfld_sd ///
    exp_psu_addregfld_sd {

    assert ///
        `variable' >= 0 ///
        if !missing(`variable')

    tempvar variable_min variable_max

    bysort codigo_unico: ///
        egen double `variable_min' = ///
            min(`variable')

    bysort codigo_unico: ///
        egen double `variable_max' = ///
            max(`variable')

    assert abs( ///
        `variable_max' - `variable_min' ///
    ) < 1e-10

    drop ///
        `variable_min' ///
        `variable_max'
}


/*
Confirm that SD scaling preserves zero exposure.
*/

assert exp_psu_sd == 0 ///
    if exp_psu == 0

assert exp_psu_reg_sd == 0 ///
    if exp_psu_reg == 0

assert exp_psu_addreg_sd == 0 ///
    if exp_psu_addreg == 0

assert exp_psu_regfld_sd == 0 ///
    if exp_psu_regfld == 0

assert exp_psu_addregfld_sd == 0 ///
    if exp_psu_addregfld == 0


/*******************************************************************************
8. FIXED-EFFECT IDENTIFIERS
*******************************************************************************/

egen long program_id = ///
    group(codigo_unico)

egen long field_year = ///
    group( ///
        field_2011 ///
        ao_proceso ///
    )

egen long region_year = ///
    group( ///
        region_2011 ///
        ao_proceso ///
    )

label variable field_year ///
    "Broad-field x admission-year FE"

label variable region_year ///
    "Campus-region x admission-year FE"


/*******************************************************************************
9. SAMPLE DIAGNOSTICS
*******************************************************************************/

egen byte tag_program = ///
    tag(program_id)


display ""
display "============================================================"
display " COSINE EVENT-STUDY SAMPLES"
display "============================================================"


count

local full_observations = ///
    r(N)

display ///
    "Full-sample program-year observations = " ///
    %9.0fc `full_observations'


count if ///
    tag_program == 1

local full_programs = ///
    r(N)

display ///
    "Full-sample programs                  = " ///
    %9.0fc `full_programs'


count if ///
    sample_min10 == 1

local min10_observations = ///
    r(N)

display ///
    "Min-10 program-year observations      = " ///
    %9.0fc `min10_observations'


count if ///
    tag_program == 1 & ///
    sample_min10 == 1

local min10_programs = ///
    r(N)

display ///
    "Min-10 programs                       = " ///
    %9.0fc `min10_programs'


/*
Flag unexpected changes without stopping execution.
*/

if `full_observations' != 9105 {

    display as error ///
        "Warning: expected 9,105 observations in the full sample."
}

if `full_programs' != 996 {

    display as error ///
        "Warning: expected 996 programs in the full sample."
}

if `min10_observations' != 8618 {

    display as error ///
        "Warning: expected 8,618 observations in the min-10 sample."
}

if `min10_programs' != 939 {

    display as error ///
        "Warning: expected 939 programs in the min-10 sample."
}


drop tag_program


/*******************************************************************************
10. MANUAL YEAR INTERACTIONS
*******************************************************************************/

/*
Each exposure is measured in original cross-program SD units.

Each coefficient describes the enrollment difference associated with a
one-SD increase in exposure in year t relative to 2011.
*/

foreach measure in ///
    psu ///
    psureg ///
    psuaddreg ///
    psuregfld ///
    psuaddregfld {

    if "`measure'" == "psu" {

        local exposure_variable ///
            "exp_psu_sd"
    }

    if "`measure'" == "psureg" {

        local exposure_variable ///
            "exp_psu_reg_sd"
    }

    if "`measure'" == "psuaddreg" {

        local exposure_variable ///
            "exp_psu_addreg_sd"
    }

    if "`measure'" == "psuregfld" {

        local exposure_variable ///
            "exp_psu_regfld_sd"
    }

    if "`measure'" == "psuaddregfld" {

        local exposure_variable ///
            "exp_psu_addregfld_sd"
    }


    foreach year in ///
        2007 2008 2009 2010 ///
        2012 2013 2014 2015 2016 {

        gen double es_`measure'_`year' = ///
            `exposure_variable' * ///
            (ao_proceso == `year')

        assert es_`measure'_`year' == 0 ///
            if ao_proceso != `year'
    }
}


/*******************************************************************************
11. TEMPORARY EVENT-STUDY RESULTS
*******************************************************************************/

tempfile event_results

tempname results_handle

postfile `results_handle' ///
    str5 sample ///
    str2 spec ///
    str12 measure ///
    int year ///
    double beta ///
    double se ///
    double lower_ci ///
    double upper_ci ///
    double pretrend_F ///
    double pretrend_p ///
    long observations ///
    long programs ///
    using `event_results', ///
    replace


/*******************************************************************************
12. ESTIMATE ALL EVENT STUDIES
*******************************************************************************/

/*
Samples:

    full  = full analytical sample
    min10 = at least 10 first-year students in 2011

Specifications:

    fy = program FE + Broad-field x year FE

    ry = program FE + Broad-field x year FE
         + campus-region x year FE
*/

foreach sample in ///
    full ///
    min10 {

    local sample_if ""

    if "`sample'" == "min10" {

        local sample_if ///
            "if sample_min10 == 1"
    }


    foreach spec in ///
        fy ///
        ry {

        if "`spec'" == "fy" {

            local absorb_fe ///
                "program_id field_year"

            local specification_label ///
                "Program + Broad-field x year FE"
        }

        if "`spec'" == "ry" {

            local absorb_fe ///
                "program_id field_year region_year"

            local specification_label ///
                "Program + Broad-field x year FE + campus-region x year FE"
        }


        foreach measure in ///
            psu ///
            psureg ///
            psuaddreg ///
            psuregfld ///
            psuaddregfld {

            if "`measure'" == "psu" {

                local measure_label ///
                    "PSU only"
            }

            if "`measure'" == "psureg" {

                local measure_label ///
                    "PSU x campus region"
            }

            if "`measure'" == "psuaddreg" {

                local measure_label ///
                    "PSU + campus region"
            }

            if "`measure'" == "psuregfld" {

                local measure_label ///
                    "PSU x campus region x Broad field"
            }

            if "`measure'" == "psuaddregfld" {

                local measure_label ///
                    "PSU + campus region + Broad field"
            }


            local annual_interactions ""

            foreach year in ///
                2007 2008 2009 2010 ///
                2012 2013 2014 2015 2016 {

                local annual_interactions ///
                    "`annual_interactions' es_`measure'_`year'"
            }


            display ""
            display "============================================================"
            display " COSINE EXPOSURE EVENT STUDY"
            display "============================================================"
            display "Sample         = `sample'"
            display "Measure        = `measure_label'"
            display "Fixed effects  = `specification_label'"
            display "Omitted year   = 2011"
            display "============================================================"


            reghdfe ///
                N_firstyear ///
                `annual_interactions' ///
                `sample_if', ///
                absorb( ///
                    `absorb_fe' ///
                ) ///
                vce(cluster program_id)


            /*
            Save the effective estimation sample.
            */

            tempvar estimation_sample

            gen byte `estimation_sample' = ///
                e(sample)


            local observations = ///
                e(N)

            local residual_df = ///
                e(df_r)


            tempvar tag_estimation_program

            egen byte `tag_estimation_program' = ///
                tag(program_id) ///
                if `estimation_sample' == 1

            quietly count if ///
                `tag_estimation_program' == 1

            local programs = ///
                r(N)


            /*
            Joint pretrend test: 2007-2010.
            */

            test ///
                es_`measure'_2007 ///
                es_`measure'_2008 ///
                es_`measure'_2009 ///
                es_`measure'_2010

            local pretrend_F = ///
                r(F)

            local pretrend_p = ///
                r(p)


            /*
            Critical value using the regression residual degrees of freedom.
            */

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


            /*
            Store annual coefficients.
            */

            forvalues year = 2007/2016 {

                if `year' == 2011 {

                    local coefficient = 0
                    local standard_error = 0
                    local lower_bound = 0
                    local upper_bound = 0
                }

                else {

                    local coefficient = ///
                        _b[es_`measure'_`year']

                    local standard_error = ///
                        _se[es_`measure'_`year']

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
                    ("`sample'") ///
                    ("`spec'") ///
                    ("`measure'") ///
                    (`year') ///
                    (`coefficient') ///
                    (`standard_error') ///
                    (`lower_bound') ///
                    (`upper_bound') ///
                    (`pretrend_F') ///
                    (`pretrend_p') ///
                    (`observations') ///
                    (`programs')
            }


            drop ///
                `estimation_sample' ///
                `tag_estimation_program'
        }
    }
}


postclose `results_handle'


/*******************************************************************************
13. PREPARE EVENT-STUDY RESULTS
*******************************************************************************/

use `event_results', clear


gen byte sample_order = .

replace sample_order = 1 ///
    if sample == "full"

replace sample_order = 2 ///
    if sample == "min10"


gen str24 sample_label = ""

replace sample_label = ///
    "Full sample" ///
    if sample == "full"

replace sample_label = ///
    "At least 10 in 2011" ///
    if sample == "min10"


gen byte spec_order = .

replace spec_order = 1 ///
    if spec == "fy"

replace spec_order = 2 ///
    if spec == "ry"


gen str52 spec_label = ""

replace spec_label = ///
    "Program + Broad-field x year FE" ///
    if spec == "fy"

replace spec_label = ///
    "+ campus-region x year FE" ///
    if spec == "ry"


gen byte measure_order = .

replace measure_order = 1 ///
    if measure == "psu"

replace measure_order = 2 ///
    if measure == "psureg"

replace measure_order = 3 ///
    if measure == "psuaddreg"

replace measure_order = 4 ///
    if measure == "psuregfld"

replace measure_order = 5 ///
    if measure == "psuaddregfld"


gen str44 measure_label = ""

replace measure_label = ///
    "PSU only" ///
    if measure == "psu"

replace measure_label = ///
    "PSU x campus region" ///
    if measure == "psureg"

replace measure_label = ///
    "PSU + campus region" ///
    if measure == "psuaddreg"

replace measure_label = ///
    "PSU x campus region x Broad field" ///
    if measure == "psuregfld"

replace measure_label = ///
    "PSU + campus region + Broad field" ///
    if measure == "psuaddregfld"


sort ///
    sample_order ///
    spec_order ///
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
14. DISPLAY ANNUAL COEFFICIENTS
*******************************************************************************/

display ""
display "============================================================"
display " COSINE EVENT-STUDY COEFFICIENTS"
display "============================================================"

list ///
    sample_label ///
    spec ///
    measure_label ///
    year ///
    beta ///
    se ///
    lower_ci ///
    upper_ci, ///
    sepby( ///
        sample ///
        spec ///
        measure ///
    ) ///
    noobs clean


/*******************************************************************************
15. COMPACT PRETREND SUMMARY
*******************************************************************************/

preserve

    keep ///
        sample ///
        sample_label ///
        sample_order ///
        spec ///
        spec_label ///
        spec_order ///
        measure ///
        measure_label ///
        measure_order ///
        pretrend_F ///
        pretrend_p ///
        observations ///
        programs

    duplicates drop

    isid ///
        sample ///
        spec ///
        measure

    count
    assert r(N) == 20

    sort ///
        sample_order ///
        spec_order ///
        measure_order


    display ""
    display "============================================================"
    display " COSINE EVENT-STUDY PRETREND SUMMARY"
    display "============================================================"

    list ///
        sample_label ///
        spec ///
        measure_label ///
        pretrend_F ///
        pretrend_p ///
        observations ///
        programs, ///
        sepby( ///
            sample ///
            spec ///
        ) ///
        noobs clean

restore


/*******************************************************************************
16. HORIZONTAL POSITIONS FOR THE FIVE MEASURES
*******************************************************************************/

/*
The offsets are only visual. All five estimates continue to correspond to
the same admission year.
*/

gen double graph_year = ///
    year

replace graph_year = ///
    year - 0.16 ///
    if measure == "psu"

replace graph_year = ///
    year - 0.08 ///
    if measure == "psureg"

replace graph_year = ///
    year ///
    if measure == "psuaddreg"

replace graph_year = ///
    year + 0.08 ///
    if measure == "psuregfld"

replace graph_year = ///
    year + 0.16 ///
    if measure == "psuaddregfld"


/*******************************************************************************
17. CREATE THE TWO FULL-SAMPLE FIGURES
*******************************************************************************/

foreach spec in ///
    fy ///
    ry {

    if "`spec'" == "fy" {

        local graph_title ///
            "Cosine exposure event studies"

        local graph_subtitle ///
            "Program FE and Broad-field x year FE; 2011 omitted"

        local graph_output ///
            "`graph_baseline'"

        local graph_name ///
            "cosine_event_baseline"
    }

    if "`spec'" == "ry" {

        local graph_title ///
            "Cosine exposure event studies"

        local graph_subtitle ///
            "Program FE, Broad-field x year FE, and campus-region x year FE; 2011 omitted"

        local graph_output ///
            "`graph_regionyear'"

        local graph_name ///
            "cosine_event_regionyear"
    }


    /*
    Pretrend p-values for the graph note.
    */

    foreach measure in ///
        psu ///
        psureg ///
        psuaddreg ///
        psuregfld ///
        psuaddregfld {

        quietly summarize ///
            pretrend_p ///
            if ///
                sample == "full" & ///
                spec == "`spec'" & ///
                measure == "`measure'", ///
            meanonly

        local p_`measure' : ///
            display %6.4f r(mean)
    }


    /*
    Common vertical range across the five measures.
    */

    quietly summarize ///
        lower_ci ///
        if ///
            sample == "full" & ///
            spec == "`spec'" & ///
            year != 2011, ///
        meanonly

    local graph_min = ///
        r(min)


    quietly summarize ///
        upper_ci ///
        if ///
            sample == "full" & ///
            spec == "`spec'" & ///
            year != 2011, ///
        meanonly

    local graph_max = ///
        r(max)


    if `graph_min' > 0 {

        local graph_min = 0
    }

    if `graph_max' < 0 {

        local graph_max = 0
    }


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


    /*
    The first five plots are confidence intervals.
    Plots 6-10 are coefficient markers.
    Plot 11 is the single omitted-year marker.
    */

    twoway ///
        (rspike ///
            lower_ci ///
            upper_ci ///
            graph_year ///
            if ///
                sample == "full" & ///
                spec == "`spec'" & ///
                measure == "psu" & ///
                year != 2011, ///
            lcolor(navy%45) ///
            lwidth(thin)) ///
        (rspike ///
            lower_ci ///
            upper_ci ///
            graph_year ///
            if ///
                sample == "full" & ///
                spec == "`spec'" & ///
                measure == "psureg" & ///
                year != 2011, ///
            lcolor(maroon%45) ///
            lwidth(thin)) ///
        (rspike ///
            lower_ci ///
            upper_ci ///
            graph_year ///
            if ///
                sample == "full" & ///
                spec == "`spec'" & ///
                measure == "psuaddreg" & ///
                year != 2011, ///
            lcolor(forest_green%45) ///
            lwidth(thin)) ///
        (rspike ///
            lower_ci ///
            upper_ci ///
            graph_year ///
            if ///
                sample == "full" & ///
                spec == "`spec'" & ///
                measure == "psuregfld" & ///
                year != 2011, ///
            lcolor(dkorange%45) ///
            lwidth(thin)) ///
        (rspike ///
            lower_ci ///
            upper_ci ///
            graph_year ///
            if ///
                sample == "full" & ///
                spec == "`spec'" & ///
                measure == "psuaddregfld" & ///
                year != 2011, ///
            lcolor(purple%45) ///
            lwidth(thin)) ///
        (scatter ///
            beta ///
            graph_year ///
            if ///
                sample == "full" & ///
                spec == "`spec'" & ///
                measure == "psu" & ///
                year != 2011, ///
            mcolor(navy) ///
            mlcolor(navy) ///
            msymbol(circle) ///
            msize(medsmall)) ///
        (scatter ///
            beta ///
            graph_year ///
            if ///
                sample == "full" & ///
                spec == "`spec'" & ///
                measure == "psureg" & ///
                year != 2011, ///
            mcolor(maroon) ///
            mlcolor(maroon) ///
            msymbol(triangle) ///
            msize(medsmall)) ///
        (scatter ///
            beta ///
            graph_year ///
            if ///
                sample == "full" & ///
                spec == "`spec'" & ///
                measure == "psuaddreg" & ///
                year != 2011, ///
            mcolor(forest_green) ///
            mlcolor(forest_green) ///
            msymbol(diamond) ///
            msize(medsmall)) ///
        (scatter ///
            beta ///
            graph_year ///
            if ///
                sample == "full" & ///
                spec == "`spec'" & ///
                measure == "psuregfld" & ///
                year != 2011, ///
            mcolor(dkorange) ///
            mlcolor(dkorange) ///
            msymbol(square) ///
            msize(medsmall)) ///
        (scatter ///
            beta ///
            graph_year ///
            if ///
                sample == "full" & ///
                spec == "`spec'" & ///
                measure == "psuaddregfld" & ///
                year != 2011, ///
            mcolor(purple) ///
            mlcolor(purple) ///
            msymbol(X) ///
            msize(medsmall)) ///
        (scatter ///
            beta ///
            year ///
            if ///
                sample == "full" & ///
                spec == "`spec'" & ///
                measure == "psu" & ///
                year == 2011, ///
            mcolor(gs6) ///
            mlcolor(gs6) ///
            msymbol(Oh) ///
            msize(medsmall)) ///
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
            range(2006.65 2016.35) ///
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
            format(%5.1f) ///
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
            "Enrollment coefficient per SD of exposure", ///
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
                6  "PSU" ///
                7  "PSU x R" ///
                8  "PSU + R" ///
                9  "PSU x R x F" ///
                10 "PSU + R + F" ///
            ) ///
            rows(2) ///
            position(6) ///
            size(small) ///
            region( ///
                lcolor(none) ///
                fcolor(none) ///
            ) ///
        ) ///
        note( ///
			"R denotes campus region; F denotes Broad field. 95% CIs; SEs clustered by program." ///
			"Joint pretrend p-values: PSU = `p_psu'; PSU x R = `p_psureg'; PSU + R = `p_psuaddreg'." ///
			"PSU x R x F = `p_psuregfld'; PSU + R + F = `p_psuaddregfld'.", ///
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
            `graph_name', ///
            replace ///
        )


    graph export ///
        "`graph_output'.png", ///
        width(3000) ///
        replace

    capture noisily graph export ///
        "`graph_output'.pdf", ///
        replace
}


/*******************************************************************************
18. END
*******************************************************************************/

display ""
display "============================================================"
display " COSINE EXPOSURE EVENT STUDIES COMPLETED"
display "============================================================"

display ///
    "Baseline graph:    `graph_baseline'.png"

display ///
    "Region-year graph: `graph_regionyear'.png"

display ""
display "07_cosine_event_studies.do completed successfully."