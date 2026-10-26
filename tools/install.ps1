<#
 CRT-mpv installer for Windows (no admin needed). Most people double-click install.bat, which runs this with -OpenWith.
   .\tools\install.ps1              download mpv + dependencies into the CRT-mpv folder
   .\tools\install.ps1 -OpenWith    also add "CRT-mpv" to the right-click > Open with menu
 Every download is pinned to an exact version and verified with SHA-256.
#>
param([switch]$OpenWith)
# mpv needs Windows 10 (1607) or newer. Checked first, with PowerShell 2.0 syntax only, so Windows 7 and 8 get a
# plain message instead of errors.
$winVer = [Version](Get-WmiObject Win32_OperatingSystem).Version
if ($winVer -lt [Version]'10.0.14393') {
    Write-Host 'CRT-mpv needs Windows 10 or Windows 11. mpv, the player it runs on, does not support older Windows.'
    exit 1
}
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$root = Split-Path -Parent $PSScriptRoot

function Get-Verified([string]$Url, [string]$Sha256, [string]$Out) {
    if ((Test-Path $Out) -and ((Get-FileHash $Out -Algorithm SHA256).Hash -eq $Sha256.ToUpper())) { return }
    New-Item -ItemType Directory -Force (Split-Path $Out) | Out-Null
    Write-Host "  downloading $(Split-Path $Out -Leaf)"
    Invoke-WebRequest -Uri $Url -OutFile $Out -UseBasicParsing
    if ((Get-FileHash $Out -Algorithm SHA256).Hash -ne $Sha256.ToUpper()) {
        Remove-Item $Out -Force
        throw "Checksum mismatch for $Url - refusing to use it."
    }
}

