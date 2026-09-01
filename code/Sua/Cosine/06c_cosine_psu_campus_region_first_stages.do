/*******************************************************************************
06c_cosine_first_stages_full_and_min10.do

PURPOSE

Estimate cosine-exposure first stages using two samples:

    1. Full sample
    2. Programs with at least 10 first-year students in 2011

Five exposure measures are considered:

    1. PSU bins
    2. PSU bins x campus region
    3. PSU bins + campus region
    4. PSU bins x campus region x Broad field
    5. PSU bins + campus region + Broad field

Three fixed-effect specifications are estimated:

    1. Program FE + year FE
    2. Program FE + Broad-field x year FE
    3. Program FE + Broad-field x year FE + campus-region x year FE

The minimum-enrollment restriction changes only the regression sample.
Exposure measures and their original scaling are not reconstructed.

Run the revised 05d construction file before this file.
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
2. MERGE THE FIVE EXPOSURE MEASURES
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
    Short working names for raw exposure measures.
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
4. FIX PROGRAM CHARACTERISTICS AND ENROLLMENT IN 2011
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

drop if missing(N_firstyear)

isid codigo_unico ao_proceso


/*******************************************************************************
5. DEFINE THE TWO ANALYTICAL SAMPLES
*******************************************************************************/

local min_enroll 10

gen byte sample_min10 = ///
    enroll_2011 >= `min_enroll'

label variable sample_min10 ///
    "At least 10 first-year students in 2011"


/*
Eligibility must be fixed within program.
*/

bysort codigo_unico: ///
    assert sample_min10 == sample_min10[1]


/*******************************************************************************
6. SAMPLE DIAGNOSTICS
*******************************************************************************/

egen byte tag_program = ///
    tag(codigo_unico)


display ""
display "============================================================"
display " FULL ANALYTICAL SAMPLE"
display "============================================================"

count

display ///
    "Program-year observations = " ///
    %9.0fc r(N)

count if tag_program == 1

display ///
    "Programs = " ///
    %9.0fc r(N)


display ""
display "============================================================"
display " SAMPLE WITH AT LEAST 10 STUDENTS IN 2011"
display "============================================================"

count if sample_min10 == 1

display ///
    "Program-year observations = " ///
    %9.0fc r(N)

count if ///
    tag_program == 1 & ///
    sample_min10 == 1

display ///
    "Programs = " ///
    %9.0fc r(N)


count if ///
    tag_program == 1 & ///
    sample_min10 == 0

display ///
    "Excluded programs = " ///
    %9.0fc r(N)


/*
Display excluded programs for documentation.
*/

list ///
    codigo_unico ///
    field_2011 ///
    region_2011 ///
    enroll_2011 ///
    if ///
        tag_program == 1 & ///
        sample_min10 == 0, ///
    noobs clean


/*******************************************************************************
7. EXPOSURE x POST VARIABLES
*******************************************************************************/

/*
Exposure is measured in cross-program SD units without subtracting its mean.
Therefore, raw exposure equal to zero remains equal to zero.
*/

gen byte post = ///
    inrange(ao_proceso, 2012, 2016)

label variable post ///
    "Admission year 2012-2016"


/*
1. PSU bins.
*/

gen double fs_psu = ///
    exp_psu_sd * post


/*
2. PSU bins x campus region.
*/

gen double fs_psu_reg = ///
    exp_psu_reg_sd * post


/*
3. PSU bins + campus region.
*/

gen double fs_psu_addreg = ///
    exp_psu_addreg_sd * post


/*
4. PSU bins x campus region x Broad field.
*/

gen double fs_psu_regfld = ///
    exp_psu_regfld_sd * post


/*
5. PSU bins + campus region + Broad field.
*/

gen double fs_psu_addregfld = ///
    exp_psu_addregfld_sd * post


/*
All first-stage regressors must equal zero before 2012.
*/

assert fs_psu == 0 ///
    if post == 0

assert fs_psu_reg == 0 ///
    if post == 0

assert fs_psu_addreg == 0 ///
    if post == 0

assert fs_psu_regfld == 0 ///
    if post == 0

assert fs_psu_addregfld == 0 ///
    if post == 0


/*
Economically zero exposures must remain zero.
*/

assert fs_psu == 0 ///
    if exp_psu == 0

assert fs_psu_reg == 0 ///
    if exp_psu_reg == 0

assert fs_psu_addreg == 0 ///
    if exp_psu_addreg == 0

assert fs_psu_regfld == 0 ///
    if exp_psu_regfld == 0

assert fs_psu_addregfld == 0 ///
    if exp_psu_addregfld == 0


/*
No missing first-stage regressors.
*/

assert !missing( ///
    post, ///
    fs_psu, ///
    fs_psu_reg, ///
    fs_psu_addreg, ///
    fs_psu_regfld, ///
    fs_psu_addregfld ///
)


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


/*******************************************************************************
9. EXPOSURE SUPPORT BY SAMPLE
*******************************************************************************/

foreach sample in full min10 {

    display ""
    display "============================================================"
    display " EXPOSURE SUPPORT: `sample'"
    display "============================================================"

    local program_if ///
        "tag_program == 1"

    if "`sample'" == "min10" {
        local program_if ///
            "tag_program == 1 & sample_min10 == 1"
    }


    count if `program_if'

    display ///
        "Programs in sample = " ///
        %9.0fc r(N)


    foreach variable in ///
        exp_psu ///
        exp_psu_reg ///
        exp_psu_addreg ///
        exp_psu_regfld ///
        exp_psu_addregfld {

        count if ///
            `program_if' & ///
            `variable' > 0

        display ///
            "Programs with positive `variable' = " ///
            %9.0fc r(N)
    }
}


