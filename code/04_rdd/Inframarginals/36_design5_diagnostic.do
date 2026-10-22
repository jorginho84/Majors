/**********************************************************************
* 36_design5_diagnostic.do
*
* Design V (issue #8), step 1: diagnostics before estimation.
*   (a) how many inframarginal applications per student-year, and their
*       status (admitted vs. waitlisted), to choose the one-row rule
*   (b) retakers: students inframarginal in more than one year
*   (c) outcome coverage
*   (d) ROL sparsity under each ROL definition: singletons, and the share
*       of students whose ROL group spans >= 2 years of the same program
*       (the only variation in Z left once program and ROL FE are in)
*   (e) variation in Z left after the FE, and the first stage
*       n_pt = a Z_pt + FE, clustered by program-year
*
* Input: $processed/design5_individual_2007_2016.dta (02_build/16)
* Output: output/inframarginal/tables/im_d5_rol_sparsity.tex
**********************************************************************/

clear all
set more off
do "code/config.do"

* 8-year outcomes are observed for cohorts <= last titulados year - 8
use grad_year using "$processed/check_06b_titulados_all.dta", clear
quietly summarize grad_year
local last_cohort = r(max) - 8
di as result "8-year outcomes valid for cohorts <= `last_cohort'"

use "$processed/design5_individual_2007_2016.dta", clear

di as text _n "== Merge coverage =="
tab _m_rol
tab _m_panel
keep if _m_panel == 3 & ao_proceso <= `last_cohort'

/**********************************************************************
* (a) applications per student-year and status
**********************************************************************/

di as text _n "== (a) Inframarginal applications: status and multiplicity =="
count
quietly egen tag_it = tag(mrun ao_proceso)
count if tag_it
tab estado_preferencia, missing
tab n_infra_it if tag_it
tab estado_preferencia pick_toppref, missing
di as text "Student-years with no admitted infra application:"
bysort mrun ao_proceso: egen byte any_admit = max(pick_admit)
tab any_admit if tag_it
di as text "Does the most preferred infra application coincide with the admitted one?"
tab pick_admit if pick_toppref & any_admit

/**********************************************************************
* (b) retakers
**********************************************************************/

di as text _n "== (b) Years in which each student is inframarginal =="
quietly egen tag_i = tag(mrun)
bysort mrun ao_proceso: gen byte f_y = _n == 1
bysort mrun: egen byte n_years_i = total(f_y)
drop f_y
tab n_years_i if tag_i

/**********************************************************************
* (c) outcomes
**********************************************************************/

di as text _n "== (c) Outcomes, all inframarginal applications =="
tabstat graduates_enrolled_program_8y graduates_uni_8y graduates_he_8y ///
    graduates_target_8y enrolls_target, ///
    statistics(n mean) columns(statistics) format(%9.3f)
tabstat graduates_enrolled_program_8y graduates_target_8y, ///
    by(enrolls_target) statistics(n mean) format(%9.3f)
tabstat psu_lm nem female priv mun n_apps, ///
    statistics(n mean sd) columns(statistics) format(%9.2f)

/**********************************************************************
* One row per student: main rule = most preferred infra application in the
* first year the student is inframarginal. Alternative = admitted program.
**********************************************************************/

gen byte S_main  = pick_toppref & ao_proceso == first_year_i
gen byte S_admit = pick_admit   & ao_proceso == first_year_i
foreach S in S_main S_admit {
    di as text _n "== Sample `S' =="
    count if `S'
    capture noisily isid mrun if `S'
}

keep if S_main
egen long pt = group(program_id_rank_analysis ao_proceso)
egen long programs = group(program_id_rank_analysis)
quietly count
local N = r(N)
di as result "Main sample: `N' students, " _continue
quietly tab programs
di as result r(r) " programs, " _continue
quietly tab pt
di as result r(r) " program-years"

/**********************************************************************
* (d) ROL sparsity
**********************************************************************/

