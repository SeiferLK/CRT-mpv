# Removes the "CRT-mpv" Open with entry added by register-openwith.ps1, plus what Windows itself recorded about
# CRT-mpv once it was used (recently used lists, default-app choices, cached names, "new app" notices,
# compatibility and usage records, per-app audio device, the taskbar's hidden shortcut). Only entries for this
# folder are touched.
# Per-user (HKCU) - no admin needed. uninstall.ps1 runs this for you.
#   .\tools\unregister-openwith.ps1 -WhatIf    list what would be removed, change nothing
[CmdletBinding(SupportsShouldProcess)] param()
$root = Split-Path -Parent $PSScriptRoot
function Test-InRoot([string]$s) { $s.StartsWith("$root\", 'OrdinalIgnoreCase') }

# An app's Open with entries are removed only if its registration points into this folder, or nothing on this PC
# registers it any more (leftovers, e.g. "mpv.exe" from an earlier CRT-mpv version). So another copy of CRT-mpv,
# or another mpv install, keeps its entries.
function Test-Ours([string]$exe) {
    $cmd = [string](Get-ItemProperty "HKCU:\Software\Classes\Applications\$exe\shell\open\command" -ErrorAction SilentlyContinue).'(default)'
    if ($cmd) { return Test-InRoot $cmd.Trim('"') }
    -not ((Test-Path "HKCU:\Software\Classes\Applications\$exe") -or (Test-Path "HKLM:\Software\Classes\Applications\$exe") -or
          (Test-Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\App Paths\$exe"))
}
$apps = @('CRT-mpv.exe', 'mpv.exe' | Where-Object { Test-Ours $_ })

$exts = '.mkv','.mp4','.avi','.mov','.wmv','.webm','.m4v','.flv','.ts','.m2ts','.mpg','.mpeg','.ogv','.3gp','.divx','.vob'
foreach ($e in $exts) { foreach ($a in $apps) {
    Remove-Item "HKCU:\Software\Classes\$e\OpenWithList\$a" -Recurse -ErrorAction SilentlyContinue
} }
foreach ($a in $apps) { Remove-Item "HKCU:\Software\Classes\Applications\$a" -Recurse -ErrorAction SilentlyContinue }

# Explorer's per-type lists (any file type, not just the ones above: "Choose another app" works on all of them).
# Windows 11 keeps the default app in UserChoiceLatest, older versions in UserChoice.
$fileExts = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts'
$defaults = @()
foreach ($k in Get-ChildItem $fileExts -ErrorAction SilentlyContinue) {
    $list = Join-Path $k.PSPath 'OpenWithList'
    $p = Get-ItemProperty $list -ErrorAction SilentlyContinue
    if ($p) {
        $mru = [string]$p.MRUList
        foreach ($v in $p.PSObject.Properties | Where-Object { $_.Name.Length -eq 1 -and $apps -contains $_.Value }) {
            Remove-ItemProperty $list -Name $v.Name
            $mru = $mru.Replace($v.Name, '')
        }
        if ($mru -ne [string]$p.MRUList) { Set-ItemProperty $list -Name MRUList -Value $mru }
    }
    foreach ($c in 'UserChoice', 'UserChoiceLatest') {
        $choice = Join-Path $k.PSPath $c
        $progId = (Get-ItemProperty $choice -ErrorAction SilentlyContinue).ProgId
        if (-not $progId) { $progId = (Get-ItemProperty "$choice\ProgId" -ErrorAction SilentlyContinue).ProgId }
        if ($apps | Where-Object { $progId -eq "Applications\$_" }) {
            Remove-Item $choice -Recurse -ErrorAction SilentlyContinue
            if ((Test-Path $choice) -and $defaults -notcontains $k.PSChildName) { $defaults += $k.PSChildName }
        }
    }
}

# Values named after a file in this folder: cached app names, compatibility records, usage counters.
$byPath = @('HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache',
            'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Compatibility Assistant\Store') +
          @(Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FeatureUsage' -ErrorAction SilentlyContinue |
            ForEach-Object { $_.PSPath })
foreach ($key in $byPath) {
    foreach ($n in (Get-Item $key -ErrorAction SilentlyContinue).Property) {
        if (Test-InRoot $n) { Remove-ItemProperty $key -Name $n }
    }
}

# "You have a new app that can open this" notices.
$toasts = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ApplicationAssociationToasts'
foreach ($n in (Get-Item $toasts -ErrorAction SilentlyContinue).Property) {
    if ($apps | Where-Object { $n -like "Applications\${_}_*" }) { Remove-ItemProperty $toasts -Name $n }
}

# Per-app audio output device that Windows remembered for this folder's mpv.exe (stored as \Device\...\Users\...).
$audio = 'HKCU:\Software\Microsoft\Internet Explorer\LowRegistry\Audio\PolicyConfig\PropertyStore'
$tail = $root.Substring(2) + '\'                     # the path without its drive letter
foreach ($k in Get-ChildItem $audio -ErrorAction SilentlyContinue) {
    $d = [string](Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue).'(default)'
    if ($d.IndexOf($tail, [StringComparison]::OrdinalIgnoreCase) -ge 0) { Remove-Item $k.PSPath -Recurse }
}

# The hidden shortcut the taskbar keeps for the player window's app ID (see tools\set-window-icon.ps1).
$implicit = Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\ImplicitAppShortcuts'
$shell = New-Object -ComObject WScript.Shell
foreach ($lnk in Get-ChildItem $implicit -Recurse -Filter *.lnk -ErrorAction SilentlyContinue) {
    if (Test-InRoot $shell.CreateShortcut($lnk.FullName).TargetPath) {
        Remove-Item -LiteralPath $lnk.FullName
        if (-not $WhatIfPreference -and -not (Get-ChildItem -LiteralPath $lnk.DirectoryName -Force)) { Remove-Item -LiteralPath $lnk.DirectoryName }
    }
}

if ($WhatIfPreference) { Write-Host 'Nothing was changed (-WhatIf).'; return }
Write-Host 'Removed.'
if ($defaults) {
    Write-Host "CRT-mpv is still the default app for $($defaults -join ', ') - Windows will ask which app to use next time; pick another one there."
}
