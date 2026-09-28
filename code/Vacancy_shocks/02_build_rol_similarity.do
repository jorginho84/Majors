/**********************************************************************
* 02_build_rol_similarity.do
*
* Design III — rank-order-list (ROL) similarity between programs.
*
* Idea: program k faces competitive pressure from j when applicants who
* list k also list j, and list them close together.
*
* For applicant i with list L_i and ranks r (1 = top choice):
*
*   s_rol(k<-j)  = sum_i 1{j,k in L_i} / |r_j - r_k|   /   #{i : k in L_i}
*
* Directed on purpose: normalized by k's applicant pool, so a large j
* can press on a small k without the reverse holding.
*
* Variants (same denominator):
*   s_adj    only adjacent ranks, |r_j - r_k| = 1
*   s_top2   both programs in the applicant's top two choices
*   s_colist plain co-listing share, no distance weight
*
* Window: 2007-2009 lists, before the shocks used in estimation (2010+),
* so similarity is predetermined. Programs absent from 2007-2009 lists
* have no similarity; they cannot be a treated k, and as a shock source j
* they contribute nothing to ROL exposure (see the market-based exposure
* in 03 for a measure that does not have this limitation).
*
* Input:   $processed/applications.dta
* Output:  $processed/vs_rol_similarity.dta   (one row per directed pair k,j)
**********************************************************************/

do "code/config.do"

local y0 = 2007
local y1 = 2009

capture program drop harmonize_code
program define harmonize_code
    syntax varname, Generate(name)
    tempvar s
    gen str12 `s' = strtrim(string(`varlist', "%12.0f"))
    gen long `generate' = `varlist'
    replace `generate' = real(substr(`s', 1, 2) + "0" + substr(`s', 3, 2)) ///
        if length(`s') == 4
end

tempfile lists den


/**********************************************************************
* 1. Lists: one row per applicant-year-program, consecutive ranks
**********************************************************************/

use mrun ao_proceso codigo_carrera preferencia ///
    using "$processed/applications.dta", clear
keep if inrange(ao_proceso, `y0', `y1')
drop if missing(mrun, codigo_carrera, preferencia)

harmonize_code codigo_carrera, generate(code_h)

* a program listed twice keeps its best rank
bys mrun ao_proceso code_h (preferencia): keep if _n == 1

* re-rank consecutively (reported preferences can have gaps)
bys mrun ao_proceso (preferencia): gen byte r = _n
bys mrun ao_proceso: gen byte L = _N

di as text "List length distribution, `y0'-`y1'"
tab L if r == 1

keep mrun ao_proceso code_h r
save `lists'

* denominator: number of lists containing k
gen byte one = 1
collapse (sum) n_list = one, by(code_h)
rename code_h k
label var n_list "Applicant lists containing k, `y0'-`y1'"
save `den'


/**********************************************************************
* 2. Directed pairs within each list
**********************************************************************/

use `lists', clear
rename (code_h r) (j rj)
tempfile jside
save `jside'

use `lists', clear
rename (code_h r) (k rk)
joinby mrun ao_proceso using `jside'
drop if k == j

gen byte d = abs(rk - rj)
gen double w_inv = 1 / d
gen byte   w_adj  = d == 1
gen byte   w_top2 = rk <= 2 & rj <= 2
gen byte   w_co   = 1

collapse (sum) w_inv w_adj w_top2 w_co, by(k j)

merge m:1 k using `den', keep(match) nogen

gen double s_rol    = w_inv  / n_list
gen double s_adj    = w_adj  / n_list
gen double s_top2   = w_top2 / n_list
gen double s_colist = w_co   / n_list

label var s_rol    "ROL similarity k<-j, inverse rank distance"
label var s_adj    "ROL similarity k<-j, adjacent ranks only"
label var s_top2   "ROL similarity k<-j, both in top two"
label var s_colist "Co-listing share k<-j"

drop w_*
compress
isid k j
save "$processed/vs_rol_similarity.dta", replace


/**********************************************************************
* 3. Descriptives of the measure
**********************************************************************/

di as text _n "Pairs with positive similarity: " _N
summarize s_rol s_adj s_top2 s_colist, detail

* how concentrated is each k's competitive neighborhood?
bys k: egen double tot = total(s_rol)
gen double sh = s_rol / tot
bys k (sh): gen double top1 = sh[_N]
bys k: gen byte first = _n == 1
bys k: gen int n_nbr = _N
di as text _n "Per-program: number of neighbors, total similarity, top-neighbor share"
summarize n_nbr tot top1 if first, detail

di as result "vs_rol_similarity.dta saved."
