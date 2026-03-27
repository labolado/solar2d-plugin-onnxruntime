@echo off
REM Build OnnxDemo for Windows using CoronaBuilder
REM
REM Usage:
REM   1. Install Solar2D (Corona)
REM   2. Double-click this file or run from command prompt
REM   3. Output: build\OnnxDemo.exe

set SCRIPT_DIR=%~dp0
set DST=%SCRIPT_DIR%build\win32
set APP_NAME=OnnxDemo
set PACKAGE=com.labolado.onnxruntime.demo

REM Find CoronaBuilder
set BUILDER=
for %%d in (
    "C:\Program Files (x86)\Corona Labs\Corona\Native\Corona\win\bin\CoronaBuilder.exe"
    "C:\Program Files\Corona Labs\Corona\Native\Corona\win\bin\CoronaBuilder.exe"
    "%APPDATA%\..\Local\Programs\Corona Labs\Corona\Native\Corona\win\bin\CoronaBuilder.exe"
) do (
    if exist %%d (
        set BUILDER=%%d
        goto :found
    )
)

echo ERROR: CoronaBuilder not found. Install Solar2D first.
echo Looked in:
echo   C:\Program Files (x86)\Corona Labs\Corona\
echo   C:\Program Files\Corona Labs\Corona\
pause
exit /b 1

:found
echo CoronaBuilder: %BUILDER%

REM Create build args
mkdir "%DST%" 2>nul
(
echo local params = {
echo     platform = 'win32',
echo     appName = '%APP_NAME%',
echo     appVersion = '1.0',
echo     dstPath = [[%DST%]],
echo     projectPath = [[%SCRIPT_DIR%]],
echo }
echo return params
) > "%TEMP%\win32-build-args.lua"

echo Building %APP_NAME% for Windows...
%BUILDER% build --lua "%TEMP%\win32-build-args.lua"

if %ERRORLEVEL% neq 0 (
    echo BUILD FAILED
    pause
    exit /b 1
)

echo.
echo === Build complete ===
echo Output: %DST%
dir "%DST%"
echo.
echo Press any key to launch...
pause
start "" "%DST%\%APP_NAME%.exe"
