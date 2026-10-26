@echo off
REM Double-click to install CRT-mpv into this folder and add it to the right-click > Open with menu.
REM No admin needed. Safe to run again (after moving the folder, or to repair an install).
title Install CRT-mpv
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\install.ps1" -OpenWith
echo.
pause
