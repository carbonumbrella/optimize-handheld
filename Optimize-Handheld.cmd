@echo off
rem Menu for Optimize-Handheld.ps1. Keep this file ASCII with CRLF line ends.
setlocal
set "PS=powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Optimize-Handheld.ps1""
echo.
echo   Optimize-Handheld
echo.
echo   1  Audit: only check, change nothing (start here)
echo   2  Apply Standard: safe set
echo   3  Apply Full: Standard + small apps, WMIC, vendor background services, OneDrive sync off
echo   4  Undo the latest Apply
echo   5  Check savings: compare with the state before Apply (reboot first)
echo   6  Disable BitLocker: decrypt drive C: to reduce SSD overhead
echo   7  Exit
echo.
choice /c 1234567 /n /m "Choose 1-7: "
if errorlevel 7 goto :eof
if errorlevel 6 (%PS% -Mode BitLocker -Pause & goto :eof)
if errorlevel 5 (%PS% -Mode Savings -Pause & goto :eof)
if errorlevel 4 (%PS% -Mode Undo -Pause & goto :eof)
if errorlevel 3 (%PS% -Mode Apply -Level Full -Pause & goto :eof)
if errorlevel 2 (%PS% -Mode Apply -Level Standard -Pause & goto :eof)
%PS% -Mode Audit -Level Full -Pause
