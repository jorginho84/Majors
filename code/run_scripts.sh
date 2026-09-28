#!/usr/bin/env bash
# Run a list of Stata do-files in order, with the same logging and failure
# detection as run_pipeline.sh. Stops at the first failure.
#
# Usage (from project root, on the server):
#   screen -dmS vs bash code/run_scripts.sh vs code/Vacancy_shocks/01_x.do code/Vacancy_shocks/02_y.do
#
# The first argument is a tag; logs go to logs/<tag>/ and status to
# logs/<tag>/status.txt.

set -u
cd "$(dirname "$0")/.."

STATA=${STATA:-/usr/local/stata17/stata-mp}
TAG=$1; shift
LOGDIR=logs/$TAG
STATUS=$LOGDIR/status.txt
mkdir -p "$LOGDIR"

echo "# started $(date '+%F %T')" >> "$STATUS"
for s in "$@"; do
  name=$(basename "$s" .do | tr ' ' '_')
  wrapper="$LOGDIR/$name.do"
  printf 'do "%s"\n' "$s" > "$wrapper"
  t0=$(date +%s)
  "$STATA" -b do "$wrapper" > /dev/null 2>&1
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
  case "$result" in OK) ;; *) break ;; esac
done
echo "# finished $(date '+%F %T')" >> "$STATUS"
