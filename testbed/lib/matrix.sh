#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

: "${here:?source from testbed.sh}" "${work:?}" "${workspace_source:?}" "${keep_all:?}" "${skip_run:?}"
matrix_failed=0
mkdir -p "$work/logs"
printf 'version\tresult\texit\treport\tlog\n' > "$work/results.tsv"

matrix_report() {
  local status=PASS version result exit_code report log
  (( matrix_failed == 0 )) || status=FAIL
  {
    printf '# Project Template Testbed Matrix\n\nResult: **%s**\n\n' "$status"
    printf 'Release, newest RC with a higher base version than the release (if any), and latest snapshot.\n\n'
    printf '| bnd | Result | Exit | Report | Runner log |\n| --- | --- | --- | --- | --- |\n'
    while IFS=$'\t' read -r version result exit_code report log; do
      [[ "$version" != version ]] || continue
      if [[ "$report" != - ]]; then report="[REPORT.md]($report)"; fi
      printf '| %s | %s | %s | %s | [%s](%s) |\n' "$version" "$result" "$exit_code" "$report" "$log" "$log"
    done < "$work/results.tsv"
  } > "$work/REPORT.md"
}

matrix_finish() {
  local exit_code=$?
  trap - EXIT
  if (( exit_code != 0 )); then matrix_failed=1; fi
  matrix_report
  err "Matrix report: $work/REPORT.md"
  if (( matrix_failed != 0 )); then exit 1; fi
  exit "$exit_code"
}
trap matrix_finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if ! planned_versions="$(bash "$here/lib/fetch-bnd.sh" --matrix "${TESTBED_CACHE_DIR:-$here/.cache}" 2> "$work/logs/plan.log")"; then
  printf 'plan\tFAIL\t1\t-\tlogs/plan.log\n' >> "$work/results.tsv"
  die "version discovery failed: $(tail -n 1 "$work/logs/plan.log"); see $work/logs/plan.log"
fi
mapfile -t versions <<< "$planned_versions"
flags=()
(( keep_all == 0 )) || flags+=(--keep-all)
(( skip_run == 0 )) || flags+=(--skip-run)
err "bnd matrix: $(IFS=,; printf '%s' "${versions[*]}")"
for version in "${versions[@]}"; do
  err "Starting bnd $version"
  exit_code=0
  bash "$here/testbed.sh" --bnd "$version" --workspace "$workspace_source" \
    --work-dir "$work/$version" "${flags[@]}" > "$work/logs/$version.log" 2>&1 || exit_code=$?
  status=PASS
  if (( exit_code != 0 )); then status=FAIL; matrix_failed=1; fi
  report=-
  [[ ! -f "$work/$version/REPORT.md" ]] || report="$version/REPORT.md"
  printf '%s\t%s\t%s\t%s\t%s\n' "$version" "$status" "$exit_code" "$report" "logs/$version.log" >> "$work/results.tsv"
  err "[$status] bnd $version"
  matrix_report
done