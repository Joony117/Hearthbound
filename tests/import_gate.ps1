# Godot 4 serves its LSP on 6005, so a listening port means an editor or Serena LSP daemon
# is live. This gate rewrites .godot/, which is not safe to race against another engine process.
if (Get-NetTCPConnection -LocalPort 6005 -State Listen -ErrorAction SilentlyContinue) {
	Write-Host "GATE ABORTED: Godot LSP on 127.0.0.1:6005 - another engine process is live."
	Write-Host "Stop it first:  Get-Process Godot* | Stop-Process -Force"
	exit 1
}

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
