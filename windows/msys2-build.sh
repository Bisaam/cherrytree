#!/usr/bin/env bash
# Builds CherryTree for Windows, with the bundled look (look/), and packages it as
#   dist/cherrytree_<version>_win64_portable.zip   (unzip anywhere, double-click CherryTree.exe)
#   dist/cherrytree_<version>_win64_setup.exe      (per-user installer, no admin needed)
#
# Run inside the MSYS2 UCRT64 environment (build-windows.sh does that for you from WSL):
#   windows/msys2-build.sh [--version 1.2.0] [--no-installer] [--clean]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CT_VERSION="${CT_VERSION:-1.2.0}"          # 1.2.0 = the version Debian ships
MAKE_INSTALLER=1
CLEAN=0
JOBS="$(nproc)"

usage() { sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; }
step()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
die()   { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --version)      CT_VERSION="$2"; shift 2 ;;
    --no-installer) MAKE_INSTALLER=0; shift ;;
    --clean)        CLEAN=1; shift ;;
    -h|--help)      usage; exit 0 ;;
    *)              die "unknown option '$1' (see --help)" ;;
  esac
done

[ "${MSYSTEM:-}" = "UCRT64" ] || die "run from the MSYS2 UCRT64 environment (MSYSTEM is '${MSYSTEM:-unset}')"
PATCHES="${ROOT}/patches/${CT_VERSION}"
[ -d "${PATCHES}" ] || die "no patch set for ${CT_VERSION}; available: $(ls "${ROOT}/patches" | tr '\n' ' ')"

P=mingw-w64-ucrt-x86_64
WORK="${ROOT}/work"
SRC="${WORK}/cherrytree-${CT_VERSION}"
BUILD="${WORK}/build-${CT_VERSION}"
RTROOT="${WORK}/runtime-root"
PKG_NAME="cherrytree_${CT_VERSION}_win64"
STAGE="${WORK}/${PKG_NAME}"
UCRT="${STAGE}/ucrt64"
CT_SHARE="${UCRT}/usr/share/cherrytree"
DIST="${ROOT}/dist"
LOOK="${ROOT}/look"

RUNTIME_PKGS=(
  "${P}-gtkmm3" "${P}-gtksourceview4" "${P}-sqlite3" "${P}-gspell" "${P}-curl" "${P}-uchardet"
  "${P}-fribidi" "${P}-fmt" "${P}-spdlog" "${P}-webp-pixbuf-loader" "${P}-librsvg"
  "${P}-fontconfig" "${P}-adwaita-icon-theme" "${P}-hicolor-icon-theme"
)
CMAKE_EXTRA=()

[ "${CLEAN}" = 1 ] && rm -rf "${BUILD}"
mkdir -p "${WORK}" "${DIST}"

# 1. sources + patches ---------------------------------------------------------------------------
step "sources: cherrytree v${CT_VERSION}"
if [ ! -d "${SRC}/.git" ]; then
  git clone --quiet --depth 1 --branch "v${CT_VERSION}" https://github.com/giuspen/cherrytree.git "${SRC}"
fi
git -C "${SRC}" reset --quiet --hard HEAD
git -C "${SRC}" clean --quiet -fdx
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

# 1b. libxml++: whatever this release's CMakeLists asks for (decides what gets bundled too) -------
LIBXMLPP_ARCHIVED=""
if grep -q 'option(WITH_LIBXMLPP5' "${SRC}/CMakeLists.txt"; then
  LIBXMLPP_PKG="${P}-libxml++-5.0"
  CMAKE_EXTRA+=(-DWITH_LIBXMLPP5=ON)
elif grep -q 'libxml++-2.6' "${SRC}/CMakeLists.txt"; then
  # MSYS2 dropped libxml++-2.6 in 10/2026; its last archived package was built against the
  # current libxml2 ABI (2.15, libxml2-16.dll), so it is used for building and bundling
  LIBXMLPP_PKG="${P}-libxml++2.6"
  LIBXMLPP_ARCHIVED="https://repo.msys2.org/mingw/ucrt64/${P}-libxml++2.6-2.42.3-5-any.pkg.tar.zst"
else
  die "can't tell which libxml++ v${CT_VERSION} needs"
