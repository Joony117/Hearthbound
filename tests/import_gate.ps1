$godot = Join-Path $PSScriptRoot "..\tools\godot\Godot_v4.7.1-stable_win64_console.exe"
$original_appdata = $env:APPDATA
$env:APPDATA = [System.IO.Path]::GetTempPath()
$warmup_output = & $godot --headless --import 2>&1
$output = & $godot --headless --quit 2>&1
$engine_exit = $LASTEXITCODE
$env:APPDATA = $original_appdata
$warmup_output | ForEach-Object { $_.ToString() }
$output | ForEach-Object { $_.ToString() }

if (($output | Out-String) -match "SCRIPT ERROR|ERROR:|WARNING") {
	 exit 1
}

exit $engine_exit