/*******************************************************************************
10. TEMPORARY RESULTS
*******************************************************************************/

tempfile results

tempname post_results

postfile `post_results' ///
    str8 sample ///
    str4 spec ///
    str14 exposure ///
    double beta ///
    double se ///
    double wald_F ///
    double p ///
    long N ///
    long programs ///
    using `results', ///
    replace


/*******************************************************************************
11. ESTIMATE ALL MODELS IN BOTH SAMPLES
*******************************************************************************/

/*
Short specification names:

    py = program + year FE
    fy = program + field x year FE
    ry = program + field x year FE + region x year FE
*/

foreach sample in full min10 {

    local use_sample ""

    if "`sample'" == "min10" {
        local use_sample ///
            "if sample_min10 == 1"
    }


    foreach spec in py fy ry {

        local absorb_fe ""
        local spec_label ""

        if "`spec'" == "py" {
            local absorb_fe ///
                "program_id ao_proceso"

            local spec_label ///
                "Program + year FE"
        }

        if "`spec'" == "fy" {
            local absorb_fe ///
                "program_id field_year"

            local spec_label ///
                "Program + field x year FE"
        }

        if "`spec'" == "ry" {
            local absorb_fe ///
                "program_id field_year region_year"

            local spec_label ///
                "+ region x year FE"
        }


        foreach measure in ///
            psu ///
            psureg ///
            psuaddreg ///
            psuregfld ///
            psuaddregfld {

            local regressor ""
            local exp_label ""

            if "`measure'" == "psu" {
                local regressor ///
                    "fs_psu"

                local exp_label ///
                    "PSU"
            }

            if "`measure'" == "psureg" {
                local regressor ///
                    "fs_psu_reg"

                local exp_label ///
                    "PSU x region"
            }

            if "`measure'" == "psuaddreg" {
                local regressor ///
                    "fs_psu_addreg"

                local exp_label ///
                    "PSU + region"
            }

            if "`measure'" == "psuregfld" {
                local regressor ///
                    "fs_psu_regfld"

                local exp_label ///
                    "PSU x region x field"
            }

            if "`measure'" == "psuaddregfld" {
                local regressor ///
                    "fs_psu_addregfld"

                local exp_label ///
                    "PSU + region + field"
            }


            display ""
            display "============================================================"
            display " SAMPLE: `sample'"
            display " EXPOSURE: `exp_label'"
            display " SPECIFICATION: `spec_label'"
            display "============================================================"


            reghdfe ///
                N_firstyear ///
                `regressor' ///
                `use_sample', ///
                absorb( ///
                    `absorb_fe' ///
                ) ///
                vce(cluster program_id)


            /*
            Store regression with a short valid name.

            Examples:

                full_py_psu
                full_fy_psureg
                min10_ry_psuaddregfld
            */

            estimates store ///
                `sample'_`spec'_`measure'


            /*
            Robust Wald test.
            */

            test `regressor'

            local est_F = ///
                r(F)

            local est_p = ///
                r(p)


            /*
            Number of programs retained after singleton removal.
            */

            egen byte tag_est_program = ///
                tag(program_id) ///
                if e(sample)

            quietly count if ///
                tag_est_program == 1

            local est_programs = ///
                r(N)

            drop tag_est_program


            /*
            Store compact results.
            */

            post `post_results' ///
                ("`sample'") ///
                ("`spec'") ///
                ("`measure'") ///
                (_b[`regressor']) ///
                (_se[`regressor']) ///
                (`est_F') ///
                (`est_p') ///
                (e(N)) ///
                (`est_programs')
        }
    }
}


postclose `post_results'


/*******************************************************************************
12. FULL-SAMPLE RESULTS
*******************************************************************************/

display ""
display "============================================================"
display " FULL SAMPLE: PROGRAM + YEAR FE"
display "============================================================"

estimates table ///
    full_py_psu ///
    full_py_psureg ///
    full_py_psuaddreg ///
    full_py_psuregfld ///
    full_py_psuaddregfld, ///
    b(%9.3f) ///
    se(%9.3f) ///
    stats(N F)


display ""
display "============================================================"
display " FULL SAMPLE: PROGRAM + FIELD x YEAR FE"
display "============================================================"

estimates table ///
    full_fy_psu ///
    full_fy_psureg ///
    full_fy_psuaddreg ///
    full_fy_psuregfld ///
    full_fy_psuaddregfld, ///
    b(%9.3f) ///
    se(%9.3f) ///
    stats(N F)


display ""
display "============================================================"
display " FULL SAMPLE: + REGION x YEAR FE"
display "============================================================"

estimates table ///
    full_ry_psu ///
    full_ry_psureg ///
    full_ry_psuaddreg ///
    full_ry_psuregfld ///
    full_ry_psuaddregfld, ///
    b(%9.3f) ///
    se(%9.3f) ///
    stats(N F)


/*******************************************************************************
13. MINIMUM-10 SAMPLE RESULTS
*******************************************************************************/

display ""
display "============================================================"
display " MINIMUM 10: PROGRAM + YEAR FE"
display "============================================================"

estimates table ///
    min10_py_psu ///
    min10_py_psureg ///
    min10_py_psuaddreg ///
    min10_py_psuregfld ///
    min10_py_psuaddregfld, ///
    b(%9.3f) ///
    se(%9.3f) ///
    stats(N F)


display ""
display "============================================================"
display " MINIMUM 10: PROGRAM + FIELD x YEAR FE"
display "============================================================"

estimates table ///
    min10_fy_psu ///
    min10_fy_psureg ///
    min10_fy_psuaddreg ///
    min10_fy_psuregfld ///
    min10_fy_psuaddregfld, ///
    b(%9.3f) ///
    se(%9.3f) ///
    stats(N F)


display ""
display "============================================================"
display " MINIMUM 10: + REGION x YEAR FE"
display "============================================================"

estimates table ///
    min10_ry_psu ///
    min10_ry_psureg ///
    min10_ry_psuaddreg ///
    min10_ry_psuregfld ///
    min10_ry_psuaddregfld, ///
    b(%9.3f) ///
    se(%9.3f) ///
    stats(N F)


/*******************************************************************************
14. COMPACT FULL VERSUS MINIMUM-10 COMPARISON
*******************************************************************************/

use `results', clear


gen str20 sample_name = ""

replace sample_name = ///
    "Full sample" ///
    if sample == "full"

replace sample_name = ///
    "At least 10 students" ///
    if sample == "min10"


gen str28 spec_name = ""

replace spec_name = ///
    "Program + year FE" ///
    if spec == "py"

replace spec_name = ///
    "Program + field x year FE" ///
    if spec == "fy"

replace spec_name = ///
    "+ region x year FE" ///
    if spec == "ry"


gen str24 exposure_name = ""

replace exposure_name = ///
    "PSU bins" ///
    if exposure == "psu"

replace exposure_name = ///
    "PSU x region" ///
    if exposure == "psureg"

replace exposure_name = ///
    "PSU + region" ///
    if exposure == "psuaddreg"

replace exposure_name = ///
    "PSU x region x field" ///
    if exposure == "psuregfld"

replace exposure_name = ///
    "PSU + region + field" ///
    if exposure == "psuaddregfld"


sort ///
    spec ///
    exposure ///
    sample


format ///
    beta ///
    se ///
    wald_F ///
    %9.3f

format p ///
    %9.4f

format ///
    N ///
    programs ///
    %12.0fc


display ""
display "============================================================"
display " FULL VERSUS MINIMUM-10 SAMPLE"
display "============================================================"

list ///
    spec_name ///
    exposure_name ///
    sample_name ///
    beta ///
    se ///
    wald_F ///
    p ///
    N ///
    programs, ///
    sepby( ///
        spec_name ///
        exposure_name ///
    ) ///
    noobs clean


/*******************************************************************************
15. END
*******************************************************************************/

display ""
display "============================================================"
display " COSINE FIRST-STAGE ESTIMATIONS COMPLETED"
display "============================================================"