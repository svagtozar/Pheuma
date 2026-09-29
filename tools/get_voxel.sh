#!/usr/bin/env bash
# Voxel Tools (Zylann, MIT) — рельеф 3D на VoxelLodTerrain. Библиотеки модуля
# (~10 МБ на платформу) в git не лежат: скрипт качает релиз GDExtension нужной
# версии и кладёт в addons/zylann.voxel/bin только Linux и Windows x86_64
# (редактор — для запуска и тестов, template_release — для сборок).
# Запускать один раз после клонирования и при смене версии (CI делает сам).
# Без библиотек игра тоже идёт: рельеф строится по-старому (ProtoTerrainChunks).
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="v1.7x"      # Voxel Tools 1.7, GDExtension для Godot 4.5+
SHA256="600737572a5e25541ba6f503e842a3717ba19afafa5474510a6ceff995a1d2d8"
BIN=addons/zylann.voxel/bin
if [ -f "$BIN/version.txt" ] && [ "$(cat "$BIN/version.txt")" = "$VERSION" ]; then
	echo "Voxel Tools $VERSION уже на месте"
	exit 0
fi
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fsSL -o "$tmp/vox.zip" "https://github.com/Zylann/godot_voxel/releases/download/$VERSION/GodotVoxelExtension.zip"
echo "$SHA256  $tmp/vox.zip" | sha256sum -c --quiet
mkdir -p "$BIN"
for f in libvoxel.linux.editor.x86_64.so libvoxel.linux.template_release.x86_64.so \
		libvoxel.windows.editor.x86_64.dll libvoxel.windows.template_release.x86_64.dll; do
	unzip -qoj "$tmp/vox.zip" "addons/zylann.voxel/bin/$f" -d "$BIN"
done
echo "$VERSION" > "$BIN/version.txt"
echo "Voxel Tools $VERSION: $(ls "$BIN" | grep -c libvoxel) библиотеки в $BIN"
