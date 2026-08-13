/*******************************************************************************
05b_build_cosine_exposure_same_region_cine97.do

PURPOSE

Construct two alternative cosine-exposure measures restricting
incumbent-entrant comparisons to programs in the SAME:

    university/sede region × CINE97 subarea

Variants:

1. PSU-only cosine
       vector cells = PSU bins

2. Geo-PSU cosine
       vector cells = high-school region of origin × PSU bins

IMPORTANT

- Original cosine exposure is NOT modified.
- Entrant weights remain defined relative to ALL entrant programs.
- We do NOT renormalize entrant weights within region × CINE97.
- Entrants outside the incumbent's region × CINE97 contribute zero.

Year: 2011
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

local chars ///
    "$processed/cosine_program_characteristics_2011.dta"

local weights ///
    "$processed/cosine_entrant_weights_2011.dta"

local sies_panel ///
    "$processed/sua_exposure/sies_program_year_with_demre_2007_2016.dta"


/*******************************************************************************
1. PROGRAM REGION × CINE97, FIXED AT 2011
*******************************************************************************/

use "`sies_panel'", clear

keep if ao_proceso == 2011

keep ///
    codigo_unico ///
    id_region ///
    cine_f_13_subarea

drop if missing(codigo_unico)

isid codigo_unico


rename id_region region_2011
rename cine_f_13_subarea field_2011


/*
Programs without region or CINE97 cannot be assigned
to a restricted market.
*/

count if missing(region_2011)

display ///
    "Programs missing 2011 region = " ///
    %9.0fc r(N)


count if missing(field_2011) | field_2011 == ""

display ///
    "Programs missing 2011 CINE97 = " ///
    %9.0fc r(N)


drop if missing(region_2011)

drop if ///
    missing(field_2011) | ///
    field_2011 == ""


tempfile program_market_2011
save `program_market_2011', replace



/*******************************************************************************
2. ATTACH REGION × CINE97 TO EXISTING GEO × PSU VECTORS
*******************************************************************************/

use "`vectors'", clear


merge m:1 codigo_unico ///
    using `program_market_2011', ///
    keep(master match) ///
    gen(_merge_market)


tabulate _merge_market, missing


/*
Keep programs for which region × CINE97 can be defined.
*/

keep if _merge_market == 3

drop _merge_market


isid ///
    codigo_unico ///
    geo_psu_cell



/*******************************************************************************
3. SAVE GEO × PSU VECTORS WITH REGION × CINE97
*******************************************************************************/

tempfile vectors_geopsu_rcine

save `vectors_geopsu_rcine', replace



/*******************************************************************************
4. BUILD PSU-ONLY VECTORS
*
* Collapse the existing high-school-region × PSU vector over
* high-school region of origin.
*******************************************************************************/

collapse ///
    (sum) N_cell_psu = N_cell ///
    (firstnm) ///
        cod_inst ///
        sigla_universidad ///
        nomb_inst_roster ///
        entrant_2012 ///
        sua_incumbent ///
        N_firstyear_total ///
        N_firstyear_geo_psu ///
        program_geo_psu_coverage ///
        region_2011 ///
        field_2011, ///
    by( ///
        codigo_unico ///
        psu_bin_lower ///
        psu_bin_upper ///
    )


isid ///
    codigo_unico ///
    psu_bin_lower


label variable N_cell_psu ///
    "First-year students in PSU bin, 2011"


tempfile vectors_psu_rcine

save `vectors_psu_rcine', replace



/*******************************************************************************
5. PSU-ONLY COSINE WITHIN SAME REGION × CINE97
*******************************************************************************/

use `vectors_psu_rcine', clear


/*******************************************************************************
5.1 Vector norms
*******************************************************************************/

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
5.2 Incumbent vectors
*******************************************************************************/

