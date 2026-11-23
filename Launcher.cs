// Ender Chest başlatıcısı: PowerShell panelini konsol penceresi açmadan başlatır.
// Derleme: tools\Build.ps1
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;

[assembly: AssemblyTitle("Ender Chest")]
[assembly: AssemblyProduct("Ender Chest")]
[assembly: AssemblyDescription("Gather desktop projects in one chest without breaking their paths.")]
[assembly: AssemblyVersion("3.4.0.0")]
[assembly: AssemblyFileVersion("3.4.0.0")]

static class EnderChestLauncher {
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern int MessageBoxW(IntPtr hWnd, string text, string caption, uint type);

    [STAThread]
    static int Main(string[] args) {
        string dir = AppDomain.CurrentDomain.BaseDirectory;
        string script = Path.Combine(dir, "EnderChest.ps1");
        if (!File.Exists(script)) {
            MessageBoxW(IntPtr.Zero, "EnderChest.ps1 bulunamadı:\n" + script, "Ender Chest", 0x10);
            return 1;
        }
        bool tray = Array.Exists(args, a => string.Equals(a, "--tray", StringComparison.OrdinalIgnoreCase));
        string powershell = Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe");
        var psi = new ProcessStartInfo(powershell,
            "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + script + "\"" + (tray ? " -Tray" : ""));
        psi.UseShellExecute = false;
        psi.CreateNoWindow = true;
        psi.WorkingDirectory = dir;
        try {
            Process.Start(psi);
        } catch (Exception e) {
            MessageBoxW(IntPtr.Zero, "Ender Chest başlatılamadı:\n" + e.Message, "Ender Chest", 0x10);
            return 1;
        }
        return 0;
    }
}
