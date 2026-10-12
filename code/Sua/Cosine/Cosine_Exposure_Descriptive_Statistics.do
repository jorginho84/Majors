/*******************************************************************************
Cosine_Exposure_Descriptive_Statistics.do

COSINE EXPOSURE: DESCRIPTIVE STATISTICS

This file constructs descriptive statistics for:

    A. Cosine exposure using alternative academic-field definitions
       - General field
       - CINE97 field
       - Generic field

    B. Cosine exposure using alternative PSU-region vectors
       - PSU only
       - PSU x campus region
       - PSU + campus region

Common sample restriction:
    Incumbent SUA programs with at least 10 first-year students in 2011.

No regressions are estimated and no permanent datasets are created.
*******************************************************************************/

version 18.0
clear all
set more off


/*******************************************************************************
0. INPUT FILES
*******************************************************************************/

local panel ///
    "$processed/sua_exposure/sies_program_year_with_demre_2007_2016.dta"

local roster ///
    "$processed/sua_exposure/sua_university_sies_roster.dta"

local vectors ///
    "$processed/program_geo_psu_vectors_2011.dta"


/*
Field-definition cosine exposures.
*/

local exposure_general ///
    "$processed/cosine_exposure_incumbents_2011_same_region_field.dta"

local exposure_cine97 ///
    "$processed/cosine_exposure_incumbents_2011_same_region_cine97.dta"

local exposure_generic ///
    "$processed/cosine_exposure_incumbents_2011_same_region_generic.dta"


/*
PSU-region cosine exposures.
*/

local exposure_psu_region ///
    "$processed/cosine_exposure_incumbents_2011_psu_campus_region.dta"


/*
Minimum first-year enrollment required in 2011.
*/

local minimum_enrollment_2011 10


/*******************************************************************************
1. RECONSTRUCT PROGRAM-LEVEL MEAN PSU IN 2011
*******************************************************************************/

use "`vectors'", clear

keep ///
    codigo_unico ///
    psu_bin_lower ///
    psu_bin_upper ///
    N_cell

drop if missing( ///
    codigo_unico, ///
    psu_bin_lower, ///
    psu_bin_upper, ///
    N_cell ///
)


/*
Approximate each student's PSU using the midpoint of the corresponding
25-point PSU interval.
*/

gen double psu_midpoint = ///
    (psu_bin_lower + psu_bin_upper) / 2

gen double weighted_psu_points = ///
    psu_midpoint * N_cell


/*
Collapse all PSU cells to the program level.
*/

collapse ///
    (sum) students_psu_2011 = N_cell ///
          weighted_psu_points, ///
    by(codigo_unico)

gen double mean_psu_2011 = ///
    weighted_psu_points / students_psu_2011

drop weighted_psu_points

isid codigo_unico

tempfile program_psu_2011
save `program_psu_2011', replace


/*******************************************************************************
2. PREPARE THE UNIVERSITY ROSTER
*******************************************************************************/

use "`roster'", clear

keep ///
    cod_inst ///
    entrant_2012

duplicates drop

isid cod_inst

tempfile university_roster
save `university_roster', replace


/*******************************************************************************
3. PREPARE FIELD-DEFINITION EXPOSURES
*******************************************************************************/

/*
3.1 General field.
*/

use "`exposure_general'", clear

keep ///
    codigo_unico_2011 ///
    exp_psu_rf

rename codigo_unico_2011 codigo_unico
rename exp_psu_rf exposure_general_field

isid codigo_unico

tempfile general_field_exposure
save `general_field_exposure', replace


/*
3.2 CINE97 field.
*/

use "`exposure_cine97'", clear

keep ///
    codigo_unico_2011 ///
    exp_psu_rcine

rename codigo_unico_2011 codigo_unico
rename exp_psu_rcine exposure_cine97_field

isid codigo_unico

tempfile cine97_field_exposure
save `cine97_field_exposure', replace


/*
3.3 Generic field.
*/

use "`exposure_generic'", clear

keep ///
    codigo_unico_2011 ///
    exp_psu_rgen

rename codigo_unico_2011 codigo_unico
rename exp_psu_rgen exposure_generic_field

isid codigo_unico

tempfile generic_field_exposure
save `generic_field_exposure', replace


/*******************************************************************************
4. PREPARE PSU-REGION EXPOSURES
*******************************************************************************/

use "`exposure_psu_region'", clear

keep ///
    codigo_unico_2011 ///
    exp_psu ///
    exp_psu_region ///
    exp_psu_plus_region

rename codigo_unico_2011 codigo_unico

rename exp_psu ///
    exposure_psu_only

rename exp_psu_region ///
    exposure_psu_by_region

rename exp_psu_plus_region ///
    exposure_psu_plus_region

isid codigo_unico

tempfile psu_region_exposures
save `psu_region_exposures', replace


/*******************************************************************************
5. CONSTRUCT THE COMMON ANALYTICAL SAMPLE
*******************************************************************************/

use "`panel'", clear

