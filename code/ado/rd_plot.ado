*! rd_plot v2.0 - RD plot with clean publication style
*! Based on reference figure style: black dots, linear fit, subtle histogram
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
*!   bandwidth() - bandwidth for regression/fitted line (default: 25)
*!   binwidth()  - width of bins for scatter (default: 5)
*!   degree()    - polynomial degree: 1=linear, 2=quadratic (default: 1)
*!   absorb()    - fixed effects to absorb
*!   cluster()   - cluster variable for SE
*!   saving()    - file path to save graph (without extension)
*!   title()     - custom title for the graph
*!   ytitle()    - custom y-axis title
*!   xtitle()    - custom x-axis title
*!   yrange()    - y-axis range as "min max" (default: auto)
*!   xsupport()  - x-axis display range (default: 50, shows -50 to 50)
*!   nohistogram - suppress histogram overlay

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
         XSupport(real 50) ///
         noHISTogram]

    *---------------------------------------------------------------------------
    * Setup
    *---------------------------------------------------------------------------

    local outcome `varlist'
    local rv `running'
    local treat `treatment'
    local bw `bandwidth'
    local bin `binwidth'
    local poly `degree'
    local xsupp `xsupport'

    * Mark sample (full sample for display, bandwidth for regression)
    marksample touse
    markout `touse' `outcome' `rv' `treat'

    * Check we have observations
    qui count if `touse' & abs(`rv') <= `bw'
    if r(N) == 0 {
        di as error "No observations within bandwidth"
        exit 2000
    }

    * Get variable labels for axis titles
    local outcome_label: variable label `outcome'
    if "`outcome_label'" == "" local outcome_label "`outcome'"

    local rv_label: variable label `rv'
    if "`rv_label'" == "" local rv_label "Test Score Relative to Cutoff"

    *---------------------------------------------------------------------------
    * Residualize outcome (remove fixed effects)
    *---------------------------------------------------------------------------

    tempvar outcome_resid

    if "`absorb'" != "" {
        * Get interaction of absorb variables
        local absorb_interact: subinstr local absorb " " "#i.", all
        local absorb_interact "i.`absorb_interact'"

        qui reghdfe `outcome' if `touse' & abs(`rv') <= `xsupp', absorb(`absorb_interact') residuals
        qui predict `outcome_resid' if `touse' & abs(`rv') <= `xsupp', residuals

        * Add back mean
        qui summarize `outcome' if `touse' & abs(`rv') <= `xsupp'
        local outcome_mean = r(mean)
        qui replace `outcome_resid' = `outcome_resid' + `outcome_mean' if `touse'
    }
    else {
        qui gen `outcome_resid' = `outcome' if `touse'
    }

    *---------------------------------------------------------------------------
    * Generate bins for scatter plot (over full x support)
    *---------------------------------------------------------------------------

    tempvar bin_var bin_mean_y bin_mean_x bin_tag

    * Create bin variable (centered on bin midpoint)
    qui gen `bin_var' = floor(`rv' / `bin') * `bin' + `bin'/2 if `touse' & abs(`rv') <= `xsupp'

    * Compute bin means
    qui bysort `bin_var': egen `bin_mean_y' = mean(`outcome_resid') if `touse' & abs(`rv') <= `xsupp'
    qui bysort `bin_var': egen `bin_mean_x' = mean(`rv') if `touse' & abs(`rv') <= `xsupp'
    qui bysort `bin_var': gen `bin_tag' = (_n == 1) if `touse' & abs(`rv') <= `xsupp'

    *---------------------------------------------------------------------------
    * Run RD regression (within bandwidth only)
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

    * Run regression within bandwidth
    if `poly' == 1 {
        qui reghdfe `outcome' `treat' `rv' 1.`treat'#c.`rv' if `touse' & abs(`rv') <= `bw', ///
            `reg_absorb' `cluster_opt'
    }
    else if `poly' == 2 {
        qui reghdfe `outcome' `treat' `rv' 1.`treat'#c.`rv' ///
            c.`rv'#c.`rv' 1.`treat'#c.`rv'#c.`rv' if `touse' & abs(`rv') <= `bw', ///
            `reg_absorb' `cluster_opt'
    }

    * Store coefficient and SE
    local beta = _b[`treat']
    local se = _se[`treat']
    local beta_fmt: display %5.3f `beta'
    local se_fmt: display %5.3f `se'
    local coef_text "First Stage: `beta_fmt' (`se_fmt')"

    * Return results
    return scalar beta = `beta'
    return scalar se = `se'
    return scalar N = e(N)

    *---------------------------------------------------------------------------
    * Generate fitted values (within bandwidth only)
    *---------------------------------------------------------------------------

    tempvar fitted_below fitted_above xgrid

    * Get regression coefficients
    local b0 = _b[_cons]
    local b1 = _b[`treat']
    local b2 = _b[`rv']
    local b3 = _b[1.`treat'#c.`rv']

    * Generate fitted values at data points
    qui gen `fitted_below' = `b0' + `b2' * `rv' if `touse' & `rv' >= -`bw' & `rv' < 0
    qui gen `fitted_above' = `b0' + `b1' + (`b2' + `b3') * `rv' if `touse' & `rv' >= 0 & `rv' <= `bw'

    *---------------------------------------------------------------------------
    * Set up graph parameters
    *---------------------------------------------------------------------------

    * Y-axis range
    if "`yrange'" != "" {
        local ymin: word 1 of `yrange'
        local ymax: word 2 of `yrange'
    }
    else {
        qui summarize `bin_mean_y' if `bin_tag' == 1 & `touse'
        local ymin = floor(r(min) * 10) / 10
        local ymax = ceil(r(max) * 10) / 10
        local ymin = max(0, `ymin' - 0.05)
        local ymax = min(1, `ymax' + 0.05)
    }

    local ygap = 0.1
    if `ymax' - `ymin' <= 0.5 {
        local ygap = 0.05
    }

    * X-axis gaps
    local xgap = 10
    if `xsupp' <= 25 {
        local xgap = 5
    }

    * Text position for coefficient (bottom right quadrant)
    local text_y = `ymin' + 0.06
    local text_x = `xsupp' * 0.35

    * Axis titles
    if "`ytitle'" == "" local ytitle "`outcome_label'"
    if "`xtitle'" == "" local xtitle "`rv_label'"
    if "`title'" == ""  local title "`outcome_label'"

    *---------------------------------------------------------------------------
    * Create graph
    *---------------------------------------------------------------------------

    * Build histogram component (subtle, in background)
    local hist_cmd ""
    if "`histogram'" != "nohistogram" {
        * Light blue, very transparent histogram
        local hist_cmd "(histogram `rv' if `touse' & abs(`rv') <= `xsupp', yaxis(2) width(`bin') frequency fcolor(ltblue%15) lwidth(none))"
    }

    #delimit ;
    twoway
        `hist_cmd'
        (line `fitted_below' `rv' if `touse' & `rv' >= -`bw' & `rv' < 0,
            sort lcolor(black) lwidth(medthick))
        (line `fitted_above' `rv' if `touse' & `rv' >= 0 & `rv' <= `bw',
            sort lcolor(black) lwidth(medthick))
        (scatter `bin_mean_y' `bin_mean_x' if `bin_tag' == 1 & `touse',
            mcolor(black) msize(medsmall) msymbol(circle)
            text(`text_y' `text_x' "`coef_text'", place(e) size(small) color(black)))
        ,
        xline(0, lpattern(dash) lcolor(gs8) lwidth(medium))
        ytitle("`ytitle'", size(medsmall))
        yscale(range(`ymin' `ymax') noline)
        ylabel(`ymin'(`ygap')`ymax', labsize(small) angle(horizontal) format(%9.2f) nogrid)
        xtitle("`xtitle'", size(medsmall))
        xscale(range(-`xsupp' `xsupp') noline)
        xlabel(-`xsupp'(`xgap')`xsupp', labsize(small))
        yscale(alt axis(2) off)
        legend(off)
        title("`title'", size(medsmall))
        graphregion(color(white))
        plotregion(color(white))
    ;
    #delimit cr

    *---------------------------------------------------------------------------
    * Save graph if requested
    *---------------------------------------------------------------------------

    if "`saving'" != "" {
        qui graph export "`saving'.pdf", replace as(pdf)
        di as text "Graph saved to: `saving'.pdf"
    }

    *---------------------------------------------------------------------------
    * Display results
    *---------------------------------------------------------------------------

    di _n as text "RD Plot Results"
    di as text "{hline 50}"
    di as text "Outcome:     " as result "`outcome'"
    di as text "Running var: " as result "`rv'"
    di as text "Bandwidth:   " as result "`bw'"
    di as text "X support:   " as result "[-`xsupp', `xsupp']"
    di as text "Polynomial:  " as result "`poly'"
    di as text "Observations:" as result e(N) " (within bandwidth)"
    di as text "{hline 50}"
    di as text "RD estimate: " as result "`beta_fmt'" as text " (SE: " as result "`se_fmt'" as text ")"
    di as text "{hline 50}"

end