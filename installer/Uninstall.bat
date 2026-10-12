@echo off
setlocal
set "GAME=%~1"
if "%GAME%"=="" set "GAME=C:\Program Files (x86)\Steam\steamapps\common\DELTARUNE"
if not exist "%GAME%\chapter1_windows" set /p "GAME=Paste the path of your DELTARUNE folder: "
"%~dp0drm-patcher.exe" uninstall "%GAME%"
pause
