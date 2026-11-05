# What is this Repo?

This repository is the home for the sources of some useful Bndtools Project Templates. These are provided as bundles which you can include in your workspace to add new project templates.

# How do I use these?

You can add the template bundles to any repository in your workspace, but if you use the [Bndtools Workspace Template](https://github.com/bndtools/workspace) then they're included by default.

# Testing The Templates

The [project template testbed](testbed/README.md) renders the working-tree
templates into a clean workspace, builds and tests the generated projects,
resolves and launches their run configurations, and writes a linked report.

```bash
bash testbed/testbed.sh
```

Failed workspaces and command logs are kept for inspection. The testbed also
runs in [GitHub Actions](.github/workflows/testbed.yml).
The default matrix tests the latest release, a newer RC when available, and
