/**********************************************************************
* 10_graduation_descriptive_tables_with_target.do
*
* Crea tablas LaTeX descriptivas de outcomes de titulación a 8 años,
* incluyendo titulación en target program.
*
* Input:
*   - $processed/analysis_sample_with_fields_graduation_8y.dta
*
* Output:
*   - $output/tables/graduation_descriptive_tables_with_target.tex
**********************************************************************/

clear
set more off

************************************************************
* 0. Cargar configuración
************************************************************

do "C:/Users/jigodoy/Documents/GitHub/Majors/code/config.do"

capture mkdir "$output/tables"


************************************************************
* 1. Abrir base
************************************************************

use "$processed/analysis_sample_with_fields_graduation_8y.dta", clear

drop if missing(field) | field == "" | field == "Missing"


************************************************************
* 2. Tabla 1: Titulación total a 8 años
************************************************************

preserve

    count
    local N_total = r(N)

    foreach y in graduates_he_8y graduates_uni_8y graduates_target_8y {

        quietly count if `y' == 1
        local n_`y' = r(N)
        local p_`y' = 100 * `n_`y'' / `N_total'

        quietly count if `y' == 0
        local n_no_`y' = r(N)
        local p_no_`y' = 100 * `n_no_`y'' / `N_total'
    }

restore


************************************************************
* 3. Tabla 2: Titulación por campo
************************************************************

preserve

    collapse ///
        (count) total = graduates_he_8y ///
        (sum) grad_he = graduates_he_8y ///
              grad_uni = graduates_uni_8y ///
              grad_target = graduates_target_8y, ///
        by(field)

    gen pct_grad_he     = 100 * grad_he / total
    gen pct_grad_uni    = 100 * grad_uni / total
    gen pct_grad_target = 100 * grad_target / total

    gsort field

    tempfile field_table
    save `field_table', replace

restore


************************************************************
* 4. Exportar a LaTeX
************************************************************

local texfile "$output/tables/graduation_descriptive_tables_with_target.tex"

capture erase "`texfile'"

file open tex using "`texfile'", write replace


************************************************************
* 4.1 Tabla total
************************************************************

file write tex "\begin{table}[!htbp]\centering" _n
file write tex "\caption{Graduation Outcomes within Eight Years}" _n
file write tex "\label{tab:graduation_outcomes_8y_target}" _n
file write tex "\begin{tabular}{lccc}" _n
file write tex "\hline\hline" _n
file write tex "Outcome & No & Yes & Total \\" _n
file write tex "\hline" _n

file write tex "Graduated from higher education & " ///
    %12.0fc (`n_no_graduates_he_8y') " (" %4.2f (`p_no_graduates_he_8y') "\%) & " ///
    %12.0fc (`n_graduates_he_8y') " (" %4.2f (`p_graduates_he_8y') "\%) & " ///
    %12.0fc (`N_total') " \\" _n

file write tex "Graduated from university & " ///
    %12.0fc (`n_no_graduates_uni_8y') " (" %4.2f (`p_no_graduates_uni_8y') "\%) & " ///
    %12.0fc (`n_graduates_uni_8y') " (" %4.2f (`p_graduates_uni_8y') "\%) & " ///
    %12.0fc (`N_total') " \\" _n

file write tex "Graduated from target program & " ///
    %12.0fc (`n_no_graduates_target_8y') " (" %4.2f (`p_no_graduates_target_8y') "\%) & " ///
    %12.0fc (`n_graduates_target_8y') " (" %4.2f (`p_graduates_target_8y') "\%) & " ///
    %12.0fc (`N_total') " \\" _n

file write tex "\hline\hline" _n
file write tex "\end{tabular}" _n
file write tex "\begin{minipage}{0.90\textwidth}" _n
file write tex "\footnotesize Notes: The table reports whether each observation appears as graduated within eight years of the admission process. Target-program graduation requires graduation from the same target program identified through the SIES unique program code. Percentages are row percentages within each outcome." _n
file write tex "\end{minipage}" _n
file write tex "\end{table}" _n
file write tex _n


************************************************************
* 4.2 Tabla por campo
************************************************************

use `field_table', clear

file write tex "\begin{table}[!htbp]\centering" _n
file write tex "\caption{Graduation Outcomes within Eight Years by Field of Study}" _n
file write tex "\label{tab:graduation_by_field_8y_target}" _n
file write tex "\begin{tabular}{lcccc}" _n
file write tex "\hline\hline" _n
file write tex "Field & Total observations & Graduated HE (\%) & Graduated University (\%) & Graduated Target Program (\%) \\" _n
file write tex "\hline" _n

forvalues i = 1/`=_N' {

    local f = field[`i']
    local f = subinstr("`f'", "&", "\&", .)
    local f = subinstr("`f'", "_", "\_", .)

    local total_i = total[`i']
    local phe_i = pct_grad_he[`i']
    local puni_i = pct_grad_uni[`i']
    local ptarget_i = pct_grad_target[`i']

    file write tex "`f' & " ///
        %12.0fc (`total_i') " & " ///
        %4.2f (`phe_i') " & " ///
        %4.2f (`puni_i') " & " ///
        %4.2f (`ptarget_i') " \\" _n
}

file write tex "\hline" _n

quietly summarize total
local total_all = r(sum)

quietly summarize grad_he
local grad_he_all = r(sum)

quietly summarize grad_uni
local grad_uni_all = r(sum)

quietly summarize grad_target
local grad_target_all = r(sum)

local pct_he_all     = 100 * `grad_he_all' / `total_all'
local pct_uni_all    = 100 * `grad_uni_all' / `total_all'
local pct_target_all = 100 * `grad_target_all' / `total_all'

file write tex "Total & " ///
    %12.0fc (`total_all') " & " ///
    %4.2f (`pct_he_all') " & " ///
    %4.2f (`pct_uni_all') " & " ///
    %4.2f (`pct_target_all') " \\" _n

file write tex "\hline\hline" _n
file write tex "\end{tabular}" _n
file write tex "\begin{minipage}{0.95\textwidth}" _n
file write tex "\footnotesize Notes: HE denotes higher education. Graduation is measured within eight years of the admission process using SIES graduation records. Target-program graduation requires matching the target program to the SIES unique program code. Percentages are row percentages within each field of study." _n
file write tex "\end{minipage}" _n
file write tex "\end{table}" _n

file close tex


************************************************************
* 5. Fin
************************************************************

di as result "Tablas LaTeX guardadas en:"
di as result "`texfile'"