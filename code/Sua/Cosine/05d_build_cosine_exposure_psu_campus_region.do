/*******************************************************************************
05d_build_cosine_exposure_psu_campus_region.do

PURPOSE

Construct five cosine-exposure measures using campus region and Broad field,
fixed in 2011:

    1. PSU only
    2. PSU x campus region
    3. PSU + campus region
    4. PSU x campus region x Broad field
    5. PSU + campus region + Broad field

The x measures require simultaneous coincidence in the indicated dimensions.
The + measures give equal weight to separately normalized components:

    PSU + region =
        [cosine(PSU) + same campus region] / 2

    PSU + region + field =
        [cosine(PSU) + same campus region + same Broad field] / 3

Entrant weights use the original global denominator and are not renormalized
by region or field.
*******************************************************************************/

clear all
set more off
set varabbrev off

do "code/config.do"


/*******************************************************************************
0. INPUTS
*******************************************************************************/

local vectors ///
    "$processed/program_geo_psu_vectors_2011.dta"

local weights ///
    "$processed/cosine_entrant_weights_2011.dta"

local panel ///
    "$processed/sua_exposure/sies_program_year_with_demre_2007_2016.dta"


/*******************************************************************************
1. CAMPUS REGION AND ACADEMIC FIELDS IN 2011
*******************************************************************************/

use "`panel'", clear

keep if ao_proceso == 2011

keep ///
    codigo_unico ///
    id_region ///
    area_conocimiento ///
    cine_f_13_subarea ///
    area_carrera_generica

drop if missing(codigo_unico)

isid codigo_unico

rename id_region ///
    region_2011

rename area_conocimiento ///
    field_general_2011

rename cine_f_13_subarea ///
    field_cine97_2011

rename area_carrera_generica ///
    field_generic_2011

drop if missing(region_2011)

tempfile program_chars_2011
save `program_chars_2011', replace


/******************************************************************************* 
2. CONSTRUCT PSU-ONLY PROGRAM VECTORS

The original vector contains school-region x PSU cells. Collapsing over school
region leaves each program's distribution across PSU bins.
*******************************************************************************/

use "`vectors'", clear

merge m:1 codigo_unico ///
    using `program_chars_2011', ///
    keep(match) ///
    nogen

collapse ///
    (sum) N_cell_psu = N_cell ///
    (firstnm) ///
        entrant_2012 ///
        sigla_universidad ///
        N_firstyear_total ///
        region_2011 ///
        field_general_2011 ///
        field_cine97_2011 ///
        field_generic_2011, ///
    by( ///
        codigo_unico ///
        psu_bin_lower ///
        psu_bin_upper ///
    )

isid codigo_unico psu_bin_lower

gen double N_cell_sq = ///
    N_cell_psu^2

bysort codigo_unico: ///
    egen double vector_sum_sq = ///
        total(N_cell_sq)

gen double vector_norm = ///
    sqrt(vector_sum_sq)

assert vector_norm > 0
assert !missing(vector_norm)


/*******************************************************************************
3. INCUMBENT AND ENTRANT PROGRAM LISTS
*******************************************************************************/

preserve

    keep if entrant_2012 == 0

    keep ///
        codigo_unico ///
        sigla_universidad ///
        region_2011 ///
        field_general_2011 ///
        field_cine97_2011 ///
        field_generic_2011 ///
        N_firstyear_total ///
        vector_norm

    duplicates drop

    rename ///
        (codigo_unico sigla_universidad region_2011 ///
         N_firstyear_total vector_norm) ///
        (incumbent_code incumbent_university incumbent_region ///
         incumbent_enrollment incumbent_norm)

    rename field_general_2011 ///
        incumbent_broad_field

    isid incumbent_code

    tempfile incumbent_programs
    save `incumbent_programs', replace

restore


preserve

    keep if entrant_2012 == 1

    keep ///
        codigo_unico ///
        sigla_universidad ///
        region_2011 ///
        field_general_2011 ///
        N_firstyear_total ///
        vector_norm

    duplicates drop

    rename ///
        (codigo_unico sigla_universidad region_2011 ///
         N_firstyear_total vector_norm) ///
        (entrant_code entrant_university entrant_region ///
         entrant_enrollment entrant_norm)

    rename field_general_2011 ///
        entrant_broad_field

    isid entrant_code

    tempfile entrant_programs
    save `entrant_programs', replace

restore


/*******************************************************************************
4. PSU COSINE FOR PAIRS WITH COMMON PSU CELLS
*******************************************************************************/

preserve

    keep if entrant_2012 == 0

    keep ///
        codigo_unico ///
        psu_bin_lower ///
        N_cell_psu ///
        vector_norm

    rename ///
        (codigo_unico N_cell_psu vector_norm) ///
        (incumbent_code N_cell_incumbent incumbent_norm)

    tempfile incumbent_vectors
    save `incumbent_vectors', replace