di as text _n "== (d) ROL sparsity =="
di as text %-10s "ROL" %12s "groups" %12s "singleton%" %14s ">=2 years%" ///
    %18s ">=2 yrs same p%" %12s "mean size"
foreach r in exact set top3 top2 top1u univ top1 {
    quietly {
        bysort rol_`r': gen long sz = _N
        bysort rol_`r' ao_proceso: gen byte f1 = _n == 1
        bysort rol_`r': egen int ny = total(f1)
        bysort rol_`r' program_id_rank_analysis ao_proceso: gen byte f2 = _n == 1
        bysort rol_`r' program_id_rank_analysis: egen int nyp = total(f2)
        drop f1 f2
        egen tg = tag(rol_`r')
        count if tg
        local G = r(N)
        count if sz == 1
        local s1 = 100 * r(N) / `N'
        count if ny >= 2
        local s2 = 100 * r(N) / `N'
        count if nyp >= 2
        local s3 = 100 * r(N) / `N'
        local ms = `N' / `G'
        drop sz ny nyp tg
    }
    local G_`r'  = `G'
    local s1_`r' = `s1'
    local s2_`r' = `s2'
    local s3_`r' = `s3'
    local ms_`r' = `ms'
    di as text %-10s "`r'" %12.0fc `G' %12.1f `s1' %14.1f `s2' %18.1f `s3' %12.1f `ms'
}

* table for the deck
global im_out "$output/inframarginal"
cap mkdir "$im_out"
cap mkdir "$im_out/tables"
local rn_exact "Exact ordered list"
local rn_set   "Unordered set of programs"
local rn_top3  "Top 3 preferences"
local rn_top1u "First preference + set of universities"
local rn_top2  "Top 2 preferences"
local rn_univ  "Set of universities"
local rn_top1  "First preference"
file open T using "$im_out/tables/im_d5_rol_sparsity.tex", write replace
file write T "\begin{tabular}{lrrrr}" _n "\toprule" _n
file write T "ROL definition & Groups & Singletons (\%) & Spans \(\geq\)2 years (\%) & Mean size \\" _n "\midrule" _n
foreach r in exact set top3 top1u top2 univ top1 {
    file write T "`rn_`r'' & " %9.0fc (`G_`r'') " & " %5.1f (`s1_`r'') " & " %5.1f (`s3_`r'') " & " %6.1f (`ms_`r'') " \\" _n
}
file write T "\bottomrule" _n "\end{tabular}" _n
file close T

/**********************************************************************
* (e) variation in Z left after the FE, and first stage
**********************************************************************/

di as text _n "== (e) Residual variation in Z and first stage =="
quietly summarize Z_total_cupos
di as result "SD of Z (raw): " %8.2f r(sd)

foreach fe in "programs" "programs ao_proceso" {
    quietly reghdfe Z_total_cupos, absorb(`fe') resid(zr)
    quietly summarize zr
    di as result "SD of Z residual, absorb(`fe'): " %8.2f r(sd) "  N=" e(N)
    drop zr
    reghdfe N_total_enter Z_total_cupos, absorb(`fe') vce(cluster pt)
}

foreach r in exact set top3 top2 top1u univ top1 {
    foreach fe in "programs rol_`r'" "programs rol_`r' ao_proceso" {
        quietly reghdfe Z_total_cupos, absorb(`fe') resid(zr)
        quietly summarize zr if e(sample)
        local sdz = r(sd)
        quietly reghdfe N_total_enter Z_total_cupos, absorb(`fe') vce(cluster pt)
        local t = _b[Z_total_cupos] / _se[Z_total_cupos]
        di as result "absorb(`fe'): N=" %9.0fc e(N) "  SD(Z resid)=" %6.2f `sdz' ///
            "  pi=" %6.3f _b[Z_total_cupos] "  se=" %6.3f _se[Z_total_cupos] ///
            "  F=" %8.1f `t'^2
        drop zr
    }
}

di as result "36_design5_diagnostic.do finished."
