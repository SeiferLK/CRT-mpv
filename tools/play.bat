@echo off
REM Fallback launcher if CRT-mpv.exe is missing. Drag a video onto this file, or: tools\play.bat "video.mkv"
"%~dp0..\mpv\mpv.exe" --config-dir="%~dp0..\config" --fullscreen %*
