@echo off
REM Double-click to uninstall CRT-mpv: removes its Open with entry and everything Windows recorded about it,
REM then deletes this folder. Asks first. No admin needed.
title Uninstall CRT-mpv
echo This removes CRT-mpv from this PC and deletes its folder:
echo   %~dp0
echo including your remote settings and any TV pictures you added.
echo.
set "ok="
set /p "ok=Uninstall CRT-mpv? Type Y and press Enter: "
if /i not "%ok%"=="Y" (echo Cancelled. Nothing was changed. & pause & exit /b)
echo.
REM Run from outside the folder so it can be deleted. This file is deleted too, so everything is on one line and
REM "(goto)" ends the batch first: the rest of the line still runs, but cmd never goes back to the missing file.
cd /d "%TEMP%" & (goto) 2>nul & powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\uninstall.ps1" -RemoveFolder & echo. & pause