# --- mpv (portable Windows build by shinchiro, pinned) ---
$mpvExe = Join-Path $root 'mpv\mpv.exe'
if (-not (Test-Path $mpvExe)) {
    Write-Host '[1/4] mpv'
    $arc = Join-Path $env:TEMP 'crt-mpv-mpv.7z'
    Get-Verified 'https://github.com/shinchiro/mpv-winbuild-cmake/releases/download/20261021/mpv-x86_64-20261021-git-e471496c56.7z' `
                 '4a355f3e89c83fabc730d33fb4e759dfec747806ed2287b61a90d1681b83e8d3' $arc
    New-Item -ItemType Directory -Force (Join-Path $root 'mpv') | Out-Null
    if (Get-Command 7z -ErrorAction SilentlyContinue) { & 7z x -y "-o$root\mpv" $arc | Out-Null }
    else { & tar -xf $arc -C (Join-Path $root 'mpv') }      # Windows 10 1803+ bsdtar reads .7z
    Remove-Item $arc -Force
    if (-not (Test-Path $mpvExe)) { throw 'mpv extraction failed (install 7-Zip and re-run).' }
} else { Write-Host '[1/4] mpv already present' }

# --- on-screen controls (ModernZ v0.3.3) and folder playlist (mpv project) ---
Write-Host '[2/4] hover controls + folder playlist'
$mzOrig = Join-Path $root '.cache\modernz.lua'
Get-Verified 'https://github.com/Samillion/ModernZ/releases/download/v0.3.3/modernz.lua' `
             'c36aef0152d3fdb0c769cefe7074648b457ed50ea4ddcc402b778bec23ca32c8' $mzOrig
# Two-string patch of the verified file: the bar's "i" button becomes the CRT remote button.
$mz = [IO.File]::ReadAllText($mzOrig)
foreach ($needle in 'ne.content = icons.info', 'ne.tooltipF = locale.stats_info') {
    if (-not $mz.Contains($needle)) { throw "ModernZ patch failed: '$needle' not found." }
}
$mz = $mz.Replace('ne.content = icons.info', 'ne.content = icons.menu').Replace('ne.tooltipF = locale.stats_info', 'ne.tooltipF = "CRT remote"')
# Attach our seek controller after each ModernZ layout rebuild.
if (-not $mz.Contains('local function osc_init()')) { throw 'ModernZ seek hook: osc_init not found.' }
$mz += @'

local crt_seek = dofile(mp.command_native({"expand-path", "~~/script-modules/crt_seek.lua"}))
local upstream_osc_init = osc_init
osc_init = function()
    upstream_osc_init()
    crt_seek.attach(state.seekbar_element, get_slider_value, request_tick, state, user_opts)
end
'@
New-Item -ItemType Directory -Force (Join-Path $root 'config\scripts') | Out-Null
[IO.File]::WriteAllText((Join-Path $root 'config\scripts\modernz.lua'), $mz, (New-Object Text.UTF8Encoding $false))
Get-Verified 'https://github.com/Samillion/ModernZ/releases/download/v0.3.3/modernz-icons.ttf' `
             '5033b84d569502538968c6f23b0859bda790eed85c10e419b0759537ec60a016' (Join-Path $root 'config\fonts\modernz-icons.ttf')
Get-Verified 'https://raw.githubusercontent.com/mpv-player/mpv/867990d949e9ad99406e0f26e5528e95046b30a7/TOOLS/lua/autoload.lua' `
             '5d2f5491edf1c9857932a4fd816413651d110345e7e57b5ad915f74fb4d516ca' (Join-Path $root 'config\scripts\autoload.lua')

# --- TV pictures (Soqueroeu TV Backgrounds, via the VLC plugin repo, pinned commit) ---
Write-Host '[3/4] TV pictures'
$ovBase = 'https://raw.githubusercontent.com/itsdunintime104/VLC-CRT-emulator-plugin/603a77752cd78d091389072e6ad61f86086cd31f/overlays'
$tvs = [ordered]@{
    'G02_Generic_TV.png' = '9402db8d7fd2824496885244f7e1c163db168a40da3ff2821d110764fb85150d'
    'Generic_CRT_Monitor.png' = '42d6b67dc85229e0f9f7f468acad49a13fd156d599ec7b21cabdb193b7c7633d'
    'Generic_Flat_TV.png' = '3265ce23975385d0e0f5e6381fb47b2112110b1019032bf74821e86dd65e0758'
    'Generic_Gray_TV.png' = 'c4f0a100084fde578af12be600cf0d8e5d6e63dc6b91b615aeedfa380f1d8e33'
    'Generic_White_TV.png' = 'c81a41f23a778f4cb9b8f22ed4a0e9e64c23a1db41143b4ec220984cfc92d340'
    'Nintendo_Famicom.png' = 'e12af654b3ca7c7d22720dcfa5c6b50293fb85dd6d3d9573de74347598a9f325'
    'Nintendo_N64.png' = '997bd3923eb6bc9c1c0d11fbe98daa1f7a901b40fb204d6bfd6710caaee948de'
    'Nintendo_NES.png' = '4b806f0a9ff18ba59d6261dc810472d42025d60991b613e4d3de7f552ffab89b'
    'Nintendo_SNES.png' = '898c5273c0a70bf10207de66c6dd42d2400d51ce2cd85fb69028dba3c6631006'
    'SNK_NeoGeo.png' = '6a72a6e7b7708c9fb43869c06e47ad0390efeb9937697fd39dd9d19eab0e0139'
    'Sega_Dreamcast.png' = 'e5888e01245081a8c64014341c05845276efb1253b4bb51b64b241f0769f98c4'
    'Sega_Genesis.png' = '77d150ca4b6360c89f8ccf1863b6b28d5c479774a5f912e49838c369b291e60e'
    'Sega_MasterSystem.png' = 'c91d779cffce543ffbc157d67f2d2c436247bfa0fcbe9135dc265cdd5de40e0f'
    'Sony_PS2.png' = '521956983f30bded9566ffec3deeb7242ce20f1fcfd52b777b81598c60f0421e'
    'Sony_PlayStation.png' = 'febbba2594cf1732709188ebc7d932be574358a80f441336d5e75e6d04532ee4'
}
foreach ($n in $tvs.Keys) {
    Get-Verified "$ovBase/$n" $tvs[$n] (Join-Path $root "config\overlays\$n")
}

Write-Host '[4/4] launcher'
& (Join-Path $root 'tools\build-launcher.ps1')
if ($OpenWith) { & (Join-Path $root 'tools\register-openwith.ps1') }
Write-Host ''
Write-Host 'Installed. Drag a video onto CRT-mpv.exe, or right-click a video > Open with > CRT-mpv.'
Write-Host 'To uninstall, double-click uninstall.bat.'
