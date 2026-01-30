/*------------------------------------------------------------------------------
                        Threshold-Crossing Effects in Higher Education

                        Configuration File

                        This file sets up paths and globals for the project.
                        Run this at the start of every do-file.
------------------------------------------------------------------------------*/

clear all
set more off

*-------------------------------------------------------------------------------
* Project paths
*-------------------------------------------------------------------------------

* Server paths (where data lives and code runs)
global root     "/home/jrodriguezo/majors"
global code     "$root/code"
global data     "$root/data"
global raw      "$data"
global processed "$data/processed"
global output   "$root/output"
global logs     "$root/logs"

* Raw data subdirectories
global psu_raw      "$raw/PSU_scores"
global app_raw      "$raw/MINEDUC/Applications"
global mat_raw      "$raw/MINEDUC/Matricula Educacion Superior"
global tit_raw      "$raw/MINEDUC/Base Titulados"

*-------------------------------------------------------------------------------
* Analysis parameters
*-------------------------------------------------------------------------------

* Year range for analysis
global year_start = 2007
global year_end   = 2016

* RDD parameters
global bandwidth = 25          // Bandwidth for RDD (in score points)

* Key variable values
global admitted      = 24      // ESTADO_PREFERENCIA for admitted
global waiting_list  = 25      // ESTADO_PREFERENCIA for waiting list
global rejected      = 26      // ESTADO_PREFERENCIA for rejected

*-------------------------------------------------------------------------------
* Output settings
*-------------------------------------------------------------------------------

* Set scheme for figures
set scheme s2color

* Log file (optional - uncomment to enable)
* capture log close
* log using "$logs/`c(current_date)'.log", replace

di "Configuration loaded successfully"
di "Root: $root"
di "Data: $data"
di "Output: $output"
