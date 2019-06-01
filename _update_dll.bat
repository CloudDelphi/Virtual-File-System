@echo off
:start
cls
set h3dir=D:\Heroes 3
copy /Y Vfs.dll "%h3dir%\vfs.dll"
copy /Y Vfs.map "%h3dir%\Vfs.map"
php "%h3dir%\Tools\ExeMapCompiler\compile.phc" "vfs.map" "%h3dir%/DebugMaps"
echo.
echo.
echo %date% %time%
echo.
pause
goto start