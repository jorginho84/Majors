/**********************************************************************
* 30_selectivity_heterogeneity_population.do
*
* Design I, proposal item 5 (issue #4, approved 2026-10-06): heterogeneity
* by predetermined selectivity for different inframarginal populations.
*
* Populations (program x cohort graduation rate within 8 years):
*   all   all ranked applicants with lugar <= threshold (as in 21b);
*         non-enrollees count as non-graduates
*   enr   inframarginals enrolled in the program (enrolls_target == 1):
*         the students who actually receive the new classmates
*   top   enrolled, lugar <= threshold / 2   (top half of the infra ranks)
*   near  enrolled, threshold / 2 < lugar <= threshold (close to the margin)
* Restricting to enrollees conditions on take-up, which the shock can move:
* report "all" (intent) next to "enr" (exposed) rather than replacing it.
*
* Estimator as in 29: first differences, year FE, SE clustered by program,
* weight = mean inframarginal count of the population; dN instrumented by
* dZ. By quartile of 2007-09 entrant PSU, joint quartile model (equality
* test), continuous interaction dN x S~, and Q4 with university x year FE.
*
* Inputs: analysis_inframarginal_enrollmentthreshold_allapp_2007_2016.dta
*         and panels inframarginal_rank_panel_..._{first,min}_enroll.dta (21b),
*         vs_program_year_2007_2016.dta
* Output: output/inframarginal/tables/im_pop_{first,min}.tex
**********************************************************************/

clear all
set more off
do "code/config.do"

global im_out "$output/inframarginal"
cap mkdir "$im_out"
cap mkdir "$im_out/tables"

use grad_year using "$processed/check_06b_titulados_all.dta", clear
quietly summarize grad_year
local last_cohort = r(max) - 8

