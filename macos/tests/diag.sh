#!/usr/bin/env bash
# temporary: why does the bundled cherrytree hang at start (state U, no output)?
set -uo pipefail
APP="$1"
OUT="$2"; mkdir -p "$OUT"
T="$(mktemp -d)"
probe() {  # name, then the command; runs it for 15 s with library-load tracing
  local name="$1"; shift
  echo "=== ${name}"
  DYLD_PRINT_LIBRARIES=1 "$@" > "${OUT}/${name}.log" 2>&1 &
  local pid=$!
  sleep 15
  ps -o pid,stat,etime,command -p "${pid}" | cut -c1-200
  if kill -0 "${pid}" 2>/dev/null; then
    sudo spindump "${pid}" 3 10 -file "${OUT}/${name}-spindump.txt" >/dev/null 2>&1 || echo "spindump failed"
    sudo chmod a+r "${OUT}/${name}-spindump.txt" 2>/dev/null
    grep -A60 "^Thread 0x" "${OUT}/${name}-spindump.txt" 2>/dev/null | head -80
    kill -9 "${pid}" 2>/dev/null
  fi
  echo "--- $(wc -l < "${OUT}/${name}.log") log lines; last ones:"; tail -15 "${OUT}/${name}.log"
}
codesign -dvvv "${APP}" 2>&1 | head -20
codesign --verify --deep --strict --verbose=2 "${APP}" 2>&1 | tail -5
spctl --assess --type execute -vv "${APP}" 2>&1 | tail -3
xattr -lr "${APP}" | head -5
probe version "${APP}/Contents/MacOS/cherrytree" --version
probe direct "${APP}/Contents/MacOS/cherrytree"
probe launcher "${APP}/Contents/MacOS/CherryTree"
echo "=== system log (amfid, syspolicyd, kernel, cherrytree)"
log show --last 2m --style compact --predicate 'process == "amfid" OR process == "syspolicyd" OR process == "kernel" OR process CONTAINS "cherrytree" OR eventMessage CONTAINS[c] "cherrytree"' 2>/dev/null | tail -80
