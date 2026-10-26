<#
 CRT-mpv updater for Windows. Started by config\scripts\update.lua when "Update now" is chosen in the player.
 Waits for the player to close, downloads the release from GitHub (checked against GitHub's SHA-256 when it
 publishes one), installs it over this folder, fetches anything new it needs (tools\install.ps1), rebuilds
 CRT-mpv.exe and starts CRT-mpv again on the same video.
 Kept as they are: config\settings.json (TV, look, presets, volume), resume positions, the shader cache, mpv, and
 TV pictures you added yourself (their tvs.json entries are carried over). Every file it replaces or removes is
 copied to backup\<old version>-<date>\ first (the three newest backups are kept), and if anything goes wrong the
 old version is put back.
   -Job <file>   JSON written by update.lua: url, sha256, tag, pid (the player), relaunch (arguments for CRT-mpv.exe)
#>
param([Parameter(Mandatory = $true)][string]$Job)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$root = Split-Path -Parent $PSScriptRoot
Add-Type -AssemblyName System.Windows.Forms, System.Drawing, System.IO.Compression.FileSystem
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$j = Get-Content -Raw -LiteralPath $Job | ConvertFrom-Json
Remove-Item -LiteralPath $Job -Force -ErrorAction SilentlyContinue
$tag = [string]$j.tag
$relaunch = @($j.relaunch | Where-Object { $_ -is [string] -and $_ })   # (an empty list arrives as {} from Lua)

# The player has closed by the time anything happens, so this small window is all there is to see.
$form = New-Object Windows.Forms.Form
$form.Text = 'Updating CRT-mpv'
$form.FormBorderStyle = 'FixedDialog'; $form.MaximizeBox = $false; $form.MinimizeBox = $false; $form.ControlBox = $false
$form.StartPosition = 'CenterScreen'; $form.ClientSize = New-Object Drawing.Size(440, 104); $form.TopMost = $true
$ico = Join-Path $root 'assets\crt-mpv.ico'
if (Test-Path $ico) { $form.Icon = New-Object Drawing.Icon $ico }
$label = New-Object Windows.Forms.Label
$label.SetBounds(18, 16, 404, 40); $label.Font = New-Object Drawing.Font('Segoe UI', 10)
$bar = New-Object Windows.Forms.ProgressBar
$bar.SetBounds(18, 62, 404, 22); $bar.Style = 'Marquee'
$form.Controls.AddRange(@($label, $bar))
$form.Show()
function Status([string]$text, [int]$percent = -1) {
    $label.Text = $text
    if ($percent -ge 0) { $bar.Style = 'Continuous'; $bar.Value = [Math]::Max(0, [Math]::Min(100, $percent)) }
    else { $bar.Style = 'Marquee' }
    [Windows.Forms.Application]::DoEvents()
}

function Start-Player([string[]]$extra) {
    $exe = Join-Path $root 'CRT-mpv.exe'
    if (-not (Test-Path $exe)) { return }
    $argList = @($extra) + $relaunch | ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' }
    Start-Process -FilePath $exe -ArgumentList ($argList -join ' ') -WorkingDirectory $root
}

function Invoke-Script([string]$script, [string[]]$scriptArgs) {
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root $script) @scriptArgs 2>&1
    if ($LASTEXITCODE -ne 0) { throw "$script failed: $((@($out) | Select-Object -Last 3) -join ' ')" }
}

$tmp = Join-Path $env:TEMP "crt-mpv-update-$PID"
$playerClosed = $false
$backup = $null
$added = New-Object Collections.Generic.List[string]     # files that did not exist before (deleted on rollback)
$saved = New-Object Collections.Generic.List[string]     # files copied to the backup (restored on rollback)
function Save-Old([string]$rel) {
    $dst = Join-Path $backup $rel
    New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null
    Copy-Item -LiteralPath (Join-Path $root $rel) -Destination $dst -Force
    $saved.Add($rel)
}

