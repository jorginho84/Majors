/**********************************************************************
* 02_build_similarity.do
*
* Design III — pairwise similarity between incumbent k and source j,
* using the same measures as Design II (SUA entry).
*
* (A) Market kernels. Market m = field x campus region, for three field
*     definitions (broad, isced, generic). For j != k in the same market:
*       Total       w = 1
*       Triangular  w = max(0, 1 - |S_k - S_j| / 50)
*       Gaussian    w = exp(-0.5 (|S_k - S_j| / 50)^2)
*     S = mean entrant PSU (2007-2009; first three years for later programs).
*
* (B) Cosine similarity of first-year student PSU distributions
*     (25-point bins). Vectors use 2007-2009 entrants, or the first three
*     years with entrants for later programs. Each program has one campus
*     region and one broad field, so the interaction-cell cosines are
*       cos(PSU x R)     = cos(PSU) * 1{r_j = r_k}
*       cos(PSU x R x F) = cos(PSU) * 1{r_j = r_k, f_j = f_k}
*     and the additive ones are
*       cos(PSU + R)     = [cos(PSU) + 1{r_j = r_k}] / 2
*       cos(PSU + R + F) = [cos(PSU) + 1{r_j = r_k} + 1{f_j = f_k}] / 3
*
* Output: $processed/vs_similarity_pairs.dta  (k j, one row per ordered pair)
*         $processed/vs_markets.dta           (program -> market ids, T_m)
**********************************************************************/

do "code/config.do"

local h = 50

use "$processed/vs_program_year_2007_2016.dta", clear
bys pid: keep if _n == 1
keep code_h field isced_field generic_field region psu_S N_first_pre first_year_S entrant_2012
drop if missing(region)
tempfile progs
save `progs'


/**********************************************************************
* 1. Markets and pre-period market enrollment T_m
**********************************************************************/

foreach f in broad isced generic {
    local fv = cond("`f'" == "broad", "field", "`f'_field")
    egen long mkt_`f' = group(`fv' region) if `fv' != ""
    bys mkt_`f': egen double T_`f' = total(N_first_pre) if !missing(mkt_`f')
    label var mkt_`f' "Market: `f' field x region"
    label var T_`f'   "Market first-year enrollment, 2007-2009 (`f')"
}
keep code_h mkt_* T_*
save "$processed/vs_markets.dta", replace


/**********************************************************************
* 2. Cosine of PSU-bin vectors (Mata)
**********************************************************************/

use "$processed/vs_first_year_students.dta", clear
merge m:1 code_h using `progs', keepusing(first_year_S) keep(match) nogen
keep if ao_proceso <= max(2009, first_year_S + 2)
gen int bin = floor(psu_lm / 25)
contract code_h bin, freq(n)
reshape wide n, i(code_h) j(bin)
foreach v of varlist n* {
    replace `v' = 0 if missing(`v')
}
sort code_h
mata:
    V = st_data(., "n*")
    ids = st_data(., "code_h")
    V = V :/ sqrt(rowsum(V:^2))
    C = V * V'
    n = rows(C)
    K = J(n * n, 1, .)
    Jj = J(n * n, 1, .)
    S = J(n * n, 1, .)
    r = 0
    for (a = 1; a <= n; a++) {
        for (b = 1; b <= n; b++) {
            if (a == b) continue
            r++
            K[r] = ids[a]
            Jj[r] = ids[b]
            S[r] = C[a, b]
        }
    }
    K = K[1..r]; Jj = Jj[1..r]; S = S[1..r]
end
clear
getmata k = K j = Jj cos_psu = S, double
tempfile cos
save `cos'


/**********************************************************************
* 3. All ordered pairs with market kernels and cosine variants
**********************************************************************/

use `progs', clear
merge 1:1 code_h using "$processed/vs_markets.dta", nogen
rename * k_*
rename k_code_h k
tempfile K
save `K'
rename k_* j_*
rename k j
tempfile J
save `J'

use `cos', clear
merge m:1 k using `K', keep(match) nogen
merge m:1 j using `J', keep(match) nogen

gen double gap = abs(k_psu_S - j_psu_S)
gen double w_tri = max(0, 1 - gap / `h') if !missing(gap)
gen double w_gau = exp(-0.5 * (gap / `h')^2) if !missing(gap)

foreach f in broad isced generic {
    gen byte same_`f' = k_mkt_`f' == j_mkt_`f' & !missing(k_mkt_`f')
    gen double s_tot_`f' = same_`f'
    gen double s_tri_`f' = same_`f' * cond(missing(w_tri), 0, w_tri)
    gen double s_gau_`f' = same_`f' * cond(missing(w_gau), 0, w_gau)
}

gen byte same_r  = k_region == j_region
gen byte same_f  = k_field == j_field & k_field != ""
gen double cos_psuR   = cos_psu * same_r
gen double cos_psuRF  = cos_psu * same_r * same_f
gen double cos_psu_pR  = (cos_psu + same_r) / 2
gen double cos_psu_pRF = (cos_psu + same_r + same_f) / 3

keep k j s_* cos_*
compress
save "$processed/vs_similarity_pairs.dta", replace

di as text _n "Similarity pairs"
summarize s_* cos_*
