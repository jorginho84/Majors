/**********************************************************************
* 05_forecast_bias.do
*
* Program value-added (issue #9): forecast-bias test of the VA against
* the RD at each admission cutoff (Angrist, Hull, Pathak & Walters 2017,
* adapted to the DEMRE cutoffs).
*
* RD sample: applicant i at the cutoff of program-year c = (j, t) if
*   - j is oversubscribed (waiting list) with a first-round cutoff,
*   - i is eligible at j and no program ranked above j is feasible
*     (crossing j's cutoff changes the assignment),
*   - i has a feasible fallback k below j (the assignment below the
*     cutoff). Feasibility at k depends on the score smoothly, so this
*     condition does not jump at j's cutoff,
*   - |score - cutoff_j| <= $bandwidth.
*   Z = 1[score >= cutoff_j].
*
* Endogenous variable: D_i = v_{S_i}, VA of the assigned program. Under
* the DA, D jumps from v_k to v_j at the cutoff. Unbiased VA implies
*   Y_i = phi D_i + cutoff FE + slopes + e,  phi = 1
* with Z x 10 bins of the predicted jump as instruments (forecast
* coefficient, AHPW), the same phi in every bin (Hansen J) and both
* jointly (omnibus test). Just-identified with Z for reference: it only
* uses the mean jump, which is small (jumps go both ways).
* Placebo: covariate-predicted outcome instead of Y, phi = 0.
* Also on cutoffs where j and k have >= `nbig' students, where robust
* SEs fit the noise and EB shrinks correctly (see README).
*
* VA (version itt, inc_rank, main specification):
*   xfit      cross-fit: students split at random by mrun; RD
*             observations in one half use the VA from the other half
*             (no own-outcome overlap). EB within each half. Main.
*   xfit_raw  same, unshrunk
*   full      full-sample EB VA from 02 (own-outcome overlap)
*   full_raw  same, unshrunk
* Programs j and k must have >= `nmin' students in the identifying
* sample of every VA version (common sample across versions).
*
* Per-cutoff RD: local linear on each side, jump in Y (rho_c) and in D
* (pi_c); binned scatter of rho_c on pi_c against the 45-degree line.
*
* Inputs:  $processed/pva_students_2007_2016.dta,
*          pva_applications_2007_2016.dta, pva_program_va.dta (02)
* Output:  output/tables/pva_forecast_bias.csv, pva_forecast_bias.tex,
*          pva_forecast_bias_cutoffs.csv,
*          output/figures/ProgramVA/pva_forecast_bias_*.pdf
**********************************************************************/

clear all
set more off
do "code/config.do"
do "code/ProgramVA/00_va_helpers.do"

capture log close
log using "$logs/pva_05_forecast_bias.log", replace text

global fig "$output/figures/ProgramVA"
local gopt graphregion(color(white)) plotregion(color(white)) ///
    ylabel(, angle(0) nogrid labsize(small)) xlabel(, labsize(small))

* minimum students per program in the identifying sample (full sample;
* halved for the cross-fit VA)
local nmin 20
* minimum observations on each side for a per-cutoff RD
local nside 10
* both programs at the cutoff with at least `nbig' students (EB check)
local nbig 100
local versions xfit xfit_raw full full_raw

/**********************************************************************
* 1. Students: controls, predicted outcome, random halves
**********************************************************************/

use "$processed/pva_students_2007_2016.dta", clear
pva_controls
quietly reg inc_rank $X i.ao_proceso
predict double p_inc_rank, xb

* split by student, so the cohorts of a retaker stay in one half
set seed 20261026
bysort mrun (ao_proceso): gen double u = runiform() if _n == 1
bysort mrun (ao_proceso): replace u = u[1]
gen byte half = u >= 0.5
drop u
tempfile stud
save `stud'

/**********************************************************************
* 2. VA by half (cross-fit)
**********************************************************************/

