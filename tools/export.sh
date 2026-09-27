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
ls -la build/windows build/linux build/windows3d build/steamdeck