fi
step "libxml++ (${LIBXMLPP_PKG})"
if ! pacman -Q "${LIBXMLPP_PKG}" >/dev/null 2>&1; then
  if [ -n "${LIBXMLPP_ARCHIVED}" ]; then
    pacman -U --needed --noconfirm "${LIBXMLPP_ARCHIVED}"
  else
    pacman -S --needed --noconfirm "${LIBXMLPP_PKG}"
  fi
fi
pacman -Q "${LIBXMLPP_PKG}"

# 2. build ---------------------------------------------------------------------------------------
step "build (Release, ${JOBS} jobs)"
cmake -S "${SRC}" -B "${BUILD}" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++ \
  -DBUILD_TESTING=OFF \
  "${CMAKE_EXTRA[@]}"
ninja -C "${BUILD}" -j "${JOBS}" -k 0   # -k 0: report every failing file in one run
CT_EXE="${BUILD}/cherrytree.exe"
[ -f "${CT_EXE}" ] || die "build finished without ${CT_EXE}"

# 3. clean runtime tree (same approach as upstream scripts/msys2_prepare_standalone.sh) ----------
step "runtime: minimal ucrt64 tree via pacman --root"
# the tree only changes with the package list or the MSYS2 package database, so it is cached
RT_KEY="$( { printf '%s\n' "${RUNTIME_PKGS[@]}" "${LIBXMLPP_PKG}" "${LIBXMLPP_ARCHIVED:-}"; \
             cat /var/lib/pacman/sync/ucrt64.db /var/lib/pacman/sync/msys.db; } | sha1sum | cut -c1-12)"
# one cache per libxml++ flavour, so alternating 1.2.0 / 1.7.2 builds don't evict each other
RT_FLAVOUR="${LIBXMLPP_PKG#"${P}-"}"; RT_FLAVOUR="${RT_FLAVOUR//+/p}"
RT_CACHE="${WORK}/runtime-cache-${RT_FLAVOUR}-${RT_KEY}"
if [ -d "${RT_CACHE}/ucrt64" ]; then
  echo "  using cached runtime tree ${RT_CACHE##*/}"
else
  find "${WORK}" -maxdepth 1 \( -name "runtime-cache-${RT_FLAVOUR}-*" -o -regex '.*/runtime-cache-[0-9a-f]*' \) -exec rm -rf {} +
  rm -rf "${RTROOT}"
  mkdir -p "${RTROOT}/var/lib/pacman" "${RTROOT}/var/log" "${RTROOT}/tmp"
  pacman -Sy --root "${RTROOT}" --noconfirm >/dev/null
  # bash: lets the packages' post-install scriptlets run inside the root (as upstream does)
  pacman -S --root "${RTROOT}" --noconfirm --needed filesystem bash "${RUNTIME_PKGS[@]}" \
    $( [ -z "${LIBXMLPP_ARCHIVED}" ] && echo "${LIBXMLPP_PKG}" )
  if [ -n "${LIBXMLPP_ARCHIVED}" ]; then
    pacman -U --root "${RTROOT}" --noconfirm "${LIBXMLPP_ARCHIVED}"
  fi
  mkdir -p "${RT_CACHE}"
  mv "${RTROOT}/ucrt64" "${RT_CACHE}/ucrt64"
  rm -rf "${RTROOT}"
fi
rm -rf "${STAGE}"
mkdir -p "${STAGE}"
cp -a "${RT_CACHE}/ucrt64" "${UCRT}"

step "runtime: trim"
find "${UCRT}" -name "*.a" -delete
# keep only the helper executables GTK/GLib/fontconfig need at runtime
find "${UCRT}/bin" -name "*.exe" \
  ! -name "gdbus.exe" ! -name "gspawn-win64-helper*.exe" ! -name "glib-compile-schemas.exe" \
  ! -name "gdk-pixbuf-query-loaders.exe" ! -name "gtk-update-icon-cache*.exe" ! -name "fc-cache.exe" \
  -delete
rm -rf "${UCRT}"/bin/*-config "${UCRT}"/bin/*.sh "${UCRT}/sbin" "${UCRT}/var" "${UCRT}/include" "${UCRT}/libexec"
for d in man readline info aclocal gnome-common glade gettext terminfo tabset pkgconfig bash-completion \
         appdata gdb help gtk-doc doc applications devhelp installed-tests vala metainfo thumbnailers; do
  rm -rf "${UCRT}/share/${d}"
done
rm -rf "${UCRT}"/share/gir-* "${UCRT}"/share/graphite*
rm -rf "${UCRT}"/lib/{cmake,pkgconfig,python*,girepository*,terminfo,gettext} "${UCRT}"/lib/*mm-*
rm -f "${UCRT}"/share/sqlite/extensions/*.c 2>/dev/null || true
# locales: keep only the languages cherrytree is translated to
LOCALE="${UCRT}/share/locale"; mkdir -p "${LOCALE}.keep"
for lang_dir in "${SRC}"/po/*/; do
  lang="$(basename "${lang_dir}")"
  [ -d "${LOCALE}/${lang}" ] && mv "${LOCALE}/${lang}" "${LOCALE}.keep/"
