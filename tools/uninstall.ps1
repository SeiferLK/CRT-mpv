<#
 CRT-mpv uninstaller for Windows (no admin needed). Undoes install.ps1.
 Most people double-click uninstall.bat instead, which asks first and then runs this with -RemoveFolder.
   .\tools\uninstall.ps1                 remove the Open with entry, everything the installer downloaded or built,
                                         and the player's saved state (settings, resume positions, shader cache, logs)
   .\tools\uninstall.ps1 -RemoveFolder   also delete the whole CRT-mpv folder
 Without -RemoveFolder the folder is left as a fresh copy: double-click install.bat to reinstall.
 TV pictures you added yourself to config\overlays are kept (unless -RemoveFolder).
#>
param([switch]$RemoveFolder)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

# Files in use can't be deleted, so CRT-mpv has to be closed first (it is never stopped for you).
$running = Get-Process mpv -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith("$root\", 'OrdinalIgnoreCase') }
if ($running) { Write-Host 'CRT-mpv is still playing. Close it, then run the uninstaller again. Nothing was changed.'; exit 1 }

Write-Host '[1/3] Open with entry and what Windows recorded about CRT-mpv'
& (Join-Path $root 'tools\unregister-openwith.ps1')
Remove-Item (Join-Path $env:TEMP 'crt-mpv-mpv.7z') -Force -ErrorAction SilentlyContinue   # left by an interrupted install

if ($RemoveFolder) {
    Write-Host "[2/3] deleting $root"
    Set-Location (Split-Path $root)                  # step out, so the folder isn't held open by this script
    [Environment]::CurrentDirectory = (Get-Location).Path
    Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host '[3/3] done'
    Write-Host ''
    if (Test-Path $root) {
        Write-Host "Uninstalled, but Windows kept part of $root (probably a window that is open in it). Close that window and delete the folder."
    } else {
        Write-Host 'Uninstalled. CRT-mpv is gone from this PC.'
    }
    return
}

Write-Host '[2/3] downloaded and built files'
$tvs = 'G02_Generic_TV','Generic_CRT_Monitor','Generic_Flat_TV','Generic_Gray_TV','Generic_White_TV',
       'Nintendo_Famicom','Nintendo_N64','Nintendo_NES','Nintendo_SNES','SNK_NeoGeo','Sega_Dreamcast',
       'Sega_Genesis','Sega_MasterSystem','Sony_PS2','Sony_PlayStation'
$paths = @('mpv', 'CRT-mpv.exe', '.cache', 'config\scripts\modernz.lua', 'config\scripts\autoload.lua',
           'config\fonts\modernz-icons.ttf') + ($tvs | ForEach-Object { "config\overlays\$_.png" })
foreach ($p in $paths) { Remove-Item (Join-Path $root $p) -Recurse -Force -ErrorAction SilentlyContinue }
$fonts = Join-Path $root 'config\fonts'            # created by the installer; kept if you put fonts of your own there
if ((Test-Path $fonts) -and -not (Get-ChildItem $fonts -Force)) { Remove-Item $fonts }

Write-Host '[3/3] saved settings, resume positions, shader cache and logs'
foreach ($p in 'config\settings.json', 'config\watch_later', 'config\cache', 'config\*.log', '*.log') {
    Remove-Item (Join-Path $root $p) -Recurse -Force -ErrorAction SilentlyContinue
}

$left = $paths | Where-Object { Test-Path (Join-Path $root $_) }
Write-Host ''
if ($left) { Write-Host "Could not remove: $($left -join ', '). Close anything using them and run the uninstaller again."; exit 1 }
Write-Host 'Uninstalled. Delete this folder to remove CRT-mpv completely, or double-click install.bat to reinstall.'
