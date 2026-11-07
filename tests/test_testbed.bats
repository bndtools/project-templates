#!/usr/bin/env bats

setup() {
  repo="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  runner="$repo/testbed/testbed.sh"
  output="$BATS_TEST_TMPDIR/output with spaces"
  real_java="${JAVA_HOME:+$JAVA_HOME/bin/}java"
  mkdir -p "$BATS_TEST_TMPDIR/jdk/bin"
  cp "$BATS_TEST_DIRNAME/fixtures/testbed/java" "$BATS_TEST_TMPDIR/jdk/bin/java"
  chmod +x "$BATS_TEST_TMPDIR/jdk/bin/java"
  export JAVA_HOME="$BATS_TEST_TMPDIR/jdk"
  export TESTBED_CACHE_DIR="$BATS_TEST_TMPDIR/cache"
  jar="$BATS_TEST_TMPDIR/mock.jar"
  touch "$jar"
}

mock_downloads() {
  curl() {
    local destination=""
    while (( $# )); do
      if [[ "$1" == --output ]]; then
        destination="$2"
        shift 2
      else
        shift
      fi
    done
    printf 'mock download\n' > "$destination"
  }
  export -f curl
}

@test "help needs no Python or bnd" {
  run bash "$runner" --help
  [[ "$status" == 0 ]]
  [[ "$output" == *'--render-only'* ]]
}

@test "missing option value exits with usage error" {
  run bash "$runner" --bnd
  [[ "$status" == 2 ]]
  [[ "$output" == *'missing value'* ]]
}

@test "nonempty output is never overwritten" {
  directory="$BATS_TEST_TMPDIR/existing"
  mkdir -p "$directory"
  printf keep > "$directory/keep.txt"
  run bash "$runner" --work-dir "$directory" --render-only
  [[ "$status" == 2 ]]
  [[ "$(< "$directory/keep.txt")" == keep ]]
}

@test "all templates render without build output or unresolved variables" {
  directory="$BATS_TEST_TMPDIR/render"
  run bash "$runner" --render-only --work-dir "$directory"
  [[ "$status" == 0 ]]
  for name in api app ds integration-test jax-rs jpa-dao servlet; do
    [[ -f "$directory/workspace/template-$name/bnd.bnd" ]]
    [[ ! -d "$directory/workspace/template-$name/generated" ]]
  done
  [[ -f "$directory/workspace/template-launch-probe/template-launch.bndrun" ]]
  grep -q 'osgi.ee;osgi.ee=JavaSE;version:Version=1.7.0' "$directory/workspace/template-ds/launch.bndrun"
  grep -q 'osgi.ee;osgi.ee=JavaSE;version:Version=1.8.0' "$directory/workspace/template-ds/launch.bndrun"
  run grep -R -E '\$(srcDir|testSrcDir|basePackageDir|basePackageName|projectName|javaLevel)\$' "$directory/workspace"
  [[ "$status" == 1 ]]
}

@test "successful mock run removes workspace and keeps report and logs" {
  directory="$BATS_TEST_TMPDIR/pass with spaces"
  run bash "$runner" --bnd "$jar" --work-dir "$directory"
  [[ "$status" == 0 ]]
  [[ ! -d "$directory/workspace" ]]
  [[ -f "$directory/REPORT.md" ]]
  [[ -f "$directory/logs/01-build.log" ]]
  [[ -n "$(find "$directory" -name 'smoke-*.marker' -print -quit)" ]]
  grep -q 'Result: \*\*PASS\*\*' "$directory/REPORT.md"
}

@test "keep-all preserves successful workspace" {
  directory="$BATS_TEST_TMPDIR/keep"
  run bash "$runner" --bnd "$jar" --work-dir "$directory" --keep-all
  [[ "$status" == 0 ]]
  [[ -d "$directory/workspace" ]]
}

@test "failed build keeps workspace and records failure" {
  directory="$BATS_TEST_TMPDIR/fail"
  export TESTBED_MOCK_FAIL_BUILD=1
  run bash "$runner" --bnd "$jar" --work-dir "$directory"
  [[ "$status" == 1 ]]
  [[ -d "$directory/workspace" ]]
  grep -q 'Result: \*\*FAIL\*\*' "$directory/REPORT.md"
  grep -q $'build\ttemplate-ds\tFAIL' "$directory/results.tsv"
}

@test "skip-run resolves but does not launch applications" {
  directory="$BATS_TEST_TMPDIR/skip"
  run bash "$runner" --bnd "$jar" --work-dir "$directory" --skip-run
  [[ "$status" == 0 ]]
  grep -q $'resolve\ttemplate-servlet/launch.bndrun\tPASS' "$directory/results.tsv"
  grep -q $'run\ttemplate-servlet/launch.bndrun\tSKIP' "$directory/results.tsv"
  [[ -z "$(find "$directory/logs" -name '*-run.log' -print -quit)" ]]
}

@test "missing local JAR fails without downloading" {
  run bash "$repo/testbed/lib/fetch-bnd.sh" "$BATS_TEST_TMPDIR/missing.jar" "$BATS_TEST_TMPDIR/cache"
  [[ "$status" == 1 ]]
  [[ "$output" == *'JAR not found'* ]]
}

@test "JDK XML parser rejects zero tests and accepts nonzero passing tests" {
  report="$BATS_TEST_TMPDIR/tests.xml"
  printf '<testsuite tests="0" failures="0" errors="0"/>' > "$report"
  run "$real_java" "$repo/testbed/lib/Xml.java" junit "$report"
  [[ "$status" != 0 ]]
  printf '<testsuite tests="1" failures="0" errors="0"/>' > "$report"
  run "$real_java" "$repo/testbed/lib/Xml.java" junit "$report"
  [[ "$status" == 0 ]]
}

@test "JDK XML parser rejects failed tests and external entities" {
  report="$BATS_TEST_TMPDIR/tests.xml"
  printf '<testsuite tests="1" failures="1" errors="0"/>' > "$report"
  run "$real_java" "$repo/testbed/lib/Xml.java" junit "$report"
  [[ "$status" != 0 ]]
  printf '<!DOCTYPE testsuite SYSTEM "file:///does-not-exist"><testsuite tests="1"/>' > "$report"
  run "$real_java" "$repo/testbed/lib/Xml.java" junit "$report"
  [[ "$status" != 0 ]]
}

@test "RC selection chooses numerically newest candidate newer than release" {
  release="$BATS_TEST_TMPDIR/release.xml"
  candidates="$BATS_TEST_TMPDIR/candidates.xml"
  printf '<metadata><versioning><release>7.4.0</release></versioning></metadata>' > "$release"
  printf '<metadata><versioning><versions><version>7.3.0-RC99</version><version>7.4.0-RC1</version><version>7.5.0-RC10</version><version>7.5.0-RC2</version><version>7.5.0-SNAPSHOT</version></versions></versioning></metadata>' > "$candidates"
  run "$real_java" "$repo/testbed/lib/Xml.java" rc "$release" "$candidates"
  [[ "$status" == 0 ]]
  [[ "$output" == 7.5.0-RC10 ]]
}

@test "RC selection omits candidates older than or belonging to current release" {
  release="$BATS_TEST_TMPDIR/release.xml"
  candidates="$BATS_TEST_TMPDIR/candidates.xml"
  printf '<metadata><versioning><release>7.5.0</release></versioning></metadata>' > "$release"
  printf '<metadata><versioning><versions><version>7.4.0-RC9</version><version>7.5.0-RC20</version></versions></versioning></metadata>' > "$candidates"
  run "$real_java" "$repo/testbed/lib/Xml.java" rc "$release" "$candidates"
  [[ "$status" == 0 ]]
  [[ -z "$output" ]]
}

@test "default matrix omits RC when no newer candidate exists" {
  mock_downloads
  directory="$BATS_TEST_TMPDIR/matrix without rc"
  run bash "$runner" --work-dir "$directory"
  [[ "$status" == 0 ]]
  [[ -f "$directory/release/REPORT.md" ]]
  [[ -f "$directory/snapshot/REPORT.md" ]]
  [[ "$(wc -l < "$directory/results.tsv")" == 3 ]]
  grep -q '(release/REPORT.md)' "$directory/REPORT.md"
  grep -q '(snapshot/REPORT.md)' "$directory/REPORT.md"
}

@test "matrix includes newer RC and continues after failed release" {
  mock_downloads
  export TESTBED_MOCK_RC=7.5.0-RC1
  export TESTBED_MOCK_FAIL_BUILD=1
  directory="$BATS_TEST_TMPDIR/matrix with rc"
  run bash "$runner" --work-dir "$directory"
  [[ "$status" == 1 ]]
  [[ -d "$directory/release/workspace" ]]
  [[ -f "$directory/7.5.0-RC1/REPORT.md" ]]
  [[ -f "$directory/snapshot/REPORT.md" ]]
  [[ "$(wc -l < "$directory/results.tsv")" == 4 ]]
  grep -q 'Result: \*\*FAIL\*\*' "$directory/REPORT.md"
}