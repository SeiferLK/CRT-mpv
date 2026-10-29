#!/usr/bin/env bash
# CRT-mpv updater for macOS and Linux. Started by config/scripts/update.lua when "Update now" is chosen in the player:
#   mac-linux/update.sh URL SHA256 TAG PLAYER_PID [arguments for mac-linux/crt-mpv ...]
# Waits for the player to close, downloads the release from GitHub (checked against GitHub's SHA-256 when it
# publishes one), installs it over this folder, fetches anything new it needs (mac-linux/install.sh) and starts
# CRT-mpv again on the same video. Kept as they are: config/settings.json, resume positions, the shader cache and TV
# pictures you added yourself (their tvs.json entries are carried over when python3 is available). Every file it
# replaces or removes is copied to backup/<old version>-<date>/ first; if anything goes wrong the old version is put back.
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
url=$1 sha=$2 tag=$3 pid=$4
shift 4
relaunch=("$@")
start_player() { nohup "$root/mac-linux/crt-mpv" "$1" ${relaunch[@]+"${relaunch[@]}"} >/dev/null 2>&1 & }

sha_ok() {   # file expected-hash
    if command -v sha256sum >/dev/null 2>&1; then echo "$2  $1" | sha256sum -c - >/dev/null 2>&1
    else echo "$2  $1" | shasum -a 256 -c - >/dev/null 2>&1; fi
}

# wait for the player to close (it is never stopped from here)
for _ in $(seq 1 60); do kill -0 "$pid" 2>/dev/null || break; sleep 0.25; done
kill -0 "$pid" 2>/dev/null && exit 1

tmp="$(mktemp -d)"
backup=""
added=() saved=()
cleanup() { rm -rf "$tmp"; }
trap cleanup EXIT
fail() {
    echo "CRT-mpv update failed: $1" >&2
    if [ -n "$backup" ]; then                       # put the old version back
        for rel in ${added[@]+"${added[@]}"}; do rm -f "$root/$rel"; done
        for rel in ${saved[@]+"${saved[@]}"}; do cp -p "$backup/$rel" "$root/$rel"; done
    fi
    start_player --script-opts-append=crt-update-failed=1
    exit 1
}
save_old() { mkdir -p "$(dirname "$backup/$1")" && cp -p "$root/$1" "$backup/$1" && saved+=("$1"); }

curl -fsSL -A "CRT-mpv updater" "$url" -o "$tmp/update.zip" || fail "download"
if [ -n "$sha" ]; then sha_ok "$tmp/update.zip" "$sha" || fail "checksum mismatch"; fi
mkdir "$tmp/x"
if command -v unzip >/dev/null 2>&1; then unzip -q "$tmp/update.zip" -d "$tmp/x" || fail "unpack"
else python3 -m zipfile -e "$tmp/update.zip" "$tmp/x" || fail "unpack"; fi
inst="$(find "$tmp/x" -maxdepth 4 -path '*/tools/install.ps1' | head -1)"
[ -n "$inst" ] || fail "not a CRT-mpv release"
new="$(cd "$(dirname "$inst")/.." && pwd)"
for must in VERSION config/scripts/crt.lua config/overlays/tvs.json; do [ -f "$new/$must" ] || fail "$must missing"; done

# TVs you added (a picture in config/overlays plus an entry in tvs.json) stay in the new tvs.json
if [ -f "$root/config/overlays/tvs.json" ] && command -v python3 >/dev/null 2>&1; then
    python3 - "$root" "$new" <<'EOF' || fail "tvs.json"
import json, os, sys
root, new = sys.argv[1], sys.argv[2]
old_p, new_p = os.path.join(root, "config/overlays/tvs.json"), os.path.join(new, "config/overlays/tvs.json")
shipped = json.load(open(new_p))
names = {t["name"] for t in shipped}
mine = [t for t in json.load(open(old_p))
        if t["name"] not in names and os.path.exists(os.path.join(root, "config/overlays", t["name"] + ".png"))]
if mine:
    with open(new_p, "w") as f:
        f.write("[\n" + ",\n".join(" " + json.dumps(t) for t in shipped + mine) + "\n]\n")
EOF
fi

old="$(head -1 "$root/VERSION" 2>/dev/null | tr -d '[:space:]')"
backup="$root/backup/${old:-old}-$(date +%Y%m%d-%H%M%S)"
keep='^(config/settings\.json|config/update\.json|config/open-locations\.json|config/watch_later/|config/cache/|backup/|mpv/|\.cache/|CRT-mpv\.exe$|\.update-manifest$)'
files="$(cd "$new" && find . -type f | sed 's|^\./||' | grep -Ev "$keep")"
while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    if [ -f "$root/$rel" ]; then
        cmp -s "$new/$rel" "$root/$rel" && continue
        save_old "$rel" || fail "backup"
    else added+=("$rel"); fi
    mkdir -p "$(dirname "$root/$rel")" && cp -p "$new/$rel" "$root/$rel" || fail "copy $rel"
done <<< "$files"
# files the previous update installed that this release no longer has
if [ -f "$root/.update-manifest" ]; then
    while IFS= read -r rel; do
        [ -n "$rel" ] && [ -f "$root/$rel" ] || continue
        grep -qxF "$rel" <<< "$files" && continue
        save_old "$rel" && rm -f "$root/$rel"
    done < "$root/.update-manifest"
    save_old .update-manifest
else added+=(.update-manifest); fi
printf '%s\n' "$files" > "$root/.update-manifest"
chmod +x "$root/mac-linux/"*.sh "$root/mac-linux/crt-mpv" 2>/dev/null

bash "$root/mac-linux/install.sh" >/dev/null 2>&1 || fail "install.sh"
ls -1d "$root/backup/"*/ 2>/dev/null | sort -r | tail -n +4 | while IFS= read -r d; do rm -rf "$d"; done
start_player "--script-opts-append=crt-update-done=$tag"
