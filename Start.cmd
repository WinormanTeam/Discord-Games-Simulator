@echo off
setlocal
title Discord Game Simulator
color 0B
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0Run-Simulator.ps1" -Menu
echo.
pause
