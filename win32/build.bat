@echo off
REM Build plugin.onnxruntime for Windows (x86 / 32-bit)
REM Solar2D Windows Simulator is 32-bit, so the plugin must be x86.
REM
REM Prerequisites:
REM   1. Visual Studio with C/C++ workload (or Build Tools)
REM   2. Download ONNX Runtime Windows (x86):
REM      powershell -File download_ort.ps1
REM
REM Usage:
REM   Open "x86 Native Tools Command Prompt for VS" (NOT x64!)
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

REM Verify we're using x86 compiler
cl 2>&1 | findstr "x86" >nul
if %ERRORLEVEL% neq 0 (
    echo WARNING: Compiler may not be x86. Use "x86 Native Tools Command Prompt for VS"
)

mkdir "%OUT_DIR%" 2>nul

echo Building plugin_onnxruntime.dll (x86) ...

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
echo To verify x86: dumpbin /headers "%OUT_DIR%\plugin_onnxruntime.dll" ^| findstr machine
echo Copy plugin_onnxruntime.dll and onnxruntime.dll to Solar2D Simulator Plugins directory.
