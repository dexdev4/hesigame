#!/bin/bash
# Exports the cars of the garage designer (tools/garage/garage_concepts.html and more_cars.js) and turns each into the game's
# meshes, then regenerates everything that is measured from the meshes:
#   tools/models/car_X.glb              the exported model (the reference --inspect-ref shows next to the game's car)
#   assets/models/car_X.mesh, _lq.mesh  the body for near and far (tools/convert_garage.py; the far one merged on a 10 cm grid)
#   assets/models/car_X_parts/          its wheels, brake callipers, interior and steering wheel
#   tools/profiles/car_X.json           its measurements -> PROFILES / SHAPES (tools/gen_imported.py)
#   scripts/hulls.gd                    the hit boxes (tools/make_hulls.py)
#   car_shells.shells, tail_frames.gd   (tools/bake_shells.tscn, tools/bake_tails.tscn)
#
#   tools/garage/build_cars.sh [designer ids...]        (no ids: every car)
set -euo pipefail
cd "$(dirname "$0")/../.."
NODE=${NODE:-node}
GODOT=${GODOT:-godot}
declare -A FILE=(
  [pulse]=car_pulse [vector]=car_vector [hornet]=car_hornet [comet]=car_comet [kestrel]=car_kestrel [vanta]=car_vanta
  [bruiser]=car_bruiser [halcyon]=car_halcyon [copperhead]=car_copperhead [marshal]=car_marshal [static]=car_static
  [lastexit]=car_lastexit [suv]=car_traffic_suv [van]=car_traffic_van [sedan]=car_traffic_sedan [hatch]=car_traffic_hatch
)
ids=("$@")
[ ${#ids[@]} -eq 0 ] && ids=("${!FILE[@]}")
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
"$NODE" tools/garage/export.js "$out" "${ids[@]}" | grep -v '^   '
for id in "${ids[@]}"; do
  n=${FILE[$id]}
  cp "$out/$id.glb" "tools/models/$n.glb"
  python3 -I tools/convert_garage.py "tools/models/$n.glb" "assets/models/$n.mesh" > "$out/$id.log"
  python3 -I tools/convert_garage.py "tools/models/$n.glb" "assets/models/${n}_lq.mesh" lq grid=0.10 >> "$out/$id.log"   # (drawn past 18-22 m)
  echo "$id -> assets/models/$n.mesh: $(grep -c tris "$out/$id.log") surfaces, $(grep '^profile' "$out/$id.log" | cut -c1-110)"
done
python3 tools/gen_imported.py
python3 tools/make_hulls.py
"$GODOT" --headless --path . tools/bake_shells.tscn 2>&1 | grep -i "baked\|error" || true
"$GODOT" --headless --path . tools/bake_tails.tscn 2>&1 | grep -i "wrote\|error" || true