try {
    Status 'Waiting for CRT-mpv to close...'
    $player = Get-Process -Id ([int]$j.pid) -ErrorAction SilentlyContinue
    for ($i = 0; $player -and -not $player.HasExited -and $i -lt 60; $i++) { Start-Sleep -Milliseconds 250; Status $label.Text }
    if ($player -and -not $player.HasExited) { throw 'CRT-mpv did not close, so nothing was changed.' }
    $playerClosed = $true

    # --- download ---
    New-Item -ItemType Directory -Force $tmp | Out-Null
    $zip = Join-Path $tmp 'update.zip'
    Status "Downloading CRT-mpv $tag..." 0
    $req = [Net.WebRequest]::Create([string]$j.url)
    if ($req -is [Net.HttpWebRequest]) { $req.UserAgent = 'CRT-mpv updater' }
    $resp = $req.GetResponse()
    $total = $resp.ContentLength
    $in = $resp.GetResponseStream()
    $out = [IO.File]::Create($zip)
    try {
        $buf = New-Object byte[] 65536
        $got = 0
        while (($n = $in.Read($buf, 0, $buf.Length)) -gt 0) {
            $out.Write($buf, 0, $n)
            $got += $n
            if ($total -gt 0) { Status ('Downloading CRT-mpv {0}...   {1:N1} of {2:N1} MB' -f $tag, ($got / 1MB), ($total / 1MB)) ([int](100 * $got / $total)) }
        }
    } finally { $out.Close(); $in.Close(); $resp.Close() }
    if ($j.sha256 -and (Get-FileHash $zip -Algorithm SHA256).Hash -ne ([string]$j.sha256).ToUpper()) {
        throw 'The download was damaged (its checksum does not match GitHub''s).'
    }

    # --- unpack and check it is CRT-mpv ---
    Status 'Unpacking...'
    $x = Join-Path $tmp 'x'
    [IO.Compression.ZipFile]::ExtractToDirectory($zip, $x)
    $inst = Get-ChildItem $x -Recurse -Filter 'install.ps1' | Where-Object { $_.Directory.Name -eq 'tools' } | Select-Object -First 1
    if (-not $inst) { throw 'The download is not a CRT-mpv release.' }
    $new = (Resolve-Path (Split-Path -Parent $inst.DirectoryName)).Path
    foreach ($must in 'VERSION', 'config\scripts\crt.lua', 'config\overlays\tvs.json') {
        if (-not (Test-Path (Join-Path $new $must))) { throw "The download is not a complete CRT-mpv release ($must is missing)." }
    }

    # never replaced, even if a release were to contain them: per-machine state, the downloaded mpv, the built launcher
    $keep = '^(config\\settings\.json|config\\update\.json|config\\watch_later\\|config\\cache\\|backup\\|mpv\\|\.cache\\|CRT-mpv\.exe$|\.update-manifest$)'
    $files = @(Get-ChildItem $new -Recurse -File | ForEach-Object { $_.FullName.Substring($new.Length + 1) } | Where-Object { $_ -notmatch $keep })

    # TVs you added (a picture in config\overlays plus an entry in tvs.json) stay in the new tvs.json
    $oldTvs = Join-Path $root 'config\overlays\tvs.json'
    $newTvs = Join-Path $new 'config\overlays\tvs.json'
    if (Test-Path $oldTvs) {
        # assigned before use: PowerShell 5 passes a JSON array down a pipeline as one object (and @() keeps it that way)
        $shipped = Get-Content -Raw $newTvs | ConvertFrom-Json
        $before = Get-Content -Raw $oldTvs | ConvertFrom-Json
        $names = @{}
        foreach ($t in $shipped) { $names[$t.name] = $true }
        $mine = @($before | Where-Object {
            -not $names[$_.name] -and (Test-Path -LiteralPath (Join-Path $root "config\overlays\$($_.name).png")) })
        if ($mine.Count) {
            $lines = @($shipped) + $mine | ForEach-Object { ' ' + ($_ | ConvertTo-Json -Compress) }
            [IO.File]::WriteAllText($newTvs, "[`n" + ($lines -join ",`n") + "`n]`n", (New-Object Text.UTF8Encoding $false))
        }
    }

    # --- install: back up what changes, then copy the new files over ---
    Status "Installing CRT-mpv $tag..."
    $old = (Get-Content (Join-Path $root 'VERSION') -ErrorAction SilentlyContinue | Select-Object -First 1)
    if (-not $old) { $old = 'old' }
    $backup = Join-Path $root ('backup\{0}-{1}' -f $old.Trim(), (Get-Date -Format 'yyyyMMdd-HHmmss'))
    foreach ($rel in $files) {
        $src = Join-Path $new $rel
        $dst = Join-Path $root $rel
        if (Test-Path -LiteralPath $dst) {
            if ((Get-FileHash -LiteralPath $dst).Hash -eq (Get-FileHash -LiteralPath $src).Hash) { continue }
            Save-Old $rel
        } else { $added.Add($rel) }
        New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null
        Copy-Item -LiteralPath $src -Destination $dst -Force
    }
    # files the previous update installed that this release no longer has
    $manifest = Join-Path $root '.update-manifest'
    if (Test-Path $manifest) {
        $inNew = @{}
        foreach ($f in $files) { $inNew[$f] = $true }
        foreach ($rel in (Get-Content $manifest)) {
            if ($rel -and -not $inNew[$rel] -and (Test-Path -LiteralPath (Join-Path $root $rel))) {
                Save-Old $rel
                Remove-Item -LiteralPath (Join-Path $root $rel) -Force
            }
        }
        Save-Old '.update-manifest'
    } else { $added.Add('.update-manifest') }
    [IO.File]::WriteAllLines($manifest, [string[]]$files)

    # --- anything new to download (TV pictures, controls), and the launcher ---
    Status 'Fetching anything new (TV pictures, controls)...'
    Invoke-Script 'tools\install.ps1' @()
    Status 'Rebuilding CRT-mpv.exe...'
    Invoke-Script 'tools\build-launcher.ps1' @('-Force')

    # keep the three newest backups
    Get-ChildItem (Join-Path $root 'backup') -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending |
        Select-Object -Skip 3 | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

    Status "Updated to CRT-mpv $tag. Starting it again..." 100
    Start-Player @("--script-opts-append=crt-update-done=$tag")
} catch {
    $err = $_.Exception.Message
    if ($backup) {                                       # put the old version back
        Status 'Putting the old version back...'
        foreach ($rel in $added) { Remove-Item -LiteralPath (Join-Path $root $rel) -Force -ErrorAction SilentlyContinue }
        foreach ($rel in $saved) {
            Copy-Item -LiteralPath (Join-Path $backup $rel) -Destination (Join-Path $root $rel) -Force -ErrorAction SilentlyContinue
        }
        try { Invoke-Script 'tools\build-launcher.ps1' @('-Force') } catch { }
    }
    $form.Hide()
    [void][Windows.Forms.MessageBox]::Show("The update to CRT-mpv $tag did not work:`n`n$err`n`nCRT-mpv was left as it was.",
        'CRT-mpv update', 'OK', 'Warning')
    if ($playerClosed) { Start-Player @('--script-opts-append=crt-update-failed=1') }
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    $form.Close()
}
