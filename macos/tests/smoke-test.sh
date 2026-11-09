#!/usr/bin/env bash
# Starts CherryTree.app with a fresh profile (bundled defaults + the demo notebook, tree expanded),
# checks it shows a window, takes screenshots, and quits it with the macOS Quit command (the Apple
# Event that Dock > Quit, log out and shut down send) to check that it saves its settings:
#   1. a 900x540 window: screenshot.png, then Quit: CherryTree must exit by itself and write config.cfg
#   2. zoom the window (double-click on the titlebar, as a user does): screenshot-zoomed.png, Quit,
#      and config.cfg must say win_is_maximized=true
#   macos/tests/smoke-test.sh <path/to/CherryTree.app> <output dir>
# Refuses to run if ~/Library/Application Support/CherryTree already exists (real settings).
# Sending the Quit command needs the Automation permission for osascript (GitHub Actions: granted
# by the workflow; on a Mac, macOS asks once), clicking needs Accessibility (granted on the runners).
set -euo pipefail
APP="$(cd "$1" && pwd)"
OUT="$(mkdir -p "$2" && cd "$2" && pwd)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG_DIR="${HOME}/Library/Application Support/CherryTree"
CFG="${CFG_DIR}/config.cfg"
[ ! -e "${CFG_DIR}" ] || { echo "refusing: ${CFG_DIR} exists (real settings)"; exit 2; }
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${APP}/Contents/Info.plist")"
LAUNCHER="${APP}/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "${APP}/Contents/Info.plist")"

T="$(mktemp -d)"
cleanup() { [ -z "${PID:-}" ] || kill "${PID}" 2>/dev/null || true; rm -rf "${CFG_DIR}" "${T}"; }
trap cleanup EXIT
cp "${HERE}/../../windows/tests/Demo Notes.ctd" "${T}/Demo Notes.ctd"
mkdir -p "${CFG_DIR}"
python3 - "${APP}/Contents/Resources/share/cherrytree/data/config-default.cfg" "${CFG}" "${T}/Demo Notes.ctd" <<'EOF'
import sys
src, dst, doc = sys.argv[1:]
state = (f"[state]\ndoc_0={doc}\nnodep_0=1:0\ncurs_0=0\nhpaned_pos=250\nwin_is_maximized=false\n"
         "win_position_x=50\nwin_position_y=60\nwin_size_w=900\nwin_size_h=540\n")
cfg = open(src).read().replace("[state]\n", state, 1)
cfg += "\n[tree]\nrest_exp_coll=1\n[misc]\nwin_title_doc_dir=false\n"
open(dst, "w").write(cfg)
EOF
SEED_SUM="$(shasum "${CFG}" | cut -d' ' -f1)"
swiftc -O -o "${T}/windows" "${HERE}/windows.swift"
swiftc -O -o "${T}/click" "${HERE}/click.swift"

# start_app <log>: start CherryTree, wait for its window (up to 240 s)
start_app() {
  local log="$1" start waited
  start=$(date +%s)
  "${LAUNCHER}" "${T}/Demo Notes.ctd" > "${OUT}/${log}" 2>&1 &
  PID=$!
  while :; do
    sleep 5
    kill -0 "${PID}" 2>/dev/null || { echo "error: CherryTree exited early:"; cat "${OUT}/${log}"; exit 1; }
    "${T}/windows" > "${OUT}/windows.txt" || true
    waited=$(( $(date +%s) - start ))
    if grep -q "pid=${PID} " "${OUT}/windows.txt"; then echo "window after ${waited} s"; break; fi
    if [ "${waited}" -ge 240 ]; then
      echo "error: no window after ${waited} s; where it is:"
      ps -o pid,ppid,stat,etime,command -p "${PID}" || true
      sudo sample "${PID}" 3 -file "${OUT}/sample.txt" || true
      sudo chmod a+r "${OUT}/sample.txt" 2>/dev/null || true
      grep -v "^ *[+!:|]* *[0-9]* *???" "${OUT}/sample.txt" | head -200 || true
      exit 1
    fi
  done
  sleep 10  # let it draw
  "${T}/windows" | grep "pid=${PID} " || true
}

# quit_app: send the Quit command, CherryTree must exit by itself within 30 s
quit_app() {
  local w=0 status=0
  osascript -e "tell application id \"${BUNDLE_ID}\" to quit" > "${OUT}/quit.log" 2>&1 &
  local osa=$!
  while kill -0 "${PID}" 2>/dev/null && [ "${w}" -lt 30 ]; do sleep 1; w=$((w + 1)); done
  kill "${osa}" 2>/dev/null || true
  if kill -0 "${PID}" 2>/dev/null; then
    echo "error: CherryTree still running ${w} s after the Quit command"; cat "${OUT}/quit.log"
    exit 1
  fi
  wait "${PID}" || status=$?
  PID=""
  echo "quit after ${w} s (exit status ${status})"
}

echo "=== 1: window 900x540"
start_app cherrytree.log
screencapture -x "${OUT}/screenshot.png" || echo "screencapture failed"
quit_app
cp "${CFG}" "${OUT}/config-after-quit.cfg" 2>/dev/null || true
[ "$(shasum "${CFG}" | cut -d' ' -f1)" != "${SEED_SUM}" ] && grep -q '^autosave_on_quit=' "${CFG}" \
  && grep -q '^win_size_w=' "${CFG}" \
  || { echo "error: the Quit command didn't save the settings (config.cfg unchanged)"; exit 1; }
[ ! -e "${CFG}.tmp" ] || { echo "error: settings left in config.cfg.tmp"; exit 1; }
echo "ok: settings saved on Quit ($(wc -c < "${CFG}" | tr -d ' ') bytes; $(grep -E '^win_(size|position)_' "${CFG}" | tr '\n' ' '))"

echo "=== 2: zoomed window"
start_app cherrytree-zoomed.log
# a point on the window title, in the titlebar: bounds include GTK's ~22 px shadow margin
read -r BX BY BW < <(grep "pid=${PID} " "${OUT}/windows.txt" | head -1 | sed -E 's/.* bounds=([0-9-]+),([0-9-]+) ([0-9]+)x.*/\1 \2 \3/')
TX=$(( BX + BW * 3 / 4 )); TY=$(( BY + 42 ))
"${T}/click" "${TX}" "${TY}" 1; sleep 1   # activate
"${T}/click" "${TX}" "${TY}" 2; sleep 4   # double-click: zoom
"${T}/windows" | grep "pid=${PID} " || true
screencapture -x "${OUT}/screenshot-zoomed.png" || echo "screencapture failed"
quit_app
cp "${CFG}" "${OUT}/config-after-zoomed-quit.cfg"
grep -q '^win_is_maximized=true$' "${CFG}" \
  || { echo "error: the double-click on the titlebar didn't zoom the window (win_is_maximized not saved)"; exit 1; }
echo "ok: zoomed with a double-click on the titlebar, saved on Quit"

echo "--- log"; cat "${OUT}/cherrytree.log" "${OUT}/cherrytree-zoomed.log"
echo "ok: CherryTree started and quit cleanly twice; screenshots in ${OUT}"
