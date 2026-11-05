#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
source "$here/lib/common.sh"

usage() {
	printf '%s\n' \
		'Usage: bash testbed/testbed.sh [options]' \
		'  --bnd <matrix|jar|version|release|rc|snapshot>  CLI (default: matrix)' \
		'  --workspace <path>                 Workspace supplying cnf (default: this repository)' \
		'  --work-dir <path>                  Empty output directory' \
		'  --keep-all                         Keep successful workspaces too' \
		'  --skip-run                         Build, test and resolve without application launches' \
		'  --render-only                      Generate workspace without running bnd' \
		'  -h, --help                         Show help' \
		'Environment: JAVA_HOME, TESTBED_CURL_OPTS (extra curl options).'
}

bnd_spec=matrix
workspace_source="$repo"
work=""
keep_all=0
skip_run=0
render_only=0
while (( $# )); do
	case "$1" in
		--bnd|--workspace|--work-dir)
			(( $# >= 2 )) && [[ -n "$2" && "$2" != --* ]] || die "missing value for $1" 2
			case "$1" in
				--bnd) bnd_spec="$2" ;;
				--workspace) workspace_source="$2" ;;
				--work-dir) work="$2" ;;
			esac
			shift 2 ;;
		--keep-all) keep_all=1; shift ;;
		--skip-run) skip_run=1; shift ;;
		--render-only) render_only=1; shift ;;
		-h|--help) usage; exit 0 ;;
		*) die "unknown option: $1" 2 ;;
	esac
done

(( BASH_VERSINFO[0] >= 4 )) || die 'bash 4+ required' 2
for tool in perl find tar git; do require_cmd "$tool"; done
[[ -f "$workspace_source/cnf/build.bnd" ]] || die "not a bnd workspace: $workspace_source" 2
workspace_source="$(cd "$workspace_source" && pwd)"
[[ -n "$work" ]] || work="$here/work/$(date +%Y%m%d-%H%M%S)-$$"
if [[ -e "$work" ]]; then
	[[ -d "$work" ]] || die "output is not a directory: $work" 2
	[[ -z "$(find "$work" -mindepth 1 -maxdepth 1 -print -quit)" ]] || die "output directory must be empty: $work" 2
fi
mkdir -p "$work"
work="$(cd "$work" && pwd)"
if [[ "$bnd_spec" == matrix ]] && (( render_only == 0 )); then
	source "$here/lib/matrix.sh"
	exit 0
fi
workspace="$work/workspace"
mkdir -p "$workspace/cnf" "$work/logs"
failed=0
step_number=0
printf 'step\tsubject\tstatus\texit\tlog\tdetail\n' > "$work/results.tsv"

record() {
	local step="$1" subject="$2" status="$3" exit_code="$4" log="$5" detail="${6:-}"
	detail="${detail//$'\t'/ }"
	detail="${detail//$'\n'/ }"
	detail="${detail//$'\r'/}"
	printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$step" "$subject" "$status" "$exit_code" "${log#"$work"/}" "$detail" >> "$work/results.tsv"
	[[ "$status" != FAIL ]] || failed=1
	err "[$status] $step $subject${detail:+: $detail}"
}

finish() {
	local exit_code=$? status=PASS step subject result code log detail
	trap - EXIT
	if (( exit_code != 0 )); then
		record setup testbed FAIL "$exit_code" '-' 'testbed interrupted or setup failed'
	fi
	(( failed == 0 )) || status=FAIL
	if [[ "$status" == PASS ]] && (( keep_all == 0 && render_only == 0 )); then
		rm -rf -- "$workspace"
	fi
	{
		printf '# Project Template Testbed\n\nResult: **%s**\n\n' "$status"
		printf '%s\n' '- Runner: Git Bash / Bash' "- Platform: $(uname -s)" "- Workspace source: $workspace_source" "- bnd: ${bnd_version:-$bnd_spec}" "- Java: ${java_version:-not required for rendering}" "- Revision: $(git -C "$repo" describe --always --dirty 2>/dev/null || printf unknown)"
		printf '\n## Checks\n\n| Step | Subject | Result | Exit | Log | Detail |\n| --- | --- | --- | --- | --- | --- |\n'
		while IFS=$'\t' read -r step subject result code log detail; do
			[[ "$step" != step ]] || continue
			if [[ "$log" != - ]]; then log="[$log]($log)"; fi
			printf '| %s | %s | %s | %s | %s | %s |\n' "$step" "$subject" "$result" "$code" "$log" "${detail//|//}"
		done < "$work/results.tsv"
		[[ ! -d "$workspace" ]] || printf '\n[Retained workspace](workspace/)\n'
	} > "$work/REPORT.md"
	err "$status: $work/REPORT.md"
	if (( failed != 0 )); then exit 1; fi
	exit "$exit_code"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

tar -C "$workspace_source/cnf" --exclude=cache --exclude=local --exclude=release \
	--exclude=templates --exclude=generated --exclude=bin -cf - . | tar -C "$workspace/cnf" -xf -
perl -pi -e 's/^-remoteworkspace\s+true\s*$/-remoteworkspace false\n/' "$workspace/cnf/build.bnd"
printf '\nsrc: src/main/java\ntestsrc: src/test/java\ntestbin: bin_test\n-plugin.99.TestRelease: aQute.bnd.deployer.repository.LocalIndexedRepo; name=TestRelease; pretty=true; local=${build}/test-release\n-releaserepo: TestRelease\n-baselinerepo: TestRelease\n' >> "$workspace/cnf/build.bnd"
perl "$here/lib/templates.pl" "$repo/org.bndtools.templates.osgi/resources/templates" "$workspace"
record render templates PASS 0 '-' '7 project templates and Felix Gogo launch template'

if (( render_only )); then
	record build workspace SKIP 0 '-' 'render-only requested'
	exit 0
fi

source "$here/lib/run.sh"