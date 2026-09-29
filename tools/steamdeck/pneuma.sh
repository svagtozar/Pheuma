#!/usr/bin/env bash
# Запуск Pneuma на Steam Deck с автообновлением.
# Перед стартом сверяет файлы с последней сборкой на GitHub и докачивает только
# изменившиеся: обычно это Pneuma.pck (~1–2 МБ), движок Pneuma.x86_64 меняется
# лишь при смене версии Godot. Нет сети или что-то пошло не так — запускает то, что есть.
#
# Канал берётся из channel.txt рядом со скриптом:
#   nightly (по умолчанию) — каждая сборка main
#   stable                 — последний релиз v*
#   off                    — не обновляться
set -u
DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
cd "$DIR" || exit 1
REPO="svagtozar/Pheuma"
FILES="Pneuma.pck Pneuma.x86_64 pneuma.sh version.txt README.md"

channel="$({ tr -d "[:space:]" < channel.txt; } 2>/dev/null)"
case "${channel:-nightly}" in
	off) base="" ;;
	stable) base="https://github.com/$REPO/releases/latest/download" ;;
	*) base="https://github.com/$REPO/releases/download/deck-nightly" ;;
esac
base="${PNEUMA_UPDATE_URL-$base}"  # для проверки со своего сервера

log() { echo "$(date '+%F %T') $*" >> update.log; }
[ -f update.log ] && tail -n 200 update.log > update.log.tmp && mv -f update.log.tmp update.log

update() {
	local tmp manifest sum name need=""
	tmp="$(mktemp -d "$DIR/.update.XXXXXX")" || return 1
	trap 'rm -rf "$tmp"' RETURN
	manifest="$tmp/manifest"
	curl -fsL --connect-timeout 3 --max-time 10 -o "$manifest" "$base/deck-manifest.txt" \
		|| { log "нет связи или манифеста — запуск без обновления"; return 0; }
	while read -r sum name; do
		case " $FILES " in *" $name "*) ;; *) continue ;; esac
		[ -f "$name" ] && [ "$(sha256sum "$name" | cut -d' ' -f1)" = "$sum" ] && continue
		need="$need $name"
	done < "$manifest"
	[ -z "$need" ] && { log "актуально: $(cat version.txt 2>/dev/null)"; return 0; }

	local ver ui=""
	ver="$(curl -fsSL --max-time 10 "$base/deck.version.txt" 2>/dev/null)"
	log "обновление до ${ver:-?}:$need"
	if command -v zenity >/dev/null && [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
		zenity --progress --pulsate --no-cancel --auto-close --title "Pneuma" \
			--text "Загружаю обновление ${ver}…" < /dev/zero > /dev/null 2>&1 &
		ui=$!
	fi
	# Сначала качаем и проверяем всё, потом подменяем разом: движок и .pck
	# не должны оказаться от разных сборок.
	local ok=1
	for name in $need; do
		sum="$(awk -v n="$name" '$2 == n {print $1}' "$manifest")"
		if ! curl -fsL --connect-timeout 5 --max-time 600 -o "$tmp/$name" "$base/deck.$name" \
				|| [ "$(sha256sum "$tmp/$name" | cut -d' ' -f1)" != "$sum" ]; then
			log "не удалось скачать $name — остаёмся на текущей версии"
			ok=0
			break
		fi
	done
	[ -n "$ui" ] && kill "$ui" 2>/dev/null
	[ "$ok" = 1 ] || return 0
	for name in $need; do
		case "$name" in *.x86_64|*.sh) chmod +x "$tmp/$name" ;; esac
		mv -f "$tmp/$name" "$name"
	done
	log "готово: $(cat version.txt 2>/dev/null)"
}

[ -n "$base" ] && update
exec ./Pneuma.x86_64 "$@"
