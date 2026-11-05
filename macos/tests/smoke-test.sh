#!/usr/bin/env bash
# Starts CherryTree.app with a fresh profile (bundled defaults + the demo notebook, tree expanded,
# window maximised), checks it is still running after a while, takes a screenshot, then stops it.
#   macos/tests/smoke-test.sh <path/to/CherryTree.app> <output dir>
# Refuses to run if ~/Library/Application Support/CherryTree already exists (real settings).
set -euo pipefail
APP="$(cd "$1" && pwd)"
OUT="$(mkdir -p "$2" && cd "$2" && pwd)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG_DIR="${HOME}/Library/Application Support/CherryTree"
[ ! -e "${CFG_DIR}" ] || { echo "refusing: ${CFG_DIR} exists (real settings)"; exit 2; }

T="$(mktemp -d)"
cp "${HERE}/../../windows/tests/Demo Notes.ctd" "${T}/Demo Notes.ctd"
mkdir -p "${CFG_DIR}"
python3 - "${APP}/Contents/Resources/share/cherrytree/data/config-default.cfg" "${CFG_DIR}/config.cfg" "${T}/Demo Notes.ctd" <<'EOF'
import sys
src, dst, doc = sys.argv[1:]
cfg = open(src).read().replace("[state]\n", f"[state]\ndoc_0={doc}\nnodep_0=1:0\ncurs_0=0\nhpaned_pos=310\nwin_is_maximized=true\n", 1)
cfg += "\n[tree]\nrest_exp_coll=1\n[misc]\nwin_title_doc_dir=false\n"
open(dst, "w").write(cfg)
EOF

"${APP}/Contents/MacOS/CherryTree" "${T}/Demo Notes.ctd" > "${OUT}/cherrytree.log" 2>&1 &
PID=$!
sleep 30
if ! kill -0 "${PID}" 2>/dev/null; then
  echo "CherryTree exited early:"; cat "${OUT}/cherrytree.log"; exit 1
fi
echo "--- on-screen windows"; swift "${HERE}/windows.swift" | tee "${OUT}/windows.txt" || true
if ! grep -q "pid=${PID} " "${OUT}/windows.txt"; then echo "warning: no on-screen window of CherryTree (pid ${PID})"; fi
screencapture -x "${OUT}/screenshot.png" || echo "screencapture failed"
cp "${CFG_DIR}/config.cfg" "${OUT}/config-after-start.cfg" 2>/dev/null || true
kill "${PID}"; wait "${PID}" 2>/dev/null || true
rm -rf "${CFG_DIR}" "${T}"
echo "--- log"; cat "${OUT}/cherrytree.log"
echo "ok: CherryTree ran for 30 s; screenshot in ${OUT}"
