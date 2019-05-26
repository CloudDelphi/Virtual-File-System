@echo off
cls
echo Version (X.X.X.X [Text]):
set /P v=
verpatch vfs.dll "%v%" /va