@echo off
setlocal
set "PYTHONHOME="
set "PYTHONPATH=%~dp0..\python"
cd /d "%~dp0.."
set "PORT=%~1"
if "%PORT%"=="" set "PORT=COM3"
set "CAMERA=%~2"
if "%CAMERA%"=="" set "CAMERA=0"
echo Open on this PC: http://127.0.0.1:8000
echo Mobile address will be printed by web_app.py.
call "python\.venv\Scripts\python.exe" "python\web_app.py" --port "%PORT%" --camera "%CAMERA%"
if errorlevel 1 pause
endlocal
