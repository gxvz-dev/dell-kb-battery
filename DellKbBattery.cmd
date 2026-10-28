@echo off
rem Double-click launcher for the GUI (no console window, no execution-policy prompt).
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0DellKbBatteryGUI.ps1"
