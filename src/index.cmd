@echo off
where pwsh >nul 2>nul
if %ERRORLEVEL%==0 goto :use_pwsh
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0index-cli.ps1" %*
exit /b %ERRORLEVEL%

:use_pwsh
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0index-cli.ps1" %*
exit /b %ERRORLEVEL%
