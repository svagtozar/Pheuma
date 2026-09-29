#!/usr/bin/env bash
# Включить/выключить движок физики Rapier3D для опыта с жидкостью:
#   tools/rapier.sh on   — скачать аддон (get_rapier.sh) и положить override.cfg
#   tools/rapier.sh off  — убрать override.cfg (физика снова Godot)
# override.cfg в git не лежит; проект сам по себе остаётся на физике Godot.
set -euo pipefail
cd "$(dirname "$0")/.."
case "${1:-on}" in
	on)
		tools/get_rapier.sh
		printf '[physics]\n3d/physics_engine="Rapier3D"\n' > override.cfg
		echo "Физика: Rapier3D (override.cfg)";;
	off)
		rm -f override.cfg
		echo "Физика: Godot";;
	*) echo "tools/rapier.sh on|off"; exit 1;;
esac
