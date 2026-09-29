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
# Версия сборки (видна в меню) и файлы для автообновления на Deck: манифест
# с sha256 и те же файлы с префиксом deck. — так они лежат в релизе на GitHub.
VERSION="${PNEUMA_VERSION:-$(git describe --tags --always 2>/dev/null || echo dev)}"
echo "$VERSION · $(date -u '+%d.%m.%Y %H:%M') UTC" > build/steamdeck/version.txt
rm -rf build/steamdeck-update
mkdir -p build/steamdeck-update
DECK_FILES="Pneuma.pck Pneuma.x86_64 pneuma.sh version.txt README.md"
(cd build/steamdeck && sha256sum $DECK_FILES) > build/steamdeck-update/deck-manifest.txt
for f in $DECK_FILES; do cp build/steamdeck/$f build/steamdeck-update/deck.$f; done
ls -la build/windows build/linux build/windows3d build/steamdeck build/steamdeck-update
