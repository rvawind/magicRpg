@echo off
rem Requires plugin\jasshelper\pjass.exe (see README.md).
set KKWE=C:\Users\admin\Documents\WE\KKWE_nncouVer1.5.7.1
set HERE=%~dp0
set PATH=%KKWE%\bin;%PATH%
cd /d "%KKWE%\plugin\jasshelper"
.\clijasshelper.exe --scriptonly common.j blizzard.j "%HERE%out\harness.j" "%HERE%out\harness_out.j" > "%HERE%out\compile.log" 2>&1
echo EXIT=%ERRORLEVEL% >> "%HERE%out\compile.log"
