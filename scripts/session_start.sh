#!/usr/bin/env bash
# ig-dpn: the one SessionStart hook (.claude/settings.json).
# Locally it only runs `bd prime --hook-json`, as the hook did before.
# In a cloud session (CLAUDE_CODE_REMOTE=true) it first installs what is missing:
#   Godot 4.7.1 Linux into tools/godot/, bd 1.2.2 into /usr/local/bin,
#   both from our release cloud-tools-v1, pinned by sha256; then `bd bootstrap --yes` if no database.
# Stdout is the hook's JSON, so every log line goes to stderr. It never exits 2 (that would block
# the session start): a failed step says so and exits 1. Each step checks first, so a rerun is a no-op.
set -u

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
	command -v bd >/dev/null 2>&1 || exit 0
	exec bd prime --hook-json
fi

root="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$root" || { echo "session_start: no project dir $root" >&2; exit 1; }

REPO="Joony117/Hearthbound"
TAG="cloud-tools-v1"
GODOT_ZIP="Godot_v4.7.1-stable_linux.x86_64.zip"
GODOT_SHA="c7ff14fd28472c8d4f193043de30278dcf7e5241a1dcf7566b02e27addaa33ba"
GODOT_BIN="tools/godot/Godot_v4.7.1-stable_linux.x86_64"
BD_TGZ="beads_1.2.2_linux_amd64.tar.gz"
BD_SHA="8140098a51d3b81d5548d1c5e6db1a2d9930e5d141efe2a4bff7d079c4d321e8"
BD_VERSION="1.2.2"
export GH_TOKEN="${GH_TOKEN:-proxy-injected}"

log() { echo "session_start: $*" >&2; }
fail() { log "FAILED: $*"; exit 1; }

# REST only: the cloud's GitHub proxy limits GraphQL. gh when the image has it, else curl
# (the proxy injects the session's credentials into api.github.com either way).
api() {
	if command -v gh >/dev/null 2>&1; then
		gh api "$@"
	else
		local accept="application/vnd.github+json"
		if [ "$1" = "-H" ]; then accept="${2#Accept: }"; shift 2; fi
		curl -fsSL -H "Accept: $accept" -H "Authorization: Bearer $GH_TOKEN" "https://api.github.com/$1"
	fi
}

release_json=""
# fetch <asset name> <sha256> <out file>: downloads one asset of $TAG, deletes it on a hash mismatch.
fetch() {
	local name="$1" sha="$2" out="$3" id
	if [ -z "$release_json" ]; then
		release_json="$(api "repos/$REPO/releases/tags/$TAG")" || { log "cannot read release $TAG"; return 1; }
	fi
	id="$(printf '%s' "$release_json" | jq -r --arg n "$name" '.assets[] | select(.name == $n) | .id')"
	[ -n "$id" ] || { log "release $TAG has no asset $name"; return 1; }
	log "downloading $name (asset $id)"
	api -H "Accept: application/octet-stream" "repos/$REPO/releases/assets/$id" > "$out" || { rm -f "$out"; log "download of $name failed"; return 1; }
	if [ "$(sha256sum "$out" | cut -d' ' -f1)" != "$sha" ]; then
		rm -f "$out"
		log "sha256 mismatch on $name, file deleted"
		return 1
	fi
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

if [ -x "$GODOT_BIN" ]; then
	log "Godot present: $GODOT_BIN"
else
	fetch "$GODOT_ZIP" "$GODOT_SHA" "$tmp/godot.zip" || fail "Godot install"
	mkdir -p tools/godot
	unzip -q -o "$tmp/godot.zip" "$(basename "$GODOT_BIN")" -d tools/godot || fail "Godot unzip"
	chmod +x "$GODOT_BIN"
	log "Godot installed: $GODOT_BIN"
fi

if command -v bd >/dev/null 2>&1 && bd version 2>/dev/null | grep -q "$BD_VERSION"; then
	log "bd $BD_VERSION present"
else
	fetch "$BD_TGZ" "$BD_SHA" "$tmp/bd.tgz" || fail "bd install"
	tar -xzf "$tmp/bd.tgz" -C "$tmp" || fail "bd untar"
	bd_src="$(find "$tmp" -type f -name bd | head -n 1)"
	[ -n "$bd_src" ] || fail "no bd binary in $BD_TGZ"
	install -m 0755 "$bd_src" /usr/local/bin/bd || fail "bd copy to /usr/local/bin"
	bd version 2>/dev/null | grep -q "$BD_VERSION" || fail "bd version is not $BD_VERSION"
	log "bd $BD_VERSION installed"
fi

# The Dolt database is gitignored; the cloud rebuilds it from the tracked .beads/issues.jsonl.
if [ -d .beads/dolt ] || [ -d .beads/embeddeddolt ]; then
	log "beads database present"
else
	log "bd bootstrap from .beads/issues.jsonl"
	bd bootstrap --yes >&2 || fail "bd bootstrap"
fi

exec bd prime --hook-json
