#!/usr/bin/env bash
# Stand a player on every mark in the showroom and say what the arms did.
#
#   test/demo/probe.sh
#
# A bay that misbehaves in the showroom while the test covering it passes is a difference
# between the two, and the only way to find it is to work the showroom itself. This runs a
# real graphical session on a private framebuffer, because the mod needs a player with a
# character and only a client makes one, and ce-probe walks that player round.
#
# Everything is torn down at the end; the PID is tracked so nothing else is killed.
#
# CE_FACTORIO    the game binary, if it is not where Steam puts it here
# CE_DEMO_DATA   the data directory the game runs out of (default ~/.cache/ce-probe)
# CE_PROBE_WAIT  how long to give it before giving up (default 900 seconds)
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
factorio="${CE_FACTORIO:-/home/sparr/Games/Steam/steamapps/common/Factorio/bin/x64/factorio}"
data="${CE_DEMO_DATA:-$HOME/.cache/ce-probe}"
patience="${CE_PROBE_WAIT:-900}"

[[ -x "$factorio" ]] || { echo "no factorio binary at $factorio" >&2; exit 2; }

mkdir -p "$data/mods" "$data/saves"
printf '[path]\nread-data=__PATH__system-read-data__\nwrite-data=%s\n\n[other]\ncheck-updates=false\nenable-blueprint-storage-cloud-sync=false\n' \
    "$data" > "$data/config.ini"

ln -sfn "$root" "$data/mods/constructor-equipment"
rm -rf "$data/mods/ce-demo" "$data/mods/ce-probe"
cp -r "$root/test/demo/ce-demo" "$data/mods/ce-demo"
cp -r "$root/test/demo/ce-probe" "$data/mods/ce-probe"
cat > "$data/mods/mod-list.json" <<JSON
{"mods":[
{"name":"base","enabled":true},
{"name":"elevated-rails","enabled":false},
{"name":"quality","enabled":false},
{"name":"recycler","enabled":false},
{"name":"space-age","enabled":false},
{"name":"constructor-equipment","enabled":true},
{"name":"ce-demo","enabled":true},
{"name":"ce-probe","enabled":true}
]}
JSON

save="$data/saves/probe.zip"
rm -f "$save"
env SteamAppId=427520 "$factorio" --create "$save" \
    --mod-directory "$data/mods" -c "$data/config.ini" > "$data/create.log" 2>&1
[[ -s "$save" ]] || { echo "the showroom could not be built:" >&2; tail -20 "$data/create.log" >&2; exit 1; }

# A display nobody is using. xvfb-run -n attaches to one that already exists rather than
# failing, so the number is checked for an answer rather than for a socket file.
display=""
for try in $(seq 131 160); do
    if ! DISPLAY=":$try" xdpyinfo >/dev/null 2>&1; then display="$try"; break; fi
done
[[ -n "$display" ]] || { echo "no free display between :131 and :160" >&2; exit 1; }

rm -f "$data/factorio-current.log"
setsid nice -n 19 xvfb-run -n "$display" -s "-screen 0 1280x800x24" \
    env LIBGL_ALWAYS_SOFTWARE=1 SDL_AUDIODRIVER=dummy SteamAppId=427520 \
    bash -c 'xfwm4 >/dev/null 2>&1 & sleep 1; exec "$@"' _ \
    "$factorio" -c "$data/config.ini" --mod-directory "$data/mods" --load-game "$save" \
    > "$data/probe.log" 2>&1 &
game=$!

trap 'kill -TERM -"$game" 2>/dev/null || kill -TERM "$game" 2>/dev/null || true;
      pkill -f "factorio .*--mod-directory $data/mods" 2>/dev/null || true;
      pkill -f "Xvfb :$display " 2>/dev/null || true' EXIT

waited=0
while (( waited < patience )); do
    if grep -q 'CEPROBE DONE' "$data/factorio-current.log" 2>/dev/null; then break; fi
    if ! kill -0 "$game" 2>/dev/null; then echo "the session ended early" >&2; break; fi
    sleep 5
    waited=$((waited + 5))
done

# The whole process group, not just the launcher: xvfb-run forks the game and the window
# manager under an Xvfb of its own, and killing the one it knows about leaves the game
# running on a display nobody can see for as long as the machine is up. Found the hard way,
# with a session still playing itself forty minutes later.
kill -TERM -"$game" 2>/dev/null || kill -TERM "$game" 2>/dev/null || true
sleep 2
pkill -f "factorio .*--mod-directory $data/mods" 2>/dev/null || true
pkill -f "Xvfb :$display " 2>/dev/null || true
wait "$game" 2>/dev/null || true
trap - EXIT

grep -o 'CEPROBE .*' "$data/factorio-current.log" 2>/dev/null || echo "the probe said nothing"
grep -n 'Error\|caused a non-recoverable' "$data/factorio-current.log" 2>/dev/null | head -5 || true
