@echo off
setlocal
set "PYTHONHOME="
set "PYTHONPATH=%~dp0..\python"
cd /d "%~dp0.."
if "%~1"=="" (
  echo Usage: run_air_drawing_uart.cmd COM7 [camera_index]
  exit /b 2
)
set "CAMERA=%~2"
if "%CAMERA%"=="" set "CAMERA=0"
call "python\.venv\Scripts\python.exe" "python\air_drawing_uart.py" --port "%~1" --camera "%CAMERA%" %~3 %~4 %~5 %~6
if errorlevel 1 pause
endlocal
