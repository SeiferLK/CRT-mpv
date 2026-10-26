# Adds "CRT-mpv" (with the CRT-mpv icon) to the Explorer right-click > Open with menu for common video types.
# Per-user (HKCU) - no admin needed. Re-run it if you move this folder.
# Remove with:  .\tools\unregister-openwith.ps1
$root = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $root 'mpv\mpv.exe'))) { throw "mpv.exe not found - double-click install.bat first." }
& (Join-Path $PSScriptRoot 'build-launcher.ps1')
$exe  = Join-Path $root 'CRT-mpv.exe'      # the launcher carries the CRT-mpv icon, which is what Windows shows
$app  = 'HKCU:\Software\Classes\Applications\CRT-mpv.exe'
New-Item -Path "$app\shell\open\command" -Force | Out-Null
Set-ItemProperty -Path $app -Name 'FriendlyAppName' -Value 'CRT-mpv'
Set-ItemProperty -Path "$app\shell\open\command" -Name '(default)' -Value "`"$exe`" `"%1`""
New-Item -Path "$app\SupportedTypes" -Force | Out-Null
$exts = '.mkv','.mp4','.avi','.mov','.wmv','.webm','.m4v','.flv','.ts','.m2ts','.mpg','.mpeg','.ogv','.3gp','.divx','.vob'
foreach ($e in $exts) {
    Set-ItemProperty -Path "$app\SupportedTypes" -Name $e -Value ''
    New-Item -Path "HKCU:\Software\Classes\$e\OpenWithList\CRT-mpv.exe" -Force | Out-Null
    Remove-Item "HKCU:\Software\Classes\$e\OpenWithList\mpv.exe" -Recurse -ErrorAction SilentlyContinue   # entry from an earlier version
}
Remove-Item 'HKCU:\Software\Classes\Applications\mpv.exe' -Recurse -ErrorAction SilentlyContinue         # entry from an earlier version
Write-Host "Registered 'CRT-mpv' for $($exts.Count) video types."