forvalues h = 0/1 {
    use `stud', clear
    gen long S = S_itt
    gen long P = port_bin
    keep if !missing(S, P) & half == `h'
    id_sample n_feas
    capture frame drop fr
    frame put S, into(fr)
    frame fr {
        bysort S: gen long n_obs = _N
        bysort S: keep if _n == 1
        sort S
    }
    va_reg inc_rank, s(S) tag(h) frame(fr) absorb(P) controls
    frame fr {
        va_disp v_h se_h n_obs
        local s2 = r(sd_signal)^2
        di as result "half `h': programs " _N ", signal SD " %6.3f r(sd_signal) ///
            ", noise SD " %6.3f r(sd_noise)
        gen double eb_h = v_h * `s2' / (`s2' + se_h^2)
        rename (S v_h eb_h n_obs) (code_h v_raw`h' v_eb`h' n`h')
        keep code_h v_raw`h' v_eb`h' n`h'
        tempfile va`h'
        save `va`h''
    }
}

* program-level VA, all versions
use code_h n_obs v_inc_main v_inc_eb version using "$processed/pva_program_va.dta", clear
keep if version == "itt"
rename (v_inc_main v_inc_eb n_obs) (v_full_raw v_full nfull)
keep code_h v_full v_full_raw nfull
merge 1:1 code_h using `va0', nogen
merge 1:1 code_h using `va1', nogen
* common program sample: enough students in the full and in each half
gen byte ok = nfull >= `nmin' & n0 >= `nmin' / 2 & n1 >= `nmin' / 2 & ///
    !missing(v_full, v_raw0, v_raw1, nfull, n0, n1)
count if ok
local nprog = r(N)
di as result "Programs in the common VA sample: `nprog'"
corr v_eb0 v_eb1 v_full if ok
keep if ok
keep code_h v_full v_full_raw v_raw0 v_raw1 v_eb0 v_eb1 nfull
tempfile va
save `va'

/**********************************************************************
* 3. RD sample: applicants at the margin of an oversubscribed cutoff
**********************************************************************/

use mrun ao_proceso preferencia code_h eligible feasible score ///
    cutoff_regular has_waiting_list pref_feas ///
    using "$processed/pva_applications_2007_2016.dta", clear

* fallback: top-ranked feasible program below each ROL entry
gsort mrun ao_proceso -preferencia
by mrun ao_proceso: gen long k = .
by mrun ao_proceso: replace k = cond(feasible[_n-1] == 1, code_h[_n-1], k[_n-1]) if _n > 1

gen byte margin = missing(pref_feas) | pref_feas >= preferencia
gen double r = score - cutoff_regular
keep if has_waiting_list == 1 & eligible == 1 & margin == 1 & ///
    !missing(r, k) & abs(r) <= $bandwidth
gen byte Z = r >= -0.001
di as result _n "=== RD observations (before VA restrictions) ==="
count
tab ao_proceso Z

merge m:1 mrun ao_proceso using `stud', ///
    keepusing(S_itt inc_rank p_inc_rank half) keep(3) nogen
keep if !missing(inc_rank)

* VA of j, of the fallback k and of the assigned program
rename code_h j
foreach x in j k {
    rename `x' code_h
    merge m:1 code_h using `va', keep(1 3) gen(_m_`x')
    foreach v in v_full v_full_raw v_raw0 v_raw1 v_eb0 v_eb1 nfull {
        rename `v' `v'_`x'
    }
    rename code_h `x'
}
keep if _m_j == 3 & _m_k == 3
drop _m_j _m_k

* sharpness: the assignment is j above the cutoff and k below
gen byte s_is_j = S_itt == j
gen byte s_is_k = S_itt == k
gen byte s_none = missing(S_itt)
di as result _n "=== Assignment by side of the cutoff ==="
tabstat s_is_j s_is_k s_none, by(Z) stat(mean) format(%5.3f)

rename S_itt code_h
merge m:1 code_h using `va', keep(1 3) gen(_m_s)
foreach v in v_full v_full_raw v_raw0 v_raw1 v_eb0 v_eb1 nfull {
    rename `v' `v'_s
}
rename code_h S_itt
* the assigned program must have VA in the common sample (it is j or k
* in all but a few cases)
count if _m_s != 3
di as text "dropped, assigned program without VA: " r(N) " of " _N
keep if _m_s == 3
drop _m_s

* D and predicted jump by version; cross-fit: VA from the other half
foreach x in s j k {
    gen double xfit_`x'     = cond(half == 0, v_eb1_`x', v_eb0_`x')
    gen double xfit_raw_`x' = cond(half == 0, v_raw1_`x', v_raw0_`x')
    gen double full_`x'     = v_full_`x'
    gen double full_raw_`x' = v_full_raw_`x'
}
foreach ver of local versions {
    rename `ver'_s D_`ver'
    gen double dv_`ver' = `ver'_j - `ver'_k
}

