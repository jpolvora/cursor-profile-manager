@echo off
:: Launches the Cursor Profile Manager GUI (no console window kept open)
cd /d "%~dp0"
start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0cursor-profile-manager.ps1"
if errorlevel 1 (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Add-Type -AssemblyName System.Windows.Forms; [void][System.Windows.Forms.MessageBox]::Show('Cursor Profile Manager failed to start. Run cursor-profile-manager.ps1 from PowerShell to see the error.', 'Cursor Profile Manager', 'OK', 'Error')"
)
