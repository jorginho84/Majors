#!/usr/bin/env bash
# Run the full pipeline in dependency order, one Stata batch job per script.
#
# Usage (from project root, on the server, inside screen):
#   screen -dmS pipeline bash code/run_pipeline.sh
#   screen -r pipeline            # attach;  Ctrl-a d to detach
#
# Each script runs through a one-line wrapper so the log name is predictable
# (Stata names the batch log after the first token of the path, which breaks on
# folders with spaces). Logs land in logs/pipeline/<n>_<script>.log.
#
# A script counts as failed if its log contains an uncaptured error `r(###);`.
# Stata's batch exit code is always 0, so it is not used. The runner keeps going
# after a failure: most branches are independent, and downstream scripts of a
# failed one will fail on their own and show up in the status file.

set -u
cd "$(dirname "$0")/.."

STATA=${STATA:-/usr/local/stata17/stata-mp}
LOGDIR=logs/pipeline
STATUS=$LOGDIR/status.txt
mkdir -p "$LOGDIR"

SCRIPTS=(
  # 1. Clean raw data
  "code/01_clean/01_clean_psu.do"
  "code/01_clean/02_clean_applications.do"
  "code/01_clean/03_clean_enrollment.do"
  "code/01_clean/04_clean_weights.do"
  "code/01_clean/05_clean_demre.do"
  "code/01_clean/06_clean_psu_2017_2018_for_retakes.do"
  "code/01_clean/07_clean_oferta_academica.do"
  # 2. Build analysis datasets
  "code/02_build/01_build_cutoffs.do"
  "code/02_build/02_build_running_var.do"
  "code/02_build/04_build_waiting_list.do"
  "code/02_build/03_build_outcomes.do"
  "code/02_build/05_build_field.do"
  "code/02_build/06_build_graduation_outcomes_8y.do"
  "code/02_build/07_build_graduation_outcomes_10y.do"
  "code/02_build/08_build_selective_programs.do"
  "code/02_build/09_build_enrollment_3y.do"
  "code/02_build/10_build_retakes_psu_2y.do"
  "code/02_build/11_build_program_year_attributes_nextbest.do"
  "code/02_build/12_build_next_best_all_targets_with_attributes.do"
  "code/02_build/13_build_program_year_vacancies.do"
  "code/02_build/14_build_inframarginal_sample_2007_2012.do"
  "code/02_build/14b_build_inframarginal_sample_2013_2016.do"
  # 3. RDD
  "code/04_rdd/01_rdd_enrollment.do"
  "code/04_rdd/02_rdd_figures.do"
  "code/04_rdd/03_rdd_heterogeneity_field.do"
  "code/04_rdd/04_rdd_figures_heterogeneity_field.do"
  "code/04_rdd/05_rdd_graduation.do"
  "code/04_rdd/06_rdd_graduation_figures.do"
  "code/04_rdd/07_rdd_graduation_by_field.do"
  "code/04_rdd/08_combined_rdd_figures_by_field.do"
  "code/04_rdd/09_combined_rdd_graduation_figures_by_field.do"
  "code/04_rdd/10_rdd_graduation_10y.do"
  "code/04_rdd/11_rdd_graduation_10y_figures.do"
  "code/04_rdd/12_rdd_selective.do"
  "code/04_rdd/13_rdd_figures_selective.do"
  "code/04_rdd/14_first_stage_figures_by_delta_groups.do"
  "code/04_rdd/15_rdd_graduates_figures_by_delta_groups.do"
  "code/04_rdd/16_rdd_figures_enrollment_3y.do"
  "code/04_rdd/17_rdd_figure_retakes_psu_2y.do"
  "code/04_rdd/18_rdd_delta_groups_by_field_enrollment_graduation.do"
  "code/04_rdd/19_rdd_figure_retakes_psu_2y_by_field.do"
  "code/04_rdd/20_rdd_same_field_nextbest_enrollment_graduation.do"
  "code/04_rdd/21_compare_inframarginal_two_instruments_full.do"
  "code/04_rdd/field_grad_selectivity_levels.do"
  # 4. Inframarginal design I
  "code/04_rdd/Inframarginals/06b_build_graduation_outcomes_8y.do"
  "code/04_rdd/Inframarginals/21b_inframarginal_rank_panel_enrollment_threshold.do"
  "code/04_rdd/Inframarginals/21c_inframarginal_rank_panel_extended_percentiles.do"
  "code/04_rdd/Inframarginals/21d_inframarginal_log_diagnostics.do"
  "code/04_rdd/Inframarginals/21e_inframarginal_log_firststage_rf_2sls.do"
  "code/04_rdd/Inframarginals/23_graph_2sls_vs_psu_by_university.do"
  "code/04_rdd/Inframarginals/24_program_selectivity_distribution.do"
  "code/04_rdd/Inframarginals/25_program_selectivity_group.do"
  "code/04_rdd/Inframarginals/26_university_heterogeneity_minimum.do"
  "code/04_rdd/Inframarginals/27_field_group_heterogeneity.do"
  "code/04_rdd/Inframarginals/28a_graduation_10y_to_inframarginal.do"
  "code/04_rdd/Inframarginals/28b_inframarginal_panel_grad8y10y.do"
  # 5. Inframarginal design II: SUA entry
  "code/Sua/00_build_validate_sua_roster.do"
  "code/Sua/01_build_sua_program_year_base_revised.do"
  "code/Sua/02_build_sua_markets_exposure.do"
  "code/Sua/03_build_sua_incumbent_panels.do"
  "code/Sua/03b_build_sua_weighted_exposure.do"
  "code/Sua/Sua kernel weights/03d_build_sua_kernel_denominator.do"
  "code/Sua/03c_sua_exposure_enrollment_descriptives.do"
  "code/Sua/Sua_Programs_Graphics.do"
  "code/Sua/SUA_Conditional_Similarity_Distributions.do"
  "code/Sua/04_sua_levels_first_stages.do"
  "code/Sua/04b_sua_log_first_stages.do"
  "code/Sua/04c_sua_exposure_decomposition_test.do"
  "code/Sua/04d_selectivity_groups_diagnostics.do"
  "code/Sua/04e_sua_similarity_log_test.do"
  "code/Sua/04f_sua_Exposure_Q_Selectivity_FirstStages.do"
  "code/Sua/05_event_studies_exposure_comparison.do"
  "code/Sua/05a_sua_log_event_studies.do"
  "code/Sua/05b_sua_similarity_event_studies.do"
  "code/Sua/Sua kernel weights/04g_sua_kernelden_first_stages.do"
  "code/Sua/Sua kernel weights/04h_sua_kernelden_log_first_stages.do"
  "code/Sua/Sua kernel weights/05c_sua_kernelden_event_studies.do"
  "code/Sua/Sua kernel weights/05d_sua_kernelden_log_event_studies.do"
  # 6. SUA cosine exposure
  "code/Sua/Cosine/01_cosine_build_inputs_2011.do"
  "code/Sua/Cosine/02_cosine_build_exposure_measures.do"
  "code/Sua/Cosine/Cosine_Exposure_Distributions.do"
  "code/Sua/Cosine/Cosine_Exposure_Descriptive_Statistics.do"
  "code/Sua/Cosine/03_cosine_estimate_first_stages.do"
  "code/Sua/Cosine/04_cosine_estimate_event_studies.do"
)