restore


keep if entrant_2012 == 1

keep ///
    codigo_unico ///
    psu_bin_lower ///
    N_cell_psu ///
    vector_norm

rename ///
    (codigo_unico N_cell_psu vector_norm) ///
    (entrant_code N_cell_entrant entrant_norm)

tempfile entrant_vectors
save `entrant_vectors', replace


use `incumbent_vectors', clear

joinby psu_bin_lower ///
    using `entrant_vectors'

gen double dot_component = ///
    N_cell_incumbent * ///
    N_cell_entrant

collapse ///
    (sum) dot_product = dot_component ///
    (firstnm) incumbent_norm entrant_norm, ///
    by(incumbent_code entrant_code)

gen double cosine_psu = ///
    dot_product / ///
    (incumbent_norm * entrant_norm)

assert inrange( ///
    cosine_psu, ///
    0, ///
    1.0000001 ///
)

replace cosine_psu = 1 ///
    if ///
        cosine_psu > 1 & ///
        cosine_psu < 1.0000001

keep ///
    incumbent_code ///
    entrant_code ///
    cosine_psu

isid incumbent_code entrant_code

tempfile psu_cosine_pairs
save `psu_cosine_pairs', replace


/*******************************************************************************
5. COMPLETE PAIR UNIVERSE AND FIVE SIMILARITIES

Pairs with no common PSU cell receive PSU cosine equal to zero. The full pair
universe is needed because the additive region and field components may still
be positive for those pairs.
*******************************************************************************/

use `incumbent_programs', clear

cross using `entrant_programs'

isid incumbent_code entrant_code

merge 1:1 ///
    incumbent_code ///
    entrant_code ///
    using `psu_cosine_pairs', ///
    keep(master match) ///
    gen(_merge_cosine)

replace cosine_psu = 0 ///
    if _merge_cosine == 1

drop _merge_cosine

assert !missing( ///
    incumbent_region, ///
    entrant_region, ///
    incumbent_broad_field, ///
    entrant_broad_field ///
)

gen byte same_campus_region = ///
    incumbent_region == entrant_region

gen byte same_broad_field = ///
    incumbent_broad_field == entrant_broad_field


/*
PSU x region.
*/

gen double cosine_psu_region = ///
    cosine_psu * ///
    same_campus_region


/*
PSU + region.
*/

gen double cosine_psu_plus_region = ///
    ( ///
        cosine_psu + ///
        same_campus_region ///
    ) / 2


/*
PSU x region x field.
*/

gen double cosine_psu_region_field = ///
    cosine_psu * ///
    same_campus_region * ///
    same_broad_field


/*
PSU + region + field.
*/

gen double cosine_psu_plus_region_field = ///
    ( ///
        cosine_psu + ///
        same_campus_region + ///
        same_broad_field ///
    ) / 3


foreach variable in ///
    cosine_psu ///
    cosine_psu_region ///
    cosine_psu_plus_region ///
    cosine_psu_region_field ///
    cosine_psu_plus_region_field {

    assert inrange( ///
        `variable', ///
        0, ///
        1.0000001 ///
    )
}


/*******************************************************************************
5.1 VERIFY THE FIVE PAIRWISE DEFINITIONS
*******************************************************************************/

assert inlist( ///
    same_campus_region, ///
    0, ///
    1 ///
)

assert inlist( ///
    same_broad_field, ///
    0, ///
    1 ///
)


/*
Reconstruct the four extensions independently.
*/

gen double check_psu_region = ///
    cosine_psu * ///
    same_campus_region

gen double check_psu_plus_region = ///
    ( ///
        cosine_psu + ///
        same_campus_region ///
    ) / 2

gen double check_psu_region_field = ///
    cosine_psu * ///
    same_campus_region * ///
    same_broad_field

gen double check_psu_plus_region_field = ///
    ( ///
        cosine_psu + ///
        same_campus_region + ///
        same_broad_field ///
    ) / 3


assert abs( ///
    cosine_psu_region - ///
    check_psu_region ///
) < 1e-12

assert abs( ///
    cosine_psu_plus_region - ///
    check_psu_plus_region ///
) < 1e-12

