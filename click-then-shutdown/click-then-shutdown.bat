@echo off
rem Double-click this file to run click-then-shutdown.ps1 (it must be in the same folder).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0click-then-shutdown.ps1" %*
pause
