@echo off
setlocal
for %%I in ("%~dp0..\.runtime") do set "APPDATA=%%~fI"
set "LOCALAPPDATA=%APPDATA%"
"D:\Tools\godot\Godot_v4.7.2-stable_win64_console.exe" %*
