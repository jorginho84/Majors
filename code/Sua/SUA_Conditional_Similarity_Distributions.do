/*******************************************************************************
SUA_Conditional_Similarity_Distributions.do

PURPOSE

Graph the distribution of conditional similarity Q_p used in the
non-cosine SUA exposure decomposition.

We produce two figures:

    1. Zeros included
    2. Positive Q only

Q is defined as:

    q_tri = exp_tri50 / exp_unw
    q_gau = exp_gau50 / exp_unw

The sample is restricted to incumbent programs in exposed markets
(exp_unw > 0), because Q is only defined there.

One observation corresponds to one incumbent program.

INPUT

    $processed/sua_incumbent_panel_w_broad_area_region_2007_2016.dta

OUTPUT

    $output/sua_q_distributions_zero_included.png
    $output/sua_q_distributions_zero_included.pdf
    $output/sua_q_distributions_positive_only.png
    $output/sua_q_distributions_positive_only.pdf
*******************************************************************************/

clear all
set more off
set varabbrev off

do "code/config.do"


/*******************************************************************************
1. LOAD PANEL
*******************************************************************************/

use ///
    "$processed/sua_incumbent_panel_w_broad_area_region_2007_2016.dta", ///
    clear

keep if inrange(ao_proceso, 2007, 2016)

drop if missing( ///
    program_id, ///
    ao_proceso, ///
    exp_unw, ///
    exp_tri50, ///
    exp_gau50 ///
)

isid program_id ao_proceso


/*******************************************************************************
2. KEEP PROGRAMS WITH PRE AND POST OBSERVATIONS
*******************************************************************************/

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
3. VERIFY TIME-INVARIANT EXPOSURE MEASURES
*******************************************************************************/

foreach v in ///
    exp_unw ///
    exp_tri50 ///
    exp_gau50 {

    bysort program_id (ao_proceso): ///
        assert `v' == `v'[1]
}


/*******************************************************************************
4. CONSTRUCT Q
*******************************************************************************/

gen byte has_entry = ///
    exp_unw > 0

label variable has_entry ///
    "Program belongs to exposed market"


gen double q_tri = .

replace q_tri = ///
    exp_tri50 / exp_unw ///
    if has_entry == 1


gen double q_gau = .

replace q_gau = ///
    exp_gau50 / exp_unw ///
    if has_entry == 1


label variable q_tri ///
    "Triangular conditional similarity"

label variable q_gau ///
    "Gaussian conditional similarity"


/*******************************************************************************
5. VERIFY DECOMPOSITION
*******************************************************************************/

assert ///
    reldif(exp_tri50, exp_unw * q_tri) < 1e-8 ///
    if has_entry == 1

assert ///
    reldif(exp_gau50, exp_unw * q_gau) < 1e-8 ///
    if has_entry == 1


/*******************************************************************************
6. KEEP ONE OBSERVATION PER PROGRAM
*******************************************************************************/

bysort program_id (ao_proceso): ///
    keep if _n == 1

keep if has_entry == 1

isid program_id


/*******************************************************************************
7. CONVERT TO PERCENTAGE POINTS
*******************************************************************************/

gen double q_tri_pct = ///
    100 * q_tri

gen double q_gau_pct = ///
    100 * q_gau


/*******************************************************************************
8. QUICK DIAGNOSTICS
*******************************************************************************/

display ""
display "============================================================"
display " CONDITIONAL SIMILARITY Q: DIAGNOSTICS"
display "============================================================"

count
display ///
    "Programs in exposed markets = " ///
    %9.0fc r(N)

count if q_tri == 0
display ///
    "Programs with q_tri = 0     = " ///
    %9.0fc r(N)

count if q_gau == 0
display ///
    "Programs with q_gau = 0     = " ///
    %9.0fc r(N)

display ""
display "Triangular Q:"
summarize q_tri_pct, detail

display ""
display "Gaussian Q:"
summarize q_gau_pct, detail


/*******************************************************************************
9. HISTOGRAMS
*******************************************************************************/

/*
Top row: zeros included
Bottom row: positive Q only
Left column: triangular
Right column: gaussian
*/

