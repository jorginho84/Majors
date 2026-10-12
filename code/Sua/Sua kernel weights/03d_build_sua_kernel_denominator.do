/**********************************************************************
* 03d_build_sua_kernel_denominator.do
*
* Objective:
*   Construct a variant of the SUA exposure measure where both the
*   numerator and denominator are weighted by PSU selectivity distance.
*
* Measure:
*
*                  sum_q k(|S_p-S_q|) * N_q
*   E_p^{k,KD} =   ---------------------------
*                  sum_l k(|S_p-S_l|) * N_l
*
* where:
*
*   p = incumbent program
*   q = entrant program
*   l = any program in the market (incumbent or entrant)
*
* Difference relative to 03b:
*
*   03b:
*       denominator = total market enrollment
*
*   03d:
*       denominator = market enrollment weighted by PSU similarity
*                     relative to incumbent program p
*
* Kernels:
*
*   Triangular:
*       k(d) = max(0, 1 - d/50)
*
*   Gaussian:
*       k(d) = exp[-0.5(d/50)^2]
*
* IMPORTANT:
*   - Does not modify or replace outputs from 03b.
*   - Keeps exp_tri50 and exp_gau50.
*   - Adds exp_tri50kd and exp_gau50kd.
*
* Inputs:
*   sua_preperiod_program_year_2009_2011.dta
*   sies_program_year_geo_2007_2016.dta
*   sua_incumbent_panel_w_<market>_<geo>_2007_2016.dta
*
* Outputs:
*   sua_incumbent_panel_kd_<market>_<geo>_2007_2016.dta
*   sua_kernelden_exposure_coverage.dta
**********************************************************************/

clear all
set more off
set varabbrev off

do "code/config.do"


/**********************************************************************
* 0. Parameters and definitions
**********************************************************************/

local h = 50

local markettypes ///
    broad_area ///
    cine_subarea ///
    generic_area

local fieldvars ///
    area_conocimiento ///
    cine_f_97_subarea ///
    area_carrera_generica

local geotypes ///
    region ///
    provincia ///
    comuna

local geoidvars ///
    id_region_2018 ///
    id_provincia_2018 ///
    id_comuna_2018

local geonamevars ///
    region_2018 ///
    provincia_2018 ///
    comuna_2018

tempfile ///
    entrants_pre ///
    coverage

tempname covpost


/**********************************************************************
* 1. Program to normalize text variables
**********************************************************************/

capture program drop make_text_key

program define make_text_key

    syntax varname, Generate(name)

    gen str244 `generate' = ///
        ustrupper(itrim(ustrtrim(`varlist')))

    replace `generate' = ///
        ustrnormalize(`generate', "nfd")

    replace `generate' = ///
        ustrregexra(`generate', "\p{Mark}", "")

    replace `generate' = ///
        ustrregexra(`generate', "[^A-Z0-9 ]", " ")

    replace `generate' = ///
        ustrregexra(`generate', " +", " ")

    replace `generate' = ///
        itrim(ustrtrim(`generate'))

end


/**********************************************************************
* 2. Prepare entrant pre-treatment information
**********************************************************************/

use ///
    "$processed/sua_preperiod_program_year_2009_2011.dta", ///
    clear

keep if inrange(ao_proceso, 2009, 2011)

merge 1:1 ///
    codigo_unico ///
    ao_proceso ///
    using "$processed/sies_program_year_geo_2007_2016.dta", ///
    keep(master match) ///
    keepusing( ///
        id_region_2018 ///
        region_2018 ///
        id_provincia_2018 ///
        provincia_2018 ///
        id_comuna_2018 ///
        comuna_2018 ///
    ) ///
    generate(_merge_geo)

assert _merge_geo == 3

drop _merge_geo

isid ///
    codigo_unico ///
    ao_proceso

