# Pneuma3D для Windows: перед запуском сверяет файлы с последней сборкой на GitHub
# и докачивает только изменившиеся — обычно Pneuma3D.pck (~12 МБ).
# Движок Pneuma3D.exe меняется лишь при смене версии Godot. Нет сети или что-то
# пошло не так — игра запускается как есть. Вызывается из Pneuma3D.cmd.
#
# Канал берётся из channel.txt рядом с игрой: nightly (по умолчанию) — каждая
# сборка main, stable — последний релиз v*, off — не обновляться.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'  # без этого Invoke-WebRequest в разы медленнее
Set-Location $PSScriptRoot
$Repo = 'svagtozar/Pheuma'
# Pneuma3D.cmd не обновляем: cmd дочитывает бат-файл по ходу, подмена его сломает.
$Files = @('Pneuma3D.pck', 'Pneuma3D.exe', 'libvoxel.windows.template_release.x86_64.dll', 'update.ps1', 'version.txt', 'README.md')

function Log($m) {
	Write-Host $m
	Add-Content -Encoding UTF8 update.log "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $m"
}
function Fetch($url, $out, $sec) { Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $out -TimeoutSec $sec }
function Sum($path) { (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLower() }

$channel = ''
if (Test-Path channel.txt) { $channel = (Get-Content channel.txt -Raw).Trim() }
switch ($channel) {
	'off' { exit 0 }
	'stable' { $base = "https://github.com/$Repo/releases/latest/download" }
	default { $base = "https://github.com/$Repo/releases/download/nightly" }
}
if ($env:PNEUMA_UPDATE_URL) { $base = $env:PNEUMA_UPDATE_URL }  # для проверки со своего сервера
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
if ((Test-Path update.log) -and (Get-Content update.log).Count -gt 200) {
	(Get-Content update.log -Tail 200) | Set-Content -Encoding UTF8 update.log
}

$tmp = Join-Path $PSScriptRoot ('.update.' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory $tmp | Out-Null
try {
	try { Fetch "$base/win-manifest.txt" "$tmp\manifest" 10 }
	catch { Log 'Нет связи или манифеста — запуск без обновления'; exit 0 }
	$want = @{}
	foreach ($line in Get-Content "$tmp\manifest") {
		$parts = $line.Trim() -split '\s+'
		if ($parts.Count -eq 2 -and $Files -contains $parts[1]) { $want[$parts[1]] = $parts[0] }
	}
	$need = @($want.Keys | Where-Object { -not (Test-Path $_) -or (Sum $_) -ne $want[$_] })
	if ($need.Count -eq 0) { Log "Актуально: $(Get-Content version.txt -ErrorAction SilentlyContinue)"; exit 0 }
	Log "Загружаю обновление: $($need -join ', ')"
	# Сначала качаем и проверяем всё, потом подменяем разом: движок и .pck
	# не должны оказаться от разных сборок.
	foreach ($name in $need) {
		try { Fetch "$base/win.$name" "$tmp\$name" 600 } catch { Log "Не удалось скачать $name — остаёмся на текущей версии"; exit 0 }
		if ((Sum "$tmp\$name") -ne $want[$name]) { Log "Файл $name не сошёлся по sha256 — остаёмся на текущей версии"; exit 0 }
	}
	foreach ($name in $need) { Move-Item -Force "$tmp\$name" $name }
	Log "Готово: $(Get-Content version.txt -ErrorAction SilentlyContinue)"
	# Пришёл новый update.ps1 — он может знать о новых файлах (библиотеках):
	# сверяемся ещё раз уже им.
	if ($need -contains 'update.ps1' -and -not $env:PNEUMA_RERUN) {
		$env:PNEUMA_RERUN = '1'
		powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\update.ps1"
	}
}
catch { Log "Ошибка обновления: $_" }
finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
