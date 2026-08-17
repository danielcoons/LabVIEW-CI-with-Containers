# Contributing to LabVIEW CI

This repository is the **tooling source**, not a client. Every repo listed on the
dashboard's Clients page installs from here, so a few things behave differently
than they would in a normal project.

## This repo is not a place to install the pipeline

The **LabVIEW CI configurator** (the "Integrate this CI pipeline" page) is a
*client installer*. It vendors a tooling payload pinned to a released version and
deletes files it does not recognise as current tooling.

This repository carries release machinery that no client has — `release.yml`,
`promote-release.py`, `discover-clients.yml`, the configurator pages themselves.
So running the configurator against this repo **or a fork of it** deletes that
machinery and overwrites `catalog.json` with an older version.

That is not hypothetical. On 2026-07-30 an install pinned at v4.11.10 landed on a
fork, downgraded the catalog from 4.12.4, removed 48 source-only files, and
stopped all client releases for two weeks.

The configurator now refuses this, and `catalog-source-sync` fails the PR if the
source-only files go missing. **To test the pipeline, install it into a separate
scratch repository.**

## `catalog.json` is the version of record

`.github/labview-ci/catalog.json` → `version` is what `release.yml` reads to cut
the `v<MAJOR>.<MINOR>.<PATCH>` tag and force-move the `v<MAJOR>` alias that every
client pins to. It is release machinery, not a config file.

- **Never hand-edit it on a feature branch**, and never resolve a conflict in it
  by taking your side. If your branch's copy is older than main's, take main's.
- The version must only ever go **up**. `catalog-source-sync` compares it against
  the highest published `v*` tag and fails the PR if it moves backwards.
- `version` must equal `history.releases[0].version`, so a bump means adding a
  history entry too.
- Patch for fixes, minor for a new capability, major for a breaking change.

A downgrade fails quietly if it gets through: `release.yml` finds the tag already
exists, publishes nothing, and leaves the alias stranded on the newer release. It
looks like a green build.

## Reverts

If a PR is reverted, do **not** bring it back by merging main into your fork and
re-merging your branch — git treats the reverted commits as already merged, so
they silently return. Revert the revert (`git revert <revert-sha>`) on a fresh
branch, fix the actual problem, and open a new PR.

This is how the 2026-07-30 downgrade came back seven minutes after it was fixed.

## Repository settings this relies on

The guards are only as good as the branch rules that enforce them. On `main`,
under **Settings › Branches › Branch protection rules**:

- Require a pull request before merging
- Require review from Code Owners (activates `.github/CODEOWNERS`)
- Require status checks to pass → **`Catalog Source Sync`**

Without the required status check, `catalog-source-sync` reports a failure that
nothing acts on.
