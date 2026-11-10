/**********************************************************************
* 43_design5_by_va.do
*
* Design V by program value-added (issue #11; Step 0 = issue #9).
* Main Design V 2SLS estimated separately for programs of high and low
* VA, with VA groups defined as in Step 0:
*   EB VA on the income rank (v_inc_eb), itt version, programs with
*   >= 20 students in the identifying sample; groups cut by number of
*   programs (as the deciles in the Step 0 slides).
*   (i)  below / above the median   -> im_d5_va_median.tex
*   (ii) terciles                   -> im_d5_va_terciles.tex
*   (iii) quintiles                 -> im_d5_va_quintiles.tex
*   Argument: list of splits to run (med ter qui; default all), e.g.
*   do code/04_rdd/Inframarginals/43_design5_by_va.do qui
*
*   Panel A: program + year FE + ROL top1u (main of 37) + controls
*   Panel B: program + university x year FE + ROL top1u + controls (39b)
*   p (equal): Wald test of equal coefficients across groups in the
*   pooled model fully interacted with the group (FE, controls, instrument)
*   SE     : clustered by program-year
*
* Input : $processed/design5_individual_2007_2016.dta (02_build/16)
*         $processed/pva_program_va.dta (ProgramVA/02)
**********************************************************************/

local splits `0'
if "`splits'" == "" local splits "med ter qui"

clear all
set more off
do "code/config.do"

global im_out "$output/inframarginal"

use grad_year using "$processed/check_06b_titulados_all.dta", clear
quietly summarize grad_year
local last_cohort = r(max) - 8

