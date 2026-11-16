/**********************************************************************
* 08_clean_ses_finance.do
*
* University finances (revenue channel behind the t-1 graduation
* coefficient of Design V; 2026-11-10 meeting). Builds an
* institution x fiscal-year panel of income and expenses from the
* SIES/SES "fichas financieras", 2013-2025.
*
*   Unit   : institution (ID_IES = MINEDUC cod_inst) x fiscal year.
*            All institution types are kept (universities, IP, CFT);
*            univ = 1 for universities.
*   Source : sheet "Ingresos y gastos" of each file. File year is not
*            the fiscal year until 2019:
*              fichas_financieras_2014            FY 2013
*              fichas_financieras_2015_2          FY 2014
*              base_fichas_financieras_2016_sies  FY 2015
*              base-fichas_financieras_2017_sies  FY 2016
*              ficha_financiera_2017_b            FY 2017
*              Base_Fichas_Financieras_2019_SIES  FY 2018
*              Resumen-financiero-YYYY-SES        FY YYYY (2019-2025)
*   Units  : thousands of current pesos (M$), as published. Not
*            deflated: use logs with year FE, or deflate downstream.
*   Variables (columns are matched by header text, because the column
*   order of the salary breakdown changes across years):
*     income : tuition (aranceles, undergraduate + graduate), public
*              funds (aportes basales y fondos concursables; renamed
*              aportes fiscales from FY 2020), extension, services,
*              donations, consulting (FY 2024+), other, non-operating
*     salary : total (FY 2013-2022 = expense line "Remuneraciones";
*              FY 2023+ = "Total remuneraciones"), academic,
*              executive, administrative, other
*     expense: total = sum of the expense lines in absolute value
*              (the sign convention changes across years). The
*              classification changes in FY 2023 (operating costs,
*              administration, financial costs, other replace
*              salaries, admin and sales, other operating,
*              non-operating), so the lines are kept separately and
*              only the total is comparable over time.
*     balance: non-current and total assets, from the audited-
*              statements sheet of the same files (act_nc, act_total)
*   Breaks to keep in mind: the expense classification (FY 2023) and
*   tuition of some universities jumping in FY 2023 (e.g. UDP 75 -> 121
*   M$ bn); "s/i" (no information) is set to missing.
*
* Input:  $raw/SES_finanzas/raw/ (13 xlsx files listed below)
* Output: $processed/ses_finance_2013_2025.dta
**********************************************************************/

clear all
set more off
do "code/config.do"

local fin_raw "$raw/SES_finanzas/raw"

* file -> fiscal year
local f2013 "fichas_financieras_2014.xlsx"
local f2014 "fichas_financieras_2015_2.xlsx"
local f2015 "base_fichas_financieras_2016_sies.xlsx"
local f2016 "base-fichas_financieras_2017_sies.xlsx"
local f2017 "ficha_financiera_2017_b.xlsx"
local f2018 "Base_Fichas_Financieras_2019_SIES.xlsx"
local f2019 "Resumen-financiero-2019-SES.xlsx"
local f2020 "Resumen-financiero-2020-SES-1.xlsx"
local f2021 "Resumen-financiero-2021-SES.xlsx"
local f2022 "Resumen-financiero-2022-SES.xlsx"
local f2023 "Resumen-financiero-2023-SES.xlsx"
local f2024 "Resumen-financiero-2024-SES.xlsx"
local f2025 "Resumen-financiero-2025-SES.xlsx"

local outvars "aranceles aportes extension prestaciones donaciones asesorias otros_ing ing_noop rem_total rem_acad rem_dir rem_adm rem_otras g_rem g_adm g_otrop g_noop c_oper c_adm c_fin g_otros"