done
rm -rf "${LOCALE}"; mv "${LOCALE}.keep" "${LOCALE}"

# 4. cherrytree files ----------------------------------------------------------------------------
step "cherrytree files"
cp "${CT_EXE}" "${UCRT}/bin/"
cp "${SRC}/license.txt" "${STAGE}/license.txt"
mkdir -p "${CT_SHARE}/data" "${CT_SHARE}/icons" "${UCRT}/share/hunspell"
cp -r "${SRC}/language-specs" "${SRC}/styles" "${CT_SHARE}/"
for f in script3.js styles4.css user-style.xml; do
  [ -f "${SRC}/data/${f}" ] && cp "${SRC}/data/${f}" "${CT_SHARE}/data/"
done
cp "${SRC}/icons/ct_home.svg" "${CT_SHARE}/icons/" 2>/dev/null || true
for d in Breeze_Dark_icons Breeze_Light_icons; do
  [ -d "${SRC}/icons/${d}" ] && cp -r "${SRC}/icons/${d}" "${CT_SHARE}/icons/"
done
for lang_dir in "${SRC}"/po/*/; do cp -r "${lang_dir%/}" "${LOCALE}/"; done
cp "${SRC}"/hunspell/*.aff "${SRC}"/hunspell/*.dic "${UCRT}/share/hunspell/"
# the ssl bundle is not populated correctly by --root installs (upstream note)
rm -rf "${UCRT}/etc/ssl"; cp -r /ucrt64/etc/ssl "${UCRT}/etc/"

# 5. Bundled look -----------------------------------------------------------------------------------
step "bundled look"
# GTK theme + icon theme + settings (gtk reads <prefix>/etc/gtk-3.0/settings.ini on Windows)
mkdir -p "${UCRT}/share/themes" "${UCRT}/share/icons" "${UCRT}/etc/gtk-3.0"
cp -r "${LOOK}/themes/Cherry-Dark" "${UCRT}/share/themes/"
cp -r "${LOOK}/icons/Flat-Remix-Blue-Dark" "${UCRT}/share/icons/"
cp "${LOOK}/gtk-3.0/settings.ini" "${UCRT}/etc/gtk-3.0/settings.ini"
# editor colour schemes + first-run cherrytree config
cp "${LOOK}"/styles/*.xml "${CT_SHARE}/styles/"
cp "${LOOK}/config/config.cfg" "${CT_SHARE}/data/config-default.cfg"
# fonts: Cantarell + Fira Code, found by fontconfig through a conf.d snippet
mkdir -p "${UCRT}/share/fonts/cherrytree" "${UCRT}/etc/fonts/conf.d"
cp "${LOOK}"/fonts/*.otf "${LOOK}"/fonts/*.ttf "${LOOK}"/fonts/LICENSE-*.txt "${UCRT}/share/fonts/cherrytree/"
cp "${LOOK}/fonts/99-cherrytree-fonts.conf" "${UCRT}/etc/fonts/conf.d/"
# caches
ICON_CACHE_TOOL="$(command -v gtk-update-icon-cache || command -v gtk-update-icon-cache-3.0)"
for theme in "${UCRT}"/share/icons/*/; do
  if [ -f "${theme}index.theme" ]; then "${ICON_CACHE_TOOL}" -q -f -t "${theme}"; fi