# Optional: start from script number N (1-based) to resume after a fix.
START=${1:-1}

echo "# pipeline started $(date '+%F %T')  (from #$START)" >> "$STATUS"
n=0
for s in "${SCRIPTS[@]}"; do
  n=$((n + 1))
  [ "$n" -lt "$START" ] && continue
  name=$(printf '%02d_%s' "$n" "$(basename "$s" .do | tr ' ' '_')")
  wrapper="$LOGDIR/$name.do"
  printf 'do "%s"\n' "$s" > "$wrapper"
  t0=$(date +%s)
  "$STATA" -b do "$wrapper" > /dev/null 2>&1
  # Stata writes <wrapper basename>.log to the working directory
  mv -f "$name.log" "$LOGDIR/$name.log" 2>/dev/null
  rm -f "$wrapper"
  dt=$(( $(date +%s) - t0 ))
  if [ ! -f "$LOGDIR/$name.log" ]; then
    result="NOLOG"
  elif tail -n 15 "$LOGDIR/$name.log" | grep -qE '^r\([0-9]+\);'; then
    result="FAIL $(tail -n 15 "$LOGDIR/$name.log" | grep -oE '^r\([0-9]+\);' | tail -1)"
  else
    result="OK"
  fi
  printf '%-6s %-5ss  %s\n' "$result" "$dt" "$name" | tee -a "$STATUS"
done
echo "# pipeline finished $(date '+%F %T')" >> "$STATUS"
