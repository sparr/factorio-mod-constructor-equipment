#!/usr/bin/env bash
# Launch the game with this mod and the showroom, and nothing else.
#
#   test/demo/run.sh
#
# The showroom is one of every thing this mod does, in labelled bays laid out in rows on a
# surface of its own, to be walked round. Every bay says where to stand and what to do, on
# the ground above it. What is in it is in test/demo/README.md. /ce-demo builds it again.
#
# The game runs out of its own data directory, so nothing here touches your real mods,
# saves or settings. The repo is symlinked in, so whatever is in the working tree is what
# loads -- script changes are picked up by restarting, prototype changes too. Editor
# Extensions and flib (its one dependency) come from the newest zips in ~/.factorio/mods.
#
# CE_FACTORIO    the game binary, if it is not where Steam puts it here
# CE_DEMO_DATA   the data directory the game runs out of (default ~/.cache/bo-play)
# CE_SPACE_AGE   set to 1 to load the expansion as well, which the quality row wants
# CE_AAI         set to 0 to leave AAI's vehicle mods out. They are loaded when they are in
#                ~/.factorio/mods, because the rows about their hulls are worth seeing and
#                the showroom leaves those rows out when the vehicles are not there.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
factorio="${CE_FACTORIO:-/home/sparr/Games/Steam/steamapps/common/Factorio/bin/x64/factorio}"
data="${CE_DEMO_DATA:-$HOME/.cache/ce-demo}"

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

# Everything the game writes goes to the throwaway directory. read-data is left as the
# game wrote it, since it resolves against the binary and so already points at the
# installation this is launching.
if grep -q '^write-data=' "$data/config.ini"; then
    sed -i -e "s|^write-data=.*|write-data=$data|" "$data/config.ini"
else
    sed -i -e "/^\[path\]/a write-data=$data" "$data/config.ini"
fi

# The two that have to be said out loud. A throwaway session must not push its blueprint
# library into the player's Steam Cloud: with the sync left on, the game pulls the real
# library in on the way up and writes whatever the session did with it back out again, so
# an evening of testing can edit the blueprints of a game nobody was testing.
grep -q '^\[other\]' "$data/config.ini" || printf '\n[other]\n' >> "$data/config.ini"
sed -i \
    -e 's|^check-updates=|; check-updates=|' \
    -e 's|^enable-blueprint-storage-cloud-sync=|; enable-blueprint-storage-cloud-sync=|' \
    "$data/config.ini"
sed -i -e '/^\[other\]/a check-updates=false\nenable-blueprint-storage-cloud-sync=false' \
    "$data/config.ini"

ln -sfn "$root" "$data/mods/constructor-equipment"
rm -rf "$data/mods/ce-demo"
cp -r "$root/test/demo/ce-demo" "$data/mods/ce-demo"

# The expansion mods ship inside the installation and are enabled unless a mod-list says
# otherwise -- leaving them out of the list is not the same as switching them off, and the
# first version of this script found that out by loading the whole of Space Age into a
# session that had asked for two mods. Name every one of them, every time.
# CE_SPACE_AGE=1 turns them back on, the same knob test/ft/run.sh uses.
expansion=false
[[ "${CE_SPACE_AGE:-0}" == "1" ]] && expansion=true
# AAI's vehicles, if they have been asked for and are there to be had. Each is its own mod
# and none is a dependency of anything here: the rows about them are left out of the
# showroom when they are absent, so this only ever adds rows.
aai_entries=""
if [[ "${CE_AAI:-1}" == "1" ]]; then
    for want in aai-vehicles-chaingunner aai-vehicles-ironclad aai-vehicles-hauler; do
        found=$(ls -1 "$HOME/.factorio/mods/${want}"_*.zip 2>/dev/null | sort -V | tail -1)
        if [[ -n "$found" ]]; then
            ln -sfn "$found" "$data/mods/$(basename "$found")"
            aai_entries+="{\"name\":\"$want\",\"enabled\":true},"
        else
            echo "no $want installed; the showroom will leave its row out" >&2
        fi
    done
fi

cat > "$data/mods/mod-list.json" <<JSON
{"mods":[
{"name":"base","enabled":true},
{"name":"elevated-rails","enabled":$expansion},
{"name":"quality","enabled":$expansion},
{"name":"recycler","enabled":$expansion},
{"name":"space-age","enabled":$expansion},
$aai_entries
{"name":"constructor-equipment","enabled":true},
{"name":"ce-demo","enabled":true}
]}
JSON

# Built first and then loaded, rather than left at the menu for somebody to pick freeplay
# out of. Freeplay is the wrong thing to start here twice over: it runs its own scenario,
# and it puts the player beside a crashed ship on Nauvis rather than in the showroom. The
# save is made fresh every time so that whatever is in the working tree is what gets built.
mkdir -p "$data/saves"
save="$data/saves/showroom.zip"
rm -f "$save"
env SteamAppId=427520 "$factorio" --create "$save" \
    --mod-directory "$data/mods" -c "$data/config.ini" > "$data/create.log" 2>&1
[[ -s "$save" ]] || {
    echo "the showroom could not be built. The end of $data/create.log:" >&2
    tail -20 "$data/create.log" >&2
    exit 1
}
missing=$(grep -c 'could not place' "$data/create.log" || true)
[[ "$missing" -eq 0 ]] ||
    echo "warning: $missing things could not be placed; see $data/create.log" >&2

# SteamAppId keeps the Steam client from taking over the launch.
exec env SteamAppId=427520 "$factorio" -c "$data/config.ini" \
    --mod-directory "$data/mods" --load-game "$save"
