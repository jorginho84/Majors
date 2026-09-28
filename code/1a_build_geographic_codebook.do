// Build geographic codebook (comuna -> provincia -> region), LOCAL version
// Insumo: codigos territoriales oficiales SUBDERE (CUT 2018)
// Fuente: https://www.subdere.gov.cl (Codigos Unicos Territoriales)
// Genera: ${build_data}/geographic_codebook.dta

clear all

// Import the raw territorial codes
import excel "${dataraw}/Codigos Provincia/CUT_2018_v04.xls", sheet("Sheet 1") firstrow clear

// Clean non-ASCII characters in variable names
capture rename Región          Region
capture rename CódigoRegión    CodigoRegion
capture rename NombreRegión    NombreRegion
capture rename CódigoProvincia CodigoProvincia
capture rename CódigoComuna    CodigoComuna
capture rename NombreComuna    NombreComuna

// Rename to the names the pipeline expects
rename CodigoComuna    id_comuna
rename CodigoProvincia id_provincia
rename CodigoRegion    id_region
rename NombreProvincia provincia
rename NombreRegion    region
rename NombreComuna    comuna

keep id_comuna id_provincia id_region provincia region comuna
destring id_comuna id_provincia id_region, replace

// Save the geographic codebook used by the 3_create_* do-files
save "${build_data}/geographic_codebook.dta", replace