keep if inrange(ao_proceso, 2007, 2016)

isid ///
    codigo_unico ///
    ao_proceso


/*
Identify programs belonging to incumbent SUA universities.
*/

merge m:1 cod_inst ///
    using `university_roster', ///
    keep(match) ///
    nogen

keep if entrant_2012 == 0


/*
Attach the three field-definition exposures.
*/

merge m:1 codigo_unico ///
    using `general_field_exposure', ///
    keep(match) ///
    nogen

merge m:1 codigo_unico ///
    using `cine97_field_exposure', ///
    keep(match) ///
    nogen

merge m:1 codigo_unico ///
    using `generic_field_exposure', ///
    keep(match) ///
    nogen


/*
Attach the three PSU-region exposures.
*/

merge m:1 codigo_unico ///
    using `psu_region_exposures', ///
    keep(match) ///
    nogen

drop if missing(N_firstyear)


/*******************************************************************************
6. DEFINE THE PROGRAM SAMPLE
*******************************************************************************/

/*
First-year enrollment in 2011.
*/

bysort codigo_unico: ///
    egen double firstyear_enrollment_2011 = ///
        max( ///
            cond( ///
                ao_proceso == 2011, ///
                N_firstyear, ///
                . ///
            ) ///
        )


/*
Require observations before and after the 2012 reform.
*/

bysort codigo_unico: ///
    egen byte has_pre_reform = ///
        max(ao_proceso <= 2011)

bysort codigo_unico: ///
    egen byte has_post_reform = ///
        max(ao_proceso >= 2012)

keep if ///
    has_pre_reform == 1 & ///
    has_post_reform == 1

drop ///
    has_pre_reform ///
    has_post_reform


/*
Apply the minimum-enrollment restriction using 2011 enrollment.
The entire program panel is removed when enrollment in 2011 is below 10.
*/

egen byte tag_program_before_restriction = ///
    tag(codigo_unico)

count if tag_program_before_restriction == 1

display ""
display "Programs before enrollment restriction = " ///
    %9.0fc r(N)

count if ///
    tag_program_before_restriction == 1 & ///
    firstyear_enrollment_2011 < ///
        `minimum_enrollment_2011'

display "Programs excluded because enrollment in 2011 is below 10 = " ///
    %9.0fc r(N)

keep if ///
    firstyear_enrollment_2011 >= ///
        `minimum_enrollment_2011'

drop tag_program_before_restriction


/*******************************************************************************
7. CONSTRUCT PRE-REFORM PROGRAM CHARACTERISTICS
*******************************************************************************/

/*
Average annual first-year enrollment during 2007-2011.
*/

gen double enrollment_pre_temp = ///
    N_firstyear ///
    if inrange(ao_proceso, 2007, 2011)

bysort codigo_unico: ///
    egen double mean_firstyear_enrollment_pre = ///
        mean(enrollment_pre_temp)

drop enrollment_pre_temp


/*
Store the number of program-year observations before retaining one row
per program.
*/

quietly count
local program_year_observations = r(N)


/*
Keep one observation per incumbent program.
*/

bysort codigo_unico (ao_proceso): ///
    keep if _n == 1

isid codigo_unico


/*
Attach reconstructed PSU characteristics.
*/

merge 1:1 codigo_unico ///
    using `program_psu_2011', ///
    keep(match) ///
    nogen


/*******************************************************************************
8. VERIFY THE COMMON SAMPLE
*******************************************************************************/

drop if missing( ///
    firstyear_enrollment_2011, ///
    mean_firstyear_enrollment_pre, ///
    mean_psu_2011, ///
    exposure_general_field, ///
    exposure_cine97_field, ///
    exposure_generic_field, ///
    exposure_psu_only, ///
    exposure_psu_by_region, ///
    exposure_psu_plus_region ///
)


/*
Sample totals.
*/

quietly count
local number_programs = r(N)

egen byte tag_university = ///
    tag(cod_inst)

quietly count if tag_university == 1
local number_universities = r(N)

quietly summarize firstyear_enrollment_2011
local total_enrollment_2011 = r(sum)

quietly summarize students_psu_2011
local students_in_psu_vectors = r(sum)

local psu_vector_coverage = ///
    100 * ///
    `students_in_psu_vectors' / ///
    `total_enrollment_2011'


/*******************************************************************************
9. COMMON SAMPLE CHARACTERISTICS
*******************************************************************************/

label variable firstyear_enrollment_2011 ///
    "First-year enrollment, 2011"

label variable mean_firstyear_enrollment_pre ///
    "Annual first-year enrollment, 2007-2011"

label variable mean_psu_2011 ///
    "Mean PSU score, 2011"


display ""
display "============================================================"
display " COMMON COSINE SAMPLE: PROGRAM CHARACTERISTICS"
display "============================================================"

tabstat ///
    firstyear_enrollment_2011 ///
    mean_firstyear_enrollment_pre ///
    mean_psu_2011, ///
    statistics( ///
        mean ///
        sd ///
        min ///
        max ///
    ) ///
    columns(statistics)


