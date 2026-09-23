#!/usr/bin/env bash
# Build the showroom headless and say what came out, without opening a window.
#
#   test/demo/smoke.sh
#
# It builds the save the same way test/demo/run.sh does and then stops. What it is looking
# for is anything the showroom could not place, and any vehicle that cannot drive off its
# own mark: a bay that quietly failed to build, or one holding a vehicle that is stuck where
# it stands, looks exactly like a bay demonstrating that nothing happens.
#
# CE_AAI   set to 0 to leave AAI's vehicle mods out. They are loaded when they are in
#          ~/.factorio/mods, the same as test/demo/run.sh does it, because three of the
#          showroom's rows are theirs and a run without them never builds those rows at all.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
factorio="${CE_FACTORIO:-/home/sparr/Games/Steam/steamapps/common/Factorio/bin/x64/factorio}"
data="${CE_DEMO_DATA:-$HOME/.cache/ce-demo}"

[[ -x "$factorio" ]] || { echo "no factorio binary at $factorio" >&2; exit 2; }

mkdir -p "$data/mods" "$data/saves"
if [[ ! -f "$data/config.ini" ]]; then
    printf '[path]\nread-data=__PATH__system-read-data__\nwrite-data=%s\n' "$data" \
        > "$data/config.ini"
else
    sed -i -e "s|^write-data=.*|write-data=$data|" "$data/config.ini"
fi

ln -sfn "$root" "$data/mods/constructor-equipment"
rm -rf "$data/mods/ce-demo"
cp -r "$root/test/demo/ce-demo" "$data/mods/ce-demo"

# AAI's vehicles, on the same terms as test/demo/run.sh. Three rows of the showroom are
# theirs, and a smoke run without them reports everything placed while never laying those
# rows at all -- which is how a beached ironclad went unremarked.
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
{"name":"elevated-rails","enabled":false},
{"name":"quality","enabled":false},
{"name":"recycler","enabled":false},
{"name":"space-age","enabled":false},
$aai_entries
{"name":"constructor-equipment","enabled":true},
{"name":"ce-demo","enabled":true}
]}
JSON

save="$data/saves/smoke.zip"
rm -f "$save"
env SteamAppId=427520 "$factorio" --create "$save" \
    --mod-directory "$data/mods" -c "$data/config.ini" > "$data/smoke.log" 2>&1

grep -o 'ce-demo: built .*' "$data/smoke.log" || echo "the showroom never reported building"

missing=$(grep -c 'could not place\|could not put\|cannot drive' "$data/smoke.log" || true)
if [[ "$missing" -eq 0 ]]; then
    echo "everything placed, and every vehicle can drive off its mark"
else
    echo "$missing things wrong with the showroom:"
    grep 'could not place\|could not put\|cannot drive' "$data/smoke.log" | sed 's/^.*ce-demo: /  /'
    exit 1
fi