tempfile panel
local first 1
forvalues fy = 2013/2025 {
    * income-and-expense sheet: the one whose name mentions ingresos,
    * I-G or Y-G, or FECU
    import excel using "`fin_raw'/`f`fy''", describe
    local nsh = r(N_worksheet)
    local sheet ""
    forvalues k = 1/`nsh' {
        local s = ustrlower("`r(worksheet_`k')'")
        if "`sheet'" == "" & (strpos("`s'", "ingreso") | strpos("`s'", "i-g") | ///
            strpos("`s'", "y-g") | strpos("`s'", "fecu") | strpos("`s'", "hoja 2")) {
            local sheet "`r(worksheet_`k')'"
        }
    }
    di as result "FY `fy': `f`fy'' / sheet: `sheet'"
    import excel using "`fin_raw'/`f`fy''", sheet("`sheet'") clear allstring

    * header row: first row with "Aranceles" in any cell
    local hr 0
    forvalues r = 1/8 {
        if `hr' == 0 {
            foreach v of varlist _all {
                if strpos(ustrlower(`v'[`r']), "aranceles") local hr `r'
            }
        }
    }
    assert `hr' > 0

    * map columns by header text (header row, else row 1 for id/name)
    local idv ""
    local nmv ""
    foreach v of varlist _all {
        local h  = ustrlower(strtrim(`v'[`hr']))
        local h1 = ustrlower(strtrim(`v'[1]))
        local new ""
        if "`idv'" == "" & (inlist("`h1'", "id_ies", "id", "cod_ies", "codigo_sies", "código sies") | ///
            inlist("`h'", "id_ies", "id", "cod_ies", "codigo_sies")) {
            local idv `v'
            continue
        }
        if "`nmv'" == "" & (strpos("`h1'", "nombre") | strpos("`h'", "nombre")) {
            local nmv `v'
            continue
        }
        if      strpos("`h'", "aranceles")                       local new aranceles
        else if strpos("`h'", "aportes")                         local new aportes
        else if strpos("`h'", "extensi")                         local new extension
        else if strpos("`h'", "prestaci")                        local new prestaciones
        else if strpos("`h'", "donaci")                          local new donaciones
        else if strpos("`h'", "asesor")                          local new asesorias
        else if strpos("`h'", "otros ingresos")                  local new otros_ing
        else if strpos("`h'", "ingresos no operacionales")       local new ing_noop
        else if strpos("`h'", "total remuneraciones")            local new rem_total
        else if strpos("`h'", "otras remuneraciones")            local new rem_otras
        else if strpos("`h'", "remuneraciones")                  local new g_rem
        else if strpos("`h'", "académ")                          local new rem_acad
        else if strpos("`h'", "directiv")                        local new rem_dir
        else if strpos("`h'", "administrativ")                   local new rem_adm
        else if strpos("`h'", "administraci")                    local new g_adm
        else if strpos("`h'", "otros gastos operacionales")      local new g_otrop
        else if strpos("`h'", "no operacional")                  local new g_noop
        else if strpos("`h'", "costos operacionales")            local new c_oper
        else if strpos("`h'", "costos financieros")              local new c_fin
        else if strpos("`h'", "otros gastos")                    local new g_otros
        * FY 2024: non-operating income has its label one row above
        else if "`h'" == "" & `fy' == 2024 & strpos(ustrlower(`v'[2]), "no operacionales") local new ing_noop
        if "`new'" != "" {
            capture confirm variable `new'
            if _rc == 0 {
                di as error "FY `fy': two columns map to `new'"
                exit 198
            }
            rename `v' `new'
        }
    }
    assert "`idv'" != "" & "`nmv'" != ""
    rename `idv' id_ies
    rename `nmv' nombre_ies
    drop in 1/`hr'
    * FY 2023+ "Gastos de administración" is c_adm (new classification)
    if `fy' >= 2023 capture rename g_adm c_adm
    foreach v of local outvars {
        capture confirm variable `v'
        if _rc gen str1 `v' = ""
    }
    keep id_ies nombre_ies `outvars'
    destring id_ies, replace force
    drop if missing(id_ies)
    foreach v of local outvars {
        replace `v' = "" if inlist(ustrlower(strtrim(`v')), "s/i", "-", "n/a")
        destring `v', replace force
    }
    gen int fy = `fy'
    if !`first' append using `panel'
    save `panel', replace
    local first 0
}

* blank cells mean zero (FY 2017 and 2019 leave zeros blank): within a
* fiscal year, a line that exists for some institution is set to 0
* where blank, for institutions that report tuition
foreach v of local outvars {
    tempvar any
    bysort fy: egen `any' = count(`v')
    replace `v' = 0 if missing(`v') & `any' > 0 & !missing(aranceles)
    drop `any'
}

* salaries: FY 2013-2022 the total is the expense line
replace rem_total = abs(g_rem) if missing(rem_total)
* expenses in absolute value; total comparable across classifications
foreach v in g_rem g_adm g_otrop g_noop c_oper c_adm c_fin g_otros {
    replace `v' = abs(`v')
}
egen double gasto_total = rowtotal(g_rem g_adm g_otrop g_noop c_oper c_adm c_fin g_otros), missing
egen double ing_total   = rowtotal(aranceles aportes extension prestaciones donaciones asesorias otros_ing ing_noop), missing