assert abs( ///
    cosine_psu_region_field - ///
    check_psu_region_field ///
) < 1e-12

assert abs( ///
    cosine_psu_plus_region_field - ///
    check_psu_plus_region_field ///
) < 1e-12


/*
Logical implications of the multiplicative definitions.
*/

assert cosine_psu_region == 0 ///
    if same_campus_region == 0

assert cosine_psu_region_field == 0 ///
    if ///
        same_campus_region == 0 | ///
        same_broad_field == 0


drop ///
    check_psu_region ///
    check_psu_plus_region ///
    check_psu_region_field ///
    check_psu_plus_region_field

display ""
display "============================================================"
display " ALL FIVE PAIRWISE SIMILARITY DEFINITIONS VERIFIED"
display "============================================================"


/*******************************************************************************
6. ATTACH GLOBAL ENTRANT WEIGHTS
*******************************************************************************/

preserve

    use "`weights'", clear

    keep ///
        entrant_code_check ///
        entrant_weight

    rename entrant_code_check ///
        entrant_code

    isid entrant_code

    tempfile entrant_weights
    save `entrant_weights', replace

restore


merge m:1 entrant_code ///
    using `entrant_weights', ///
    keep(master match) ///
    gen(_merge_weight)

assert _merge_weight == 3

drop _merge_weight


gen double component_psu = ///
    entrant_weight * ///
    cosine_psu

gen double component_psu_region = ///
    entrant_weight * ///
    cosine_psu_region

gen double component_psu_plus_region = ///
    entrant_weight * ///
    cosine_psu_plus_region

gen double component_psu_region_field = ///
    entrant_weight * ///
    cosine_psu_region_field

gen double component_psu_plus_region_field = ///
    entrant_weight * ///
    cosine_psu_plus_region_field


/*******************************************************************************
7. AGGREGATE TO THE INCUMBENT PROGRAM LEVEL
*******************************************************************************/

collapse ///
    (sum) ///
        exp_psu = component_psu ///
        exp_psu_region = component_psu_region ///
        exp_psu_plus_region = component_psu_plus_region ///
        exp_psu_region_field = component_psu_region_field ///
        exp_psu_plus_region_field = component_psu_plus_region_field ///
        n_same_region_pairs = same_campus_region ///
        n_same_field_pairs = same_broad_field ///
    (count) ///
        n_entrant_pairs = cosine_psu ///
    (firstnm) ///
        incumbent_university ///
        incumbent_region ///
        incumbent_enrollment ///
        incumbent_broad_field ///
        field_cine97_2011 ///
        field_generic_2011, ///
    by(incumbent_code)

isid incumbent_code

rename incumbent_broad_field ///
    field_general_2011

assert !missing( ///
    exp_psu, ///
    exp_psu_region, ///
    exp_psu_plus_region, ///
    exp_psu_region_field, ///
    exp_psu_plus_region_field ///
)

assert exp_psu_region <= ///
    exp_psu + 1e-12

assert exp_psu_region_field <= ///
    exp_psu_region + 1e-12


/*******************************************************************************
8. STANDARDIZE WITHOUT CHANGING THE ECONOMIC ZERO

The z_* variables are conventional mean-zero standardizations.

The sd_* variables divide only by the cross-program standard deviation.
Therefore, raw exposure equal to zero remains equal to zero. The first-stage
regressions use the sd_* measures.
*******************************************************************************/

