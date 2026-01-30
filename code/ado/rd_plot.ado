*! rd_plot v1.0 - RD plot with binned scatter, fitted lines, and histogram
*! Based on legacy code: 04_a2_figures_enrollment.do
*!
*! Syntax:
*!   rd_plot outcome, running(varname) treatment(varname) [options]
*!
*! Required:
*!   outcome     - outcome variable
*!   running()   - running variable (distance to cutoff)
*!   treatment() - treatment indicator (1 if above cutoff)
*!
*! Optional:
*!   bandwidth() - bandwidth for sample restriction (default: 25)
*!   binwidth()  - width of bins for scatter (default: 5)
*!   degree()    - polynomial degree: 1=linear, 2=quadratic (default: 1)
*!   absorb()    - fixed effects to absorb (e.g., "año_proceso t_codigo_carrera")
*!   cluster()   - cluster variable for SE (e.g., "año_proceso#t_codigo_carrera")
*!   saving()    - file path to save graph (without extension)
*!   title()     - custom title for the graph
*!   ytitle()    - custom y-axis title
*!   xtitle()    - custom x-axis title
*!   yrange()    - y-axis range as "min max" (default: auto)
*!   nohistogram - suppress histogram overlay
*!   noci        - suppress confidence intervals display

capture program drop rd_plot
program define rd_plot, rclass
    version 14.0

    syntax varname(numeric) [if] [in], ///
        RUnning(varname numeric) ///
        TReatment(varname numeric) ///
        [BANDwidth(real 25) ///
         BINwidth(real 5) ///
         DEGree(integer 1) ///
         ABsorb(string) ///
         CLuster(string) ///
         SAVing(string) ///
         TItle(string) ///
         YTitle(string) ///
         XTitle(string) ///
         YRange(numlist min=2 max=2) ///
         noHISTogram ///
         noCI]

    *---------------------------------------------------------------------------
    * Setup
    *---------------------------------------------------------------------------

    local outcome `varlist'
    local rv `running'
    local treat `treatment'
    local bw `bandwidth'
    local bin `binwidth'
    local poly `degree'

    * Mark sample
    marksample touse
    markout `touse' `outcome' `rv' `treat'

    * Apply bandwidth restriction
    qui replace `touse' = 0 if abs(`rv') > `bw'

    * Check we have observations
    qui count if `touse'
    if r(N) == 0 {
        di as error "No observations in bandwidth"
        exit 2000
    }

    * Get variable labels for axis titles
    local outcome_label: variable label `outcome'
    if "`outcome_label'" == "" local outcome_label "`outcome'"

    local rv_label: variable label `rv'
    if "`rv_label'" == "" local rv_label "Distance to cutoff"

    *---------------------------------------------------------------------------
    * Center running variable for cleaner display at cutoff
    * (Following legacy code lines 27-38)
    *---------------------------------------------------------------------------

    tempvar rv_centered

    * Get max negative and min positive values
    qui summarize `rv' if `touse' & `rv' < 0
    local max_neg = r(max)

    qui summarize `rv' if `touse' & `rv' > 0
    local min_pos = r(min)

    * Create centered variable
    qui gen `rv_centered' = `rv' + abs(`max_neg') if `rv' < 0 & `touse'
    qui replace `rv_centered' = `rv' - `min_pos' if `rv' >= 0 & `touse'

    *---------------------------------------------------------------------------
    * Residualize outcome (remove fixed effects)
    *---------------------------------------------------------------------------

    tempvar outcome_resid

    if "`absorb'" != "" {
        * Build absorb specification
        local absorb_spec ""
        foreach v of local absorb {
            local absorb_spec "`absorb_spec' i.`v'"
        }

        * Get interaction of absorb variables
        local absorb_interact: subinstr local absorb " " "#i.", all
        local absorb_interact "i.`absorb_interact'"

        qui reghdfe `outcome' if `touse', absorb(`absorb_interact') residuals
        qui predict `outcome_resid' if `touse', residuals

        * Add back constant
        local b_cons = _b[_cons]
        qui replace `outcome_resid' = `outcome_resid' + `b_cons' if `touse'
    }
    else {
        qui gen `outcome_resid' = `outcome' if `touse'
    }

    *---------------------------------------------------------------------------
    * Generate bins using rdplot
    *---------------------------------------------------------------------------

    local nbins = round(`bw' / `bin')

    qui rdplot `outcome_resid' `rv' if `touse', ///
        c(0) p(`poly') ///
        nbins(`nbins' `nbins') ///
        kernel(uniform) ///
        h(`bw' `bw') ///
        support(-`bw' `bw') ///
        hide genvars

    * Create bin identifier
    tempvar bin_id
    qui bysort rdplot_mean_y: gen `bin_id' = _n

    *---------------------------------------------------------------------------
    * Run RD regression
    *---------------------------------------------------------------------------

    * Build cluster option
    local cluster_opt ""
    if "`cluster'" != "" {
        local cluster_opt "cluster(i.`cluster')"
    }

    * Build absorb option for regression
    local reg_absorb ""
    if "`absorb'" != "" {
        local reg_absorb "absorb(`absorb_interact')"
    }

    * Run regression based on polynomial degree
    if `poly' == 1 {
        qui reghdfe `outcome' `treat' `rv' 1.`treat'#c.`rv' if `touse', ///
            `reg_absorb' `cluster_opt'
    }
    else if `poly' == 2 {
        qui reghdfe `outcome' `treat' `rv' 1.`treat'#c.`rv' ///
            c.`rv'#c.`rv' 1.`treat'#c.`rv'#c.`rv' if `touse', ///
            `reg_absorb' `cluster_opt'
    }

    * Store coefficient and SE
    local beta = _b[`treat']
    local se = _se[`treat']
    local beta_fmt: display %6.3f `beta'
    local se_fmt: display %6.3f `se'
    local coef_text "β = `beta_fmt' (`se_fmt')"

    * Return results
    return scalar beta = `beta'
    return scalar se = `se'
    return scalar N = e(N)

    *---------------------------------------------------------------------------
    * Set up graph parameters
    *---------------------------------------------------------------------------

    * Y-axis range
    if "`yrange'" != "" {
        local ymin: word 1 of `yrange'
        local ymax: word 2 of `yrange'
    }
    else {
        qui summarize rdplot_mean_y if `touse'
        local ymin = floor(r(min) * 20) / 20
        local ymax = ceil(r(max) * 20) / 20
        * Ensure some padding
        local ymin = max(0, `ymin' - 0.05)
        local ymax = min(1, `ymax' + 0.05)
    }

    local ygap = 0.05
    if `ymax' - `ymin' > 0.5 {
        local ygap = 0.1
    }

    * X-axis
    local bin_gap = `bin' * 2
    local bw_fmt: display %4.0f `bw'

    * Text position for coefficient
    local text_y = `ymax' - 0.05

    * Axis titles
    if "`ytitle'" == "" local ytitle "`outcome_label'"
    if "`xtitle'" == "" local xtitle "`rv_label'"
    if "`title'" == ""  local title "RD Plot: `outcome_label'"

    *---------------------------------------------------------------------------
    * Create graph
    *---------------------------------------------------------------------------

    * Build fit command based on degree
    if `poly' == 1 {
        local fit_cmd "lfit"
    }
    else {
        local fit_cmd "qfit"
    }

    * Build histogram component
    local hist_cmd ""
    if "`histogram'" != "nohistogram" {
        local hist_cmd "(histogram `rv_centered', yaxis(2) width(`bin') start(-`bw') frequency fintensity(40) fcolor(edkblue) lwidth(none))"
    }

    #delimit ;
    twoway
        `hist_cmd'
        (`fit_cmd' `outcome_resid' `rv_centered' if `rv_centered' < 0 & `touse', lcolor(red) lwidth(medium))
        (`fit_cmd' `outcome_resid' `rv_centered' if `rv_centered' >= 0 & `touse', lcolor(red) lwidth(medium))
        (scatter rdplot_mean_y rdplot_mean_x if `bin_id' == 1 & `touse',
            sort mcolor(navy) msize(small) msymbol(circle)
            text(`text_y' 1 "`coef_text'", place(e) size(small) color(black)))
        ,
        ytitle("`ytitle'", size(medsmall))
        yscale(range(`ymin' `ymax'))
        ylabel(`ymin'(`ygap')`ymax', labels labsize(small) angle(horizontal) format(%9.2f))
        xline(0, lpattern(dash) lcolor(black))
        xtitle("`xtitle'", size(medsmall))
        xlabel(-`bw_fmt'(`bin_gap')`bw_fmt', labsize(small))
        legend(off)
        title("`title'", size(medium))
        plotregion(lcolor(black) lwidth(thin))
        graphregion(color(white))
        scheme(s2color)
    ;
    #delimit cr

    * Add histogram y-axis label if included
    if "`histogram'" != "nohistogram" {
        * Note: ytitle for axis 2 set in options above if needed
    }

    *---------------------------------------------------------------------------
    * Save graph if requested
    *---------------------------------------------------------------------------

    if "`saving'" != "" {
        qui graph save "`saving'.gph", replace
        qui graph export "`saving'.pdf", replace as(pdf)
        di as text "Graph saved to: `saving'.gph and `saving'.pdf"
    }

    *---------------------------------------------------------------------------
    * Clean up rdplot generated variables
    *---------------------------------------------------------------------------

    capture drop rdplot_id rdplot_mean_x rdplot_mean_y rdplot_ci_l rdplot_ci_r
    capture drop rdplot_N rdplot_min_bin rdplot_max_bin rdplot_mean_bin rdplot_se_y rdplot_hat_y

    *---------------------------------------------------------------------------
    * Display results
    *---------------------------------------------------------------------------

    di _n as text "RD Plot Results"
    di as text "{hline 50}"
    di as text "Outcome:     " as result "`outcome'"
    di as text "Running var: " as result "`rv'"
    di as text "Bandwidth:   " as result "`bw'"
    di as text "Polynomial:  " as result "`poly'"
    di as text "Observations:" as result e(N)
    di as text "{hline 50}"
    di as text "RD estimate: " as result "`beta_fmt'" as text " (SE: " as result "`se_fmt'" as text ")"
    di as text "{hline 50}"

end
