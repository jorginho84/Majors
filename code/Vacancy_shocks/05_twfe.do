/**********************************************************************
* 05_twfe.do
*
* Design III — two-way fixed effects on cumulative ROL exposure.
*
*   y_kt = b * cumE_kt + d * own_cumshock_kt
*          + mu_k + a_{f(k),t} + g_{r(k),t} + e_kt
*
* cumE is standardized by its SD in the estimation sample, so b is the
* effect of a one-SD increase in cumulative competitor seats (ROL-weighted,
* per own seat). SE clustered by program.
*
* Tables (output/vacancy_shocks/tables/, booktabs fragments):
*   vs_twfe_main.tex        four outcomes x {year FE; field-year, region-year FE + own shocks}
*   vs_twfe_shockdefs.tex   log enrollment, across the seven shock definitions
*   vs_twfe_similarity.tex  log enrollment, across similarity measures (incl. market benchmark)
*
* Input: $processed/vs_panel_exposure.dta
**********************************************************************/

do "code/config.do"

global vs_out "$output/vacancy_shocks"
cap mkdir "$vs_out/tables"

use "$processed/vs_panel_exposure.dta", clear
keep if est_sample
xtset pid ao_proceso

egen long fy = group(field ao_proceso)
egen long ry = group(region ao_proceso)

* standardize every cumulative exposure by its own SD
foreach v of varlist cumE_* {
    quietly summarize `v'
    gen double z_`v' = `v' / r(sd)
    local sd_`v' = r(sd)
}

label var lnN       "Log enrollment"
label var N_first   "Enrollment"
label var psu_first "Entrant PSU"
label var cutoff    "Cutoff"

estimates clear


/**********************************************************************
* 1. Main table
**********************************************************************/

local j = 0
foreach y in lnN N_first psu_first cutoff {
    local ++j
    rename z_cumE_rol_main exposure
    reghdfe `y' exposure, absorb(pid ao_proceso) cluster(pid)
    estadd local fe_fy "No"
    estadd local own "No"
    quietly summarize `y' if e(sample)
    estadd scalar ymean = r(mean)
    estimates store a`j'

    reghdfe `y' exposure own_cumshock, absorb(pid fy ry) cluster(pid)
    estadd local fe_fy "Yes"
    estadd local own "Yes"
    quietly summarize `y' if e(sample)
    estadd scalar ymean = r(mean)
    estimates store b`j'
    rename exposure z_cumE_rol_main
}

esttab a1 b1 a2 b2 a3 b3 a4 b4 using "$vs_out/tables/vs_twfe_main.tex", ///
    replace booktabs fragment nomtitles nonumbers ///
    keep(exposure own_cumshock) ///
    coeflabels(exposure "Cumulative ROL exposure (1 SD)" own_cumshock "Own vacancy shocks") ///
    b(%9.3f) se(%9.3f) star(* 0.10 ** 0.05 *** 0.01) ///
    stats(ymean fe_fy own N, ///
        labels("Mean of outcome" "Field \(\times\) year, region \(\times\) year FE" ///
               "Own-shock control" "Observations") ///
        fmt(%9.2f %s %s %9.0fc)) ///
    prehead("\begin{tabular}{l*{8}{c}}" "\toprule") ///
    posthead(" & \multicolumn{2}{c}{Log enrollment} & \multicolumn{2}{c}{Enrollment}" ///
             " & \multicolumn{2}{c}{Entrant PSU} & \multicolumn{2}{c}{Cutoff} \\" ///
             "\cmidrule(lr){2-3}\cmidrule(lr){4-5}\cmidrule(lr){6-7}\cmidrule(lr){8-9}" ///
             " & (1) & (2) & (3) & (4) & (5) & (6) & (7) & (8) \\" "\midrule") ///
    prefoot("\midrule") postfoot("\bottomrule" "\end{tabular}")

di as text "SD of cumulative ROL exposure (main): " as result %9.4f `sd_cumE_rol_main'


/**********************************************************************
* 2. Robustness to the shock definition (log enrollment)
**********************************************************************/

estimates clear
local cols
foreach t in main p90 p75 within nosud lev ind adm {
    rename z_cumE_rol_`t' exposure
    reghdfe lnN exposure own_cumshock, absorb(pid fy ry) cluster(pid)
    estimates store s_`t'
    local cols `cols' s_`t'
    rename exposure z_cumE_rol_`t'
}

esttab `cols' using "$vs_out/tables/vs_twfe_shockdefs.tex", ///
    replace booktabs fragment nomtitles nonumbers ///
    keep(exposure) coeflabels(exposure "Cumulative ROL exposure (1 SD)") ///
    b(%9.3f) se(%9.3f) star(* 0.10 ** 0.05 *** 0.01) ///
    stats(N, labels("Observations") fmt(%9.0fc)) ///
    prehead("\begin{tabular}{l*{8}{c}}" "\toprule") ///
    posthead(" & Main & Top 10\% & Top 25\% & Within-year & No sudden & Levels & INDICES & Admissions \\" ///
             " & (1) & (2) & (3) & (4) & (5) & (6) & (7) & (8) \\" "\midrule") ///
    prefoot("\midrule") postfoot("\bottomrule" "\end{tabular}")


/**********************************************************************
* 3. Robustness to the similarity measure (log enrollment)
**********************************************************************/

estimates clear
local cols
foreach s in rol adj top2 colist mkt {
    rename z_cumE_`s'_main exposure
    reghdfe lnN exposure own_cumshock, absorb(pid fy ry) cluster(pid)
    estimates store m_`s'
    local cols `cols' m_`s'
    rename exposure z_cumE_`s'_main
}

esttab `cols' using "$vs_out/tables/vs_twfe_similarity.tex", ///
    replace booktabs fragment nomtitles nonumbers ///
    keep(exposure) coeflabels(exposure "Cumulative exposure (1 SD)") ///
    b(%9.3f) se(%9.3f) star(* 0.10 ** 0.05 *** 0.01) ///
    stats(N, labels("Observations") fmt(%9.0fc)) ///
    prehead("\begin{tabular}{l*{5}{c}}" "\toprule") ///
    posthead(" & \multicolumn{4}{c}{Rank-order-list similarity} & Market \\" ///
             "\cmidrule(lr){2-5}" ///
             " & Inverse distance & Adjacent & Top two & Co-listing & Field \(\times\) region \\" ///
             " & (1) & (2) & (3) & (4) & (5) \\" "\midrule") ///
    prefoot("\midrule") postfoot("\bottomrule" "\end{tabular}")

di as result "Design III TWFE tables written."
