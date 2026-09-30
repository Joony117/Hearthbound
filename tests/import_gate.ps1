# Godot 4 serves its LSP on 6005, so a listening port means a Godot editor is live.
# This gate rewrites .godot/, which is not safe to race against another engine process.
if (Get-NetTCPConnection -LocalPort 6005 -State Listen -ErrorAction SilentlyContinue) {
	Write-Host "GATE ABORTED: Godot LSP on 127.0.0.1:6005 - another engine process is live."
	Write-Host "Stop it first: close that editor, or reap it by its own checkout's path (CLAUDE.md, Engine)."
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
	Write-Host "Stop it first:  Get-Process Godot_v4* | Where-Object Path -like '$godotDir\*' | Stop-Process -Force"
	exit 1
}

$godot =Join-Path $PSScriptRoot "..\tools\godot\Godot_v4.7.1-stable_win64_console.exe"
$original_appdata = $env:APPDATA
# ig-dw2: a fresh dir per run, as the .sh's mktemp: two checkouts' gates never share user:// or the
# engine's settings.
$gate_appdata = Join-Path ([System.IO.Path]::GetTempPath()) ("hb-gate-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $gate_appdata | Out-Null
$env:APPDATA = $gate_appdata
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
# ig-4k2, ig-k65: a headless run never prints a GDScript warning, so project.godot's [debug] section raises
# each warning the tree is clean of to Error (2). In this debug binary the script then fails with
# "(Warning treated as error.)" and its file and line, which both runs above and GUT catch. At Error:
# unassigned_variable_op_assign, unused_variable, unused_local_constant, unused_private_class_variable,
# unused_signal, unreachable_code, unreachable_pattern, standalone_expression, standalone_ternary,
# unsafe_void_return, missing_tool, redundant_static_unload, redundant_await, assert_always_true,
# assert_always_false, narrowing_conversion, int_as_enum_without_match, enum_variable_without_default,
# empty_file, deprecated_keyword, confusable_identifier, confusable_local_usage,
# confusable_capture_reassignment, confusable_temporary_modification, property_used_as_function,
# constant_used_as_function, function_used_as_property, static_called_on_instance,
# shadowed_global_identifier, confusable_local_declaration, shadowed_variable, integer_division,
# unused_parameter, shadowed_variable_base_class, incompatible_ternary, unassigned_variable,
# int_as_enum_without_cast. Every site of integer_division is an intended floor and carries
# @warning_ignore("integer_division"); one that meant a float is a bug, so fix it, not the annotation.
# Engine defaults stay as they are (the unsafe_*, untyped and inferred declarations are off; four are
# already Error). Export builds skip warnings.
$parse_output = & $godot --headless -s res://tests/gate_parse.gd -- @standalone 2>&1
$parse_exit = $LASTEXITCODE
$env:APPDATA = $original_appdata
Remove-Item -LiteralPath $gate_appdata -Recurse -Force -ErrorAction SilentlyContinue
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
