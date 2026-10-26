<#
 Gives a player window the CRT-mpv icon (taskbar button + title bar) and, with -Launcher, its taskbar
 identity: right-click the button and the app entry reads "CRT-mpv" and starts CRT-mpv.exe, and "Pin to
 taskbar" pins CRT-mpv instead of plain mpv. Windows only; started by config/scripts/window-icon.lua.
 It never touches mpv.exe itself.
   -Hwnd        window handle (mpv's "window-id")
   -ProcessId   mpv's process id; the helper stays until that process exits so the icon handles stay valid
   -Icon        path to assets\crt-mpv.ico
   -Launcher    path to CRT-mpv.exe (optional)
 Developer options: -DumpTo file.png saves the icon the window ends up with; -NoWait exits straight away.
#>
param(
    [Parameter(Mandatory)][long]$Hwnd,
    [Parameter(Mandatory)][int]$ProcessId,
    [Parameter(Mandatory)][string]$Icon,
    [string]$Launcher = '',
    [string]$DumpTo = '',
    [switch]$NoWait
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class WinIcon
{
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr LoadImage(IntPtr h, string f, uint type, int cx, int cy, uint flags);
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
}

// The window's taskbar identity (System.AppUserModel.* on the window's property store)
public static class TaskbarId
{
    [StructLayout(LayoutKind.Sequential, Pack = 4)]
    struct PropertyKey { public Guid fmtid; public uint pid; }

    [StructLayout(LayoutKind.Explicit, Size = 24)]
    struct PropVariant { [FieldOffset(0)] public ushort vt; [FieldOffset(8)] public IntPtr p; }

    [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IPropertyStore
    {
        void GetCount(out uint count);
        void GetAt(uint i, out PropertyKey key);
        void GetValue(ref PropertyKey key, out PropVariant value);
        void SetValue(ref PropertyKey key, ref PropVariant value);
        void Commit();
    }

    [DllImport("shell32.dll")]
    static extern int SHGetPropertyStoreForWindow(IntPtr hwnd, ref Guid iid, [MarshalAs(UnmanagedType.Interface)] out IPropertyStore store);

    static readonly Guid AppUserModel = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3");

    static void Set(IPropertyStore store, uint pid, string value)
    {
        var key = new PropertyKey { fmtid = AppUserModel, pid = pid };
        var v = new PropVariant { vt = 31, p = Marshal.StringToCoTaskMemUni(value) };   // VT_LPWSTR
        try { store.SetValue(ref key, ref v); } finally { Marshal.FreeCoTaskMem(v.p); }
    }

    public static void Apply(IntPtr hwnd, string id, string command, string name, string icon)
    {
        var iid = new Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99");
        IPropertyStore store;
        Marshal.ThrowExceptionForHR(SHGetPropertyStoreForWindow(hwnd, ref iid, out store));
        try
        {
            Set(store, 2, command);   // RelaunchCommand
            Set(store, 3, icon);      // RelaunchIconResource
            Set(store, 4, name);      // RelaunchDisplayNameResource
            Set(store, 5, id);        // ID, last: the relaunch values only count once the window has an ID
        }
        finally { Marshal.ReleaseComObject(store); }
    }
}
'@
[void][WinIcon]::SetProcessDPIAware()
$win = [IntPtr]$Hwnd
function Load([int]$cx, [int]$cy) { [WinIcon]::LoadImage([IntPtr]::Zero, $Icon, 1, $cx, $cy, 0x10) }   # IMAGE_ICON, LR_LOADFROMFILE
$small = Load ([WinIcon]::GetSystemMetrics(49)) ([WinIcon]::GetSystemMetrics(50))   # SM_CXSMICON / SM_CYSMICON
$big   = Load ([WinIcon]::GetSystemMetrics(11)) ([WinIcon]::GetSystemMetrics(12))   # SM_CXICON / SM_CYICON
if ($small -eq [IntPtr]::Zero -or $big -eq [IntPtr]::Zero) { throw "could not load $Icon" }
[void][WinIcon]::SendMessage($win, 0x80, [IntPtr]0, $small)    # WM_SETICON, ICON_SMALL
[void][WinIcon]::SendMessage($win, 0x80, [IntPtr]1, $big)      # WM_SETICON, ICON_BIG
if ($Launcher -and (Test-Path $Launcher)) {
    # One ID per install folder: Windows keeps a hidden shortcut per ID and never updates its target, so a moved
    # or reinstalled copy must not share an ID with an old one
    $sha = [Security.Cryptography.SHA1]::Create()
    $tag = -join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Launcher.ToLowerInvariant()))[0..3] | ForEach-Object { $_.ToString('x2') })
    [TaskbarId]::Apply($win, "Retrogrounds.CRT-mpv.$tag", "`"$Launcher`"", 'CRT-mpv', "$Launcher,0")
}
if ($DumpTo) {
    Start-Sleep -Milliseconds 300
    $h = [WinIcon]::SendMessage($win, 0x7F, [IntPtr]1, [IntPtr]0)   # WM_GETICON, ICON_BIG
    $ic = [System.Drawing.Icon]::FromHandle($h)
    $ic.ToBitmap().Save($DumpTo, [System.Drawing.Imaging.ImageFormat]::Png)
}
if (-not $NoWait) { Wait-Process -Id $ProcessId -ErrorAction SilentlyContinue }
