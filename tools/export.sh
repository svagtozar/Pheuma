#!/usr/bin/env bash
# Сборка релизов под Windows и Linux в build/.
# Нужны Godot 4.4.1 ($GODOT, по умолчанию godot в PATH) и шаблоны экспорта той же версии
# (Editor → Manage Export Templates, или см. .github/workflows/build.yml).
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
mkdir -p build/windows build/linux
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . --export-release "Windows" build/windows/Pneuma.exe
"$GODOT" --headless --path . --export-release "Linux" build/linux/Pneuma.x86_64
ls -la build/windows build/linux
