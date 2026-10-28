<#
.SYNOPSIS
  GUI for Get-DellKbBattery.ps1: Dell receiver keyboard/mouse battery on one PC.
  Remote PC over WinRM (current credentials); this PC runs locally. Many PCs: see README (-Csv).
  Keep both .ps1 files in the same folder. Ctrl+C in the grid copies selected rows.
#>
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()

$Script  = Join-Path $PSScriptRoot 'Get-DellKbBattery.ps1'
$Replace = 20   # battery % below this = red "Replace"
$Low     = 40   # below this = amber "Low"; otherwise green "OK"

$form = New-Object Windows.Forms.Form -Property @{
    Text = 'Dell Keyboard Battery'; Size = '680,280'; StartPosition = 'CenterScreen'
    Font = New-Object Drawing.Font('Segoe UI', 9)
}
$top   = New-Object Windows.Forms.Panel -Property @{ Dock = 'Top'; Height = 40; Padding = '8,8,8,6' }
$pcBox = New-Object Windows.Forms.TextBox -Property @{ Dock = 'Fill'; Text = $env:COMPUTERNAME }
$check = New-Object Windows.Forms.Button -Property @{ Dock = 'Right'; Width = 90; Text = 'Check' }
$top.Controls.AddRange(@($pcBox, $check))

$grid = New-Object Windows.Forms.DataGridView -Property @{
    Dock = 'Fill'; ReadOnly = $true; AllowUserToAddRows = $false; RowHeadersVisible = $false
    SelectionMode = 'FullRowSelect'; AutoSizeColumnsMode = 'Fill'; BackgroundColor = 'Window'; BorderStyle = 'None'
    ClipboardCopyMode = 'EnableAlwaysIncludeHeaderText'
}
foreach ($c in 'Device', 'Battery', 'Status', 'Receiver') { [void]$grid.Columns.Add($c, $c) }
$grid.Columns['Device'].FillWeight = 200

$strip  = New-Object Windows.Forms.StatusStrip
$status = New-Object Windows.Forms.ToolStripStatusLabel -Property @{ Text = 'Enter a PC name, then Check (Enter).' }
[void]$strip.Items.Add($status)

$form.Controls.AddRange(@($grid, $top, $strip))     # Fill first so Top/Bottom dock around it
$form.AcceptButton = $check

function Add-Row($device, $battery, $state, $receiver) {
    $i = $grid.Rows.Add($device, $battery, $state, $receiver)
    $color = switch ($state) { 'Replace' { 'LightPink' } 'Low' { 'Moccasin' } 'OK' { 'PaleGreen' } 'Error' { 'Gainsboro' } }
    if ($color) { $grid.Rows[$i].DefaultCellStyle.BackColor = $color }
}

$timer = New-Object Windows.Forms.Timer -Property @{ Interval = 300 }

# Run as a job so the window stays responsive while WinRM connects.
$check.Add_Click({
    $script:pc = $pcBox.Text.Trim()
    if (-not $script:pc) { return }
    $grid.Rows.Clear()
    $script:job = if ($script:pc -in $env:COMPUTERNAME, 'localhost') { Start-Job -FilePath $Script }
                  else { Invoke-Command -ComputerName $script:pc -FilePath $Script -AsJob }
    $script:started = Get-Date
    $check.Enabled = $false
    $status.Text = "Checking $($script:pc)..."
    $timer.Start()
})

$timer.Add_Tick({
    if ($script:job.State -in 'NotStarted', 'Running') { return }
    $timer.Stop()
    foreach ($r in $script:job | Receive-Job -ErrorAction SilentlyContinue) {
        $state = if ($r.Device -eq 'No Dell receiver found') { 'No receiver' }
                 elseif ($null -eq $r.Battery) { 'Unavailable' }
                 elseif ($r.Battery -lt $Replace) { 'Replace' }
                 elseif ($r.Battery -lt $Low) { 'Low' }
                 else { 'OK' }
        Add-Row $r.Device $r.Battery $state $r.Receiver
    }
    $failed = $script:job.ChildJobs | Where-Object State -eq 'Failed' | Select-Object -First 1
    if ($failed) { Add-Row ($failed.JobStateInfo.Reason.Message -replace '^.*error message : ' -split '\. ')[0] $null 'Error' '' }
    $grid.ClearSelection()   # selection highlight would hide the first row's colour
    $script:job | Remove-Job -Force
    $check.Enabled = $true
    $status.Text = '{0}: checked in {1:N1} s' -f $script:pc, ((Get-Date) - $script:started).TotalSeconds
})

[void]$form.ShowDialog()