capture program drop stars
program define stars
    args p name
    c_local `name' = cond(`p' < 0.01, "\sym{***}", cond(`p' < 0.05, "\sym{**}", cond(`p' < 0.10, "\sym{*}", "")))
end

**********************************************************************
* 1. VA classification (Step 0)
**********************************************************************

use code_h version n_obs v_inc_eb using "$processed/pva_program_va.dta", clear
keep if version == "itt" & !missing(v_inc_eb) & n_obs >= 20
isid code_h
xtile va_med = v_inc_eb, n(2)
xtile va_ter = v_inc_eb, n(3)
xtile va_qui = v_inc_eb, n(5)
di as result "Classified programs (Step 0, n >= 20): " _N
tabstat v_inc_eb, by(va_med) stat(n mean min max)
tabstat v_inc_eb, by(va_ter) stat(n mean min max)
tabstat v_inc_eb, by(va_qui) stat(n mean min max)
rename code_h codigo_carrera_harmonized
keep codigo_carrera_harmonized va_med va_ter va_qui v_inc_eb
tempfile va
save `va'

**********************************************************************
* 2. Design V sample (same as 37) merged to VA
**********************************************************************

use "$processed/design5_individual_2007_2016.dta", clear
keep if _m_panel == 3 & ao_proceso <= `last_cohort'
keep if pick_toppref & ao_proceso == first_year_i
duplicates drop mrun, force
isid mrun

merge m:1 codigo_carrera_harmonized using `va', keep(master match)
di as result "=== Coverage: Design V students in a VA-classified program ==="
tab _merge
egen long programs = group(program_id_rank_analysis)
egen byte tagp = tag(programs)
tab _merge if tagp
keep if _merge == 3
drop _merge tagp

* the VA group must be constant within the Design V program
bysort programs (va_ter): gen byte bad = va_ter[1] != va_ter[_N]
count if bad
di as result "Students in programs with more than one VA tercile: " r(N)
drop if bad
drop bad

egen long pt         = group(program_id_rank_analysis ao_proceso)
egen long uni_year   = group(sigla_universidad ao_proceso)

foreach v in program uni he {
    local src = cond("`v'" == "program", "graduates_enrolled_program_8y", "graduates_`v'_8y")
    gen double y_`v' = `src'
}

local ctrl ""
foreach v in psu_lm nem female priv mun {
    gen byte m_`v' = missing(`v')
    replace `v' = 0 if missing(`v')
    local ctrl "`ctrl' `v' m_`v'"
}

local feA "programs ao_proceso rol_top1u"
local feB "programs uni_year rol_top1u"
local fpA "programs grp#ao_proceso grp#rol_top1u"
local fpB "programs grp#uni_year grp#rol_top1u"

**********************************************************************
* 3. Estimates by group, and pooled test of equality
**********************************************************************

foreach s of local splits {
    local G = cond("`s'" == "med", 2, cond("`s'" == "ter", 3, 5))
    capture drop grp
    gen byte grp = va_`s'
    capture drop n_g* z_g* ci_*
    local nl ""
    local zl ""
    local ctrli ""
    forvalues g = 1/`G' {
        gen double n_g`g' = N_total_enter * (grp == `g')
        gen double z_g`g' = Z_total_cupos * (grp == `g')
        local nl "`nl' n_g`g'"
        local zl "`zl' z_g`g'"
        foreach v of local ctrl {
            gen double ci_`v'_`g' = `v' * (grp == `g')
            local ctrli "`ctrli' ci_`v'_`g'"
        }
    }
    local eqz ""
    local eqn ""
    forvalues g = 2/`G' {
        local eqz "`eqz' (z_g1 = z_g`g')"
        local eqn "`eqn' (n_g1 = n_g`g')"
    }

    foreach pa in A B {
        forvalues g = 1/`G' {
            local k "`s'`pa'`g'"
            quietly reghdfe N_total_enter Z_total_cupos `ctrl' if grp == `g', ///
                absorb(`fe`pa'') vce(cluster pt)
            local fs`k'   = _b[Z_total_cupos]
            local fsse`k' = _se[Z_total_cupos]
            local fsp`k'  = 2 * ttail(e(df_r), abs(_b[Z_total_cupos] / _se[Z_total_cupos]))
            foreach y in program uni he {
                quietly ivreghdfe y_`y' (N_total_enter = Z_total_cupos) `ctrl' if grp == `g', ///
                    absorb(`fe`pa'') cluster(pt)
                local iv`k'`y'   = _b[N_total_enter]
                local ivse`k'`y' = _se[N_total_enter]
                local ivp`k'`y'  = 2 * normal(-abs(_b[N_total_enter] / _se[N_total_enter]))
                if "`y'" == "program" {
                    local F`k' = e(widstat)
                    local N`k' = e(N)
                    tempvar sm
                    gen byte `sm' = e(sample)
                    quietly distinct programs if `sm'
                    local np`k' = r(ndistinct)
                    quietly summarize y_program if `sm'
                    local ym`k' = r(mean)
                    quietly summarize v_inc_eb if `sm'
                    local va`k' = r(mean)
                    drop `sm'
                }
                di as result "`s' panel `pa' group `g' `y': FS=" %6.3f `fs`k'' " (" %5.3f `fsse`k'' ///
                    ")  2SLS=" %8.5f `iv`k'`y'' " (" %7.5f `ivse`k'`y'' ")"
            }
            di as result "`s' panel `pa' group `g': F=" %7.1f `F`k'' "  N=" %9.0fc `N`k'' ///
                "  programs=" `np`k'' "  mean VA=" %6.2f `va`k'' "  mean grad=" %5.3f `ym`k''
        }
        * pooled, fully interacted with the group
        quietly reghdfe N_total_enter `zl' `ctrli', absorb(`fp`pa'') vce(cluster pt)
        quietly test `eqz'
        local pfs`s'`pa' = r(p)
        foreach y in program uni he {
            quietly ivreghdfe y_`y' (`nl' = `zl') `ctrli', absorb(`fp`pa'') cluster(pt)
            quietly test `eqn'
            local piv`s'`pa'`y' = r(p)
            di as result "`s' panel `pa' `y': pooled 2SLS " _c
            forvalues g = 1/`G' {
                di as result %8.5f _b[n_g`g'] " " _c
            }
            di as result " p(equal)=" %5.3f `piv`s'`pa'`y''
        }
        di as result "`s' panel `pa': p(equal FS)=" %5.3f `pfs`s'`pa''
    }
}

**********************************************************************
* 4. Tables
**********************************************************************

foreach s of local splits {
    local G = cond("`s'" == "med", 2, cond("`s'" == "ter", 3, 5))
    local nc = `G' + 2
    local cols "l"
    forvalues g = 0/`G' {
        local cols "`cols'c"
    }
    local fname = cond("`s'" == "med", "median", cond("`s'" == "ter", "terciles", "quintiles"))
    if "`s'" == "med"      local hdr " & Below median & Above median & \(p\) (equal) \\"
    else if "`s'" == "ter" local hdr " & Tercile 1 (low) & Tercile 2 & Tercile 3 (high) & \(p\) (equal) \\"
    else                   local hdr " & Q1 (low) & Q2 & Q3 & Q4 & Q5 (high) & \(p\) (equal) \\"

    file open T using "$im_out/tables/im_d5_va_`fname'.tex", write replace
    file write T "\begin{tabular}{`cols'}" _n "\toprule" _n "`hdr'" _n "\midrule" _n
    foreach pa in A B {
        local plab = cond("`pa'" == "A", "Panel A: program and year FE (main)", "Panel B: program and university \(\times\) year FE")
        if "`pa'" == "B" file write T "\addlinespace" _n
        file write T "\multicolumn{`nc'}{l}{\textit{`plab'}} \\" _n
        * first stage
        file write T "First stage: \(n_{pt}\) on \(Z_{pt}\)"
        forvalues g = 1/`G' {
            stars `fsp`s'`pa'`g'' st
            file write T " & " %6.3f (`fs`s'`pa'`g'') "`st'"
        }
        file write T " & " %5.3f (`pfs`s'`pa'') " \\" _n
        forvalues g = 1/`G' {
            file write T " & (" %5.3f (`fsse`s'`pa'`g'') ")"
        }
        file write T " & \\" _n "Kleibergen--Paap F"
        forvalues g = 1/`G' {
            file write T " & " %6.0f (`F`s'`pa'`g'')
        }
        file write T " & \\" _n
        foreach y in program uni he {
            local yl = cond("`y'" == "program", "2SLS: graduation, enrolled program, 8y", cond("`y'" == "uni", "2SLS: graduation, any university, 8y", "2SLS: graduation, any higher education, 8y"))
            file write T "`yl'"
            forvalues g = 1/`G' {
                stars `ivp`s'`pa'`g'`y'' st
                file write T " & " %8.5f (`iv`s'`pa'`g'`y'') "`st'"
            }
            file write T " & " %5.3f (`piv`s'`pa'`y'') " \\" _n
            forvalues g = 1/`G' {
                file write T " & (" %8.5f (`ivse`s'`pa'`g'`y'') ")"
            }
            file write T " & \\" _n
        }
    }
    file write T "\midrule" _n "Mean program VA (EB, income rank points)"
    forvalues g = 1/`G' {
        file write T " & " %5.1f (`va`s'A`g'')
    }
    file write T " & \\" _n "Mean of program graduation"
    forvalues g = 1/`G' {
        file write T " & " %5.3f (`ym`s'A`g'')
    }
    file write T " & \\" _n "Students (Panel A)"
    forvalues g = 1/`G' {
        file write T " & " %9.0fc (`N`s'A`g'')
    }
    file write T " & \\" _n "Programs (Panel A)"
    forvalues g = 1/`G' {
        file write T " & " %6.0fc (`np`s'A`g'')
    }
    file write T " & \\" _n "\bottomrule" _n "\end{tabular}" _n
    file close T
}

di as result "43_design5_by_va.do finished."
