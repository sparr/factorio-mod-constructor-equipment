#!/usr/bin/env bash
# Build the showroom headless and say what came out, without opening a window.
#
#   test/demo/smoke.sh
#
# It builds the save the same way test/demo/run.sh does and then stops. What it is looking
# for is anything the showroom could not place: a bay that quietly failed to build looks
# exactly like a bay demonstrating that nothing happens.
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
cat > "$data/mods/mod-list.json" <<JSON
{"mods":[
{"name":"base","enabled":true},
{"name":"elevated-rails","enabled":false},
{"name":"quality","enabled":false},
{"name":"recycler","enabled":false},
{"name":"space-age","enabled":false},
{"name":"constructor-equipment","enabled":true},
{"name":"ce-demo","enabled":true}
]}
JSON

save="$data/saves/smoke.zip"
rm -f "$save"
env SteamAppId=427520 "$factorio" --create "$save" \
    --mod-directory "$data/mods" -c "$data/config.ini" > "$data/smoke.log" 2>&1

grep -o 'ce-demo: built .*' "$data/smoke.log" || echo "the showroom never reported building"

missing=$(grep -c 'could not place\|could not put' "$data/smoke.log" || true)
if [[ "$missing" -eq 0 ]]; then
    echo "everything placed"
else
    echo "$missing things could not be placed:"
    grep 'could not place\|could not put' "$data/smoke.log" | sed 's/^.*ce-demo: /  /'
    exit 1
fi
