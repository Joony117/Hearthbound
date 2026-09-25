# Godot 4 serves its LSP on 6005, so a listening port means a Godot editor is live.
# This gate rewrites .godot/, which is not safe to race against another engine process.
if (Get-NetTCPConnection -LocalPort 6005 -State Listen -ErrorAction SilentlyContinue) {
	Write-Host "GATE ABORTED: Godot LSP on 127.0.0.1:6005 - another engine process is live."
	Write-Host "Stop it first:  Get-Process Godot_v4* | Stop-Process -Force"
	exit 1
}

# The port-6005 check above only catches the LSP daemon. A stray process running this repo's own
# engine binary (tools/godot/) without serving the LSP - e.g. a plain "--headless -s <script>" run
# left behind by a subagent, with no --path argument naming the project at all - slips past it.
# Match on ExecutablePath rather than command-line text: the gitignored tools/godot/ binary is
# unique per checkout, so any process running it is this repo's engine regardless of what script
# or project path (if any) appears on its command line. This also covers both the _console wrapper
# and the differently-named child it spawns, since both live in the same folder.
$godotDir = (Resolve-Path (Join-Path $PSScriptRoot "..\tools\godot")).Path
$strays = Get-CimInstance -ClassName Win32_Process -Filter "Name LIKE 'Godot%'" -ErrorAction SilentlyContinue |
	Where-Object { $_.ExecutablePath -and $_.ExecutablePath.StartsWith($godotDir, [System.StringComparison]::OrdinalIgnoreCase) }
if ($strays) {
	$p = $strays | Select-Object -First 1
	Write-Host "GATE ABORTED: PID $($p.ProcessId) ($($p.Name)) is already running this repo's engine binary ($godotDir)."
	Write-Host "Command line: $($p.CommandLine)"
	Write-Host "Stop it first:  Get-Process Godot_v4* | Stop-Process -Force"
	exit 1
}

$godot = Join-Path $PSScriptRoot "..\tools\godot\Godot_v4.7.1-stable_win64_console.exe"
$original_appdata = $env:APPDATA
$env:APPDATA = [System.IO.Path]::GetTempPath()
$warmup_output = & $godot --headless --import 2>&1
$output = & $godot --headless --quit 2>&1
$engine_exit = $LASTEXITCODE
# ig-rd9: --quit never compiles a script only reached by -s or load() (harnesses, checks, the stage
# bot), so a helper load()s every .gd under tests/ that GUT doesn't run (tests/unit/test_*.gd), found
# by glob so a new harness is covered. One engine process for all of them, after the one above exits.
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$standalone = Get-ChildItem -Path $PSScriptRoot -Recurse -Filter *.gd |
	Where-Object { -not ($_.Directory.Name -eq "unit" -and $_.Name -like "test_*") } |
	ForEach-Object { "res://" + $_.FullName.Substring($root.Length + 1).Replace("\", "/") }
$parse_output = & $godot --headless -s res://tests/gate_parse.gd -- @standalone 2>&1
$parse_exit = $LASTEXITCODE
$env:APPDATA = $original_appdata
$warmup_output | ForEach-Object { $_.ToString() }
$output | ForEach-Object { $_.ToString() }
$parse_output | ForEach-Object { $_.ToString() }

if ((($output + $parse_output) | Out-String) -match "SCRIPT ERROR|ERROR:|WARNING") {
	 exit 1
}
if ($parse_exit -ne 0) {
	exit 1
}

exit $engine_exit
