/*******************************************************************************
06d_cosine_first_stages_10restricted.do

PURPOSE

Compare three cosine-exposure measures:

    1. PSU bins only
    2. PSU bins x campus region
    3. Equal-weight PSU + campus region

For each measure, the first-stage regressor is constructed directly as:

    standardized exposure x Post

where Post equals one in 2012-2016.

The geographic variable is the region of the university campus in 2011.
Student school region and SES are not used.

All three measures are built without restricting pairs by academic field.
Broad field enters only through field x year fixed effects.

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

local exposure ///
    "$processed/cosine_exposure_incumbents_2011_psu_campus_region.dta"


/*******************************************************************************
1. ANALYTICAL PANEL OF INCUMBENT SUA PROGRAMS
*******************************************************************************/

use "`panel'", clear

keep if inrange(ao_proceso, 2007, 2016)

isid codigo_unico ao_proceso


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

/*
Keep programs belonging to incumbent universities.
*/

keep if entrant_2012 == 0


/*******************************************************************************
2. MERGE THE THREE EXPOSURES
*******************************************************************************/

preserve

    use "`exposure'", clear

    rename codigo_unico_2011 codigo_unico

    keep ///
        codigo_unico ///
        exp_psu ///
        exp_psu_region ///
        exp_psu_plus_region ///
        sd_exp_psu ///
        sd_exp_psu_region ///
        sd_exp_psu_plus_region

    isid codigo_unico

    tempfile exposure_clean
    save `exposure_clean', replace

restore


merge m:1 codigo_unico ///
    using `exposure_clean', ///
    keep(match) ///
    nogen


/*******************************************************************************
3. REQUIRE PRE- AND POST-2012 OBSERVATIONS
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
4. FIX BROAD FIELD, CAMPUS REGION, AND ENROLLMENT IN 2011
*******************************************************************************/

preserve

    keep if ao_proceso == 2011

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

    rename ///
        area_conocimiento ///
        field_2011

    rename ///
        id_region ///
        region_2011

    rename ///
        N_firstyear ///
        firstyear_enrollment_2011

    tempfile chars2011
    save `chars2011', replace

restore


merge m:1 codigo_unico ///
    using `chars2011', ///
    keep(match) ///
    nogen

drop if missing(N_firstyear)

isid codigo_unico ao_proceso

/*******************************************************************************
4.1 EXCLUDE PROGRAMS WITH FEWER THAN 10 STUDENTS IN 2011

This is an exploratory restriction. Program eligibility is determined using
first-year enrollment in 2011, the year used to construct the PSU vectors.
Once a program is classified as ineligible, all its program-year observations
are removed from the analytical panel.
*******************************************************************************/

local minimum_enrollment_2011 10


/*
Count programs before applying the restriction.
*/

egen byte tag_program_before_minimum = ///
    tag(codigo_unico)

count if tag_program_before_minimum == 1

display ///
    "Programs before minimum-enrollment restriction = " ///
    %9.0fc r(N)


/*
Identify and display the programs that will be excluded.
*/

count if ///
    tag_program_before_minimum == 1 & ///
    firstyear_enrollment_2011 < ///
        `minimum_enrollment_2011'

display ///
    "Programs excluded because 2011 enrollment is below 10 = " ///
    %9.0fc r(N)


list ///
    codigo_unico ///
    field_2011 ///
    region_2011 ///
    firstyear_enrollment_2011 ///
    if ///
        tag_program_before_minimum == 1 & ///
        firstyear_enrollment_2011 < ///
            `minimum_enrollment_2011', ///
    noobs clean


/*
Remove every program-year observation belonging to these programs.
*/

keep if ///
    firstyear_enrollment_2011 >= ///
        `minimum_enrollment_2011'

drop tag_program_before_minimum


/*
Verify the restricted sample.
*/

assert ///
    firstyear_enrollment_2011 >= ///
        `minimum_enrollment_2011'


egen byte tag_program_after_minimum = ///
    tag(codigo_unico)

count if tag_program_after_minimum == 1

display ///
    "Programs after minimum-enrollment restriction = " ///
    %9.0fc r(N)

drop tag_program_after_minimum


count

display ///
    "Program-year observations after restriction = " ///
    %9.0fc r(N)

/*******************************************************************************
5. EXPOSURE x POST VARIABLES

Each exposure is divided by its cross-program standard deviation without
subtracting its mean. Therefore, raw exposure equal to zero remains zero.

The first-stage regressor is defined directly as:

    Exposure_p x Post_t

No separate positive-exposure dummy is required.
*******************************************************************************/

gen byte post2012 = ///
    inrange(ao_proceso, 2012, 2016)


/*
PSU-bin exposure only.
*/

gen double fs_psu = ///
    sd_exp_psu * post2012


/*
PSU-bin exposure restricted to programs in the same campus region.
*/

gen double fs_psu_region = ///
    sd_exp_psu_region * post2012


/*
Equal-weight combination of PSU similarity and campus-region similarity.
*/

gen double fs_psu_plus_region = ///
    sd_exp_psu_plus_region * post2012


/*
Verify that the interactions equal zero before 2012.
*/

assert fs_psu == 0 ///
    if post2012 == 0

assert fs_psu_region == 0 ///
    if post2012 == 0

assert fs_psu_plus_region == 0 ///
    if post2012 == 0


/*
Verify that economically zero exposures remain zero.
*/

assert fs_psu == 0 ///
    if exp_psu == 0

assert fs_psu_region == 0 ///
    if exp_psu_region == 0

assert fs_psu_plus_region == 0 ///
    if exp_psu_plus_region == 0


/*
Verify that the constructed variables have no missing values.
*/