replace nombre_ies = strtrim(subinstr(nombre_ies, "*", "", .))
gen byte univ = regexm(ustrlower(nombre_ies), "^(universidad|pontificia)")

isid id_ies fy
order id_ies nombre_ies fy univ aranceles aportes extension prestaciones donaciones asesorias otros_ing ing_noop ing_total rem_total rem_acad rem_dir rem_adm rem_otras g_rem g_adm g_otrop g_noop c_oper c_adm c_fin g_otros gasto_total
compress

* labels (amounts in thousands of current pesos, M$)
label variable id_ies       "Institution code (SIES ID_IES = MINEDUC cod_inst)"
label variable nombre_ies   "Institution name (as published that year)"
label variable fy           "Fiscal year"
label variable univ         "University (name starts with Universidad/Pontificia)"
* income
label variable aranceles    "Income: tuition, undergrad + grad (M$)"
label variable aportes      "Income: public funds (basal/competitive; aportes fiscales from 2020) (M$)"
label variable extension    "Income: extension and continuing education (M$)"
label variable prestaciones "Income: provision of services (M$)"
label variable donaciones   "Income: donations (M$)"
label variable asesorias    "Income: consulting and research (FY 2024+) (M$)"
label variable otros_ing    "Income: other (operating) (M$)"
label variable ing_noop     "Income: non-operating (M$)"
label variable ing_total    "Income: total, sum of income lines (M$)"
* salaries
label variable rem_total    "Salaries: total (FY<=2022 expense line; FY 2023+ total) (M$)"
label variable rem_acad     "Salaries: academic staff (M$)"
label variable rem_dir      "Salaries: executives (M$)"
label variable rem_adm      "Salaries: administrative staff (M$)"
label variable rem_otras    "Salaries: other (M$)"
* expenses, FY 2013-2022 classification (absolute value)
label variable g_rem        "Expense FY<=2022: salaries (M$)"
label variable g_adm        "Expense FY<=2022: administration and sales (M$)"
label variable g_otrop      "Expense FY<=2022: other operating (M$)"
label variable g_noop       "Expense FY<=2022: non-operating (M$)"
* expenses, FY 2023+ classification (absolute value)
label variable c_oper       "Expense FY 2023+: operating costs (M$)"
label variable c_adm        "Expense FY 2023+: administration (M$)"
label variable c_fin        "Expense FY 2023+: financial costs (M$)"
label variable g_otros      "Expense FY 2023+: other (M$)"
label variable gasto_total  "Expense: total, sum of expense lines in abs. value (M$)"

