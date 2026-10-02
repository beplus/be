# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

<!-- markdownlint-disable MD024 -->

## [Unreleased]

https://github.com/beplus/be/compare/v0.9.0...main

## [v0.9.0] (10/02/2026)

Verify every download against the `SHA256SUMS` the beplus CLI release publishes beside its
tarballs, and extract only a match. A missing `SHA256SUMS`, a tarball it does not list or a
mismatch aborts with the URL and extracts nothing; until now a download's integrity rested on TLS
alone. Verifying uses `sha256sum`, or `shasum` where there is none. Both line forms the releases
use are read: `<hash>  <name>` from 2.x on, and v1.0.5's `<name>: <hash>`.

Detect the installed version by comparing `$BE_PREFIX/bin/beplus` with the downloads it was copied
from. With a 2.x CLI detection always came up empty, so `be prune` deleted the installed version
along with the rest.

Stop `be uninstall` at end of input, deleting nothing, as if answered no. It used to ask again for
ever.

Always download the `.tar.gz`. From major 4 on, `be` asked for a `.tar.xz`, which the beplus CLI
release does not publish; `--use-xz`, `--no-use-xz` and `BE_USE_XZ` are gone with it.

## [v0.8.0] (10/02/2026)

Resolve versions by SemVer precedence instead of trusting the order the release index arrives in.
The GitHub Releases API sorts by `created_at`, and every beplus/cli release shares one, so the list
tied and came back unordered — `be 2` could hand out a stage build published before the prod one,
and `be latest` could pick an older major. A release now always outranks the pre-releases it was
promoted from, and pre-release build numbers compare numerically (`beta.11` > `beta.2`).

## [v0.7.0] (07/03/2026)

Make `be latest`/`current`/`stable` install the newest official release, skipping pre-releases (explicit pre-release versions can still be installed)

## [v0.6.0] (07/03/2026)

Fix incomplete numeric versions so they filter by series again: `be ls-remote 1` lists only `1.x`, and `be 1`/`be install v1.2` resolve to the newest matching version

## [v0.5.0] (02/06/2026)

Fix the way env-specific versions are downloaded

## [v0.4.0] (02/06/2026)

Update the install script
Allow env-specific versions

## [v0.3.0] (06/09/2024)

Add the install script
Update the Makefile
Allow pre-release versions

## [v0.2.0] (09/23/2023)

Update the URL from which the actual available releases are being fetched.

## [v0.1.0] (12/20/2022)

Initial release of `@beplus/be`.

Interactively Manage Your `@beplus/cli` Versions.

This project is based on https://github.com/tj/n ❤️
