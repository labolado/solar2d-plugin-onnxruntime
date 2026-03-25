@echo off
REM Build plugin.onnxruntime for Windows (x64)
REM
REM Prerequisites:
REM   1. Visual Studio with C/C++ workload (or Build Tools)
REM   2. Download ONNX Runtime Windows:
REM      powershell -File download_ort.ps1
REM
REM Usage:
REM   Open "Developer Command Prompt for VS"
REM   cd win32
REM   build.bat

set SCRIPT_DIR=%~dp0
set PLUGIN_DIR=%SCRIPT_DIR%..
set ORT_DIR=%SCRIPT_DIR%onnxruntime-win
set OUT_DIR=%SCRIPT_DIR%build

if not exist "%ORT_DIR%\lib\onnxruntime.lib" (
    echo ERROR: ONNX Runtime Windows not found at %ORT_DIR%
    echo   Run: powershell -File download_ort.ps1
    exit /b 1
)

REM Find Lua headers — use Solar2D's bundled Lua 5.1 headers
REM Adjust this path to your Solar2D installation
set LUA_INCLUDE=C:\Program Files (x86)\Corona Labs\Corona\Native\Corona\shared\include\lua
if not exist "%LUA_INCLUDE%\lua.h" (
    echo ERROR: Solar2D Lua 5.1 headers not found at %LUA_INCLUDE%
    echo Set LUA_INCLUDE to your Solar2D Lua headers path.
    exit /b 1
)

mkdir "%OUT_DIR%" 2>nul

echo Building plugin_onnxruntime.dll ...

cl /O2 /LD /W3 ^
    /I"%ORT_DIR%\include" ^
    /I"%LUA_INCLUDE%" ^
    "%PLUGIN_DIR%\plugin_onnxruntime.c" ^
    /Fe"%OUT_DIR%\plugin_onnxruntime.dll" ^
    /link /LIBPATH:"%ORT_DIR%\lib" onnxruntime.lib

if %ERRORLEVEL% neq 0 (
    echo BUILD FAILED
    exit /b 1
)

echo Built: %OUT_DIR%\plugin_onnxruntime.dll
echo.
echo Copy to Solar2D project or Simulator Plugins directory to use.
