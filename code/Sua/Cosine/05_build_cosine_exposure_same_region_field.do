/*******************************************************************************
05_build_cosine_exposure_same_region_field.do

PURPOSE

Construct two alternative cosine-exposure measures restricting
incumbent-entrant comparisons to programs in the SAME:

    university/sede region × field of study

Variants:

1. PSU-only cosine
       vector cells = PSU bins

2. Geo-PSU cosine
       vector cells = high-school region of origin × PSU bins

IMPORTANT

- Original cosine exposure is NOT modified.
- Entrant weights remain defined relative to ALL entrant programs.
- We do NOT renormalize entrant weights within region × field.
- Entrants outside the incumbent's region × field contribute zero.

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
1. PROGRAM REGION × FIELD, FIXED AT 2011
*******************************************************************************/

use "`sies_panel'", clear

keep if ao_proceso == 2011

keep ///
    codigo_unico ///
    id_region ///
    area_conocimiento

drop if missing(codigo_unico)

isid codigo_unico


rename id_region region_2011
rename area_conocimiento field_2011


/*
Programs without region or field cannot be assigned to a restricted market.
*/

count if missing(region_2011)
display ///
    "Programs missing 2011 region = " ///
    %9.0fc r(N)

count if missing(field_2011) | field_2011 == ""
display ///
    "Programs missing 2011 field = " ///
    %9.0fc r(N)


drop if missing(region_2011)
drop if missing(field_2011) | field_2011 == ""


tempfile program_market_2011
save `program_market_2011', replace



/*******************************************************************************
2. ATTACH REGION × FIELD TO EXISTING GEO × PSU VECTORS
*******************************************************************************/

use "`vectors'", clear

merge m:1 codigo_unico ///
    using `program_market_2011', ///
    keep(master match) ///
    gen(_merge_market)

tabulate _merge_market, missing


/*
Keep programs for which region × field can be defined.
*/

keep if _merge_market == 3
drop _merge_market


isid codigo_unico geo_psu_cell



/*******************************************************************************
3. SAVE GEO × PSU VECTORS WITH REGION × FIELD
*******************************************************************************/

tempfile vectors_geopsu_rf
save `vectors_geopsu_rf', replace



/*******************************************************************************
4. BUILD PSU-ONLY VECTORS
*
* Collapse the existing region-of-origin × PSU vector over
* region of origin.
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


tempfile vectors_psu_rf
save `vectors_psu_rf', replace



/*******************************************************************************
5. PSU-ONLY COSINE WITHIN SAME REGION × FIELD
*******************************************************************************/

use `vectors_psu_rf', clear


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
5.4 Pair programs ONLY within same region × field,
*    and match common PSU cells.
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


gen double cosine_psu_same_rf = ///
    dot_product / ///
    (norm_incumbent * norm_entrant)


assert inrange( ///
    cosine_psu_same_rf, ///
    0, ///
    1.0000001 ///
)


replace cosine_psu_same_rf = 1 ///
    if ///
        cosine_psu_same_rf > 1 ///
        & cosine_psu_same_rf < 1.0000001


tempfile pairs_psu_rf
save `pairs_psu_rf', replace



/*******************************************************************************
6. GEO × PSU COSINE WITHIN SAME REGION × FIELD
*******************************************************************************/

use `vectors_geopsu_rf', clear


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
6.4 Pair programs ONLY within same region × field,
*    and match common high-school-region × PSU cells.
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


gen double cosine_geopsu_same_rf = ///
    dot_product / ///
    (norm_incumbent * norm_entrant)


assert inrange( ///
    cosine_geopsu_same_rf, ///
    0, ///
    1.0000001 ///
)


replace cosine_geopsu_same_rf = 1 ///
    if ///
        cosine_geopsu_same_rf > 1 ///
        & cosine_geopsu_same_rf < 1.0000001


tempfile pairs_geopsu_rf
save `pairs_geopsu_rf', replace



/*******************************************************************************
7. PREPARE ORIGINAL ENTRANT WEIGHTS
*
* IMPORTANT:
*
* These weights remain relative to ALL entrant enrollment.
* They are NOT normalized within region × field.
*******************************************************************************/

