#!/usr/bin/env bash
# Build the Windows version of CherryTree from WSL.
# Drives MSYS2 on the Windows host (default C:\msys64, override with MSYS2_ROOT=D:\msys64).
#
#   ./build-windows.sh --setup            first time: update MSYS2, install build deps, then build
#   ./build-windows.sh                    build CherryTree 1.2.0 (the version Debian ships)
#   ./build-windows.sh --version 1.7.2    build another version that has a patches/<version> set
#   ./build-windows.sh --run              build, then start the portable app on Windows
#   ./build-windows.sh --no-build --run   just start the last build
#
# Outputs land in ./dist (portable zip + setup.exe).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MSYS2_ROOT_WIN="${MSYS2_ROOT:-C:\\msys64}"
MSYS2="$(wslpath -u "${MSYS2_ROOT_WIN}")"
BUILD_MSYS_PATH="/opt/cherrytree"               # inside MSYS2
BUILD_DIR="${MSYS2}${BUILD_MSYS_PATH}"         # same folder seen from WSL

DO_SETUP=0
DO_BUILD=1
DO_RUN=0
BUILD_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --setup) DO_SETUP=1; shift ;;
    --run)   DO_RUN=1; shift ;;
    --no-build) DO_BUILD=0; shift ;;
    -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) BUILD_ARGS+=("$1"); shift ;;
  esac
done

if [ ! -x "${MSYS2}/usr/bin/bash.exe" ]; then
  cat >&2 <<EOF
MSYS2 not found at ${MSYS2_ROOT_WIN}.
Install it on Windows (PowerShell), then re-run with --setup:
    winget install --id MSYS2.MSYS2 -e
EOF
  exit 1
fi

# run a command in an MSYS2 UCRT64 login shell on the Windows host
msys() {
  MSYSTEM=UCRT64 CHERE_INVOKING=1 WSLENV="MSYSTEM:CHERE_INVOKING:${WSLENV:-}" \
    "${MSYS2}/usr/bin/bash.exe" -lc "$1"
}

if [ "${DO_SETUP}" = 1 ]; then
  echo "==> MSYS2: core update (may need two passes)"
  msys "pacman -Syuu --noconfirm" || true
  msys "pacman -Syuu --noconfirm"
fi

echo "==> sync project -> ${MSYS2_ROOT_WIN}\\opt\\cherrytree"
mkdir -p "${BUILD_DIR}"
# work/ and dist/ on the Windows side are kept between runs (incremental source checkout);
# everything else is replaced so removed/renamed patches don't linger
rm -rf "${BUILD_DIR}/patches" "${BUILD_DIR}/windows" "${BUILD_DIR}/look" "${BUILD_DIR}/macos"
# (tar exit 1 = "file changed as we read it", e.g. an editor saving meanwhile: harmless here)
{ tar -C "${HERE}" --exclude=./ref --exclude=./dist --exclude=./work --exclude=./logs --exclude=./.git \
      --warning=no-file-changed -cf - . || [ $? -eq 1 ]; } \
  | tar -C "${BUILD_DIR}" -xf -

if [ "${DO_SETUP}" = 1 ]; then
  echo "==> MSYS2: build dependencies"
  msys "cd '${BUILD_MSYS_PATH}' && bash windows/msys2-setup.sh"
fi

if [ "${DO_BUILD}" = 1 ]; then
  echo "==> build"
  msys "cd '${BUILD_MSYS_PATH}' && bash windows/msys2-build.sh ${BUILD_ARGS[*]:-}"
  mkdir -p "${HERE}/dist"
  # only the release files (dist/ may also hold a folder someone unzipped there)
  find "${BUILD_DIR}/dist" -maxdepth 1 -type f \( -name "*.zip" -o -name "*.exe" \) -exec cp -v {} "${HERE}/dist/" \;
  # finished builds only: C:\msys64\opt\cherrytree\release is never written while building
  "$(wslpath -u 'C:\Windows\System32\Robocopy.exe')" "$(wslpath -w "${BUILD_DIR}/dist")" \
    "$(wslpath -w "${BUILD_DIR}/release")" "*.zip" "*.exe" /NFL /NDL /NJH /NJS /NP >/dev/null || true
  echo "==> release: $(wslpath -w "${BUILD_DIR}/release")"
fi

if [ "${DO_RUN}" = 1 ]; then
  EXE="$(ls -d "${BUILD_DIR}"/work/cherrytree_*_win64/CherryTree.exe | tail -1)"
  echo "==> start $(wslpath -w "${EXE}") (PATH = Windows only, like on another PC)"
  # cd to a Windows dir first so cmd.exe doesn't start inside \\wsl.localhost
  ( cd "$(dirname "${EXE}")" && cmd.exe /c "set PATH=%SystemRoot%\\System32;%SystemRoot%&& start \"\" \"$(wslpath -w "${EXE}")\"" ) >/dev/null 2>&1
fi