* checks
tab fy univ
tabstat aranceles aportes ing_total gasto_total rem_total if univ, by(fy) stat(n mean) format(%12.0fc)
* within-university jumps in tuition (possible unit errors)
xtset id_ies fy
gen double r_ar = aranceles / L.aranceles
gen double r_ar_f = F.aranceles / aranceles
* flag: tuition moves by a factor > 2.5 from the year before (closures
* winding down, or a unit error such as U. de Aconcagua FY 2023)
gen byte flag_jump = (r_ar > 2.5 | r_ar < 0.4) & !missing(r_ar)
list id_ies nombre_ies fy aranceles r_ar r_ar_f if univ & flag_jump, noobs abbrev(12) clean
label variable flag_jump "Tuition changes by a factor > 2.5 vs. previous year"
drop r_ar r_ar_f
tempfile ig
save `ig'

/**********************************************************************
* Balance sheet (audited statements): non-current and total assets
**********************************************************************/

* The audited-statements sheet is the one whose first rows contain
* "activo(s) no corriente(s)". Non-current assets (mostly property,
* plant and equipment) proxy the capital stock; their change is net
* investment (after depreciation; it also includes long-term financial
* assets). There is no capital-expenditure line in the fichas.
tempfile bal
local first 1
forvalues fy = 2013/2025 {
    import excel using "`fin_raw'/`f`fy''", describe
    local nsh = r(N_worksheet)
    forvalues k = 1/`nsh' {
        local s`k' "`r(worksheet_`k')'"
    }
    local found 0
    forvalues k = 1/`nsh' {
        if `found' continue
        import excel using "`fin_raw'/`f`fy''", sheet("`s`k''") clear allstring
        if _N < 3 continue
        * header row: first row with non-current assets
        local hr 0
        forvalues r = 1/4 {
            if `hr' == 0 {
                foreach v of varlist _all {
                    if ustrregexm(ustrlower(strtrim(`v'[`r'])), "^activos? no corrientes?( totales)?$") local hr `r'
                }
            }
        }
        if `hr' == 0 continue
        local found 1
        local idv ""
        local anc ""
        local ato ""
        foreach v of varlist _all {
            forvalues r = 1/`hr' {
                local h = ustrlower(strtrim(`v'[`r']))
                if "`idv'" == "" & inlist("`h'", "id_ies", "id", "cod_ies", "codigo_sies", "código sies") local idv `v'
            }
            local h = ustrlower(strtrim(`v'[`hr']))
            if "`anc'" == "" & ustrregexm("`h'", "^activos? no corrientes?( totales)?$") local anc `v'
            if "`ato'" == "" & ustrregexm("`h'", "^(total activos|activos totales)$") local ato `v'
        }
        di as result "FY `fy': balance sheet `s`k'' (header row `hr'; id `idv', non-current `anc', total `ato')"
        assert "`idv'" != "" & "`anc'" != "" & "`ato'" != ""
        keep `idv' `anc' `ato'
        rename (`idv' `anc' `ato') (id_ies act_nc act_total)
        drop in 1/`hr'
        foreach v in id_ies act_nc act_total {
            replace `v' = "" if inlist(ustrlower(strtrim(`v')), "s/i", "-", "n/a")
            destring `v', replace force
        }
        drop if missing(id_ies)
        duplicates drop id_ies, force
        gen int fy = `fy'
        if !`first' append using `bal'
        save `bal', replace
        local first 0
    }
    assert `found'
}

use `ig', clear
merge 1:1 id_ies fy using `bal', keep(master match)
tab fy _merge if univ
drop _merge
label variable act_nc    "Balance: non-current assets (M$)"
label variable act_total "Balance: total assets (M$)"
* within-university jumps in non-current assets (possible unit errors)
xtset id_ies fy
gen double r_nc = act_nc / L.act_nc
* flag: non-current assets move by a factor > 2.5 (e.g. UNAB FY 2018-19,
* a change in the consolidation perimeter)
gen byte flag_nc = (r_nc > 2.5 | r_nc < 0.4) & !missing(r_nc)
list id_ies nombre_ies fy act_nc r_nc if univ & flag_nc, noobs abbrev(12) clean
label variable flag_nc "Non-current assets change by a factor > 2.5 vs. previous year"
drop r_nc
tabstat act_nc act_total if univ, by(fy) stat(n mean) format(%14.0fc)

describe
save "$processed/ses_finance_2013_2025.dta", replace
di as result "08_clean_ses_finance.do finished."
