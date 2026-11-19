@echo off
setlocal
title Discord Game Simulator
color 0B
cd /d "%~dp0"

rem UTF-8 для корректной кириллицы в консоли (для текущего окна).
chcp 65001 >nul 2>&1

where powershell.exe >nul 2>&1
if errorlevel 1 (
    echo.
    echo [ERROR] PowerShell не найден в PATH. Требуется Windows 10 или новее.
    echo [ERROR] PowerShell was not found in PATH. Windows 10+ is required.
    echo.
    pause
    exit /b 1
)

rem -ExecutionPolicy Bypass действует ТОЛЬКО для этого процесса и не меняет
rem системные настройки. Это нужно, потому что файлы из ZIP помечаются
rem «заблокированными из интернета» и не проходят политику RemoteSigned.
rem Сам скрипт дополнительно снимает блокировку через Unblock-File.
powershell.exe -NoProfile -NoLogo -ExecutionPolicy Bypass -File "%~dp0Run-Simulator.ps1" -Menu %*

set "EXITCODE=%errorlevel%"
echo.
if not "%EXITCODE%"=="0" (
    echo [INFO] Прогон завершился с кодом %EXITCODE%. Журнал: simulator-data\logs
    echo [INFO] Run finished with exit code %EXITCODE%. Logs: simulator-data\logs
)
pause
exit /b %EXITCODE%
