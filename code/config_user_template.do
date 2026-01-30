/*------------------------------------------------------------------------------
                    User-Specific Configuration Template

                    INSTRUCTIONS:
                    1. Copy this file to: config_user.do
                    2. Edit the paths below to match your setup
                    3. config_user.do is gitignored, so your paths won't affect others

                    This file is loaded by config.do if it exists.
------------------------------------------------------------------------------*/

* Set your root project path
* Examples:
*   - Server:  global root "/home/jrodriguezo/majors"
*   - Mac:     global root "/Users/yourname/Research/Majors"
*   - Windows: global root "C:/Users/yourname/Research/Majors"

global root "/path/to/your/majors/folder"

* If your raw data is in a different location than $root/data, uncomment and edit:
* global data "/path/to/data"

* If you have subdirectories organized differently, uncomment and edit:
* global psu_raw      "$data/PSU_scores"
* global app_raw      "$data/MINEDUC/Applications"
* global mat_raw      "$data/MINEDUC/Matricula Educacion Superior"
* global tit_raw      "$data/MINEDUC/Base Titulados"
