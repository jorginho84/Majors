/*------------------------------------------------------------------------------
                    Threshold-Crossing Effects in Higher Education

                    00_master.do

                    Master do-file that runs the entire analysis pipeline.

                    Structure:
                    1. Clean raw data
                    2. Build analysis datasets
                    3. RDD estimation and figures

                    Usage:
                        do "$code/00_master.do"

                    Or run individual sections by setting the appropriate flags below.
------------------------------------------------------------------------------*/

clear all
set more off

*-------------------------------------------------------------------------------
* Configuration
*-------------------------------------------------------------------------------

* Set root path (adjust for your environment)
global root "/home/jrodriguezo/majors"
global code "$root/code"

* Which sections to run? (1 = run, 0 = skip)
local run_clean  = 1
local run_build  = 1
local run_rdd    = 1

*-------------------------------------------------------------------------------
* 1. Clean raw data
*-------------------------------------------------------------------------------

if `run_clean' {
    di _n _dup(70) "="
    di "SECTION 1: CLEANING RAW DATA"
    di _dup(70) "="

    * Clean PSU scores
    di _n "Running: 01_clean_psu.do"
    do "$code/01_clean/01_clean_psu.do"

    * Clean applications
    di _n "Running: 02_clean_applications.do"
    do "$code/01_clean/02_clean_applications.do"

    * Clean enrollment (matrícula)
    di _n "Running: 03_clean_enrollment.do"
    do "$code/01_clean/03_clean_enrollment.do"

    * Clean program weights
    di _n "Running: 04_clean_weights.do"
    do "$code/01_clean/04_clean_weights.do"

    di _n "Data cleaning complete."
}

*-------------------------------------------------------------------------------
* 2. Build analysis datasets
*-------------------------------------------------------------------------------

if `run_build' {
    di _n _dup(70) "="
    di "SECTION 2: BUILDING ANALYSIS DATASETS"
    di _dup(70) "="

    * Build cutoffs
    di _n "Running: 01_build_cutoffs.do"
    do "$code/02_build/01_build_cutoffs.do"

    * Build running variable
    di _n "Running: 02_build_running_var.do"
    do "$code/02_build/02_build_running_var.do"

    * Build outcomes
    di _n "Running: 03_build_outcomes.do"
    do "$code/02_build/03_build_outcomes.do"

    * Build waiting list indicator
    di _n "Running: 04_build_waiting_list.do"
    do "$code/02_build/04_build_waiting_list.do"

    di _n "Data construction complete."
}

*-------------------------------------------------------------------------------
* 3. RDD estimation and figures
*-------------------------------------------------------------------------------

if `run_rdd' {
    di _n _dup(70) "="
    di "SECTION 3: RDD ESTIMATION AND FIGURES"
    di _dup(70) "="

    * RDD estimation
    di _n "Running: 01_rdd_enrollment.do"
    do "$code/04_rdd/01_rdd_enrollment.do"

    * RDD figures
    di _n "Running: 02_rdd_figures.do"
    do "$code/04_rdd/02_rdd_figures.do"

    di _n "RDD analysis complete."
}

*-------------------------------------------------------------------------------
* Done
*-------------------------------------------------------------------------------

di _n _dup(70) "="
di "MASTER DO-FILE COMPLETE"
di _dup(70) "="
di _n "Output locations:"
di "  Tables:  $output/tables/"
di "  Figures: $output/figures/"
di _dup(70) "="