save `entrants_pre', replace


/**********************************************************************
* 3. Coverage file
**********************************************************************/

postfile `covpost' ///
    str20 market_type ///
    str12 geo_type ///
    long n_programs ///
    long n_kden ///
    double mean_tri_old ///
    double mean_tri_kd ///
    double mean_gau_old ///
    double mean_gau_kd ///
    double mean_den_cov ///
    using `coverage', ///
    replace


/**********************************************************************
* 4. Construct new exposure measures
**********************************************************************/

forvalues i = 1/3 {

    local markettype : word `i' of `markettypes'
    local fieldvar   : word `i' of `fieldvars'

    forvalues g = 1/3 {

        local geotype : word `g' of `geotypes'
        local geoid   : word `g' of `geoidvars'
        local geoname : word `g' of `geonamevars'

        tempfile ///
            entrant_programs ///
            incumbent_programs ///
            all_programs ///
            p_programs ///
            kd_exposure

        di as text ///
            "------------------------------------------------------------"

        di as result ///
            "Kernel denominator: `markettype' × `geotype'"


        /**************************************************************
        * 4.1 Entrant programs: PSU and enrollment, 2009-2011
        **************************************************************/

        use `entrants_pre', clear

        make_text_key `fieldvar', ///
            generate(field_pre)

        rename `geoid' ///
            geo_pre

        rename `geoname' ///
            geo_name_pre

        drop if ///
            field_pre == "" | ///
            missing(geo_pre)

        gen double psu_sum = ///
            mean_psu_lm_firstyear * ///
            n_firstyear_psu ///
            if ///
                !missing(mean_psu_lm_firstyear) & ///
                n_firstyear_psu > 0

        replace psu_sum = 0 ///
            if missing(psu_sum)

        collapse ///
            (sum) ///
                l_n3 = N_firstyear ///
                l_psu_n3 = n_firstyear_psu ///
                psu_sum, ///
            by( ///
                codigo_unico ///
                field_pre ///
                geo_pre ///
            )

        gen double l_psu_pre = ///
            psu_sum / ///
            l_psu_n3 ///
            if l_psu_n3 > 0

        drop psu_sum

        gen byte l_entrant = 1

        /*
        codigo_unico is no longer needed.
        We do not create source_id because incumbent and entrant
        programs use identifiers of different types.
        */

        keep ///
            field_pre ///
            geo_pre ///
            l_n3 ///
            l_psu_n3 ///
            l_psu_pre ///
            l_entrant

        save `entrant_programs', replace


        /**************************************************************
        * 4.2 Incumbent programs: PSU and enrollment, 2009-2011
        *
        * Start from the validated output of 03b.
        **************************************************************/

        use ///
            "$processed/sua_incumbent_panel_w_`markettype'_`geotype'_2007_2016.dta", ///
            clear

        keep if inrange(ao_proceso, 2009, 2011)

        drop if missing( ///
            program_id, ///
            field_pre, ///
            geo_pre ///
        )

        gen double psu_sum = ///
            mean_psu_lm_firstyear * ///
            n_firstyear_psu ///
            if ///
                !missing(mean_psu_lm_firstyear) & ///
                n_firstyear_psu > 0

        replace psu_sum = 0 ///
            if missing(psu_sum)

        collapse ///
            (sum) ///
                l_n3 = N_firstyear_incumbent ///
                l_psu_n3 = n_firstyear_psu ///
                psu_sum, ///
            by( ///
                program_id ///
                field_pre ///
                geo_pre ///
            )

        gen double l_psu_pre = ///
            psu_sum / ///
            l_psu_n3 ///
            if l_psu_n3 > 0

        drop psu_sum

        gen byte l_entrant = 0

        /*
        program_id is also no longer needed in the pool of programs l.
        */

        keep ///
            field_pre ///
            geo_pre ///
            l_n3 ///
            l_psu_n3 ///
            l_psu_pre ///
            l_entrant

        save `incumbent_programs', replace


        /**************************************************************
        * 4.3 Pool of all programs l in the market
        *
        * Denominator:
        *   incumbents + entrants
        **************************************************************/

        use `incumbent_programs', clear

        append using `entrant_programs'

        assert ///
            l_n3 >= 0 ///
            if !missing(l_n3)

        gen byte l_has_psu = ///
            !missing(l_psu_pre)

        save `all_programs', replace


        /**************************************************************
        * 4.4 Incumbent programs p
        *
        * One observation per p.
        **************************************************************/

        use ///
            "$processed/sua_incumbent_panel_w_`markettype'_`geotype'_2007_2016.dta", ///
            clear

        keep ///
            program_id ///
            field_pre ///
            geo_pre ///
            market_pre ///
            inc_psu_pre ///
            exp_unw ///
            exp_tri50 ///
            exp_gau50 ///
            total_n3_mkt

        drop if missing( ///
            program_id, ///
            field_pre, ///
            geo_pre ///
        )

        duplicates drop

        isid program_id

        save `p_programs', replace


        /**************************************************************
        * 4.5 Form incumbent p × program l pairs
        *
        * Same market definition as in 03b:
        * field × pre-treatment geography.
        **************************************************************/

        use `p_programs', clear

        joinby ///
            field_pre ///
            geo_pre ///
            using `all_programs'


        /**************************************************************
        * 4.6 PSU distance between p and l
        **************************************************************/

        gen double psu_gap_pl = ///
            abs(inc_psu_pre - l_psu_pre) ///
            if ///
                !missing(inc_psu_pre) & ///
                !missing(l_psu_pre)


        /**************************************************************
        * 4.7 Kernels for p-l pairs
        **************************************************************/

        gen double w_tri_pl = ///
            max(0, 1 - psu_gap_pl / `h') ///
            if !missing(psu_gap_pl)

        gen double w_gau_pl = ///
            exp(-0.5 * (psu_gap_pl / `h')^2) ///
            if !missing(psu_gap_pl)


        /**************************************************************
        * 4.8 Denominator components
        **************************************************************/

        gen double den_tri_part = ///
            w_tri_pl * l_n3 ///
            if !missing(w_tri_pl)

        gen double den_gau_part = ///
            w_gau_pl * l_n3 ///
            if !missing(w_gau_pl)

        replace den_tri_part = 0 ///
            if missing(den_tri_part)

        replace den_gau_part = 0 ///
            if missing(den_gau_part)


        /**************************************************************
        * 4.9 Numerator components
        *
        * Entrant programs q only.
        **************************************************************/

        gen double num_tri_part = ///
            den_tri_part * l_entrant

        gen double num_gau_part = ///
            den_gau_part * l_entrant


        /**************************************************************
        * 4.10 PSU coverage of the denominator
        **************************************************************/

        gen double n_psu_part = ///
            l_n3 ///
            if l_has_psu == 1

        replace n_psu_part = 0 ///
            if missing(n_psu_part)

        gen double n_all_part = ///
            l_n3

        replace n_all_part = 0 ///
            if missing(n_all_part)


        /**************************************************************
        * 4.11 Collapse to incumbent program p
        **************************************************************/

        collapse ///
            (sum) ///
                num_tri50 = num_tri_part ///
                num_gau50 = num_gau_part ///
                den_tri50 = den_tri_part ///
                den_gau50 = den_gau_part ///
                den_n_psu = n_psu_part ///
                den_n_all = n_all_part ///
            (firstnm) ///
                market_pre ///
                inc_psu_pre ///
                exp_unw ///
                exp_tri50 ///
                exp_gau50 ///
                total_n3_mkt, ///
            by(program_id)

        isid program_id


        /**************************************************************
        * 4.12 New exposure with kernel-weighted denominator
        **************************************************************/

        gen double exp_tri50kd = ///
            num_tri50 / ///
            den_tri50 ///
            if den_tri50 > 0

        gen double exp_gau50kd = ///
            num_gau50 / ///
            den_gau50 ///
            if den_gau50 > 0


        /**************************************************************
        * 4.13 Denominator coverage
        **************************************************************/

        gen double den_psu_cov = ///
            den_n_psu / ///
            den_n_all ///
            if den_n_all > 0


        /**************************************************************
        * 4.14 Main validations
        **************************************************************/

        /*
        Entrants are a subset of all programs.
        */

        assert ///
            num_tri50 <= den_tri50 + 1e-10 ///
            if !missing(num_tri50, den_tri50)

        assert ///
            num_gau50 <= den_gau50 + 1e-10 ///
            if !missing(num_gau50, den_gau50)


        /*
        Exposure must lie between 0 and 1.
        */

        assert inrange( ///
            exp_tri50kd, ///
            0, ///
            1.0000001 ///
        ) if !missing(exp_tri50kd)

        assert inrange( ///
            exp_gau50kd, ///
            0, ///
            1.0000001 ///
        ) if !missing(exp_gau50kd)


        /*
        PSU coverage must lie between 0 and 1.
        */

        assert inrange( ///
            den_psu_cov, ///
            0, ///
            1.0000001 ///
        ) if !missing(den_psu_cov)


        /**************************************************************
        * 4.15 Save program-level measure
        **************************************************************/

        keep ///
            program_id ///
            num_tri50 ///
            num_gau50 ///
            den_tri50 ///
            den_gau50 ///
            den_psu_cov ///
            exp_tri50kd ///
            exp_gau50kd

        save `kd_exposure', replace


        /**************************************************************
        * 4.16 Merge onto the original 03b panel
        **************************************************************/

        use ///
            "$processed/sua_incumbent_panel_w_`markettype'_`geotype'_2007_2016.dta", ///
            clear

        merge m:1 ///
            program_id ///
            using `kd_exposure', ///
            keep(master match) ///
            generate(_merge_kd)

        gen byte has_kden = ///
            _merge_kd == 3

        drop _merge_kd


        /**************************************************************
        * 4.17 Post-2012 interactions
        *
        * One unit = 10 percentage points.
        **************************************************************/

        gen double z_tri50kd10 = ///
            10 * exp_tri50kd * post2012 ///
            if !missing(exp_tri50kd)

        gen double z_gau50kd10 = ///
            10 * exp_gau50kd * post2012 ///
            if !missing(exp_gau50kd)


        /**************************************************************
        * 4.18 Labels
        **************************************************************/

        label variable num_tri50 ///
            "Triangular weighted entrant enrollment"

        label variable num_gau50 ///
            "Gaussian weighted entrant enrollment"

        label variable den_tri50 ///
            "Triangular weighted total enrollment"

        label variable den_gau50 ///
            "Gaussian weighted total enrollment"

        label variable den_psu_cov ///
            "Enrollment share with PSU in kernel denominator"

        label variable exp_tri50kd ///
            "Triangular exposure, kernel denominator, h=50"

        label variable exp_gau50kd ///
            "Gaussian exposure, kernel denominator, h=50"

        label variable z_tri50kd10 ///
            "10 p.p. triangular KD exposure x post-2012"

        label variable z_gau50kd10 ///
            "10 p.p. Gaussian KD exposure x post-2012"


        /**************************************************************
        * 4.19 Verify that exposure is fixed within program
        **************************************************************/

        isid ///
            program_id ///
            ao_proceso

        bysort program_id: ///
            assert exp_tri50kd == exp_tri50kd[1] ///
            if !missing(exp_tri50kd)

        bysort program_id: ///
            assert exp_gau50kd == exp_gau50kd[1] ///
            if !missing(exp_gau50kd)


        /**************************************************************
        * 4.20 Order variables and save new panel
        **************************************************************/

        order ///
            program_id ///
            ao_proceso ///
            sigla_universidad ///
            demre_code_h ///
            nombre_carrera ///
            sede_carrera ///
            market_type_w ///
            geo_type_w ///
            market_year ///
            field_pre ///
            geo_pre ///
            geo_name_pre ///
            market_pre ///
            inc_psu_pre ///
            inc_psu_cov ///
            ent_psu_cov ///
            den_psu_cov ///
            exp_unw ///
            exp_tri50 ///
            exp_gau50 ///
            exp_tri50kd ///
            exp_gau50kd ///
            post2012 ///
            z_unw10 ///
            z_tri10 ///
            z_gau10 ///
            z_tri50kd10 ///
            z_gau50kd10 ///
            N_firstyear_incumbent

        sort ///
            program_id ///
            ao_proceso

        compress

        local output ///
            "$processed/sua_incumbent_panel_kd_`markettype'_`geotype'_2007_2016.dta"

        save "`output'", replace


        /**************************************************************
        * 4.21 Coverage summary
        **************************************************************/

        egen byte tag_program = ///
            tag(program_id)

        quietly count if ///
            tag_program == 1

        local n_programs = r(N)

        quietly count if ///
            tag_program == 1 & ///
            has_kden == 1

        local n_kden = r(N)


        quietly summarize ///
            exp_tri50 ///
            if tag_program == 1

        local mean_tri_old = r(mean)


        quietly summarize ///
            exp_tri50kd ///
            if tag_program == 1

        local mean_tri_kd = r(mean)


        quietly summarize ///
            exp_gau50 ///
            if tag_program == 1

        local mean_gau_old = r(mean)


        quietly summarize ///
            exp_gau50kd ///
            if tag_program == 1

        local mean_gau_kd = r(mean)


        quietly summarize ///
            den_psu_cov ///
            if tag_program == 1

        local mean_den_cov = r(mean)


        post `covpost' ///
            ("`markettype'") ///
            ("`geotype'") ///
            (`n_programs') ///
            (`n_kden') ///
            (`mean_tri_old') ///
            (`mean_tri_kd') ///
            (`mean_gau_old') ///
            (`mean_gau_kd') ///
            (`mean_den_cov')


        di as result ///
            "`markettype' × `geotype' guardado."

    }
}


postclose `covpost'


/**********************************************************************
* 5. Save coverage summary
**********************************************************************/

use `coverage', clear

gen byte market_order = .

replace market_order = 1 ///
    if market_type == "broad_area"

replace market_order = 2 ///
    if market_type == "cine_subarea"

replace market_order = 3 ///
    if market_type == "generic_area"


gen byte geo_order = .

replace geo_order = 1 ///
    if geo_type == "region"

replace geo_order = 2 ///
    if geo_type == "provincia"

replace geo_order = 3 ///
    if geo_type == "comuna"


sort ///
    market_order ///
    geo_order


format ///
    mean_tri_old ///
    mean_tri_kd ///
    mean_gau_old ///
    mean_gau_kd ///
    mean_den_cov ///
    %9.3f


list, ///
    noobs ///
    clean ///
    separator(3)


save ///
    "$processed/sua_kernelden_exposure_coverage.dta", ///
    replace


di as result ///
    "Kernel-denominator exposures constructed for nine markets."