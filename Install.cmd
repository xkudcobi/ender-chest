@echo off
rem One-time install / Tek seferlik kurulum. Ender Chest starts afterwards and asks for your language.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Install.ps1"
pause
