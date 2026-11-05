#!/usr/bin/env bash
# Installs everything needed to build CherryTree for Windows.
# Run inside an "MSYS2 UCRT64" shell (or via build-windows.sh from WSL).
set -euo pipefail

if [ "${MSYSTEM:-}" != "UCRT64" ]; then
  echo "error: run this from the MSYS2 UCRT64 environment (MSYSTEM=UCRT64), not '${MSYSTEM:-none}'" >&2
  exit 1
fi

P=mingw-w64-ucrt-x86_64

# if this updates MSYS2 core packages, restart the shell and run the script again
pacman -Syu --noconfirm

pacman -S --needed --noconfirm \
  git patch p7zip zip unzip rsync \
  ${P}-toolchain ${P}-cmake ${P}-ninja ${P}-python ${P}-pkgconf \
  ${P}-gtkmm3 ${P}-gtksourceview4 ${P}-libxml++-5.0 ${P}-sqlite3 \
  ${P}-gspell ${P}-curl ${P}-uchardet ${P}-fribidi ${P}-fmt ${P}-spdlog \
  ${P}-webp-pixbuf-loader ${P}-librsvg ${P}-adwaita-icon-theme ${P}-hicolor-icon-theme \
  ${P}-fontconfig ${P}-gettext-tools ${P}-nsis

echo "msys2-setup: done"
