# Releasing

A release is cut by merging a pull request into `main` that bumps the version. Nobody publishes
by hand. The [Release workflow](../.github/workflows/release.yml) publishes `@beplus/be` to the
**public npm registry** and creates the `vX.Y.Z` tag and GitHub Release.

## The flow

```
feature/…  ──▶  (optional) _versions/vX.Y.Z  ──▶  PR into main  ──▶  npm + tag + GitHub Release
```

1. On your branch, run `bin/bump patch|minor|major` (or `bin/bump X.Y.Z`). It writes the version
   into `package.json`, `package-lock.json` and `bin/be`. It also opens the version's section in
   `CHANGELOG.md` and moves any notes under `[Unreleased]` into it. It commits, tags and publishes
   nothing.
2. Describe the release under its `## [vX.Y.Z]` heading in `CHANGELOG.md`. That text becomes the
   GitHub Release notes.
3. Open a PR into `main`. CI runs the tests and lint, and checks the version.
4. Once the PR is approved and merged, the Release workflow publishes the version.

A PR that doesn't touch `bin/be` (docs, tests, CI) can merge without a bump, and then releases
nothing. A PR that changes `bin/be` must bump. `scripts/install.sh` installs straight from `main`,
so whatever lands there must be a released version.

To batch several PRs into one release, collect them on a `_versions/vX.Y.Z` branch first. Bump
on that branch, where `bin/bump` defaults to `X.Y.Z`, then open one PR from it into `main`. CI
checks that the branch name and the version agree.

`dev` is retired. Nothing targets it any more.

## What CI checks

[`scripts/release/verify-version.sh`](../scripts/release/verify-version.sh) holds the rules. Both
the PR check and the release run use it.

- `bin/be`, `package.json` and `package-lock.json` carry the same version.
- A bump is newer than `main`'s version, isn't tagged or on npm yet, and has a non-empty
  `CHANGELOG.md` section.
- A change to `bin/be` comes with a bump.
- A `_versions/vX.Y.Z` branch carries exactly `vX.Y.Z`.

## When a release run fails

Re-run it from the Actions tab. Each step skips what's already done (on npm, tagged), so a re-run
picks up where the failed one stopped. If a run was cancelled while it waited behind another
release, re-run that run too, because it holds its own commit.

## One-time setup

- **npm.** On npmjs.com, go to `@beplus/be` → Settings → Trusted Publisher → GitHub Actions and
  enter organization `beplus`, repository `be`, workflow `release.yml`, environment `npm`. No npm
  token exists anywhere: the workflow authenticates with OIDC, and npm attaches provenance to every
  version. Under Publishing access, choose "Require two-factor authentication and disallow tokens".
- **GitHub.** The `npm` environment is created on the first run. Limit its deployment branches to
  `main`.

`package.json` pins both `publishConfig.registry` and `publishConfig["@beplus:registry"]` to
`https://registry.npmjs.org/`. A beplus machine maps the `@beplus` scope to `npm.beplus.cloud`, and
that mapping beats a plain `registry` pin, so the scoped key is what keeps `@beplus/be` from being
published there. The same mapping also overrides `npm view --registry`. Check public npm with
`curl -s https://registry.npmjs.org/@beplus%2fbe`.