display ""
display "Program-year observations = " ///
    %12.0fc `program_year_observations'

display "Programs = " ///
    %12.0fc `number_programs'

display "Incumbent universities = " ///
    %12.0fc `number_universities'

display "Total first-year enrollment in 2011 = " ///
    %12.0fc `total_enrollment_2011'

display "Students represented in PSU vectors = " ///
    %12.0fc `students_in_psu_vectors'

display "PSU-vector enrollment coverage (%) = " ///
    %9.1f `psu_vector_coverage'


/*******************************************************************************
10. CREATE THE TWO EXPOSURE TABLES
*******************************************************************************/

label variable exposure_general_field ///
    "General field"

label variable exposure_cine97_field ///
    "CINE97 field"

label variable exposure_generic_field ///
    "Generic field"

label variable exposure_psu_only ///
    "PSU only"

label variable exposure_psu_by_region ///
    "PSU x campus region"

label variable exposure_psu_plus_region ///
    "PSU + campus region"


tempname exposure_results_post
tempfile exposure_results

postfile `exposure_results_post' ///
    byte table_number ///
    byte row_order ///
    str35 table ///
    str40 exposure ///
    double mean ///
    double sd ///
    double minimum ///
    double maximum ///
    double share_zero ///
    using `exposure_results', ///
    replace


/*
Table A: academic-field definitions.
*/

local row_order = 0

foreach exposure_variable in ///
    exposure_general_field ///
    exposure_cine97_field ///
    exposure_generic_field {

    local ++row_order

    quietly summarize `exposure_variable'

    local exposure_mean = r(mean)
    local exposure_sd = r(sd)
    local exposure_minimum = r(min)
    local exposure_maximum = r(max)

    quietly count if !missing(`exposure_variable')
    local exposure_observations = r(N)

    quietly count if ///
        `exposure_variable' == 0 & ///
        !missing(`exposure_variable')

    local exposure_share_zero = ///
        100 * r(N) / `exposure_observations'

    local exposure_label : ///
        variable label `exposure_variable'

    post `exposure_results_post' ///
        (1) ///
        (`row_order') ///
        ("Academic-field definitions") ///
        ("`exposure_label'") ///
        (`exposure_mean') ///
        (`exposure_sd') ///
        (`exposure_minimum') ///
        (`exposure_maximum') ///
        (`exposure_share_zero')
}


/*
Table B: PSU and campus-region definitions.
*/

local row_order = 0

foreach exposure_variable in ///
    exposure_psu_only ///
    exposure_psu_by_region ///
    exposure_psu_plus_region {

    local ++row_order

    quietly summarize `exposure_variable'

    local exposure_mean = r(mean)
    local exposure_sd = r(sd)
    local exposure_minimum = r(min)
    local exposure_maximum = r(max)

    quietly count if !missing(`exposure_variable')
    local exposure_observations = r(N)

    quietly count if ///
        `exposure_variable' == 0 & ///
        !missing(`exposure_variable')

    local exposure_share_zero = ///
        100 * r(N) / `exposure_observations'

    local exposure_label : ///
        variable label `exposure_variable'

    post `exposure_results_post' ///
        (2) ///
        (`row_order') ///
        ("PSU and campus-region definitions") ///
        ("`exposure_label'") ///
        (`exposure_mean') ///
        (`exposure_sd') ///
        (`exposure_minimum') ///
        (`exposure_maximum') ///
        (`exposure_share_zero')
}

postclose `exposure_results_post'


/*******************************************************************************
11. DISPLAY THE TWO EXPOSURE TABLES
*******************************************************************************/

use `exposure_results', clear

sort ///
    table_number ///
    row_order

format ///
    mean ///
    sd ///
    minimum ///
    maximum ///
    %9.4f

format share_zero %9.1f


display ""
display "============================================================"
display " TABLE A: COSINE EXPOSURE BY ACADEMIC-FIELD DEFINITION"
display "============================================================"

list ///
    exposure ///
    mean ///
    sd ///
    minimum ///
    maximum ///
    share_zero ///
    if table_number == 1, ///
    noobs clean


display ""
display "============================================================"
display " TABLE B: COSINE EXPOSURE BY PSU-REGION DEFINITION"
display "============================================================"

list ///
    exposure ///
    mean ///
    sd ///
    minimum ///
    maximum ///
    share_zero ///
    if table_number == 2, ///
    noobs clean


/*******************************************************************************
12. NOTES
*******************************************************************************/

display ""
display "============================================================"
display " NOTES"
display "============================================================"

display "Unit: incumbent SUA program."
display "All characteristics and cosine exposures are fixed in 2011."
display "Programs must have at least 10 first-year students in 2011."
display "Exposure statistics use raw, non-standardized cosine measures."
display "Campus region is the region of the university program in 2011."
display "Student school region and SES are not used."
display "Means are unweighted across incumbent programs."