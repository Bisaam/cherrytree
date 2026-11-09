#!/usr/bin/env bash
# Builds CherryTree for macOS (Apple silicon) with the bundled look and packages it as
#   dist/cherrytree_<version>_macos_arm64.dmg   (open it, drag CherryTree to Applications)
#
# Needs Homebrew (https://brew.sh). Run on a Mac, or let .github/workflows/macos.yml do it:
#   macos/build-macos.sh [--version 1.7.2] [--no-deps]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CT_VERSION="1.7.2"
INSTALL_DEPS=1

usage() { sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; }
step()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
die()   { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --version) CT_VERSION="$2"; shift 2 ;;
    --no-deps) INSTALL_DEPS=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option '$1' (see --help)" ;;
  esac
done

[ "$(uname -s)" = "Darwin" ] || die "run this on macOS"
command -v brew >/dev/null || die "Homebrew is needed: https://brew.sh"
PATCHES="${ROOT}/patches/${CT_VERSION}"
[ -d "${PATCHES}" ] || die "no patch set for ${CT_VERSION}; available: $(ls "${ROOT}/patches" | tr '\n' ' ')"

BREW="$(brew --prefix)"
ARCH="$(uname -m)"
WORK="${ROOT}/work/macos"
SRC="${WORK}/cherrytree-${CT_VERSION}"
BUILD="${WORK}/build-${CT_VERSION}"
INSTALL="${WORK}/install-${CT_VERSION}"
APP="${WORK}/CherryTree.app"
DIST="${ROOT}/dist"
PKG_NAME="cherrytree_${CT_VERSION}_macos_${ARCH}"
mkdir -p "${WORK}" "${DIST}"

# 0. Homebrew packages (the same set as Homebrew's own cherrytree formula, plus the bundle's extras)
BREW_PKGS=(cmake ninja pkgconf gettext gtk+3 gtkmm3 gtksourceview4 gspell enchant libxml++ fmt spdlog
           uchardet fribidi sqlite vte3 adwaita-icon-theme hicolor-icon-theme librsvg webp-pixbuf-loader
           fontconfig)
if [ "${INSTALL_DEPS}" = 1 ]; then
  step "Homebrew packages"
  brew install --quiet "${BREW_PKGS[@]}"
fi

# 1. sources + patches
step "sources: cherrytree v${CT_VERSION}"
rm -rf "${SRC}" "${BUILD}" "${INSTALL}"
git clone --quiet --depth 1 --branch "v${CT_VERSION}" https://github.com/giuspen/cherrytree.git "${SRC}"
CMAKE_EXTRA=()
case "${CT_VERSION}" in
  1.[0-2].*)
    # 2024 sources vs fmt 12: build with the spdlog+fmt bundled with that release
    git -C "${SRC}" submodule update --quiet --init --depth 1 src/spdlog
    CMAKE_EXTRA+=(-DUSE_SHARED_FMT_SPDLOG=OFF)
    ;;
esac
for patch in "${PATCHES}"/*.patch; do
  echo "applying $(basename "${patch}")"
  git -C "${SRC}" apply --whitespace=nowarn "${patch}"
done
grep -q 'option(WITH_LIBXMLPP5' "${SRC}/CMakeLists.txt" && die "v${CT_VERSION} wants libxml++-5.0, which Homebrew doesn't have"

# 2. build (like Homebrew's formula: keg-only .pc files visible, libxml2 C API linked directly)
step "build"
PKG_CONFIG_PATH="${PKG_CONFIG_PATH:-}"
for d in "${BREW}"/opt/*/lib/pkgconfig "${BREW}"/opt/*/share/pkgconfig; do
  PKG_CONFIG_PATH="${PKG_CONFIG_PATH:+${PKG_CONFIG_PATH}:}${d}"
done
export PKG_CONFIG_PATH
# -lobjc: the patch replaces a method of GTK's NSApplication delegate (macOS quit handling)
cmake -S "${SRC}" -B "${BUILD}" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF \
  -DCMAKE_INSTALL_PREFIX="${INSTALL}" \
  -DCMAKE_FIND_FRAMEWORK=LAST \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$(sw_vers -productVersion | cut -d. -f1).0" \
  -DCMAKE_CXX_FLAGS="-I${BREW}/include" \
  -DCMAKE_EXE_LINKER_FLAGS="-L${BREW}/lib -lxml2 -lobjc" \
  ${CMAKE_EXTRA[@]+"${CMAKE_EXTRA[@]}"}
cmake --build "${BUILD}"
cmake --install "${BUILD}"

# 3. CherryTree.app: bundled look, every Homebrew library inside, ad-hoc signed
step "CherryTree.app"
python3 "${ROOT}/macos/make_app.py" --version "${CT_VERSION}" --install "${INSTALL}" --root "${ROOT}" \
  --brew "${BREW}" --app "${APP}"

# 4. disk image
step "disk image"
DMG_STAGE="${WORK}/dmg"
rm -rf "${DMG_STAGE}" "${WORK}/${PKG_NAME}.dmg"
mkdir -p "${DMG_STAGE}"
cp -R "${APP}" "${DMG_STAGE}/"
ln -s /Applications "${DMG_STAGE}/Applications"
cp "${ROOT}/macos/README-macos.txt" "${DMG_STAGE}/README.txt"
hdiutil create -quiet -volname "CherryTree ${CT_VERSION}" -srcfolder "${DMG_STAGE}" -ov -format UDZO \
  "${WORK}/${PKG_NAME}.dmg"
mv -f "${WORK}/${PKG_NAME}.dmg" "${DIST}/${PKG_NAME}.dmg"
ls -la "${DIST}/${PKG_NAME}.dmg"
