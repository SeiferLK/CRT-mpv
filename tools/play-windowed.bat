@echo off
REM Same as play.bat, but in a window
"%~dp0..\mpv\mpv.exe" --config-dir="%~dp0..\config" --geometry=1920x1080 %*
