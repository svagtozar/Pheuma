#!/usr/bin/env bash
# Rapier Physics 3D (appsinacup, MIT) — опыт с жидкостью частицами (ProtoRapierFluid).
# Аддона в git нет: скрипт качает релиз нужной версии (SIMD, параллельный),
# проверяет sha256 и кладёт в addons/godot-rapier3d библиотеки только для
# Linux и Windows x86_64. Движок физики включает tools/rapier.sh on.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="v0.8.34"    # для Godot 4.6+
SHA256="8bb9991e01cc78e47e3d3792f83d8df985e838031bd6ffd4d69d683aa15ad342"
DST=addons/godot-rapier3d
if [ -f "$DST/version.txt" ] && [ "$(cat "$DST/version.txt")" = "$VERSION" ]; then
	echo "Rapier $VERSION уже на месте"
	exit 0
fi
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fsSL -o "$tmp/r.zip" "https://github.com/appsinacup/godot-rapier-physics/releases/download/$VERSION/godot-rapier-3d-single-simd-parallel.zip"
echo "$SHA256  $tmp/r.zip" | sha256sum -c --quiet
unzip -q "$tmp/r.zip" -d "$tmp/x"
SRC="$tmp/x/godot-rapier-3d-single-simd-parallel/addons/godot-rapier3d"
rm -rf "$DST"
mkdir -p "$DST/bin"
for f in LICENSE THIRDPARTY.txt godot-rapier3d.gdextension icons; do
	cp -r "$SRC/$f" "$DST/"
done
cp "$SRC/bin/libgodot_rapier.linux.x86_64-unknown-linux-gnu.so" "$SRC/bin/libgodot_rapier.windows.x86_64-pc-windows-msvc.dll" "$DST/bin/"
echo "$VERSION" > "$DST/version.txt"
echo "Rapier $VERSION в $DST"
