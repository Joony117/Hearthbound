# Godot 4 serves its LSP on 6005, so a listening port means an editor or Serena LSP daemon
# is live. This gate rewrites .godot/, which is not safe to race against another engine process.
if (Get-NetTCPConnection -LocalPort 6005 -State Listen -ErrorAction SilentlyContinue) {
	Write-Host "GATE ABORTED: Godot LSP on 127.0.0.1:6005 - another engine process is live."
	Write-Host "Stop it first:  Get-Process Godot* | Stop-Process -Force"
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
