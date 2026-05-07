/*------------------------------------------------------------------------------
                    User-Specific Configuration Template

                    NOTE: config.do auto-detects known users (jorge-home, jigodoy).
                    Only create this file if your username is not yet recognized.

                    INSTRUCTIONS:
                    1. Copy this file to: config_user.do
                    2. Edit the paths below to match your setup
                    3. config_user.do is gitignored, so your paths won't affect others

                    This file is loaded AFTER auto-detection and overrides it.
------------------------------------------------------------------------------*/

* Set your root project path (where you cloned the repo)
* Examples:
*   - Mac:     global root "/Users/yourname/Research/Majors"
*   - Windows: global root "C:/Users/yourname/Documents/GitHub/Majors"

global root "/path/to/your/majors/folder"

* If your raw data is in a different location than $root/data, set this too:
* global data "C:/Users/yourname/Documents/data"

* If you have subdirectories organized differently, uncomment and edit:
* global psu_raw      "$data/PSU_scores"
* global app_raw      "$data/MINEDUC/Applications"
* global mat_raw      "$data/MINEDUC/Matricula Educacion Superior"
* global tit_raw      "$data/MINEDUC/Base Titulados"
