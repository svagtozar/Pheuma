#!/usr/bin/env bash
# Сборка релизов в build/: игра под Windows и Linux и сборки для проверки 3D
# (сразу в 3D с геймпадом) под Windows и Steam Deck.
# Нужны Godot 4.4.1 ($GODOT, по умолчанию godot в PATH) и шаблоны экспорта той же версии
# (Editor → Manage Export Templates, или см. .github/workflows/build.yml).
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
mkdir -p build/windows build/linux build/windows3d build/steamdeck
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . --export-release "Windows" build/windows/Pneuma.exe
"$GODOT" --headless --path . --export-release "Linux" build/linux/Pneuma.x86_64
"$GODOT" --headless --path . --export-release "Windows 3D" build/windows3d/Pneuma3D.exe
"$GODOT" --headless --path . --export-release "Steam Deck" build/steamdeck/Pneuma.x86_64
cp docs/steamdeck.md build/steamdeck/README.md
cp tools/steamdeck/pneuma.sh build/steamdeck/pneuma.sh
chmod +x build/steamdeck/pneuma.sh
cp docs/windows3d.md build/windows3d/README.md
cp tools/windows/Pneuma3D.cmd tools/windows/update.ps1 build/windows3d/
# Версия сборки (видна в меню) и файлы автообновления 3D-сборок: манифест с sha256
# и сами файлы с префиксом deck./win. — так они лежат в релизе на GitHub.
VERSION="${PNEUMA_VERSION:-$(git describe --tags --always 2>/dev/null || echo dev)}"
rm -rf build/update
mkdir -p build/update
update_files() {  # папка сборки, префикс, файлы
	local dir=$1 prefix=$2
	shift 2
	echo "$VERSION, $(date -u '+%d.%m.%Y %H:%M') UTC" > "$dir/version.txt"
	(cd "$dir" && sha256sum "$@") > "build/update/$prefix-manifest.txt"
	for f in "$@"; do cp "$dir/$f" "build/update/$prefix.$f"; done
}
update_files build/steamdeck deck Pneuma.pck Pneuma.x86_64 pneuma.sh version.txt README.md
update_files build/windows3d win Pneuma3D.pck Pneuma3D.exe update.ps1 version.txt README.md
ls -la build/windows build/linux build/windows3d build/steamdeck build/update
