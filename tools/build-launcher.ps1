<#
 Builds CRT-mpv.exe in the repo folder: a tiny launcher that carries the CRT-mpv icon and starts the bundled
 mpv with this folder's config (fullscreen by default). Windows only; compiled with the C# compiler that ships
 with Windows, so nothing is downloaded and mpv.exe is never modified.
 Started without a video (from a pinned taskbar icon, say), the player opens with the TV showing no signal.
   .\tools\build-launcher.ps1            build it (skips if it is newer than the icon and this script)
   .\tools\build-launcher.ps1 -Force     rebuild
#>
param([switch]$Force)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$out  = Join-Path $root 'CRT-mpv.exe'
$ico  = Join-Path $root 'assets\crt-mpv.ico'
if (-not (Test-Path $ico)) { throw "icon not found: $ico" }
$newestInput = (Get-Item $ico, $PSCommandPath | Sort-Object LastWriteTime | Select-Object -Last 1).LastWriteTime
if ((Test-Path $out) -and -not $Force -and ((Get-Item $out).LastWriteTime -ge $newestInput)) {
    Write-Host 'CRT-mpv.exe is up to date.'; return
}

$source = @'
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text;
using System.Windows.Forms;

[assembly: AssemblyTitle("CRT-mpv")]
[assembly: AssemblyProduct("CRT-mpv")]
[assembly: AssemblyDescription("CRT TV look for video, rendered by mpv")]
[assembly: AssemblyVersion("1.2.0.0")]

static class Launcher
{
    static string Quote(string a)
    {
        return "\"" + a.Replace("\"", "\\\"") + "\"";
    }

    [STAThread]
    static int Main(string[] args)
    {
        string root = AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\');
        string mpv = Path.Combine(Path.Combine(root, "mpv"), "mpv.exe");
        if (!File.Exists(mpv))
        {
            MessageBox.Show("mpv.exe was not found in " + Path.Combine(root, "mpv") + ". Double-click install.bat first.", "CRT-mpv");
            return 1;
        }
        var sb = new StringBuilder();
        sb.Append("--config-dir=" + Quote(Path.Combine(root, "config")));
        bool windowed = false;
        var files = new StringBuilder();
        foreach (string a in args)
        {
            if (a == "--windowed") { windowed = true; continue; }
            if (a.StartsWith("--")) { sb.Append(" " + Quote(a)); continue; }     // other mpv options pass straight through
            files.Append(" " + Quote(a));
        }
        // started without a video (double-clicked, pinned icon): the player opens with the TV showing no signal
        // (config\scripts\open.lua), and the hover bar's eject button opens a video
        if (!windowed) sb.Append(" --fullscreen");
        if (files.Length > 0) sb.Append(" --").Append(files);
        var psi = new ProcessStartInfo(mpv, sb.ToString());
        psi.UseShellExecute = false;
        psi.WorkingDirectory = root;
        Process.Start(psi);
        return 0;
    }
}
'@

$cp = New-Object System.CodeDom.Compiler.CompilerParameters
$cp.GenerateExecutable = $true
$cp.OutputAssembly = $out
$cp.CompilerOptions = "/target:winexe /optimize /win32icon:`"$ico`""
[void]$cp.ReferencedAssemblies.Add('System.dll')
[void]$cp.ReferencedAssemblies.Add('System.Windows.Forms.dll')
$provider = New-Object Microsoft.CSharp.CSharpCodeProvider
$res = $provider.CompileAssemblyFromSource($cp, $source)
if ($res.Errors.HasErrors) {
    $res.Errors | ForEach-Object { Write-Host $_.ToString() }
    throw 'Could not build CRT-mpv.exe'
}
Write-Host "Built $out"