* large programs: robust SEs fit their noise, so EB shrinks them right
gen byte big = min(nfull_j, nfull_k) >= `nbig'
egen long c = group(j ao_proceso)
egen long cz = group(c Z)
egen long ch = group(c half)

di as result _n "=== Final RD sample ==="
count
local N_rd = r(N)
distinct c mrun

compress
tempfile rd
save `rd'

/**********************************************************************
* 4. Stacked 2SLS: forecast coefficient, over-identification, placebo
**********************************************************************/

* Two forecast coefficients (AHPW 2017):
*   phi_z    just-identified, Z: ratio of the mean jumps in Y and D
*   phi_oid  Z x 10 bins of the cutoff-level predicted jump: uses the
*            variation across cutoffs (AHPW's forecast coefficient)
* Hansen J tests a common phi across bins; the omnibus test (AHPW)
* tests phi = 1 and over-identification jointly: the reduced form of
* Y - D on the 10 instruments is zero, chi2(10). Placebo: phi = 0.
* Samples: all cutoffs, and cutoffs where j and k have >= `nbig' students.
tempname pf
postfile `pf' str9 version str10 depvar str3 sample double(phi se_phi ///
    p_phi1 fs_jump fs_F rf_jump hansen_j hansen_p phi_oid se_oid ///
    omni_chi2 omni_p) long(N ncut) ///
    using "$processed/pva_forecast_bias.dta", replace

foreach smp in all big {
foreach ver of local versions {
    use `rd', clear
    if "`smp'" == "big" keep if big
    * levels differ between the two cross-fit halves (each VA is centred
    * on its own sample): cutoff x half FE
    local fe ch cz#c.r

    * bins of the cutoff-level predicted jump, for over-identification
    bysort c: egen double dvc = mean(dv_`ver')
    preserve
        bysort c: keep if _n == 1
        xtile bin = dvc, n(10)
        keep c bin
        tempfile bins
        save `bins'
    restore
    merge m:1 c using `bins', nogen
    forvalues b = 1/10 {
        gen byte Zb`b' = Z * (bin == `b')
    }

    foreach y in inc_rank p_inc_rank {
        local h1 = cond("`y'" == "inc_rank", 1, 0)
        quietly reghdfe D_`ver' Z, absorb(`fe') vce(cluster c)
        local fs = _b[Z]
        local fsF = (_b[Z] / _se[Z])^2
        quietly reghdfe `y' Z, absorb(`fe') vce(cluster c)
        local rf = _b[Z]

        quietly ivreghdfe `y' (D_`ver' = Z), absorb(`fe') cluster(c)
        local phi = _b[D_`ver']
        local se  = _se[D_`ver']
        local p1  = 2 * normal(-abs((`phi' - `h1') / `se'))
        local N   = e(N)
        quietly distinct c if e(sample)
        local nc  = r(ndistinct)

        quietly ivreghdfe `y' (D_`ver' = Zb1-Zb10), absorb(`fe') cluster(c)
        local po  = _b[D_`ver']
        local so  = _se[D_`ver']
        local hj  = e(j)
        local hp  = e(jp)

        * omnibus: Y - h1 * D on the instruments, all coefficients zero
        tempvar yt
        gen double `yt' = `y' - `h1' * D_`ver'
        quietly reghdfe `yt' Zb1-Zb10, absorb(`fe') vce(cluster c)
        quietly test Zb1 Zb2 Zb3 Zb4 Zb5 Zb6 Zb7 Zb8 Zb9 Zb10
        local oc = r(chi2)
        if missing(`oc') local oc = r(F) * r(df)
        local op = chi2tail(10, `oc')
        drop `yt'

        post `pf' ("`ver'") ("`y'") ("`smp'") (`phi') (`se') (`p1') (`fs') ///
            (`fsF') (`rf') (`hj') (`hp') (`po') (`so') (`oc') (`op') ///
            (`N') (`nc')
        di as result "`smp' `ver' `y': phi_z " %6.3f `phi' " (" %5.3f `se' ///
            "), phi_oid " %6.3f `po' " (" %5.3f `so' "), Hansen p " %5.3f `hp' ///
            ", omnibus p(phi = `h1') " %6.4f `op' ", FS jump " %6.3f `fs' ///
            ", N " `N' ", cutoffs " `nc'
    }
}
}
postclose `pf'

use "$processed/pva_forecast_bias.dta", clear
format phi se_phi p_phi1 fs_jump rf_jump phi_oid se_oid hansen_p omni_p %7.3f
format fs_F hansen_j omni_chi2 %9.1f
list, noobs sepby(sample version) abbrev(10)
export delimited using "$output/tables/pva_forecast_bias.csv", replace

* tex table for the deck
capture program drop fb_cell
program define fb_cell, rclass
    args stat ver dep smp
    quietly summarize `stat' if version == "`ver'" & depvar == "`dep'" & sample == "`smp'"
    local fmt = cond("`stat'" == "fs_F", "%9.0fc", ///
        cond(inlist("`stat'", "omni_p", "p_phi1", "hansen_p"), "%5.3f", "%5.2f"))
    local val : display `fmt' r(mean)
    if inlist("`stat'", "phi", "phi_oid") {
        local sv = cond("`stat'" == "phi", "se_phi", "se_oid")
        quietly summarize `sv' if version == "`ver'" & depvar == "`dep'" & sample == "`smp'"
        local val "`val' (`: display %4.2f r(mean)')"
    }
    return local val = strtrim("`val'")
