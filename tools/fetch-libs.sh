#!/usr/bin/env bash
# Fetches the libraries RaidControl embeds into Libs for local development.
# Release builds get them from .pkgmeta externals instead; Libs/ is gitignored.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Libs
if [ ! -f Libs/Ace3/AceAddon-3.0/AceAddon-3.0.lua ]; then
    rm -rf Libs/Ace3 && git clone -q --depth 1 https://github.com/WoWUIDev/Ace3.git Libs/Ace3 && rm -rf Libs/Ace3/.git Libs/Ace3/tests
fi
# LibSharedMedia-3.0 lives on wowace (svn). Copy it from any addon that embeds it into
# Libs/LibSharedMedia-3.0/LibSharedMedia-3.0/ (same layout as the .pkgmeta external).
if [ ! -f Libs/LibSharedMedia-3.0/LibSharedMedia-3.0/LibSharedMedia-3.0.lua ]; then
    echo "LibSharedMedia-3.0 missing: copy it into Libs/LibSharedMedia-3.0/LibSharedMedia-3.0/" >&2
fi
echo "libs ready in Libs"