assert !missing( ///
    post2012, ///
    fs_psu, ///
    fs_psu_region, ///
    fs_psu_plus_region ///
)


/*******************************************************************************
6. FIXED-EFFECT IDENTIFIERS
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


/*******************************************************************************
7. SAMPLE AND EXPOSURE DIAGNOSTICS
*******************************************************************************/

display ""
display "============================================================"
display " COSINE FIRST-STAGE SAMPLE"
display "============================================================"

count

display ///
    "Program-year observations = " ///
    %9.0fc r(N)


egen byte tag_program = ///
    tag(program_id)

count if tag_program == 1

display ///
    "Programs = " ///
    %9.0fc r(N)


foreach variable in ///
    exp_psu ///
    exp_psu_region ///
    exp_psu_plus_region {

    count if ///
        tag_program == 1 & ///
        `variable' > 0

    display ///
        "Programs with positive `variable' = " ///
        %9.0fc r(N)
}


summarize ///
    N_firstyear ///
    exp_psu ///
    exp_psu_region ///
    exp_psu_plus_region ///
    fs_psu ///
    fs_psu_region ///
    fs_psu_plus_region


/*******************************************************************************
8. PROGRAM + YEAR FIXED EFFECTS
*******************************************************************************/

display ""
display "===== (1) PSU ONLY: PROGRAM + YEAR FE ====="

reghdfe ///
    N_firstyear ///
    fs_psu, ///
    absorb( ///
        program_id ///
        ao_proceso ///
    ) ///
    vce(cluster program_id)

estimates store ///
    psu_programyear


display ""
display "===== (2) PSU x CAMPUS REGION: PROGRAM + YEAR FE ====="

reghdfe ///
    N_firstyear ///
    fs_psu_region, ///
    absorb( ///
        program_id ///
        ao_proceso ///
    ) ///
    vce(cluster program_id)

estimates store ///
    psuregion_programyear


display ""
display "===== (3) PSU + CAMPUS REGION: PROGRAM + YEAR FE ====="

reghdfe ///
    N_firstyear ///
    fs_psu_plus_region, ///
    absorb( ///
        program_id ///
        ao_proceso ///
    ) ///
    vce(cluster program_id)

estimates store ///
    psuplusregion_programyear


/*******************************************************************************
9. PROGRAM + BROAD FIELD x YEAR FIXED EFFECTS

Common year fixed effects are contained in field x year fixed effects.
*******************************************************************************/

display ""
display "===== (4) PSU ONLY: PROGRAM + BROAD FIELD x YEAR FE ====="

reghdfe ///
    N_firstyear ///
    fs_psu, ///
    absorb( ///
        program_id ///
        field_year ///
    ) ///
    vce(cluster program_id)

estimates store ///
    psu_fieldyear


display ""
display "===== (5) PSU x CAMPUS REGION: PROGRAM + BROAD FIELD x YEAR FE ====="

reghdfe ///
    N_firstyear ///
    fs_psu_region, ///
    absorb( ///
        program_id ///
        field_year ///
    ) ///
    vce(cluster program_id)

estimates store ///
    psuregion_fieldyear


display ""
display "===== (6) PSU + CAMPUS REGION: PROGRAM + BROAD FIELD x YEAR FE ====="

reghdfe ///
    N_firstyear ///
    fs_psu_plus_region, ///
    absorb( ///
        program_id ///
        field_year ///
    ) ///
    vce(cluster program_id)

estimates store ///
    psuplusregion_fieldyear


/*******************************************************************************
10. PROGRAM + BROAD FIELD x YEAR + REGION x YEAR FIXED EFFECTS
*******************************************************************************/

display ""
display "===== (7) PSU ONLY: + REGION x YEAR FE ====="

reghdfe ///
    N_firstyear ///
    fs_psu, ///
    absorb( ///
        program_id ///
        field_year ///
        region_year ///
    ) ///
    vce(cluster program_id)

estimates store ///
    psu_regionyear


display ""
display "===== (8) PSU x CAMPUS REGION: + REGION x YEAR FE ====="

reghdfe ///
    N_firstyear ///
    fs_psu_region, ///
    absorb( ///
        program_id ///
        field_year ///
        region_year ///
    ) ///
    vce(cluster program_id)

estimates store ///
    psuregion_regionyear


display ""
display "===== (9) PSU + CAMPUS REGION: + REGION x YEAR FE ====="

reghdfe ///
    N_firstyear ///
    fs_psu_plus_region, ///
    absorb( ///
        program_id ///
        field_year ///
        region_year ///
    ) ///
    vce(cluster program_id)

estimates store ///
    psuplusregion_regionyear


/*******************************************************************************
11. DISPLAY COMPARABLE RESULTS
*******************************************************************************/

display ""
display "============================================================"
display " COSINE FIRST-STAGE RESULTS"
display "============================================================"

estimates table ///
    psu_programyear ///
    psuregion_programyear ///
    psuplusregion_programyear, ///
    b(%9.3f) ///
    se(%9.3f) ///
    stats(N)


display ""

estimates table ///
    psu_fieldyear ///
    psuregion_fieldyear ///
    psuplusregion_fieldyear, ///
    b(%9.3f) ///
    se(%9.3f) ///
    stats(N)


display ""

estimates table ///
    psu_regionyear ///
    psuregion_regionyear ///
    psuplusregion_regionyear, ///
    b(%9.3f) ///
    se(%9.3f) ///
    stats(N)


/*******************************************************************************
12. END
*******************************************************************************/

display ""
display "============================================================"
display " COSINE LEVEL ESTIMATIONS COMPLETED"
display "============================================================"