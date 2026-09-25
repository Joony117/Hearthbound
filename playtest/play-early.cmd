@echo off
rem ig-eek: plays the Early stage save (tests\fixtures\stages\early) in its own APPDATA, so the
rem real save is never touched. Delete playtest\early\appdata to reset the stage.
setlocal
set "ROOT=%~dp0.."
set "APPDATA=%~dp0early\appdata"
set "USERDIR=%APPDATA%\Godot\app_userdata\Infinite Gacha"
rem A torn stage (either file missing) is reset whole: a played save with the fixture's Ledger is neither.
set "RESET="
if not exist "%USERDIR%\save.json" set "RESET=1"
if not exist "%USERDIR%\ledger.jsonl" set "RESET=1"
if defined RESET (
	mkdir "%USERDIR%" 2>nul
	copy /y "%ROOT%\tests\fixtures\stages\early\save.json" "%USERDIR%\save.json" >nul
	copy /y "%ROOT%\tests\fixtures\stages\early\ledger.jsonl" "%USERDIR%\ledger.jsonl" >nul
)
start "" "%ROOT%\export\game.exe"