capture program drop stars
program define stars
    args p name
    c_local `name' = cond(`p' < 0.01, "\sym{***}", cond(`p' < 0.05, "\sym{**}", cond(`p' < 0.10, "\sym{*}", "")))
end

use code_h psu_S using "$processed/vs_program_year_2007_2016.dta", clear
bys code_h: keep if _n == 1
rename code_h codigo_carrera_harmonized
tempfile sel
save `sel'

foreach def in first_enroll min_enroll {

    local thr = cond("`def'" == "first_enroll", "threshold_first_enroll", "threshold_min_enroll")
    local inf = cond("`def'" == "first_enroll", "infra_first_enroll", "infra_min_enroll")
    local sfx = cond("`def'" == "first_enroll", "first", "min")

    /******************************************************************
    * 1. Population-specific outcome panels from the individual master
    ******************************************************************/
    use mrun ao_proceso program_id_rank_analysis codigo_carrera_harmonized sigla_universidad ///
        lugar `thr' `inf' enrolls_target graduates_enrolled_program_8y graduates_uni_8y ///
        using "$processed/analysis_inframarginal_enrollmentthreshold_allapp_2007_2016.dta", clear
    keep if `inf' == 1
    bys mrun program_id_rank_analysis ao_proceso: keep if _n == 1

    gen byte p_all  = 1
    gen byte p_enr  = enrolls_target == 1
    gen byte p_top  = p_enr & lugar <= `thr' / 2
    gen byte p_near = p_enr & lugar >  `thr' / 2

    tempfile pans
    local first = 1
    foreach p in all enr top near {
        preserve
        keep if p_`p'
        gen byte one = 1
        collapse (sum) n_`p' = one (mean) gp_`p' = graduates_enrolled_program_8y ///
            gu_`p' = graduates_uni_8y, by(program_id_rank_analysis ao_proceso)
        if !`first' merge 1:1 program_id_rank_analysis ao_proceso using `pans', nogen
        save `pans', replace
        local first = 0
        restore
    }

    di as text "`def': inframarginal students by population"
    tabstat p_all p_enr p_top p_near, statistics(sum) format(%12.0fc)

    /******************************************************************
    * 2. Merge with the 21b panel (N, Z), selectivity, differences
    ******************************************************************/
    use program_id_rank_analysis codigo_carrera_harmonized sigla_universidad ao_proceso ///
        N_total_enter Z_total_cupos D_N_total_enter D_Z_total_cupos sample_firststage ///
        using "$processed/inframarginal_rank_panel_enrollmentthreshold_allapp_2007_2016_`def'.dta", clear
    merge 1:1 program_id_rank_analysis ao_proceso using `pans', keep(master match) nogen
    merge m:1 codigo_carrera_harmonized using `sel', keep(master match) nogen
    xtset program_id_rank_analysis ao_proceso

    foreach p in all enr top near {
        foreach v in gp gu {
            replace `v'_`p' = 100 * `v'_`p'
            gen double D_`v'_`p' = D.`v'_`p' if ao_proceso <= `last_cohort'
        }
        gen double w_`p' = (n_`p' + L.n_`p') / 2
    }

    gen byte base = sample_firststage == 1 & !missing(psu_S) & ao_proceso <= `last_cohort'
    preserve
    keep if base
    bys program_id_rank_analysis: keep if _n == 1
    xtile Q = psu_S, nq(4)
    keep program_id_rank_analysis Q
    tempfile qq
    save `qq'
    restore
    merge m:1 program_id_rank_analysis using `qq', keep(master match) nogen
    quietly summarize psu_S if base
    gen double Sz = (psu_S - r(mean)) / r(sd)
    egen long univ = group(sigla_universidad)
    forvalues q = 1/4 {
        gen double dZq`q' = D_Z_total_cupos * (Q == `q')
        gen double dNq`q' = D_N_total_enter * (Q == `q')
    }
    gen double dZS = D_Z_total_cupos * Sz
    gen double dNS = D_N_total_enter * Sz

    /******************************************************************
    * 3. Estimation, by population and outcome
    ******************************************************************/
    foreach p in all enr top near {
        foreach v in gp gu {
            local c "base & !missing(D_`v'_`p', w_`p') & w_`p' > 0"
            local W "[aw = w_`p']"
            forvalues g = 0/4 {
                local cg = cond(`g' == 0, "`c'", "`c' & Q == `g'")
                quietly ivregress 2sls D_`v'_`p' i.ao_proceso (D_N_total_enter = D_Z_total_cupos) ///
                    `W' if `cg', vce(cluster program_id_rank_analysis)
                local b_`p'_`v'_`g' = _b[D_N_total_enter]
                local s_`p'_`v'_`g' = _se[D_N_total_enter]
                local pv_`p'_`v'_`g' = 2 * normal(-abs(_b[D_N_total_enter] / _se[D_N_total_enter]))
                if `g' == 0 local N_`p'_`v' = e(N)
            }
            quietly ivreghdfe D_`v'_`p' (dNq1 dNq2 dNq3 dNq4 = dZq1 dZq2 dZq3 dZq4) `W' if `c', ///
                absorb(i.ao_proceso#i.Q) cluster(program_id_rank_analysis)
            quietly test dNq1 = dNq2 = dNq3 = dNq4
            local eq_`p'_`v' = r(p)
            quietly ivreghdfe D_`v'_`p' (dNq1 dNq2 dNq3 dNq4 = dZq1 dZq2 dZq3 dZq4) `W' if `c', ///
                absorb(i.ao_proceso#i.Q i.univ#i.ao_proceso) cluster(program_id_rank_analysis)
            local u4_`p'_`v' = _b[dNq4]
            local u4s_`p'_`v' = _se[dNq4]
            local u4p_`p'_`v' = 2 * normal(-abs(_b[dNq4] / _se[dNq4]))
            quietly ivreghdfe D_`v'_`p' Sz (D_N_total_enter dNS = D_Z_total_cupos dZS) `W' if `c', ///
                absorb(ao_proceso) cluster(program_id_rank_analysis)
            local cS_`p'_`v' = _b[dNS]
            local cSs_`p'_`v' = _se[dNS]
            local cSp_`p'_`v' = 2 * normal(-abs(_b[dNS] / _se[dNS]))
            quietly summarize `v'_`p' if `c' [aw = n_`p']
            local m_`p'_`v' = r(mean)
        }
    }

    /******************************************************************
    * 4. Table: 2SLS, outcome in pct., so coefficients are pp per student
    ******************************************************************/
    file open T using "$im_out/tables/im_pop_`sfx'.tex", write replace
    file write T "\begin{tabular}{lcccccccc}" _n "\toprule" _n
    file write T "Population & Mean & Pooled & Q1 & Q2 & Q3 & Q4 & Q4, univ.\(\times\)year FE & \(\Delta N\times\tilde S\) \\" _n "\midrule" _n
    foreach v in gp gu {
        local vlab = cond("`v'" == "gp", "Graduation from the program, 8 years", "Graduation from any university, 8 years")
        file write T "\multicolumn{9}{l}{\textit{`vlab'}} \\" _n
        foreach p in all enr top near {
            local plab = cond("`p'" == "all", "All ranked inframarginals", cond("`p'" == "enr", "Enrolled in program", ///
                cond("`p'" == "top", "\quad Enrolled, top half of ranks", "\quad Enrolled, near threshold")))
            file write T "`plab' & " %5.1f (`m_`p'_`v'')
            forvalues g = 0/4 {
                stars `pv_`p'_`v'_`g'' s
                file write T " & " %7.3f (`b_`p'_`v'_`g'') "`s'"
            }
            stars `u4p_`p'_`v'' s4
            stars `cSp_`p'_`v'' s5
            file write T " & " %7.3f (`u4_`p'_`v'') "`s4'" ///
                " & " %7.3f (`cS_`p'_`v'') "`s5'" " \\" _n " & "
            forvalues g = 0/4 {
                file write T " & (" %6.3f (`s_`p'_`v'_`g'') ")"
            }
            file write T " & (" %6.3f (`u4s_`p'_`v'') ") & (" %6.3f (`cSs_`p'_`v'') ") \\" _n
        }
        file write T "\addlinespace" _n
    }
    file write T "\bottomrule" _n "\end{tabular}" _n
    file close T

    di as result "`def': population heterogeneity written."
}
