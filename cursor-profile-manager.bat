@echo off
:: Launches the Cursor Profile Manager GUI (no console window kept open)
start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0cursor-profile-manager.ps1"