foreach variable in ///
    exp_psu ///
    exp_psu_region ///
    exp_psu_plus_region ///
    exp_psu_region_field ///
    exp_psu_plus_region_field {

    quietly summarize `variable'

    local mean_`variable' = ///
        r(mean)

    local sd_`variable' = ///
        r(sd)

    assert `sd_`variable'' > 0

    gen double z_`variable' = ///
        ( ///
            `variable' - ///
            `mean_`variable'' ///
        ) / ///
        `sd_`variable''

    gen double sd_`variable' = ///
        `variable' / ///
        `sd_`variable''

    assert sd_`variable' == 0 ///
        if `variable' == 0
}


/*******************************************************************************
9. DIAGNOSTICS
*******************************************************************************/

display ""
display "============================================================"
display " COSINE EXPOSURES: PSU, CAMPUS REGION AND BROAD FIELD"
display "============================================================"

count

display ///
    "Incumbent programs = " ///
    %9.0fc r(N)

foreach variable in ///
    exp_psu ///
    exp_psu_region ///
    exp_psu_plus_region ///
    exp_psu_region_field ///
    exp_psu_plus_region_field {

    count if `variable' > 0

    display ///
        "Positive `variable' = " ///
        %9.0fc r(N)

    count if `variable' == 0

    display ///
        "Zero `variable'     = " ///
        %9.0fc r(N)

    summarize `variable', detail
}


pwcorr ///
    exp_psu ///
    exp_psu_region ///
    exp_psu_plus_region ///
    exp_psu_region_field ///
    exp_psu_plus_region_field, ///
    sig


/*******************************************************************************
9.1 DISTRIBUTIONS OF THE THREE MAIN MEASURES
*******************************************************************************/

count
local N_all = r(N)

count if exp_psu > 0
local N_pos_psu = r(N)

count if exp_psu_region > 0
local N_pos_psu_region = r(N)

count if exp_psu_plus_region > 0
local N_pos_psu_plus_region = r(N)


/*
PSU only: all programs.
*/

histogram exp_psu, ///
    percent ///
    start(0) ///
    width(0.025) ///
    xscale(range(0 0.73)) ///
    xlabel( ///
        0 0.15 0.30 0.45 0.60 0.72, ///
        format(%4.2f) ///
    ) ///
    xtitle("Cosine exposure") ///
    ytitle("Percent of programs") ///
    title("PSU only") ///
    subtitle("Zeros included; N = `N_all'") ///
    color(navy%65) ///
    lcolor(navy) ///
    graphregion(color(white)) ///
    plotregion(color(white)) ///
    name(hist_psu_all, replace)


/*
PSU x campus region: all programs.
*/

histogram exp_psu_region, ///
    percent ///
    start(0) ///
    width(0.025) ///
    xscale(range(0 0.73)) ///
    xlabel( ///
        0 0.15 0.30 0.45 0.60 0.72, ///
        format(%4.2f) ///
    ) ///
    xtitle("Cosine exposure") ///
    ytitle("Percent of programs") ///
    title("PSU x campus region") ///
    subtitle("Zeros included; N = `N_all'") ///
    color(navy%65) ///
    lcolor(navy) ///
    graphregion(color(white)) ///
    plotregion(color(white)) ///
    name(hist_psu_region_all, replace)


/*
PSU + campus region: all programs.
*/

histogram exp_psu_plus_region, ///
    percent ///
    start(0) ///
    width(0.025) ///
    xscale(range(0 0.73)) ///
    xlabel( ///
        0 0.15 0.30 0.45 0.60 0.72, ///
        format(%4.2f) ///
    ) ///
    xtitle("Cosine exposure") ///
    ytitle("Percent of programs") ///
    title("PSU + campus region") ///
    subtitle("Zeros included; N = `N_all'") ///
    color(navy%65) ///
    lcolor(navy) ///
    graphregion(color(white)) ///
    plotregion(color(white)) ///
    name(hist_psu_plus_region_all, replace)


/*
PSU only: positive exposure.
*/

histogram exp_psu ///
    if exp_psu > 0, ///
    percent ///
    start(0) ///
    width(0.025) ///
    xscale(range(0 0.73)) ///
    xlabel( ///
        0 0.15 0.30 0.45 0.60 0.72, ///
        format(%4.2f) ///
    ) ///
    xtitle("Cosine exposure") ///
    ytitle("Percent of exposed programs") ///
    title("PSU only") ///
    subtitle("Positive exposure; N = `N_pos_psu'") ///
    color(forest_green%65) ///
    lcolor(forest_green) ///
    graphregion(color(white)) ///
    plotregion(color(white)) ///
    name(hist_psu_positive, replace)


/*
PSU x campus region: positive exposure.
*/

histogram exp_psu_region ///
    if exp_psu_region > 0, ///
    percent ///
    start(0) ///
    width(0.025) ///
    xscale(range(0 0.73)) ///
    xlabel( ///
        0 0.15 0.30 0.45 0.60 0.72, ///
        format(%4.2f) ///
    ) ///
    xtitle("Cosine exposure") ///
    ytitle("Percent of exposed programs") ///
    title("PSU x campus region") ///
    subtitle("Positive exposure; N = `N_pos_psu_region'") ///
    color(forest_green%65) ///
    lcolor(forest_green) ///
    graphregion(color(white)) ///
    plotregion(color(white)) ///
    name(hist_psu_region_positive, replace)


/*
PSU + campus region: positive exposure.
*/

histogram exp_psu_plus_region ///
    if exp_psu_plus_region > 0, ///
    percent ///
    start(0) ///
    width(0.025) ///
    xscale(range(0 0.73)) ///
    xlabel( ///
        0 0.15 0.30 0.45 0.60 0.72, ///
        format(%4.2f) ///
    ) ///
    xtitle("Cosine exposure") ///
    ytitle("Percent of exposed programs") ///
    title("PSU + campus region") ///
    subtitle("Positive exposure; N = `N_pos_psu_plus_region'") ///
    color(forest_green%65) ///
    lcolor(forest_green) ///
    graphregion(color(white)) ///
    plotregion(color(white)) ///
    name(hist_psu_plus_region_positive, replace)


graph combine ///
    hist_psu_all ///
    hist_psu_region_all ///
    hist_psu_plus_region_all ///
    hist_psu_positive ///
    hist_psu_region_positive ///
    hist_psu_plus_region_positive, ///
    cols(3) ///
    imargin(tiny) ///
    graphregion(color(white)) ///
    title( ///
        "Distribution of cosine exposure measures", ///
        size(medsmall) ///
    ) ///
    subtitle( ///
        "One observation per incumbent program", ///
        size(small) ///
    ) ///
    note( ///
        "Top row includes zeros; bottom row conditions on positive exposure. Campus region is fixed in 2011.", ///
        size(vsmall) ///
    ) ///
    name(cosine_exposure_distributions, replace)


graph export ///
    "$output/cosine_exposure_distributions_psu_campus_region.png", ///
    replace ///
    width(2400)

capture noisily graph export ///
    "$output/cosine_exposure_distributions_psu_campus_region.pdf", ///
    replace

/*******************************************************************************
10. FINALIZE VARIABLE NAMES AND SAVE
*******************************************************************************/

/*
Program identifiers.
*/

rename incumbent_code ///
    codigo_unico_2011

rename incumbent_region ///
    region_2011


/*
Keep the original exposure names used by 06c and create shorter aliases
used by 06d.

The aliases contain exactly the same numerical values.
*/


/*
Raw exposure aliases.
*/

clonevar exp_psu_reg = ///
    exp_psu_region

clonevar exp_psu_addreg = ///
    exp_psu_plus_region

clonevar exp_psu_regfld = ///
    exp_psu_region_field

clonevar exp_psu_addregfld = ///
    exp_psu_plus_region_field


/*
SD-scaled exposure aliases.
*/

clonevar exp_psu_sd = ///
    sd_exp_psu

clonevar exp_psu_reg_sd = ///
    sd_exp_psu_region

clonevar exp_psu_addreg_sd = ///
    sd_exp_psu_plus_region

clonevar exp_psu_regfld_sd = ///
    sd_exp_psu_region_field

clonevar exp_psu_addregfld_sd = ///
    sd_exp_psu_plus_region_field


/*******************************************************************************
10.1 VERIFY THAT THE ALIASES ARE IDENTICAL
*******************************************************************************/

assert abs( ///
    exp_psu_reg - ///
    exp_psu_region ///
) < 1e-12

assert abs( ///
    exp_psu_addreg - ///
    exp_psu_plus_region ///
) < 1e-12

assert abs( ///
    exp_psu_regfld - ///
    exp_psu_region_field ///
) < 1e-12

assert abs( ///
    exp_psu_addregfld - ///
    exp_psu_plus_region_field ///
) < 1e-12


assert abs( ///
    exp_psu_sd - ///
    sd_exp_psu ///
) < 1e-12

assert abs( ///
    exp_psu_reg_sd - ///
    sd_exp_psu_region ///
) < 1e-12

assert abs( ///
    exp_psu_addreg_sd - ///
    sd_exp_psu_plus_region ///
) < 1e-12

assert abs( ///
    exp_psu_regfld_sd - ///
    sd_exp_psu_region_field ///
) < 1e-12

assert abs( ///
    exp_psu_addregfld_sd - ///
    sd_exp_psu_plus_region_field ///
) < 1e-12


/*******************************************************************************
10.2 LABEL ORIGINAL VARIABLES
*******************************************************************************/

label variable exp_psu ///
    "Cosine exposure: PSU bins"

label variable exp_psu_region ///
    "Cosine exposure: PSU bins x campus region"

label variable exp_psu_plus_region ///
    "Cosine exposure: equal-weight PSU plus campus region"

label variable exp_psu_region_field ///
    "Cosine exposure: PSU x campus region x Broad field"

label variable exp_psu_plus_region_field ///
    "Cosine exposure: equal-weight PSU plus region plus field"


label variable sd_exp_psu ///
    "PSU exposure in SD units; zero preserved"

label variable sd_exp_psu_region ///
    "PSU x region exposure in SD units; zero preserved"

label variable sd_exp_psu_plus_region ///
    "PSU plus region exposure in SD units; zero preserved"

label variable sd_exp_psu_region_field ///
    "PSU x region x field exposure in SD units; zero preserved"

label variable sd_exp_psu_plus_region_field ///
    "PSU plus region plus field exposure in SD units; zero preserved"


/*******************************************************************************
10.3 LABEL SHORT ALIASES
*******************************************************************************/

label variable exp_psu_reg ///
    "Alias: PSU x campus-region exposure"

label variable exp_psu_addreg ///
    "Alias: PSU plus campus-region exposure"

label variable exp_psu_regfld ///
    "Alias: PSU x region x field exposure"

label variable exp_psu_addregfld ///
    "Alias: PSU plus region plus field exposure"


label variable exp_psu_sd ///
    "Alias: PSU exposure in SD units"

label variable exp_psu_reg_sd ///
    "Alias: PSU x region exposure in SD units"

label variable exp_psu_addreg_sd ///
    "Alias: PSU plus region exposure in SD units"

label variable exp_psu_regfld_sd ///
    "Alias: PSU x region x field exposure in SD units"

label variable exp_psu_addregfld_sd ///
    "Alias: PSU plus region plus field exposure in SD units"


/*******************************************************************************
10.4 FINAL SUPPORT CHECKS
*******************************************************************************/

isid codigo_unico_2011

assert !missing( ///
    exp_psu, ///
    exp_psu_region, ///
    exp_psu_plus_region, ///
    exp_psu_region_field, ///
    exp_psu_plus_region_field ///
)

assert !missing( ///
    sd_exp_psu, ///
    sd_exp_psu_region, ///
    sd_exp_psu_plus_region, ///
    sd_exp_psu_region_field, ///
    sd_exp_psu_plus_region_field ///
)


/*
Economic zeros remain zero after division by the SD.
*/

assert sd_exp_psu == 0 ///
    if exp_psu == 0

assert sd_exp_psu_region == 0 ///
    if exp_psu_region == 0

assert sd_exp_psu_plus_region == 0 ///
    if exp_psu_plus_region == 0

assert sd_exp_psu_region_field == 0 ///
    if exp_psu_region_field == 0

assert sd_exp_psu_plus_region_field == 0 ///
    if exp_psu_plus_region_field == 0


/*
Logical ordering of multiplicative measures.
*/

assert exp_psu_region <= ///
    exp_psu + 1e-12

assert exp_psu_region_field <= ///
    exp_psu_region + 1e-12


/*******************************************************************************
10.5 ORDER AND SAVE
*******************************************************************************/

order ///
    codigo_unico_2011 ///
    incumbent_university ///
    region_2011 ///
    field_general_2011 ///
    field_cine97_2011 ///
    field_generic_2011 ///
    incumbent_enrollment ///
    exp_psu ///
    exp_psu_region ///
    exp_psu_plus_region ///
    exp_psu_region_field ///
    exp_psu_plus_region_field ///
    sd_exp_psu ///
    sd_exp_psu_region ///
    sd_exp_psu_plus_region ///
    sd_exp_psu_region_field ///
    sd_exp_psu_plus_region_field ///
    exp_psu_reg ///
    exp_psu_addreg ///
    exp_psu_regfld ///
    exp_psu_addregfld ///
    exp_psu_sd ///
    exp_psu_reg_sd ///
    exp_psu_addreg_sd ///
    exp_psu_regfld_sd ///
    exp_psu_addregfld_sd ///
    z_exp_psu ///
    z_exp_psu_region ///
    z_exp_psu_plus_region ///
    z_exp_psu_region_field ///
    z_exp_psu_plus_region_field ///
    n_entrant_pairs ///
    n_same_region_pairs ///
    n_same_field_pairs

compress

save ///
    "$processed/cosine_exposure_incumbents_2011_psu_campus_region.dta", ///
    replace

display ""
display "============================================================"
display " FINAL COSINE EXPOSURE FILE SAVED"
display " ORIGINAL NAMES AND SHORT ALIASES INCLUDED"
display "============================================================"

count

display ///
    "Incumbent programs = " ///
    %9.0fc r(N)

display ///
    "Saved: " ///
    "$processed/cosine_exposure_incumbents_2011_psu_campus_region.dta"