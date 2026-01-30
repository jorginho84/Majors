***** Generamos bases a nivel de carrera y de año.
*** Postulaciones:

forvalues x = 2007/2015 {
	
	use "\\10.60.214.178\Repositorio_Datos_ADM\REPOSITORIO_RIS\BASES_COMUNES2\MINEDUC\PSU\Formulario_C/`x'/PSU_Formulario_C_`x'_innomi", clear
	rename nuevo_run_falso mrun
	
	save "$temp/applications`x'.dta", replace
	
	}

clear 
forvalues x = 2007/2015 {
	append using "$temp/applications`x'.dta"
	erase "$temp/applications`x'.dta"
}
