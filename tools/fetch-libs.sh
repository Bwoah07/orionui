#!/usr/bin/env bash
# Fetches the libraries OrionUI embeds into OrionUI/Libs for local development and tests.
# Release builds get them from .pkgmeta externals instead; Libs/ is gitignored.
set -euo pipefail
cd "$(dirname "$0")/../OrionUI"
mkdir -p Libs
fetch() { # name url file
    local dir="Libs/$1"
    if [ -f "$dir/$3" ]; then return; fi
    rm -rf "$dir" && git clone -q --depth 1 "$2" "$dir" && rm -rf "$dir/.git"
}
fetch LibStub https://github.com/lua-wow/LibStub.git LibStub.lua   # mirror of wowace libstub (public domain)
fetch LibSerialize https://github.com/rossnichols/LibSerialize.git LibSerialize.lua
fetch LibDeflate https://github.com/SafeteeWoW/LibDeflate.git LibDeflate.lua
fetch Ace3 https://github.com/WoWUIDev/Ace3.git AceAddon-3.0/AceAddon-3.0.lua
# LibSharedMedia-3.0 lives on wowace (svn); for local dev copy it from any addon that embeds it
# into OrionUI/Libs/LibSharedMedia-3.0 (same layout as the .pkgmeta external).
echo "libs ready in OrionUI/Libs"
