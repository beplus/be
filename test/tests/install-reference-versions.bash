#!/usr/bin/env bash

# These are the versions installed and hence cached by proxy-build.

# Run commands we want to cache downloads for.

# Get index into cache for lookups of expected versions. Uncompressed.
curl --location --fail https://api.github.com/repos/beplus/cli/releases &> /dev/null

# Using 0.22.0 as a well known old version (which is no longer getting updated so does not change)
sudo be --download 0.22.0
sudo be --download latest
