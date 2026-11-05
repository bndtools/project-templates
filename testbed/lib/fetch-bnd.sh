#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/common.sh"
spec="${1:?bnd version or JAR required}"
cache="${2:-$here/../.cache}"
java="${JAVA_HOME:+$JAVA_HOME/bin/}java"

if [[ -f "$spec" ]]; then
  printf '%s/%s\n' "$(cd "$(dirname "$spec")" && pwd)" "$(basename "$spec")"
  exit 0
fi
[[ "$spec" != *.jar ]] || die "bnd CLI JAR not found: $spec"
[[ "$spec" =~ ^(release|snapshot|rc|--matrix|--list-rc|[0-9]+\.[0-9]+\.[0-9]+(-RC[0-9]+|-SNAPSHOT)?)$ ]] || die "invalid bnd version: $spec" 2
require_cmd curl
mkdir -p "$cache"
cache="$(cd "$cache" && pwd)"
temporary="$(mktemp -d "$cache/download.XXXXXX")"
trap 'rm -rf -- "$temporary"' EXIT
curl_options=()
if [[ -n "${TESTBED_CURL_OPTS:-}" ]]; then
  IFS=' ' read -r -a curl_options <<< "$TESTBED_CURL_OPTS"
fi
fetch() {
  local error="$temporary/curl-error" exit_code=0
  curl --fail --silent --show-error --location --retry 3 --connect-timeout 30 --max-time 180 \
    "${curl_options[@]}" --output "$2" "$1" 2> "$error" || exit_code=$?
  # Windows Schannel behind TLS interception: certificate still verified, only revocation lookup skipped.
  if (( exit_code == 35 )) && grep -q CRYPT_E_NO_REVOCATION_CHECK "$error"; then
    err "revocation check unavailable for $1; retrying with --ssl-no-revoke"
    exit_code=0
    curl_options+=(--ssl-no-revoke)
    curl --fail --silent --show-error --location --retry 3 --connect-timeout 30 --max-time 180 \
      "${curl_options[@]}" --output "$2" "$1" 2> "$error" || exit_code=$?
  fi
  if (( exit_code != 0 )); then
    cat "$error" >&2
    die "download failed ($exit_code): $1"
  fi
}
metadata() { "$java" "$(native_path "$here/Xml.java")" metadata "$(native_path "$1")" "$2"; }

if [[ "$spec" == --matrix || "$spec" == --list-rc || "$spec" == rc ]]; then
  fetch 'https://repo.maven.apache.org/maven2/biz/aQute/bnd/biz.aQute.bnd/maven-metadata.xml' "$temporary/release.xml"
  fetch 'https://bndtools.jfrog.io/bndtools/libs-release/biz/aQute/bnd/biz.aQute.bnd/maven-metadata.xml' "$temporary/candidates.xml"
  selected_rc="$("$java" "$(native_path "$here/Xml.java")" rc "$(native_path "$temporary/release.xml")" "$(native_path "$temporary/candidates.xml")")"
  if [[ "$spec" == --matrix ]]; then
    printf 'release\n'
    [[ -z "$selected_rc" ]] || printf '%s\n' "$selected_rc"
    printf 'snapshot\n'
    exit 0
  elif [[ "$spec" == --list-rc ]]; then
    [[ -z "$selected_rc" ]] || printf '%s\n' "$selected_rc"
    exit 0
  fi
  [[ -n "$selected_rc" ]] || die 'no release candidate newer than latest release'
  spec="$selected_rc"
fi

base='https://repo.maven.apache.org/maven2/biz/aQute/bnd/biz.aQute.bnd'
version="$spec"
if [[ "$spec" == snapshot || "$spec" == *-SNAPSHOT ]]; then
  base='https://bndtools.jfrog.io/bndtools/libs-snapshot/biz/aQute/bnd/biz.aQute.bnd'
elif [[ "$spec" == *-RC* ]]; then
  base='https://bndtools.jfrog.io/bndtools/libs-release/biz/aQute/bnd/biz.aQute.bnd'
fi
if [[ "$spec" == release || "$spec" == snapshot ]]; then
  fetch "$base/maven-metadata.xml" "$temporary/metadata.xml"
  field=release
  [[ "$spec" != snapshot ]] || field=latest
  version="$(metadata "$temporary/metadata.xml" "$field")"
fi
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-RC[0-9]+|-SNAPSHOT)?$ ]] || die "invalid version in metadata: $version"
artifact_version="$version"
if [[ "$version" == *-SNAPSHOT ]]; then
  fetch "$base/$version/maven-metadata.xml" "$temporary/snapshot.xml"
  artifact_version="$(metadata "$temporary/snapshot.xml" snapshot)"
  [[ "$artifact_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+-[0-9]{8}\.[0-9]{6}-[0-9]+$ ]] || die 'invalid snapshot version'
fi
jar="$cache/biz.aQute.bnd-$artifact_version.jar"
if [[ ! -s "$jar" ]]; then
  err "downloading bnd $artifact_version"
  fetch "$base/$version/biz.aQute.bnd-$artifact_version.jar" "$temporary/bnd.jar"
  mv -- "$temporary/bnd.jar" "$jar"
fi
printf '%s\n' "$jar"