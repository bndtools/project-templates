# What is this Repo?

[![Project template testbed](https://github.com/bndtools/project-templates/actions/workflows/testbed.yml/badge.svg?branch=master)](https://github.com/bndtools/project-templates/actions/workflows/testbed.yml)
[![bnd master project template testbed](https://github.com/bndtools/project-templates/actions/workflows/bnd-master.yml/badge.svg?branch=master)](https://github.com/bndtools/project-templates/actions/workflows/bnd-master.yml)

This repository is the home for the sources of some useful Bndtools Project Templates. These are provided as bundles which you can include in your workspace to add new project templates.

## How do I use these?

You can add the template bundles to any repository in your workspace, but if you use the [Bndtools Workspace Template](https://github.com/bndtools/workspace) then they're included by default.

## Branches and compatibility

Branch `7.5.0` tracks the bnd 7.5 release line.

| Branch | bnd | Java | OSGi API |
|--------|-----|------|----------|
| `7.5.0` | 7.5.0-RC1 | 17 | Core 8.0.0, annotations 8.1.0 |

Generated projects require Java 17, the dependencies in `cnf/build.mvn` and `cnf/runtime.mvn` and the `junit`, `mockito` and `mockito-deps` macros from `cnf/build.bnd` in the consuming workspace.

The Servlet template uses Jakarta Servlet 6.1 and the OSGi Servlet Whiteboard 2.0. The JAX-RS and JPA templates remain `javax` based because no Jakarta-capable Aries JAX-RS Whiteboard or Aries JPA release exists (latest: 2.0.2 and 2.7.3).

## Testing The Templates

The [project template testbed](testbed/README.md) renders the working-tree
templates into a clean workspace, builds and tests the generated projects,
resolves and launches their run configurations, and writes a linked report.

```bash
bash testbed/testbed.sh
```

Failed workspaces and command logs are kept for inspection. The testbed also
runs in [GitHub Actions](.github/workflows/testbed.yml).
The default matrix tests the latest release, a newer RC when available, and
the latest snapshot on Linux, Windows and macOS. Results are linked from
`testbed/work/<run>/REPORT.md`; CI publishes the combined report in the
`testbed-all` artifact.

The independent [bnd master testbed](.github/workflows/bnd-master.yml) polls
`bndtools/bnd` master every 15 minutes. It builds the detected revision and
tests the generated templates on all three platforms. All builds and results
stay in this repository; bnd CI is unaffected.
