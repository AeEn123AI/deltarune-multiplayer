@echo off
rem DELTARUNE Multiplayer installer. Drag your DELTARUNE folder onto this file, or run it
rem directly to use the default Steam location.
setlocal
set "GAME=%~1"
if "%GAME%"=="" set "GAME=C:\Program Files (x86)\Steam\steamapps\common\DELTARUNE"
if not exist "%GAME%\chapter1_windows" (
  echo Could not find DELTARUNE at "%GAME%".
  set /p "GAME=Paste the path of your DELTARUNE folder: "
)
"%~dp0drm-patcher.exe" install "%GAME%" --mod "%~dp0mod"
pause
