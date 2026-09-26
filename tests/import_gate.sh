#!/usr/bin/env bash
# ig-dpn: the Linux twin of tests/import_gate.ps1, check for check. Run as: bash tests/import_gate.sh
# Keep the two in step: a check added to one belongs in the other.

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
cd "$root" || exit 1

# Godot 4 serves its LSP on 6005, so a listening port means a Godot editor is live.
# This gate rewrites .godot/, which is not safe to race against another engine process.
if (exec 3<>/dev/tcp/127.0.0.1/6005) 2>/dev/null; then
	echo "GATE ABORTED: Godot LSP on 127.0.0.1:6005 - another engine process is live."
	echo "Stop it first:  pkill -f Godot_v4"
	exit 1
fi

# A stray process running this repo's own engine binary without serving the LSP. Match on the
# executable, not command-line text, as the .ps1 does: tools/godot/ is unique per checkout.
godot_dir="$(realpath tools/godot)"
for exe in /proc/[0-9]*/exe; do
	target="$(readlink -f "$exe" 2>/dev/null)" || continue
	case "$target" in
	"$godot_dir"/*)
		pid="${exe#/proc/}"
		pid="${pid%/exe}"
		echo "GATE ABORTED: PID $pid ($(basename "$target")) is already running this repo's engine binary ($godot_dir)."
		echo "Command line: $(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)"
		echo "Stop it first:  pkill -f Godot_v4"
		exit 1
		;;
	esac
done

godot="$root/tools/godot/Godot_v4.7.1-stable_linux.x86_64"
# The twin of the .ps1's APPDATA swap: user:// and the engine's config/cache land in a temp dir.
xdg="$(mktemp -d)"
trap 'rm -rf "$xdg"' EXIT
export XDG_DATA_HOME="$xdg/data" XDG_CONFIG_HOME="$xdg/config" XDG_CACHE_HOME="$xdg/cache"

warmup_output="$("$godot" --headless --import 2>&1)"
output="$("$godot" --headless --quit 2>&1)"
engine_exit=$?
# ig-rd9: every .gd under tests/ that GUT doesn't run (test_*.gd directly in a folder named unit).
mapfile -t standalone < <(find tests -name '*.gd' ! -regex '.*/unit/test_[^/]*' | LC_ALL=C sort | sed 's|^|res://|')
parse_output="$("$godot" --headless -s res://tests/gate_parse.gd -- "${standalone[@]}" 2>&1)"
parse_exit=$?
printf '%s\n' "$warmup_output" "$output" "$parse_output"

# -i: PowerShell's -match ignores case, so the .ps1 also fails on "Warning" or "error:".
if printf '%s\n%s\n' "$output" "$parse_output" | grep -qiE 'SCRIPT ERROR|ERROR:|WARNING'; then
	exit 1
fi
if [ "$parse_exit" -ne 0 ]; then
	exit 1
fi

exit "$engine_exit"