histogram ///
    q_tri_pct, ///
    percent ///
    start(0) ///
    width(5) ///
    xscale(range(0 100)) ///
    xlabel(0(20)100, labsize(vsmall)) ///
    ylabel(, angle(horizontal) labsize(vsmall)) ///
    color(navy%65) ///
    lcolor(navy) ///
    title( ///
        "A. Triangular similarity", ///
        size(small) ///
    ) ///
    subtitle( ///
        "Zeros included", ///
        size(vsmall) ///
    ) ///
    xtitle( ///
        "Conditional similarity (percentage points)", ///
        size(vsmall) ///
    ) ///
    ytitle( ///
        "Percent of programs", ///
        size(vsmall) ///
    ) ///
    graphregion(color(white)) ///
    plotregion(color(white)) ///
    name(h_qtri0, replace)


histogram ///
    q_gau_pct, ///
    percent ///
    start(0) ///
    width(5) ///
    xscale(range(0 100)) ///
    xlabel(0(20)100, labsize(vsmall)) ///
    ylabel(, angle(horizontal) labsize(vsmall)) ///
    color(maroon%65) ///
    lcolor(maroon) ///
    title( ///
        "B. Gaussian similarity", ///
        size(small) ///
    ) ///
    subtitle( ///
        "Zeros included", ///
        size(vsmall) ///
    ) ///
    xtitle( ///
        "Conditional similarity (percentage points)", ///
        size(vsmall) ///
    ) ///
    ytitle( ///
        "Percent of programs", ///
        size(vsmall) ///
    ) ///
    graphregion(color(white)) ///
    plotregion(color(white)) ///
    name(h_qgau0, replace)


histogram ///
    q_tri_pct ///
    if q_tri_pct > 0, ///
    percent ///
    start(0) ///
    width(5) ///
    xscale(range(0 100)) ///
    xlabel(0(20)100, labsize(vsmall)) ///
    ylabel(, angle(horizontal) labsize(vsmall)) ///
    color(navy%65) ///
    lcolor(navy) ///
    title( ///
        "C. Triangular similarity", ///
        size(small) ///
    ) ///
    subtitle( ///
        "Positive Q only", ///
        size(vsmall) ///
    ) ///
    xtitle( ///
        "Conditional similarity (percentage points)", ///
        size(vsmall) ///
    ) ///
    ytitle( ///
        "Percent of programs", ///
        size(vsmall) ///
    ) ///
    graphregion(color(white)) ///
    plotregion(color(white)) ///
    name(h_qtri1, replace)


histogram ///
    q_gau_pct ///
    if q_gau_pct > 0, ///
    percent ///
    start(0) ///
    width(5) ///
    xscale(range(0 100)) ///
    xlabel(0(20)100, labsize(vsmall)) ///
    ylabel(, angle(horizontal) labsize(vsmall)) ///
    color(maroon%65) ///
    lcolor(maroon) ///
    title( ///
        "D. Gaussian similarity", ///
        size(small) ///
    ) ///
    subtitle( ///
        "Positive Q only", ///
        size(vsmall) ///
    ) ///
    xtitle( ///
        "Conditional similarity (percentage points)", ///
        size(vsmall) ///
    ) ///
    ytitle( ///
        "Percent of programs", ///
        size(vsmall) ///
    ) ///
    graphregion(color(white)) ///
    plotregion(color(white)) ///
    name(h_qgau1, replace)


/*******************************************************************************
10. COMBINE FOUR PANELS
*******************************************************************************/

graph combine ///
    h_qtri0 ///
    h_qgau0 ///
    h_qtri1 ///
    h_qgau1, ///
    rows(2) ///
    cols(2) ///
    imargin(2 2 2 2) ///
    title( ///
        "Distribution of conditional similarity measures", ///
        size(medium) ///
    ) ///
    subtitle( ///
        "One observation per incumbent program in exposed markets", ///
        size(small) ///
    ) ///
    note( ///
        "The upper row includes zeros; the lower row conditions on positive Q. " ///
        "The horizontal axis reports conditional similarity in percentage points and the vertical axis reports the share of programs.", ///
        size(vsmall) ///
    ) ///
    graphregion(color(white)) ///
    name(qdist_all, replace)


/*******************************************************************************
11. EXPORT
*******************************************************************************/

graph export ///
    "$output/sua_q_distributions_combined.png", ///
    replace ///
    width(2400)

graph export ///
    "$output/sua_q_distributions_combined.pdf", ///
    replace


/*******************************************************************************
12. DONE
*******************************************************************************/

display ""
display "============================================================"
display " Q DISTRIBUTION FIGURE SAVED"
display "============================================================"
display "$output/sua_q_distributions_combined.png"