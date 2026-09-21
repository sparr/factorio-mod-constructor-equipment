#!/usr/bin/env bash
# Stall tier: a real game laid out on the one reproduction of the standing-still stall.
#
#   test/stall.sh                        # a fresh game, the ring already marked
#   CE_SPACE_AGE=1 test/stall.sh         # with the expansion as well
#
# Eight transport belts marked for deconstruction in a ring round a character wearing a
# fourth tier arm. Three of them are taken up and then the claw takes a job on a fourth,
# reports itself working, and never extends towards it. See TODO.md, item 18.
#
# What the stall turns on is a set of positions nothing in the game draws, so ce-stall draws
# them: the arm's base, the claw, where it is told to pick up from and drop to, and the boxes
# standing at each. The orange line is the journey the hand is refusing to make.
#
#   /ce-stall    lay the ring out again
#   /ce-ring 3   lay it out three tiles out instead of one, which is the spacing that works
#   /ce-arm      print everything about the arm, once
#   /ce-watch    print that line on every tick it changes
#   /ce-draw     turn the markers on and off
#
# The game runs out of its own data directory, so nothing here touches your real mods, saves
# or settings. The repo is symlinked in, so whatever is in the working tree is what loads:
# script changes are picked up by restarting, and so are prototype changes.
#
# CE_FACTORIO     the game binary, if it is not where Steam puts it here
# CE_STALL_DATA   the data directory the game runs out of (default ~/.cache/ce-stall)
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
factorio="${CE_FACTORIO:-/home/sparr/Games/Steam/steamapps/common/Factorio/bin/x64/factorio}"
data="${CE_STALL_DATA:-$HOME/.cache/ce-stall}"

[[ -x "$factorio" ]] || { echo "no factorio binary at $factorio" >&2; exit 2; }

mkdir -p "$data/mods"

# Start from the player's own config, so the session has their keybindings, graphics and
# audio rather than the defaults, and then override only what has to differ. A config with
# nothing in it but a path makes the game log "Resetting config" and play with stock
# settings, which is a poor way to spend an evening. The real file is read and never
# written.
real_config="$HOME/.factorio/config/config.ini"
if [[ -f "$real_config" ]]; then
    cp "$real_config" "$data/config.ini"
else
    printf '[path]\nread-data=__PATH__system-read-data__\nwrite-data=__PATH__system-write-data__\n\n[other]\n' \
        > "$data/config.ini"
fi

# Everything the game writes goes to the throwaway directory. read-data is left as the game
# wrote it, since it resolves against the binary and so already points at the installation
# this is launching.
if grep -q '^write-data=' "$data/config.ini"; then
    sed -i -e "s|^write-data=.*|write-data=$data|" "$data/config.ini"
else
    sed -i -e "/^\[path\]/a write-data=$data" "$data/config.ini"
fi

# The one that has to be said out loud. A throwaway session must not push its blueprint
# library into the player's Steam Cloud: with the sync left on, the game pulls the real
# library in on the way up and writes whatever the session did with it back out again.
grep -q '^\[other\]' "$data/config.ini" || printf '\n[other]\n' >> "$data/config.ini"
sed -i \
    -e 's|^check-updates=|; check-updates=|' \
    -e 's|^enable-blueprint-storage-cloud-sync=|; enable-blueprint-storage-cloud-sync=|' \
    "$data/config.ini"
sed -i -e '/^\[other\]/a check-updates=false\nenable-blueprint-storage-cloud-sync=false' \
    "$data/config.ini"

ln -sfn "$root" "$data/mods/constructor-equipment"
ln -sfn "$root/test/stall/ce-stall" "$data/mods/ce-stall"

# The expansion mods ship inside the installation and are enabled unless a mod list says
# otherwise: leaving one out of the list is not the same as switching it off. Name every
# one of them, every time.
expansion=false
[[ "${CE_SPACE_AGE:-0}" == "1" ]] && expansion=true
cat > "$data/mods/mod-list.json" <<JSON
{"mods":[
{"name":"base","enabled":true},
{"name":"elevated-rails","enabled":$expansion},
{"name":"quality","enabled":$expansion},
{"name":"recycler","enabled":$expansion},
{"name":"space-age","enabled":$expansion},
{"name":"constructor-equipment","enabled":true},
{"name":"ce-stall","enabled":true}
]}
JSON

# A fresh game every time, because the setup runs on_init and a save would already have had
# it. SteamAppId keeps the Steam client from taking over the launch.
exec env SteamAppId=427520 "$factorio" \
    -c "$data/config.ini" \
    --mod-directory "$data/mods" \
    --load-scenario base/freeplay \
    "$@"
