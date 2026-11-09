#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

: "${here:?source from testbed.sh}" "${bnd_spec:?}" "${workspace:?}" "${work:?}" "${skip_run:?}"

for tool in java timeout; do require_cmd "$tool"; done
java="${JAVA_HOME:+$JAVA_HOME/bin/}java"
require_cmd "$java"
java_version="$("$java" -version 2>&1)"
java_version="${java_version%%$'\n'*}"
java_major="$(printf '%s\n' "$java_version" | sed -E 's/.*"([0-9]+).*/\1/')"
[[ "$java_major" =~ ^[0-9]+$ ]] && (( java_major >= 17 )) || die "Java 17+ required: $java_version" 2
bnd_jar="$(bash "$here/lib/fetch-bnd.sh" "$bnd_spec" "${TESTBED_CACHE_DIR:-$here/.cache}")"
bnd_jar="$(native_path "$bnd_jar")"
bnd_version="$("$java" -jar "$bnd_jar" version)"
bnd_version="${bnd_version//$'\r'/}"

probe="$workspace/template-launch-probe"
mkdir -p "$probe/src/main/java/template/smoke"
cp "$here/lib/LaunchProbe.java" "$probe/src/main/java/template/smoke/LaunchProbe.java"
printf 'Bundle-SymbolicName: template-launch-probe\nBundle-Version: 1.0.0\nBundle-Activator: template.smoke.LaunchProbe\n-buildpath: osgi.core\n-privatepackage: template.smoke\njavac.source: 8\njavac.target: 8\n' > "$probe/bnd.bnd"

command_step() {
  local step="$1" subject="$2" directory="$3" seconds="$4" exit_code=0
  shift 4
  step_number=$((step_number + 1))
  last_log="$(printf '%s/logs/%02d-%s.log' "$work" "$step_number" "$step")"
  {
    printf 'Directory: %s; Subject: %s\nCommand:' "$directory" "$subject"
    printf ' %q' "$@"
    printf '\n\n'
  } > "$last_log"
  (cd "$directory" && timeout --kill-after=5s "${seconds}s" "$@") >> "$last_log" 2>&1 < /dev/null || exit_code=$?
  printf '\nExit code: %s\n' "$exit_code" >> "$last_log"
  last_exit="$exit_code"
  return 0
}

check_command() {
  command_step "$@"
  local status=PASS
  (( last_exit == 0 )) || status=FAIL
  record "$1" "$2" "$status" "$last_exit" "$last_log"
}

projects=(api app ds integration-test jax-rs jpa-dao servlet launch-probe)
for name in "${projects[@]}"; do
  check_command build "template-$name" "$workspace/template-$name" 180 "$java" -jar "$bnd_jar" build
done

for name in ds jax-rs servlet; do
  project="$workspace/template-$name"
  check_command test-build "template-$name" "$project" 180 "$java" -jar "$bnd_jar" build --test
  if (( last_exit != 0 )); then continue; fi
  command_step classpath "template-$name" "$project" 180 "$java" -jar "$bnd_jar" classpath --testpath
  if (( last_exit != 0 )); then
    record classpath "template-$name" FAIL "$last_exit" "$last_log"
    continue
  fi
  classpath="$(sed '1,3d; /^Exit code:/d' "$last_log" | tr -d '\r\n')"
  separator=:
  if is_windows; then separator=';'; fi
  classpath+="$separator$(native_path "$project/bin_test")"
  command_step junit "template-$name" "$project" 180 "$java" -cp "$classpath" org.junit.runner.JUnitCore org.bndtools.templates.smoke.ExampleTest
  status=FAIL
  if (( last_exit == 0 )) && grep -Eq 'OK \([1-9][0-9]* tests?\)' "$last_log"; then status=PASS; fi
  record junit "template-$name" "$status" "$last_exit" "$last_log" 'requires nonzero successful test count'
done

project="$workspace/template-integration-test"
check_command integration-test template-integration-test "$project" 180 "$java" -jar "$bnd_jar" test
reports=()
while IFS= read -r -d '' report; do reports+=("$(native_path "$report")"); done < <(find "$project" -name 'TEST-*.xml' -type f -print0)
if (( ${#reports[@]} )); then
  check_command junit-xml template-integration-test "$project" 60 "$java" "$(native_path "$here/lib/Xml.java")" junit "${reports[@]}"
else
  record junit-xml template-integration-test FAIL 1 '-' 'no JUnit XML reports'
fi

launches=(template-app/template-app.bndrun template-ds/launch.bndrun template-jax-rs/launch.bndrun template-servlet/launch.bndrun template-launch-probe/template-launch.bndrun)
for relative in "${launches[@]}"; do
  check_command resolve "$relative" "$workspace" 180 "$java" -jar "$bnd_jar" resolve resolve -W "$relative"
  if (( skip_run )); then
    record run "$relative" SKIP 0 '-' 'skip-run requested'
  elif (( last_exit != 0 )); then
    record run "$relative" SKIP 0 '-' 'resolution failed'
  else
    marker="$work/smoke-$((step_number + 1)).marker"
    rm -f -- "$marker"
    TEMPLATE_SMOKE_MARKER="$(native_path "$marker")"
    export TEMPLATE_SMOKE_MARKER
    command_step run "$relative" "$workspace" 60 "$java" -jar "$bnd_jar" run "$relative"
    unset TEMPLATE_SMOKE_MARKER
    status=FAIL
    if (( last_exit <= 1 )) && [[ -f "$marker" ]]; then
      if ! grep -q '^Errors' "$last_log" || grep -q 'Exit code remote process 117:' "$last_log"; then status=PASS; fi
    fi
    record run "$relative" "$status" "$last_exit" "$last_log" 'requires startup marker'
  fi
done