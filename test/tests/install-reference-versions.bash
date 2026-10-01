#!/usr/bin/env bash

# These are the versions installed and hence cached by proxy-build.

# Run commands we want to cache downloads for.

# Get index into cache for lookups of expected versions. Uncompressed.
curl --location --fail https://beplus.s3.amazonaws.com/cli/releases.json &> /dev/null

# Using 2.0.0 as a well known old version (a past release, so it does not change)
sudo be --download 2.0.0
sudo be --download latest
