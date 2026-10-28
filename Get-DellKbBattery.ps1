<#
.SYNOPSIS
  Battery level of Dell wireless keyboards/mice on a Dell USB receiver.
  No Dell software required. Windows PowerShell 5.1.

.DESCRIPTION
  Dell USB receivers (Universal 413C:2514, 413C:4503, Secure Link 413C:C080): 32-byte HID
  feature report 0x08 on interface MI_02. Query-only commands, from the reverse-engineered
  protocol in github.com/michaelknap/dell-rf (docs/PROTOCOL-4503.md):
    08 03 <slot>  slot record: [3]=kind (1 kbd, 2 mouse), [8..27]=ASCII model
    08 10 <slot>  battery: [3]=percent (0-100, anything else = unavailable)
  The record's battery-capability bit ([30] 0x10) is not used: it is 00 for a KB3121W on 4503 that
  still reports battery, and Dell's own getter only checks the 0-100 range.
  Undocumented by Dell. Verified on 2514 and 4503 with KB3121W/MS3121W. Never sends 08 06 (remove device).
  The receiver caches levels; a sleeping device may report its last known value.
  Output: objects with Device, Battery ([int] percent or $null = unavailable), Receiver.

.EXAMPLE
  .\Get-DellKbBattery.ps1
  .\Get-DellKbBattery.ps1 -ReceiverPid 'XXXX'  # try another Dell receiver PID
  .\Get-DellKbBattery.ps1 -Csv .\pcs.csv | Export-Csv .\results.csv -NoTypeInformation
#>
param(
    [string[]]$ReceiverPid = @('2514', '4503', 'C080'),
    [string]$Csv,       # PC names in the first column (header row required); runs this script on each over WinRM
    [switch]$SelfTest
)

if ($Csv) {
    $pcs = Import-Csv $Csv | ForEach-Object { @($_.PSObject.Properties.Value)[0] } | Where-Object { $_ }
    Invoke-Command -ComputerName $pcs -FilePath $PSCommandPath |
        Select-Object @{ n = 'PC'; e = { $_.PSComputerName } }, Device, Battery, Receiver
    return
}

Add-Type @'
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class DellRx {
    // HidD_* return BOOLEAN (1 byte) -- must be marshalled as U1 or failures read as success.
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern SafeFileHandle CreateFile(string name, uint access, uint share, IntPtr sa, uint disp, uint flags, IntPtr tmpl);
    [DllImport("hid.dll")] [return: MarshalAs(UnmanagedType.U1)] static extern bool HidD_SetFeature(SafeFileHandle h, byte[] buf, int len);
    [DllImport("hid.dll")] [return: MarshalAs(UnmanagedType.U1)] static extern bool HidD_GetFeature(SafeFileHandle h, byte[] buf, int len);

    // No access rights needed for feature-report IOCTLs.
    public static SafeFileHandle Open(string path) { return CreateFile(path, 0, 3, IntPtr.Zero, 3, 0, IntPtr.Zero); }

    // Send [0x08, cmd, arg, 0...] (32 bytes), return the reply if it echoes 08 <cmd> <arg>, else null.
    public static byte[] Ask(SafeFileHandle h, byte cmd, byte arg) {
        byte[] req = new byte[32]; req[0] = 0x08; req[1] = cmd; req[2] = arg;
        if (!HidD_SetFeature(h, req, 32)) return null;
        byte[] rsp = new byte[32]; rsp[0] = 0x08;
        if (!HidD_GetFeature(h, rsp, 32)) return null;
        return Echoes(rsp, cmd, arg) ? rsp : null;
    }

    public static bool Echoes(byte[] r, byte cmd, byte arg) { return r.Length >= 4 && r[0] == 0x08 && r[1] == cmd && r[2] == arg; }
}
'@

$Kind = @{ 1 = 'Keyboard'; 2 = 'Mouse' }

# Slot record -> object, or $null for empty slot (kind FF). Battery reply byte 3 -> percent.
function Read-Slot([string]$rx, [byte[]]$rec, [byte[]]$bat) {
    if ($null -eq $rec -or -not $Kind.ContainsKey([int]$rec[3])) { return }   # bare return: $null would be emitted as a row
    $model = [Text.Encoding]::ASCII.GetString($rec, 8, 20).Trim([char]0)
    $level = if ($null -eq $bat -or $bat[3] -gt 100) { $null } else { [int]$bat[3] }
    [pscustomobject]@{ Device = "$($Kind[[int]$rec[3]]) $model"; Battery = $level; Receiver = $rx }
}

if ($SelfTest) {
    # real replies captured from a 2514 receiver (KB3121W, MS3121W)
    $kb  = [byte[]](0x08,0x03,0x02,0x01,0x06,0x40,0x76,0xB4,0x4B,0x42,0x33,0x31,0x32,0x31,0x57,0,0,0,0,0,0,0,0,0,0,0,0,0,0x16,0,0x33,0x11)
    $emp = [byte[]](@(0x08,0x03,0x03) + @(0xFF) * 29)
    $r = Read-Slot 'x' $kb ([byte[]](8, 0x10, 2, 0x64))
    if ($r.Device -ne 'Keyboard KB3121W' -or $r.Battery -ne 100) { throw "kb parse: $r" }
    if ($null -ne (Read-Slot 'x' $kb ([byte[]](8, 0x10, 2, 0xFF))).Battery) { throw 'over 100' }
    if ($null -ne (Read-Slot 'x' $emp $null)) { throw 'empty slot' }
    # 4503 receiver: capability byte [30] = 00 but battery reply is valid (0x5C = 92%)
    $kb4503 = [byte[]](0x08,0x03,0x02,0x01,0x04,0x6D,0xEA,0xE3,0x4B,0x42,0x33,0x31,0x32,0x31,0x57,0,0,0,0,0,0,0,0,0,0,0,0,0,0x27,0x10,0,0)
    if ((Read-Slot 'x' $kb4503 ([byte[]](8, 0x10, 2, 0x5C))).Battery -ne 92) { throw 'capability flag ignored' }
    if ([DellRx]::Echoes([byte[]](8, 0x10, 1, 50), 0x10, 2)) { throw 'wrong slot echo' }
    'SelfTest passed'; return
}

$HidGuid = '{4d1e55b2-f16f-11cf-88cb-001111000030}'   # GUID_DEVINTERFACE_HID
$pnp = Get-PnpDevice -PresentOnly

$battery = @(
    # only the vendor collection on MI_02 answers report 0x08
    foreach ($rxPid in $ReceiverPid) {
        foreach ($c in $pnp | Where-Object { $_.InstanceId -like "HID\VID_413C&PID_$rxPid&MI_02*" }) {
            $h = [DellRx]::Open('\\?\' + $c.InstanceId.Replace('\', '#') + '#' + $HidGuid)
            try {
                if ($h.IsInvalid) { continue }
                foreach ($slot in 1..6) {
                    $rec = [DellRx]::Ask($h, 3, $slot)
                    Read-Slot "413C:$rxPid" $rec $(if ($rec) { [DellRx]::Ask($h, 0x10, $slot) })
                }
            } finally { $h.Dispose() }
        }
    }
)

if ($battery) { return $battery }
# no receiver: list the Dell USB PIDs present so an unknown receiver can be tried with -ReceiverPid
$pids = $pnp.InstanceId | Select-String 'VID_413C&PID_([0-9A-F]{4})' | ForEach-Object { $_.Matches[0].Groups[1].Value } | Sort-Object -Unique
[pscustomobject]@{ Device = 'No Dell receiver found'; Battery = $null; Receiver = "Dell USB PIDs: $($pids -join ', ')" }
