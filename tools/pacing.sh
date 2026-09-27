#!/usr/bin/env bash
# Бот темпа 3D (tools/pacing.gd) на нескольких планетах, по 3 параллельно, и сводка.
#   tools/pacing.sh [сиды…]        (по умолчанию 1 7 8 12 14 31 32 40)
# JSON по планетам — в build/pacing/, таблица — в build/pacing/summary.md.
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
OUT=build/pacing
mkdir -p "$OUT"
rm -f "$OUT"/*.json
SEEDS=("$@")
[ ${#SEEDS[@]} -eq 0 ] && SEEDS=(1 7 8 12 14 31 32 40)
for s in "${SEEDS[@]}"; do
	"$GODOT" --headless --fixed-fps 30 --path . -s tools/pacing.gd -- --seed="$s" --run --mute \
		--auto=pace --limit="${LIMIT:-40}" --out="$OUT/$s.json" > "$OUT/$s.log" 2>&1 &
	while [ "$(jobs -rp | wc -l)" -ge "${JOBS:-3}" ]; do wait -n; done
done
wait
"$GODOT" --headless --path . -s tools/pacing.gd -- --summary="$OUT" 2>/dev/null | grep '^|' | tee "$OUT/summary.md"
