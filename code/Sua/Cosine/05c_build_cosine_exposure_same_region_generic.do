/*******************************************************************************
05c_build_cosine_exposure_same_region_generic.do

PURPOSE

Construct an alternative cosine-exposure measure restricting
incumbent-entrant comparisons to programs in the SAME:

    university/sede region × generic career area

COSINE VECTOR:
    PSU bins only

COMPARISON OF MARKET DEFINITIONS:

    1. Region × General field
    2. Region × CINE97 subarea
    3. Region × Generic career area   <-- this file

IMPORTANT

- The cosine vector is held fixed: PSU bins.
- Original entrant weights are unchanged.
- Entrant weights remain relative to ALL entrant programs.
- We DO NOT renormalize entrant weights within region × generic area.
- Entrant programs outside the incumbent's region × generic area
  contribute zero exposure.

YEAR:
    2011
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
1. PROGRAM REGION × GENERIC CAREER AREA, FIXED AT 2011
*******************************************************************************/

use "`sies_panel'", clear

keep if ao_proceso == 2011

keep ///
    codigo_unico ///
    id_region ///
    area_carrera_generica

drop if missing(codigo_unico)

isid codigo_unico


rename id_region ///
    region_2011

rename area_carrera_generica ///
    field_2011


/*
Programs without region or generic career area cannot be assigned
to a restricted market.
*/

count if missing(region_2011)

display ///
    "Programs missing 2011 region = " ///
    %9.0fc r(N)


count if ///
    missing(field_2011) | ///
    field_2011 == ""

display ///
    "Programs missing 2011 generic area = " ///
    %9.0fc r(N)


drop if missing(region_2011)

drop if ///
    missing(field_2011) | ///
    field_2011 == ""


tempfile program_market_2011

save `program_market_2011', replace


/*******************************************************************************
2. ATTACH REGION × GENERIC AREA TO EXISTING VECTORS
*******************************************************************************/

use "`vectors'", clear


merge m:1 codigo_unico ///
    using `program_market_2011', ///
    keep(master match) ///
    gen(_merge_market)


tabulate _merge_market, missing


/*
Keep programs with a valid region × generic-area market.
*/

keep if _merge_market == 3

drop _merge_market


isid ///
    codigo_unico ///
    geo_psu_cell


/*******************************************************************************
3. BUILD PSU-ONLY VECTORS
*
* Collapse the existing high-school-region × PSU vectors over
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


tempfile vectors_psu_rgen

save `vectors_psu_rgen', replace


/*******************************************************************************
4. PSU VECTOR NORMS
*******************************************************************************/

use `vectors_psu_rgen', clear


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
5. INCUMBENT PSU VECTORS
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
6. ENTRANT PSU VECTORS
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
7. INCUMBENT × ENTRANT PAIRS
*
* Restrict comparisons to:
*
*     same university region
*     ×
*     same generic career area
*
* The join also requires a common PSU cell for the dot product.
*******************************************************************************/

use `incumbent_psu', clear


joinby ///
    region_2011 ///
    field_2011 ///
    psu_bin_lower ///
    using `entrant_psu'


/*
Cell-level contribution to dot product.
*/

gen double dot_component = ///
    N_cell_incumbent * ///
    N_cell_entrant


/*
Collapse to incumbent-program × entrant-program.
*/

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


/*
Cosine similarity.
*/

gen double cosine_psu_same_rgen = ///
    dot_product / ///
    (norm_incumbent * norm_entrant)


assert inrange( ///
    cosine_psu_same_rgen, ///
    0, ///
    1.0000001 ///
)


replace cosine_psu_same_rgen = 1 ///
    if ///
        cosine_psu_same_rgen > 1 ///
        & ///
        cosine_psu_same_rgen < 1.0000001


/*
Pair diagnostics.
*/

count

display ///
    "Total incumbent-entrant pairs, generic area = " ///
    %9.0fc r(N)


tempfile pairs_psu_rgen

save `pairs_psu_rgen', replace


/*******************************************************************************
8. PREPARE ORIGINAL ENTRANT WEIGHTS
*
* IMPORTANT:
*
* We keep the ORIGINAL GLOBAL weights.
*
* The denominator includes all entrant-program enrollment.
*
* We do NOT renormalize weights inside
* region × generic career area.
*******************************************************************************/

use "`weights'", clear


keep ///
    entrant_id ///
    entrant_code_check ///
    entrant_university_check ///
    entrant_weight ///
    N_firstyear_total


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
9. ATTACH WEIGHTS AND AGGREGATE EXPOSURE
*******************************************************************************/

use `pairs_psu_rgen', clear


/*
Keep the pair data as the relevant universe.

Entrant programs in the global weights file that have no comparable
incumbent under region × generic area are deliberately not added.
*/

merge m:1 entrant_code ///
    using `entrant_weights', ///
    keep(master match) ///
    gen(_m_weight)


tabulate _m_weight, missing


/*
Every entrant appearing in an actual pair must have its original weight.
*/

assert _m_weight == 3

drop _m_weight


/*
Weighted contribution of each entrant program.
*/

gen double weighted_component_psu = ///
    entrant_weight * ///
    cosine_psu_same_rgen


/*
Program-level exposure.
*/

