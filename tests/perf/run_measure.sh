#!/bin/bash
# ig-7sn.5: runs perf_baseline.gd measures, one windowed run each, every run on a fresh copy of a seeded
# throwaway APPDATA (see seed_perf.gd), never the owner's. Holds (exit 3) while a game or Godot runs.
#   tests/perf/run_measure.sh <seeded APPDATA> <bead> <measure>...
# Logs go to .agent-results/<bead>/<measure>.log; the summary lines are printed.
# ig-7sn.21: MODE=headless runs --headless instead (CPU only, no draw: its whole-frame rows are not the windowed
# ones) and names the log headless_<measure>.log. The reap is by this checkout's path, never another's Godot.
set -u
if [ $# -lt 3 ]; then echo "usage: $0 <seeded APPDATA> <bead> <measure>..."; exit 2; fi
MODE=${MODE:-windowed}; case "$MODE" in windowed|headless) ;; *) echo "bad MODE: $MODE"; exit 2;; esac
SEED=$1; case "$2" in *[!A-Za-z0-9._-]*|.*) echo "bad bead id: $2"; exit 2;; esac
cd "$(dirname "$0")/../.."
ROOT=$(cygpath -w "$PWD")
PFX=""; [ "$MODE" = headless ] && PFX=headless_
OUT=.agent-results/$2; shift 2
for m in "$@"; do
	case "$m" in pulse1|pulse5|pulse_split|settle1|settle5|hub|battle_citadel|battle_frontier|battle_frontier_nowall|roster|actions|dreams|town|load|preview) ;; *) echo "unknown measure: $m"; exit 2;; esac
done
mkdir -p "$OUT"
COMMIT=$(git rev-parse --short HEAD)
RUN=""
reap() { powershell -NoProfile -Command "Get-Process Godot_v4* -ErrorAction SilentlyContinue | Where-Object Path -like '${ROOT}\tools\*' | Stop-Process -Force"; [ -n "$RUN" ] && rm -rf "$RUN"; RUN=""; }
trap reap EXIT
trap 'exit 130' INT TERM HUP
for m in "$@"; do
	n=$(powershell -NoProfile -Command "(Get-Process game,Godot_v4* -ErrorAction SilentlyContinue | Measure-Object).Count" | tr -d '\r')
	if [ "$n" != "0" ]; then echo "HOLD: a game or Godot process is running ($n)"; trap - EXIT; exit 3; fi
	RUN=$(mktemp -d); cp -r "$SEED"/. "$RUN"
	APPDATA="$(cygpath -w "$RUN")" timeout 1000 ./tools/godot/Godot_v4.7.1-stable_win64_console.exe --$MODE -s res://tests/perf/perf_baseline.gd -- "$m" "$COMMIT" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' > "$OUT/$PFX$m.log"
	echo "$PFX$m exit=${PIPESTATUS[0]}"
	reap
	grep -E "^(MEASURE|APPDATA|CPU|SAVE|FRAMES|TIME|ORDER|SETTLE|ACTION|DREAM|load|roster|bond|DONE)|SCRIPT ERROR|ERROR|WARNING" "$OUT/$PFX$m.log" | cut -c1-260
done