end

file open tf using "$output/tables/pva_forecast_bias.tex", write replace
file write tf "\begin{tabular}{lcccc}" _n "\toprule" _n
file write tf " & \multicolumn{2}{c}{Cross-fit VA (other half)} & \multicolumn{2}{c}{Full-sample VA} \\" _n
file write tf "\cmidrule(lr){2-3}\cmidrule(lr){4-5}" _n
file write tf " & EB & Unshrunk & EB & Unshrunk \\" _n "\midrule" _n
foreach smp in all big {
    if "`smp'" == "all" file write tf "\multicolumn{5}{l}{\textit{All cutoffs}} \\" _n
    if "`smp'" == "big" file write tf "\midrule" _n ///
        "\multicolumn{5}{l}{\textit{$ j$ and $ k$ with `nbig'+ students}} \\" _n
    foreach row in phi_oid hansen_p omni_p phi p_phi1 fs_F placebo {
        local stat `row'
        local dep inc_rank
        if "`row'" == "placebo" {
            local stat phi_oid
            local dep p_inc_rank
        }
        if "`row'" == "phi_oid"  local lab "\$\hat\varphi\$, 10 instruments (AHPW)"
        if "`row'" == "hansen_p" local lab "\quad Over-id.\ p (Hansen J, 9 df)"
        if "`row'" == "omni_p"   local lab "\quad Omnibus p, \$\varphi = 1\$ and over-id.\ (10 df)"
        if "`row'" == "phi"      local lab "\$\hat\varphi\$, just-identified ($ Z$)"
        if "`row'" == "p_phi1"   local lab "\quad p, \$\varphi = 1\$"
        if "`row'" == "fs_F"     local lab "\quad First-stage F (cluster)"
        if "`row'" == "placebo"  local lab "Placebo: predicted outcome, \$\hat\varphi\$ (10 instr.)"
        file write tf "`lab'"
        foreach ver of local versions {
            fb_cell `stat' `ver' `dep' `smp'
            file write tf " & `r(val)'"
        }
        file write tf " \\" _n
    }
    quietly summarize N if depvar == "inc_rank" & sample == "`smp'"
    local Nf : display %12.0fc r(max)
    quietly summarize ncut if depvar == "inc_rank" & sample == "`smp'"
    local cf : display %9.0fc r(max)
    file write tf "\quad Observations / cutoffs & \multicolumn{4}{c}{`=strtrim("`Nf'")' / `=strtrim("`cf'")'} \\" _n
}
file write tf "\bottomrule" _n "\end{tabular}" _n
file close tf