preserve

    keep if entrant_2012 == 0


    keep ///
        codigo_unico ///
        sigla_universidad ///
        region_2011 ///
        field_2011 ///
        psu_bin_lower ///
        N_cell_psu ///
        vector_norm ///
        N_firstyear_total


    rename ///
        (codigo_unico ///
         sigla_universidad ///
         N_cell_psu ///
         vector_norm ///
         N_firstyear_total) ///
        (incumbent_code ///
         incumbent_university ///
         N_cell_incumbent ///
         norm_incumbent ///
         N_total_incumbent)


    tempfile incumbent_psu
    save `incumbent_psu', replace

restore



/*******************************************************************************
5.3 Entrant vectors
*******************************************************************************/

keep if entrant_2012 == 1


keep ///
    codigo_unico ///
    sigla_universidad ///
    region_2011 ///
    field_2011 ///
    psu_bin_lower ///
    N_cell_psu ///
    vector_norm ///
    N_firstyear_total


rename ///
    (codigo_unico ///
     sigla_universidad ///
     N_cell_psu ///
     vector_norm ///
     N_firstyear_total) ///
    (entrant_code ///
     entrant_university ///
     N_cell_entrant ///
     norm_entrant ///
     N_total_entrant)


tempfile entrant_psu

save `entrant_psu', replace



/*******************************************************************************
5.4 PAIR PROGRAMS ONLY WITHIN SAME REGION × CINE97
*
* Match common PSU cells.
*******************************************************************************/

use `incumbent_psu', clear


joinby ///
    region_2011 ///
    field_2011 ///
    psu_bin_lower ///
    using `entrant_psu'


gen double dot_component = ///
    N_cell_incumbent * ///
    N_cell_entrant


collapse ///
    (sum) dot_product = dot_component ///
    (firstnm) ///
        incumbent_university ///
        norm_incumbent ///
        N_total_incumbent ///
        entrant_university ///
        norm_entrant ///
        N_total_entrant ///
        region_2011 ///
        field_2011, ///
    by( ///
        incumbent_code ///
        entrant_code ///
    )


gen double cosine_psu_same_rcine = ///
    dot_product / ///
    (norm_incumbent * norm_entrant)


assert inrange( ///
    cosine_psu_same_rcine, ///
    0, ///
    1.0000001 ///
)


replace cosine_psu_same_rcine = 1 ///
    if ///
        cosine_psu_same_rcine > 1 ///
        & cosine_psu_same_rcine < 1.0000001


tempfile pairs_psu_rcine

save `pairs_psu_rcine', replace



/*******************************************************************************
6. GEO × PSU COSINE WITHIN SAME REGION × CINE97
*******************************************************************************/

use `vectors_geopsu_rcine', clear


/*******************************************************************************
6.1 Vector norms
*******************************************************************************/

gen double N_cell_sq = ///
    N_cell^2


bysort codigo_unico: ///
    egen double vector_sum_sq = ///
        total(N_cell_sq)


gen double vector_norm = ///
    sqrt(vector_sum_sq)


assert vector_norm > 0
assert !missing(vector_norm)



/*******************************************************************************
6.2 Incumbent vectors
*******************************************************************************/

preserve

    keep if entrant_2012 == 0


    keep ///
        codigo_unico ///
        sigla_universidad ///
        region_2011 ///
        field_2011 ///
        geo_psu_cell ///
        N_cell ///
        vector_norm ///
        N_firstyear_total


    rename ///
        (codigo_unico ///
         sigla_universidad ///
         N_cell ///
         vector_norm ///
         N_firstyear_total) ///
        (incumbent_code ///
         incumbent_university ///
         N_cell_incumbent ///
         norm_incumbent ///
         N_total_incumbent)


    tempfile incumbent_geopsu
    save `incumbent_geopsu', replace

restore



/*******************************************************************************
6.3 Entrant vectors
*******************************************************************************/

keep if entrant_2012 == 1


keep ///
    codigo_unico ///
    sigla_universidad ///
    region_2011 ///
    field_2011 ///
    geo_psu_cell ///
    N_cell ///
    vector_norm ///
    N_firstyear_total


rename ///
    (codigo_unico ///
     sigla_universidad ///
     N_cell ///
     vector_norm ///
     N_firstyear_total) ///
    (entrant_code ///
     entrant_university ///
     N_cell_entrant ///
     norm_entrant ///
     N_total_entrant)


tempfile entrant_geopsu

save `entrant_geopsu', replace



