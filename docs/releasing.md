# Releasing

`@beplus/be` releases the way every `@beplus/*` library does (beplus/setup-beplus's
`library-publish.yml`): **one version per commit, built once, promoted.** A release is cut by
merging a pull request into `dev` that bumps the version; `stage`, `prod` and `main` are
fast-forwarded from it and build nothing. Nobody publishes by hand. The
[Release workflow](../.github/workflows/release.yml) does it all:

| branch | what a push does |
| --- | --- |
| `dev` | packs the version **once**, tags it `vX.Y.Z` with a GitHub **pre-release**, publishes the tarball to **GitHub Packages** (dist-tag `dev`), then to **dev's CodeArtifact** — `npm.beplus.cloud`, where the estates' builds install `be` from |
| `stage` | fetches that tarball from GitHub Packages and publishes it, byte for byte, to **stage's CodeArtifact**, with every earlier version dev released that it lacks; GitHub Packages tags it `stage` |
| `prod` | the same into **prod's CodeArtifact** (GitHub Packages tags it `latest`), and the GitHub Release becomes a **full release**, marked latest (the earlier versions' too, never marked latest) |
| `main` | the public channel, and the one thing `be` has that the libraries don't: the same bytes to the **public npm registry**, with provenance. `main` publishes only what `prod` already has |

## The flow

```
feature/…  ──▶  (optional) _versions/vX.Y.Z  ──▶  PR into dev  ──▶  tag + GitHub pre-release
                                                                    ──▶  GitHub Packages ──▶ dev's CodeArtifact
dev  ──fast-forward──▶  stage  ──▶  stage's CodeArtifact
stage  ──fast-forward──▶  prod  ──▶  prod's CodeArtifact ──▶ full GitHub Release
prod  ──fast-forward──▶  main  ──▶  public npm
```

1. On your branch, run `bin/bump patch|minor|major` (or `bin/bump X.Y.Z`). It writes the version
   into `package.json`, `package-lock.json` and `bin/be`. It also opens the version's section in
   `CHANGELOG.md` and moves any notes under `[Unreleased]` into it. It commits, tags and publishes
   nothing.
2. Describe the release under its `## [vX.Y.Z]` heading in `CHANGELOG.md`. That text becomes the
   GitHub Release notes.
3. Open a PR into `dev`. CI runs the tests and lint, and checks the version.
4. Once the PR is approved and merged, the Release workflow releases the version on `dev`.
5. Promote it: fast-forward `stage` to `dev` (`git push origin origin/dev:stage`); once it has
   proven itself there, `prod` to `stage` (`git push origin origin/stage:prod`); and to make it
   public, `main` to `prod` (`git push origin origin/prod:main`). Never commit to `stage`, `prod`
   or `main` directly.

You don't have to promote every release. A fast-forward promotes the commits in between too, so
`stage` and `prod` also publish every earlier version dev released that their CodeArtifact lacks
([`catch-up-codeartifact.sh`](../scripts/release/catch-up-codeartifact.sh)): oldest first, under a
temporary `catch-up` dist-tag, so `latest` is only ever the version the branch is on. Each
CodeArtifact keeps every version released up to its branch, and an estate that pinned one on dev
installs it there too. A version the registry refuses (one archived there on purpose) is a
warning, and the next promotion tries again. `main` publishes only the version its commit carries.

A PR that doesn't touch `bin/be` (docs, tests, CI) can merge without a bump, and then releases
nothing. A PR that changes `bin/be` must bump. `scripts/install.sh` installs from `main`, so
whatever reaches `main` is a released, public version.

To batch several PRs into one release, collect them on a `_versions/vX.Y.Z` branch first. Bump
on that branch, where `bin/bump` defaults to `X.Y.Z`, then open one PR from it into `dev`. CI
checks that the branch name and the version agree.

The release branches are `dev` (the default), `stage`, `prod` and `main`.

## What CI checks

[`scripts/release/verify-version.sh`](../scripts/release/verify-version.sh) holds the rules. Both
the PR check and the release run use it.

- `bin/be`, `package.json` and `package-lock.json` carry the same version.
- A bump is newer than `dev`'s version, isn't tagged or on npm yet, and has a non-empty
  `CHANGELOG.md` section.
- A change to `bin/be` comes with a bump.
- A `_versions/vX.Y.Z` branch carries exactly `vX.Y.Z`.
- `stage`, `prod` and `main` promote only a version `dev` released: tagged `vX.Y.Z` and in GitHub
  Packages. Anything else is refused before a registry is touched.
- `main` is on `origin/prod`, so the public registry only ever gets what `prod` already has.

## When a release run fails

Re-run it from the Actions tab. Each step skips what's already done (tagged, in GitHub Packages,
in that environment's CodeArtifact, on npm), so a re-run picks up where the failed one stopped. If
a run was cancelled while it waited behind another release on the same branch, re-run that run
too, because it holds its own commit.

## One-time setup

- **Branches.** `dev` (the default branch), `stage`, `prod` and `main`. Protect `stage`, `prod` and
  `main` so they only move by fast-forward.
- **GitHub environments** `dev`, `stage` and `prod`, each limited to its own branch, each with two
  variables:
  - `BE_ENVIRONMENT`: `dev`, `stage` or `prod`. It picks the CodeArtifact repository
    (`beplus aws codeartifact auth --env`), and the job refuses to run without it, because the CLI
    would otherwise fall back to `dev`.
  - `BE_AWS_ACCOUNT_ID`: the account holding that environment's CodeArtifact.
  - Optionally `BE_CLI_VERSION`, as in library-publish.
- **AWS.** In each of those accounts, the role `github-actions-beplus-be-<env>-npm-publishing`,
  trusting `repo:beplus/be:environment:<env>` and `repo:beplus/be:ref:refs/heads/<env>` — the role
  every library's publish assumes, named the same way.
- **npm.** On npmjs.com, go to `@beplus/be` → Settings → Trusted Publisher → GitHub Actions and
  enter organization `beplus`, repository `be`, workflow `release.yml`, environment `npm`. No npm
  token exists anywhere: the workflow authenticates with OIDC, and npm attaches provenance to every
  version. Under Publishing access, choose "Require two-factor authentication and disallow tokens".
  Limit the `npm` GitHub environment's deployment branches to `main`.
- **GitHub Packages.** Nothing to set up: the workflow publishes with its own `GITHUB_TOKEN`, and
  the first publish creates the `be` package linked to this repository. A `be` package that already
  exists but isn't linked to `beplus/be` makes that publish fail with a 403. Either delete it, or
  give this repository the Write role under the package's settings → Manage Actions access.

GitHub Packages is where stage and prod take the bytes from, so it is published first, from the
commit the version's tag points at. A version that is tagged but missing from GitHub Packages is
published by the next `dev` run; stage, prod and main refuse it until then.

`package.json` pins both `publishConfig.registry` and `publishConfig["@beplus:registry"]` to
`https://registry.npmjs.org/`. A beplus machine maps the `@beplus` scope to `npm.beplus.cloud`, and
that mapping beats a plain `registry` pin, so the scoped key is what keeps a hand-run
`npm publish` of `@beplus/be` from landing there. The same mapping also overrides
`npm view --registry`. Check public npm with `curl -s https://registry.npmjs.org/@beplus%2fbe`.

The pin beats a `--userconfig` too, which is how the other `@beplus/*` repositories point npm at
GitHub Packages. So every publish in the workflow passes `--registry` and `--@beplus:registry` on
the command line, because only command-line flags outrank `publishConfig`.
