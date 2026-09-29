#!/usr/bin/env bash
# Запуск всех тестов GUT в headless-режиме.
# Путь к Godot 4.7 берётся из $GODOT (по умолчанию — godot в PATH).
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . -s addons/gut/gut_cmdln.gd -gexit
