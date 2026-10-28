# Dell Keyboard Battery

Checks the battery level of Dell wireless keyboards and mice that connect through a Dell USB receiver.
You don't need Dell Peripheral Manager. Runs in Windows PowerShell 5.1.

## Files

- `Get-DellKbBattery.ps1` - the check itself.
- `DellKbBatteryGUI.ps1` - a small window for checking one PC. Keep it in the same folder as the script.
- `DellKbBattery.cmd` - double-click this to open the window.

## Use

**One PC, with the window:** double-click `DellKbBattery.cmd`. To open it from a prompt instead:

```
powershell -ExecutionPolicy Bypass -File .\DellKbBatteryGUI.ps1
```

Type a PC name and press Enter. Rows are colour-coded:

- red: below 20% (replace the battery)
- amber: below 40%
- green: 40% or more
- grey: the PC couldn't be reached

You can change the thresholds at the top of the GUI file.

**This PC, from the command line:**

```
.\Get-DellKbBattery.ps1
```

**Many PCs, from a CSV:**

```
.\Get-DellKbBattery.ps1 -Csv .\pcs.csv | Export-Csv .\results.csv -NoTypeInformation
```

`pcs.csv` must have a header row. The PC names go in the first column:

```
ComputerName
PC-001
PC-002
```

Unreachable PCs are listed as errors in the console.

## Requirements

- Remote PCs must accept WinRM (PowerShell remoting) and allow your account. The tool connects with your current credentials.
- PowerShell must be able to compile C# with `Add-Type`. Constrained Language Mode blocks this.

## Supported receivers

| USB ID    | Receiver                | Tested                    |
|-----------|-------------------------|---------------------------|
| 413C:2514 | Dell Universal Receiver | Yes (KB3121W / MS3121W)   |
| 413C:4503 | Dell Universal Receiver | Yes (KB3121W / MS3121W)   |
| 413C:C080 | Dell Secure Link        | No                        |

If a PC shows "No Dell receiver found", the Receiver column lists the Dell USB IDs it does have.
To try one of them, run `-ReceiverPid XXXX`.

## Notes

- The receiver keeps the last known level. A keyboard that is asleep or switched off may show an old value.
- This uses an undocumented Dell protocol, reverse-engineered by
  [dell-rf](https://github.com/michaelknap/dell-rf). The tool only sends read queries and never pairs or removes devices.
- To test the parsing, run `.\Get-DellKbBattery.ps1 -SelfTest`.