/*******************************************************************************
6.4 PAIR PROGRAMS ONLY WITHIN SAME REGION × CINE97
*
* Match common high-school-region × PSU cells.
*******************************************************************************/

use `incumbent_geopsu', clear


joinby ///
    region_2011 ///
    field_2011 ///
    geo_psu_cell ///
    using `entrant_geopsu'


gen double dot_component = ///
    N_cell_incumbent * ///
    N_cell_entrant


collapse ///
    (sum) dot_product = dot_component ///
    (firstnm) ///
        incumbent_university ///
        norm_incumbent ///
        N_total_incumbent ///
        entrant_university ///
        norm_entrant ///
        N_total_entrant ///
        region_2011 ///
        field_2011, ///
    by( ///
        incumbent_code ///
        entrant_code ///
    )


gen double cosine_geopsu_same_rcine = ///
    dot_product / ///
    (norm_incumbent * norm_entrant)


assert inrange( ///
    cosine_geopsu_same_rcine, ///
    0, ///
    1.0000001 ///
)


replace cosine_geopsu_same_rcine = 1 ///
    if ///
        cosine_geopsu_same_rcine > 1 ///
        & cosine_geopsu_same_rcine < 1.0000001


tempfile pairs_geopsu_rcine

save `pairs_geopsu_rcine', replace



/*******************************************************************************
7. PREPARE ORIGINAL ENTRANT WEIGHTS
*
* IMPORTANT:
*
* These weights remain relative to ALL entrant enrollment.
* They are NOT normalized within region × CINE97.
*******************************************************************************/

use "`weights'", clear


keep ///
    entrant_id ///
    entrant_code_check ///
    entrant_university_check ///
    entrant_weight ///
    N_firstyear_total


/*
Rename variables to the names used in pair-level datasets.
*/

rename entrant_code_check ///
    entrant_code


rename N_firstyear_total ///
    entrant_firstyear_total


isid entrant_code


summarize entrant_weight, detail


egen double weight_sum_check = ///
    total(entrant_weight)


display ///
    "Observed entrant weight represented = " ///
    %9.6f weight_sum_check[1]


drop weight_sum_check


tempfile entrant_weights

save `entrant_weights', replace


/*******************************************************************************
8. AGGREGATE PSU-ONLY EXPOSURE
*******************************************************************************/

use `pairs_psu_rcine', clear

merge m:1 entrant_code ///
    using `entrant_weights', ///
    keep(master match) ///
    gen(_m_weight)

assert _m_weight == 3

drop _m_weight


gen double weighted_component_psu = ///
    entrant_weight * ///
    cosine_psu_same_rcine


collapse ///
    (sum) exp_psu_rcine = ///
        weighted_component_psu ///
    (count) n_pair_psu_rcine = ///
        cosine_psu_same_rcine ///
    (firstnm) ///
        region_2011 ///
        field_2011 ///
        incumbent_university, ///
    by(incumbent_code)


tempfile exposure_psu_positive

save `exposure_psu_positive', replace

/*******************************************************************************
9. AGGREGATE GEO × PSU EXPOSURE
*******************************************************************************/

use `pairs_geopsu_rcine', clear


merge m:1 entrant_code ///
    using `entrant_weights', ///
    keep(master match) ///
    gen(_m_weight)

assert _m_weight == 3

drop _m_weight


gen double weighted_component_geopsu = ///
    entrant_weight * ///
    cosine_geopsu_same_rcine


