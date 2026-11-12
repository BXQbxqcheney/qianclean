@echo off
rem ================================================================
rem  QianClean entry point  (start.bat)
rem  Finds and launches the core script (Qian*.bat) next to it.
rem  License: AGPL-3.0-or-later  -  see LICENSE
rem ================================================================
setlocal
cd /d "%~dp0"
set "CORE="
for %%f in ("Qian*.bat") do (
  if /i not "%%f"=="start.bat" if not defined CORE set "CORE=%%f"
)
if not defined CORE (
  echo.
  echo  [!] Core script "Qian*.bat" was not found next to start.bat
  echo  [!] Please keep all files in the same folder.
  echo.
  pause
  exit /b 1
)
endlocal & call "%CORE%" %*
exit /b
