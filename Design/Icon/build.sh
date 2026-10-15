#!/bin/zsh
# Baut AppIcon.png, AppIcon.icns, MenuBarTemplate.png und MenuBarTemplate@2x.png neu.
set -e
cd "${0:A:h}"
[[ -f work/renders/gargantua.png ]] || ./render.sh
mkdir -p work
swiftc -O iconkit.swift -o work/iconkit
./work/iconkit appicon .
./work/iconkit menubar .