collapse ///
    (sum) exp_psu_rgen = ///
        weighted_component_psu ///
    (count) n_pair_psu_rgen = ///
        cosine_psu_same_rgen ///
    (firstnm) ///
        region_2011 ///
        field_2011 ///
        incumbent_university, ///
    by(incumbent_code)


tempfile exposure_psu_positive

save `exposure_psu_positive', replace


/*******************************************************************************
10. MASTER LIST OF INCUMBENT PROGRAMS
*
* Programs with no entrant in the same region × generic area
* receive exposure = 0 rather than being dropped.
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
Attach 2011 region × generic-area definition.
*/

merge 1:1 codigo_unico ///
    using `program_market_2011', ///
    keep(master match) ///
    gen(_merge_market_master)


tabulate _merge_market_master, missing


/*
Only incumbents whose 2011 market can be defined.
*/

keep if _merge_market_master == 3

drop _merge_market_master


rename codigo_unico ///
    incumbent_code


isid incumbent_code


/*******************************************************************************
11. MERGE GENERIC-AREA EXPOSURE
*******************************************************************************/

merge 1:1 incumbent_code ///
    using `exposure_psu_positive', ///
    keep(master match) ///
    gen(_merge_psu)


tabulate _merge_psu, missing


/*
No comparable entrant = zero exposure.
*/

replace exp_psu_rgen = 0 ///
    if _merge_psu == 1


replace n_pair_psu_rgen = 0 ///
    if _merge_psu == 1


drop _merge_psu


/*******************************************************************************
12. RAW EXPOSURE DIAGNOSTICS
*******************************************************************************/

count

display ///
    "Incumbent programs in final market sample = " ///
    %9.0fc r(N)


count if missing(exp_psu_rgen)

display ///
    "Missing PSU exposure = " ///
    %9.0fc r(N)


assert !missing(exp_psu_rgen)


count if exp_psu_rgen > 0

local N_positive = r(N)

display ///
    "Positive PSU generic-area exposure = " ///
    %9.0fc `N_positive'


count if exp_psu_rgen == 0

local N_zero = r(N)

display ///
    "Zero PSU generic-area exposure = " ///
    %9.0fc `N_zero'


count

local N_total = r(N)


local share_zero = ///
    100 * `N_zero' / `N_total'


display ///
    "Share zero exposure = " ///
    %6.2f `share_zero' "%"


summarize ///
    exp_psu_rgen, ///
    detail


summarize ///
    n_pair_psu_rgen, ///
    detail


/*******************************************************************************
13. STANDARDIZE ACROSS INCUMBENT PROGRAMS
*******************************************************************************/

summarize exp_psu_rgen


local mean_psu = r(mean)
local sd_psu   = r(sd)


display ///
    "Mean exp_psu_rgen = " ///
    %12.6f `mean_psu'


display ///
    "SD   exp_psu_rgen = " ///
    %12.6f `sd_psu'


assert `sd_psu' > 0


gen double z_exp_psu_rgen = ///
    (exp_psu_rgen - `mean_psu') / ///
    `sd_psu'


assert !missing(z_exp_psu_rgen)


summarize ///
    z_exp_psu_rgen, ///
    detail


/*******************************************************************************
14. TOP EXPOSED PROGRAMS
*******************************************************************************/

gsort -exp_psu_rgen


list ///
    sigla_universidad ///
    incumbent_code ///
    region_2011 ///
    field_2011 ///
    exp_psu_rgen ///
    z_exp_psu_rgen ///
    n_pair_psu_rgen ///
    in 1/40, ///
    noobs clean


/*******************************************************************************
15. FINALIZE AND SAVE
*******************************************************************************/

rename incumbent_code ///
    codigo_unico_2011


label variable exp_psu_rgen ///
    "Cosine exposure: PSU, same region x generic career area"


label variable z_exp_psu_rgen ///
    "Standardized cosine exposure: PSU, same region x generic career area"


label variable n_pair_psu_rgen ///
    "Entrant pairs: PSU, same region x generic career area"


order ///
    codigo_unico_2011 ///
    sigla_universidad ///
    region_2011 ///
    field_2011 ///
    exp_psu_rgen ///
    z_exp_psu_rgen ///
    n_pair_psu_rgen ///
    N_firstyear_total ///
    N_firstyear_geo_psu ///
    program_geo_psu_coverage


isid codigo_unico_2011


compress


save ///
    "$processed/cosine_exposure_incumbents_2011_same_region_generic.dta", ///
    replace


display ""
display ///
    "Saved: $processed/cosine_exposure_incumbents_2011_same_region_generic.dta"


/*******************************************************************************
16. FINAL SUMMARY
*******************************************************************************/

display ""
display "============================================================"
display " REGION x GENERIC CAREER AREA: FINAL SUMMARY"
display "============================================================"


count

display ///
    "Total incumbents = " ///
    %9.0fc r(N)


count if exp_psu_rgen > 0

display ///
    "Positive exposure = " ///
    %9.0fc r(N)


count if exp_psu_rgen == 0

display ///
    "Zero exposure = " ///
    %9.0fc r(N)


summarize ///
    exp_psu_rgen ///
    z_exp_psu_rgen ///
    n_pair_psu_rgen, ///
    detail