collapse ///
    (sum) exp_geo_rcine = ///
        weighted_component_geopsu ///
    (count) n_pair_geo_rcine = ///
        cosine_geopsu_same_rcine ///
    (firstnm) ///
        region_2011 ///
        field_2011 ///
        incumbent_university, ///
    by(incumbent_code)


tempfile exposure_geopsu_positive

save `exposure_geopsu_positive', replace


/*******************************************************************************
10. MASTER LIST OF INCUMBENT PROGRAMS
*******************************************************************************/

use "`chars'", clear


keep if entrant_2012 == 0


keep ///
    codigo_unico ///
    sigla_universidad ///
    N_firstyear_total ///
    N_firstyear_geo_psu ///
    program_geo_psu_coverage


/*
Attach 2011 region × CINE97 using original codigo_unico.
*/

merge 1:1 codigo_unico ///
    using `program_market_2011', ///
    keep(master match) ///
    gen(_merge_market_master)


tabulate _merge_market_master, missing


/*
Only programs with a valid region × CINE97 market
can receive restricted exposure.
*/

keep if _merge_market_master == 3

drop _merge_market_master


rename codigo_unico ///
    incumbent_code


isid incumbent_code



/*******************************************************************************
11. MERGE BOTH RESTRICTED EXPOSURES
*******************************************************************************/

merge 1:1 incumbent_code ///
    using `exposure_psu_positive', ///
    keep(master match) ///
    gen(_merge_psu)


replace exp_psu_rcine = 0 ///
    if _merge_psu == 1


replace n_pair_psu_rcine = 0 ///
    if _merge_psu == 1


drop _merge_psu



merge 1:1 incumbent_code ///
    using `exposure_geopsu_positive', ///
    keep(master match) ///
    gen(_merge_geo)


replace exp_geo_rcine = 0 ///
    if _merge_geo == 1


replace n_pair_geo_rcine = 0 ///
    if _merge_geo == 1


drop _merge_geo



/*******************************************************************************
11.1 CHECK RAW EXPOSURES BEFORE STANDARDIZING
*******************************************************************************/

count

display ///
    "Incumbent programs in final market sample = " ///
    %9.0fc r(N)


count if missing(exp_psu_rcine)

display ///
    "Missing PSU exposure = " ///
    %9.0fc r(N)


count if missing(exp_geo_rcine)

display ///
    "Missing Geo-PSU exposure = " ///
    %9.0fc r(N)


assert !missing(exp_psu_rcine)
assert !missing(exp_geo_rcine)


summarize ///
    exp_psu_rcine, ///
    detail


summarize ///
    exp_geo_rcine, ///
    detail


count if exp_psu_rcine > 0

display ///
    "Positive PSU restricted exposure = " ///
    %9.0fc r(N)


count if exp_geo_rcine > 0

display ///
    "Positive Geo-PSU restricted exposure = " ///
    %9.0fc r(N)



/*******************************************************************************
12. STANDARDIZE ACROSS INCUMBENT PROGRAMS
*******************************************************************************/

/*
PSU-only restricted exposure.
*/

summarize exp_psu_rcine


local mean_psu = r(mean)
local sd_psu   = r(sd)


display ///
    "Mean exp_psu_rcine = " ///
    %12.6f `mean_psu'


display ///
    "SD   exp_psu_rcine = " ///
    %12.6f `sd_psu'


assert `sd_psu' > 0