/**********************************************************************
* 5. Per-cutoff RD: rho_c (jump in Y) and pi_c (jump in D)
*    local linear on each side (uniform kernel), intercepts at r = 0
**********************************************************************/

use `rd', clear
* remove the level difference between cross-fit halves before pooling
foreach ver of local versions {
    bysort half: egen double mD = mean(D_`ver')
    replace D_`ver' = D_`ver' - mD
    drop mD
}

* intercept at r = 0 and its variance, by cutoff x side
capture program drop side_fit
program define side_fit
    args y
    tempvar mr my sxx sxy e2 n b a
    bysort cz: egen double `mr' = mean(r)
    bysort cz: egen double `my' = mean(`y')
    bysort cz: egen double `sxx' = total((r - `mr')^2)
    bysort cz: egen double `sxy' = total((r - `mr') * (`y' - `my'))
    gen double `b' = `sxy' / `sxx'
    gen double a_`y' = `my' - `b' * `mr'
    bysort cz: egen double `e2' = total((`y' - a_`y' - `b' * r)^2)
    bysort cz: gen long `n' = _N
    gen double va_`y' = `e2' / (`n' - 2) * (1 / `n' + `mr'^2 / `sxx')
end

bysort cz: gen long nside = _N
bysort c: egen long nz = total(Z)
bysort c: gen long nc = _N
keep if nside >= `nside' & nz >= `nside' & nc - nz >= `nside'
side_fit inc_rank
foreach ver of local versions {
    side_fit D_`ver'
}
* cutoff counts as large if >= 80% of its observations have j and k large
* (some fallback is almost always small, so requiring all leaves none)
bysort c: egen double bigc = mean(big)
replace bigc = bigc >= 0.8
bysort cz: keep if _n == 1
keep c Z j ao_proceso bigc a_* va_* nside
reshape wide a_* va_* nside, i(c) j(Z)
gen double rho = a_inc_rank1 - a_inc_rank0
gen double v_rho = va_inc_rank1 + va_inc_rank0
foreach ver of local versions {
    gen double pi_`ver' = a_D_`ver'1 - a_D_`ver'0
}
gen long n_c = nside0 + nside1
rename bigc big
keep c j ao_proceso big rho v_rho pi_* n_c
di as result _n "=== Per-cutoff RDs: `nside'+ obs on each side ==="
count
local ncut = r(N)
summarize rho pi_*, detail
export delimited using "$output/tables/pva_forecast_bias_cutoffs.csv", replace

* precision-weighted slope of rho on pi; binned scatter (20 bins of pi)
gen double w = 1 / v_rho
foreach ver of local versions {
    quietly reg rho pi_`ver' [aw = w], robust
    local b : display %4.2f _b[pi_`ver']
    local s : display %4.2f _se[pi_`ver']
    di as result "`ver': slope of rho_c on pi_c " `b' " (" `s' ")"
    quietly reg rho pi_`ver' [aw = w] if big, robust
    di as result "`ver', j and k with `nbig'+ students: slope " ///
        %4.2f _b[pi_`ver'] " (" %4.2f _se[pi_`ver'] "), cutoffs " e(N)
    preserve
        xtile bin = pi_`ver' [aw = w], n(20)
        collapse (mean) rho pi_`ver' [aw = w], by(bin)
        twoway (scatter rho pi_`ver', mcolor(navy)) ///
               (lfit rho pi_`ver', lcolor(navy)) ///
               (function y = x, range(pi_`ver') lcolor(gs10) lpattern(dash)), ///
            legend(off) ///
            xtitle("Predicted jump: VA of j minus VA of the fallback (rank points)", size(small)) ///
            ytitle("RD estimate at the cutoff of j (rank points)", size(small)) ///
            note("`ncut' cutoffs with `nside'+ obs. on each side, 20 bins, precision weighted. Cutoff-level slope `b' (`s'); dashed: 45-degree line.", size(vsmall)) `gopt'
        graph export "$fig/pva_forecast_bias_`ver'.pdf", replace
    restore
}

log close