done
# gdk-pixbuf (svg/webp/... loaders): on Windows a relative module path in loaders.cache is
# resolved against the toplevel (the ucrt64 folder), so strip our staging prefix
PIXBUF_DIR="${UCRT}/lib/gdk-pixbuf-2.0/2.10.0"
UCRT_M="$(cygpath -m "${UCRT}")"
gdk-pixbuf-query-loaders $(for dll in "${PIXBUF_DIR}"/loaders/*.dll; do cygpath -m "${dll}"; done) \
  | sed -e "s|${UCRT_M}/||g" > "${PIXBUF_DIR}/loaders.cache"
grep -q '"lib/gdk-pixbuf-2.0/2.10.0/loaders/' "${PIXBUF_DIR}/loaders.cache" || die "loaders.cache has no relative module paths"
grep -q 'svg' "${PIXBUF_DIR}/loaders.cache" || die "svg pixbuf loader missing (cherrytree icons are svg)"
glib-compile-schemas "${UCRT}/share/glib-2.0/schemas"

# CherryTree.exe launcher at the top of the folder (double-click, no PATH setup) + notices
step "launcher"
LAUNCHER_TMP="${WORK}/launcher"; rm -rf "${LAUNCHER_TMP}"; mkdir -p "${LAUNCHER_TMP}"
cp "${ROOT}"/windows/launcher/launcher.{c,rc} "${SRC}/icons/cherrytree.ico" "${LAUNCHER_TMP}/"
( cd "${LAUNCHER_TMP}" \
  && windres launcher.rc -O coff -o launcher_rc.o \
  && gcc -O2 -municode -mwindows -static -s -o "${STAGE}/CherryTree.exe" launcher.c launcher_rc.o )
rm -rf "${LAUNCHER_TMP}"
cp "${ROOT}/windows/README-windows.txt" "${STAGE}/README.txt"

# 6. strip + verify + package --------------------------------------------------------------------
step "strip"
find "${UCRT}" \( -name "*.dll" -o -name "*.exe" \) -print0 | xargs -0 strip --strip-unneeded 2>/dev/null || true

step "verify: every DLL any packaged binary imports is in the package or part of Windows"
# one objdump + awk pass (spawning a process per import is very slow under MSYS2)
AVAILABLE="${WORK}/available-dlls.txt"
{ ls "${UCRT}/bin"; ls "$(cygpath -u "${SYSTEMROOT:-C:\\Windows}")/System32"; } > "${AVAILABLE}"
find "${UCRT}/bin" "${UCRT}/lib" "${STAGE}/CherryTree.exe" \( -name "*.dll" -o -name "*.exe" \) -print0 \
  | xargs -0 objdump -p 2>/dev/null | tr -d '\r' \
  | awk -v avail="${AVAILABLE}" '
      BEGIN { while ((getline l < avail) > 0) have[tolower(l)] = 1 }
      / file format / { bin = $1; sub(/:$/, "", bin) }
      /^[ \t]*DLL Name:/ { d = tolower($3)
                           if (d ~ /^(api-ms-win-|ext-ms-)/ || (d in have)) next
                           printf "  MISSING %s  (needed by %s)\n", $3, bin; bad = 1 }
      END { exit bad }' \
  || die "the package is not self-contained (see MISSING lines above)"
rm -f "${AVAILABLE}"
echo "  ok: $(find "${UCRT}" -name '*.dll' | wc -l) DLLs, all dependencies resolved inside the package"

step "portable zip"
# packages are written under a .partial name and renamed when complete, so dist/ never holds
# a half-written zip/exe that someone could try to open while a build is running
rm -f "${DIST}/${PKG_NAME}_portable.zip.partial"
( cd "${WORK}" && zip -qr -9 "${DIST}/${PKG_NAME}_portable.zip.partial" "${PKG_NAME}" )
mv -f "${DIST}/${PKG_NAME}_portable.zip.partial" "${DIST}/${PKG_NAME}_portable.zip"
ls -la "${DIST}/${PKG_NAME}_portable.zip"

if [ "${MAKE_INSTALLER}" = 1 ]; then
  step "installer (NSIS)"
  makensis -V2 -INPUTCHARSET UTF8 \
    -DCT_VERSION="${CT_VERSION}" \
    -DSTAGE_DIR="$(cygpath -w "${STAGE}")" \
    -DOUT_FILE="$(cygpath -w "${DIST}/${PKG_NAME}_setup.exe.partial")" \
    -DICON_FILE="$(cygpath -w "${SRC}/icons/cherrytree.ico")" \
    "$(cygpath -w "${ROOT}/windows/installer.nsi")"
  mv -f "${DIST}/${PKG_NAME}_setup.exe.partial" "${DIST}/${PKG_NAME}_setup.exe"
  ls -la "${DIST}/${PKG_NAME}_setup.exe"
fi

step "done: $(cygpath -w "${DIST}")"
