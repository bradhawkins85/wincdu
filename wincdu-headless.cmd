@echo off
setlocal

if "%~1"=="" goto :usage
if "%~2"=="" goto :usage

set "SCRIPT_DIR=%~dp0"
python "%SCRIPT_DIR%wincdu-headless.py" "%~1" "%~2" %3 %4 %5 %6 %7 %8 %9
exit /b %ERRORLEVEL%

:usage
echo Usage: wincdu-headless.cmd ^<scan_path^> ^<output_html^> [--follow-symlinks]
exit /b 1
