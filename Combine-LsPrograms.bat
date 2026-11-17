@echo off
REM Double-click to run Combine-LsPrograms.ps1 (settings are inside the .ps1 file)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Combine-LsPrograms.ps1" %*
