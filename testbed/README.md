# Project Template Testbed

Git Bash / Bash testbed inspired by `bndtools/workspace-templates`. Exercises
project templates from the working tree, including uncommitted changes, with
a real bnd CLI. Python is not used.

## Usage

Prerequisites: Bash 4+, Java 17+ (JDK), Perl, curl, git, GNU timeout and tar.
Git for Windows supplies the shell utilities. Set `JAVA_HOME` or put Java on
`PATH`. CI uses Java 21. Configured Maven repositories must be reachable.

Run from the repository root in Git Bash:

```bash
bash testbed/testbed.sh
bash testbed/testbed.sh --bnd matrix --work-dir testbed/work/my-matrix
bash testbed/testbed.sh --bnd release
bash testbed/testbed.sh --bnd rc
bash testbed/testbed.sh --bnd snapshot
bash testbed/testbed.sh --bnd 7.5.0-RC1 --keep-all
bash testbed/testbed.sh --bnd /c/tools/biz.aQute.bnd.jar --skip-run
bash testbed/testbed.sh --workspace /c/path/to/bndtools.workspace.min
bash testbed/testbed.sh --render-only
```

The default is a bnd version matrix: latest release, newest release candidate
whose base version is higher than the release (if available), and latest
snapshot. Comparison is numeric, including RC numbers (`RC10` is newer than
`RC2`). An RC belonging to the current or an older release is omitted.
All matrix entries run even if an earlier entry fails.

Use `--bnd release`, `--bnd rc`, `--bnd snapshot`, an explicit version or a JAR
path for a single run. `--bnd rc` fails if no newer candidate exists. To use
the installed CLI, pass `--bnd ~/biz.aQute.bnd.jar`.
Releases are downloaded from Maven Central; release candidates and snapshots use bnd's JFrog repositories.
Downloads are cached in `.cache/` and installed atomically. TLS certificate
verification stays enabled. `TESTBED_CURL_OPTS` accepts space-separated curl
options, for example `--ssl-no-revoke` behind corporate TLS interception.

| Option | Meaning |
| --- | --- |
| `--bnd <matrix\|jar\|version\|release\|rc\|snapshot>` | Version matrix (default) or a single CLI |
| `--workspace <path>` | Copy this workspace's `cnf`; default: this repository |
| `--work-dir <path>` | Empty output directory; default: `testbed/work/<timestamp>-<pid>` |
| `--keep-all` | Keep successful workspaces too |
| `--skip-run` | Skip application launches; still build, test and resolve |
| `--render-only` | Render templates without Java, bnd or network; retain workspace |

Existing output files are never overwritten. Failed workspaces are always kept.
Successful workspaces are removed unless `--keep-all` is set. Logs and reports
remain in both cases. Exit codes: `0` success, `1` failed checks or setup,
`2` invalid arguments detected before setup.

## Checks

- Render API, application, DS, integration-test, JAX-RS, JPA DAO and Servlet
  projects plus the Felix Gogo launch template into one clean workspace.
- Copy `cnf`, excluding caches and local repositories, and configure isolated
  release storage and Maven-style source directories.
- Build all seven projects and a launch probe.
- Compile and execute DS, JAX-RS and Servlet unit tests with JUnitCore; require
  a nonzero successful test count.
- Run integration tests in OSGi; parse JUnit XML and require nonzero tests
  with no failures or errors. No auto-stopping probe is added to integration
  tests, so it cannot interrupt test execution.
- Resolve all five launch configurations and start each successfully resolved
  configuration; require the probe's startup marker. The probe stops the
  framework automatically. Failed resolution skips the corresponding launch.

Bash controls execution, timeouts, results and reports. Perl handles template
substitution; the JDK XML parser handles Maven metadata and JUnit reports.
No additional Perl modules or Java libraries are required.

This checks generated project compatibility, not the Eclipse wizard or the
StringTemplate engine. The renderer substitutes known variables and the
optional Java-level block, targeting Java 8 to match the master templates.
Generated launch configurations advertise JavaSE 7 and 8 capabilities provided
by the required Java 17+ runtime. Placeholder unit-test failures are replaced
with passing assertions in the generated copy only. The launch probe is
injected into run requirements, and the JAX-RS smoke configuration advertises
an additional JAX-RS implementation capability. These checks do not prove HTTP
endpoint behavior or the presence of a working JAX-RS implementation. Template
source files are never modified by a test run.

`--skip-run` still launches the OSGi integration test framework. Application
launches have a 60-second timeout; other CLI commands default to 180 seconds.
Shutdown diagnostic `Exit code remote process 117:` is accepted only with
the startup marker and exit code `0` or `1`.

## Output

After a matrix run, open the top-level `REPORT.md`. It links to each version's
report, logs and retained failure workspace:

```text
testbed/work/<timestamp>-<pid>/
  REPORT.md                 combined matrix overview
  results.tsv               result and report path per bnd version
  logs/                     version discovery and runner logs
  release/REPORT.md         latest release checks
  <version>-RC<n>/REPORT.md  newer RC checks, only when available
  snapshot/REPORT.md        latest snapshot checks
```

For a single CLI run, or inside each matrix entry:

```text
testbed/work/<timestamp>-<pid>/
  REPORT.md       checks and links to command logs and retained workspace
  results.tsv     one result per step, including exit code and log path
  logs/           command, working directory, output and exit code
  workspace/      retained on failure, --keep-all or --render-only
```

The report records bnd and Java versions, platform, Git revision and workspace
source. Failures remain failures; template compatibility bugs are not hidden.
`TESTBED_CACHE_DIR` can override the default download cache.

## Regression Tests And CI

With [Bats Core](https://github.com/bats-core/bats-core) installed:

```bash
bats tests/test_testbed.bats
```

Tests cover rendering, argument validation, successful and failed mock CLI
runs, workspace retention and real JDK XML parsing. The mock CLI needs no
network or Maven dependencies.

### Independent CI for bnd master

[Poll bnd master](../.github/workflows/poll-bnd-master.yml) checks the public
`bndtools/bnd` master revision every 15 minutes and dispatches
[the source testbed](../.github/workflows/bnd-master.yml) only when that SHA
changes. The source workflow builds the exact commit, uploads its CLI JAR, and
calls this repository's testbed workflow to test the generated templates on
Linux, Windows and macOS. The poller and tests run entirely in this repository;
they do not add credentials, checks or status updates to `bndtools/bnd`.

[GitHub Actions](../.github/workflows/testbed.yml) discovers the same release,
optional newer RC and snapshot matrix, then runs Bats and the real CLI testbed
on Linux, Windows and macOS. Reports, command logs and failed workspaces are
uploaded even when checks fail. The workflow also supports manual dispatch
and a weekly scheduled run.

In GitHub, open **Actions > Project template testbed > a run**. Each matrix
job has a check summary and an artifact named `testbed-<os>-<bnd>`. The
**Combined report** job publishes artifact **testbed-all**: its top-level
`REPORT.md` links to every platform/version report. These CI artifacts exist
only after the workflow has run; local results remain in `testbed/work/`.