use "`weights'", clear


keep ///
    entrant_id ///
    entrant_code_check ///
    entrant_university_check ///
    entrant_weight ///
    N_firstyear_total


/*
Rename variables to the names used in the pair-level datasets.
*/

rename entrant_code_check entrant_code

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

use `pairs_psu_rf', clear

merge m:1 entrant_code ///
    using `entrant_weights', ///
    assert(match) ///
    nogen


gen double weighted_component_psu = ///
    entrant_weight * ///
    cosine_psu_same_rf


collapse ///
    (sum) cosine_exposure_psu_same_rf = ///
        weighted_component_psu ///
    (count) n_pairs_psu_same_rf = ///
        cosine_psu_same_rf ///
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

use `pairs_geopsu_rf', clear

merge m:1 entrant_code ///
    using `entrant_weights', ///
    assert(match) ///
    nogen


gen double weighted_component_geopsu = ///
    entrant_weight * ///
    cosine_geopsu_same_rf


collapse ///
    (sum) cosine_exposure_geopsu_same_rf = ///
        weighted_component_geopsu ///
    (count) n_pairs_geopsu_same_rf = ///
        cosine_geopsu_same_rf ///
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
Attach 2011 program region × field using the original
codigo_unico identifier.
*/

merge 1:1 codigo_unico ///
    using `program_market_2011', ///
    keep(master match) ///
    gen(_merge_market_master)

tabulate _merge_market_master, missing


/*
Only programs with a valid region × field market can receive
restricted exposure.
*/

keep if _merge_market_master == 3
drop _merge_market_master


/*
Now rename to the identifier used in the exposure datasets.
*/

rename codigo_unico incumbent_code


isid incumbent_code


/*******************************************************************************
11. MERGE BOTH RESTRICTED EXPOSURES
*******************************************************************************/

merge 1:1 incumbent_code ///
    using `exposure_psu_positive', ///
    keep(master match) ///
    gen(_merge_psu)

replace cosine_exposure_psu_same_rf = 0 ///
    if _merge_psu == 1

replace n_pairs_psu_same_rf = 0 ///
    if _merge_psu == 1

drop _merge_psu


merge 1:1 incumbent_code ///
    using `exposure_geopsu_positive', ///
    keep(master match) ///
    gen(_merge_geo)

replace cosine_exposure_geopsu_same_rf = 0 ///
    if _merge_geo == 1

replace n_pairs_geopsu_same_rf = 0 ///
    if _merge_geo == 1

drop _merge_geo


/*******************************************************************************
11.1 SHORT, VALID VARIABLE NAMES
*******************************************************************************/

rename cosine_exposure_psu_same_rf      exp_psu_rf
rename cosine_exposure_geopsu_same_rf   exp_geo_rf

rename n_pairs_psu_same_rf              n_pair_psu_rf
rename n_pairs_geopsu_same_rf           n_pair_geo_rf


/*******************************************************************************
11.2 CHECK RAW EXPOSURES BEFORE STANDARDIZING
*******************************************************************************/

count
display "Incumbent programs in final market sample = " %9.0fc r(N)

count if missing(exp_psu_rf)
display "Missing PSU exposure = " %9.0fc r(N)

count if missing(exp_geo_rf)
display "Missing Geo-PSU exposure = " %9.0fc r(N)

assert !missing(exp_psu_rf)
assert !missing(exp_geo_rf)


summarize exp_psu_rf, detail
summarize exp_geo_rf, detail


count if exp_psu_rf > 0
display ///
    "Positive PSU restricted exposure = " ///
    %9.0fc r(N)

count if exp_geo_rf > 0
display ///
    "Positive Geo-PSU restricted exposure = " ///
    %9.0fc r(N)


/*******************************************************************************
12. STANDARDIZE ACROSS INCUMBENT PROGRAMS
*******************************************************************************/

/*
PSU-only restricted exposure
*/

summarize exp_psu_rf

local mean_psu = r(mean)
local sd_psu   = r(sd)

display "Mean exp_psu_rf = " %12.6f `mean_psu'
display "SD   exp_psu_rf = " %12.6f `sd_psu'

assert `sd_psu' > 0