gen double z_exp_psu_rcine = ///
    (exp_psu_rcine - `mean_psu') / ///
    `sd_psu'


assert !missing(z_exp_psu_rcine)



/*
Geo × PSU restricted exposure.
*/

summarize exp_geo_rcine


local mean_geo = r(mean)
local sd_geo   = r(sd)


display ///
    "Mean exp_geo_rcine = " ///
    %12.6f `mean_geo'


display ///
    "SD   exp_geo_rcine = " ///
    %12.6f `sd_geo'


assert `sd_geo' > 0


gen double z_exp_geo_rcine = ///
    (exp_geo_rcine - `mean_geo') / ///
    `sd_geo'


assert !missing(z_exp_geo_rcine)



/*
Check standardized variables.
*/

summarize ///
    z_exp_psu_rcine ///
    z_exp_geo_rcine



/*******************************************************************************
13. FINAL DIAGNOSTICS
*******************************************************************************/

summarize ///
    exp_psu_rcine ///
    z_exp_psu_rcine ///
    exp_geo_rcine ///
    z_exp_geo_rcine ///
    n_pair_psu_rcine ///
    n_pair_geo_rcine, ///
    detail


gsort -exp_psu_rcine


list ///
    sigla_universidad ///
    incumbent_code ///
    region_2011 ///
    field_2011 ///
    exp_psu_rcine ///
    exp_geo_rcine ///
    n_pair_psu_rcine ///
    n_pair_geo_rcine ///
    in 1/40, ///
    noobs clean



/*******************************************************************************
13.1 COMPARISON OF RESTRICTED EXPOSURES
*******************************************************************************/

display ///
    "===== REGION x CINE97 EXPOSURE COMPARISON ====="


/*
Correlation between the two restricted measures.
*/

pwcorr ///
    exp_psu_rcine ///
    exp_geo_rcine, ///
    sig


pwcorr ///
    z_exp_psu_rcine ///
    z_exp_geo_rcine, ///
    sig



/*
Zero-exposure comparison.
*/

gen byte zero_psu = ///
    exp_psu_rcine == 0


gen byte zero_geo = ///
    exp_geo_rcine == 0


tab ///
    zero_psu ///
    zero_geo, ///
    missing



/*
Difference between measures.
*/

gen double dif_exp_rcine = ///
    exp_psu_rcine - ///
    exp_geo_rcine


summarize ///
    dif_exp_rcine, ///
    detail



/*
Programs with largest disagreement.
*/

gen double abs_dif_rcine = ///
    abs(dif_exp_rcine)


gsort -abs_dif_rcine


list ///
    sigla_universidad ///
    incumbent_code ///
    region_2011 ///
    field_2011 ///
    exp_psu_rcine ///
    exp_geo_rcine ///
    abs_dif_rcine ///
    n_pair_psu_rcine ///
    n_pair_geo_rcine ///
    in 1/20, ///
    noobs clean


drop ///
    zero_psu ///
    zero_geo ///
    dif_exp_rcine ///
    abs_dif_rcine



/*******************************************************************************
14. FINALIZE AND SAVE
*******************************************************************************/

rename incumbent_code ///
    codigo_unico_2011


label variable exp_psu_rcine ///
    "Cosine exposure: PSU, same region x CINE97"

label variable z_exp_psu_rcine ///
    "Standardized cosine exposure: PSU, same region x CINE97"

label variable exp_geo_rcine ///
    "Cosine exposure: school region x PSU, same region x CINE97"

label variable z_exp_geo_rcine ///
    "Standardized cosine exposure: school region x PSU, same region x CINE97"

label variable n_pair_psu_rcine ///
    "Entrant pairs: PSU, same region x CINE97"

label variable n_pair_geo_rcine ///
    "Entrant pairs: Geo-PSU, same region x CINE97"


order ///
    codigo_unico_2011 ///
    sigla_universidad ///
    region_2011 ///
    field_2011 ///
    exp_psu_rcine ///
    z_exp_psu_rcine ///
    exp_geo_rcine ///
    z_exp_geo_rcine ///
    n_pair_psu_rcine ///
    n_pair_geo_rcine ///
    N_firstyear_total ///
    N_firstyear_geo_psu ///
    program_geo_psu_coverage


isid codigo_unico_2011


compress


save ///
    "$processed/cosine_exposure_incumbents_2011_same_region_cine97.dta", ///
    replace


display ///
    "Saved: $processed/cosine_exposure_incumbents_2011_same_region_cine97.dta"