gen double z_exp_psu_rf = ///
    (exp_psu_rf - `mean_psu') / `sd_psu'

assert !missing(z_exp_psu_rf)


/*
Geo × PSU restricted exposure
*/

summarize exp_geo_rf

local mean_geo = r(mean)
local sd_geo   = r(sd)

display "Mean exp_geo_rf = " %12.6f `mean_geo'
display "SD   exp_geo_rf = " %12.6f `sd_geo'

assert `sd_geo' > 0

gen double z_exp_geo_rf = ///
    (exp_geo_rf - `mean_geo') / `sd_geo'

assert !missing(z_exp_geo_rf)


/*
Check standardized variables
*/

summarize ///
    z_exp_psu_rf ///
    z_exp_geo_rf


/*******************************************************************************
13. FINAL DIAGNOSTICS
*******************************************************************************/

summarize ///
    exp_psu_rf ///
    z_exp_psu_rf ///
    exp_geo_rf ///
    z_exp_geo_rf ///
    n_pair_psu_rf ///
    n_pair_geo_rf, ///
    detail


gsort -exp_psu_rf

list ///
    sigla_universidad ///
    incumbent_code ///
    region_2011 ///
    field_2011 ///
    exp_psu_rf ///
    exp_geo_rf ///
    n_pair_psu_rf ///
    n_pair_geo_rf ///
    in 1/40, ///
    noobs clean
	
/*******************************************************************************
13.1 COMPARISON OF RESTRICTED EXPOSURES
*******************************************************************************/

display "===== EXPOSURE COMPARISON ====="


/*
Correlation between the two restricted measures
*/

pwcorr ///
    exp_psu_rf ///
    exp_geo_rf, ///
    sig


pwcorr ///
    z_exp_psu_rf ///
    z_exp_geo_rf, ///
    sig


/*
Zero-exposure comparison
*/

gen byte zero_psu = ///
    exp_psu_rf == 0

gen byte zero_geo = ///
    exp_geo_rf == 0

tab zero_psu zero_geo, missing


/*
Absolute difference between measures
*/

gen double dif_exp_rf = ///
    exp_psu_rf - exp_geo_rf

summarize dif_exp_rf, detail


/*
Programs with largest disagreement
*/

gen double abs_dif_rf = ///
    abs(dif_exp_rf)

gsort -abs_dif_rf

list ///
    sigla_universidad ///
    incumbent_code ///
    region_2011 ///
    field_2011 ///
    exp_psu_rf ///
    exp_geo_rf ///
    abs_dif_rf ///
    n_pair_psu_rf ///
    n_pair_geo_rf ///
    in 1/20, ///
    noobs clean


drop ///
    zero_psu ///
    zero_geo ///
    dif_exp_rf ///
    abs_dif_rf	


/*******************************************************************************
14. FINALIZE AND SAVE
*******************************************************************************/

rename incumbent_code codigo_unico_2011


label variable exp_psu_rf ///
    "Cosine exposure: PSU, same region x field"

label variable z_exp_psu_rf ///
    "Standardized cosine exposure: PSU, same region x field"

label variable exp_geo_rf ///
    "Cosine exposure: school region x PSU, same region x field"

label variable z_exp_geo_rf ///
    "Standardized cosine exposure: school region x PSU, same region x field"

label variable n_pair_psu_rf ///
    "Entrant pairs: PSU, same region x field"

label variable n_pair_geo_rf ///
    "Entrant pairs: Geo-PSU, same region x field"


order ///
    codigo_unico_2011 ///
    sigla_universidad ///
    region_2011 ///
    field_2011 ///
    exp_psu_rf ///
    z_exp_psu_rf ///
    exp_geo_rf ///
    z_exp_geo_rf ///
    n_pair_psu_rf ///
    n_pair_geo_rf ///
    N_firstyear_total ///
    N_firstyear_geo_psu ///
    program_geo_psu_coverage


isid codigo_unico_2011

compress


save ///
    "$processed/cosine_exposure_incumbents_2011_same_region_field.dta", ///
    replace

display ///
    "Saved: $processed/cosine_exposure_incumbents_2011_same_region_field.dta"