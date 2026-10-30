@echo off
REM ============================================================
REM SEVEN Language — Windows Build Script
REM Requires: LLVM/Clang + Visual Studio (for CRT headers/libs)
REM   winget install LLVM.LLVM
REM ============================================================

setlocal enabledelayedexpansion

echo.
echo  SEVEN Language v1.4 — Windows Build
echo  ====================================
echo.

REM ---- Find LLVM ----
set "LLVM_DIR="
for %%P in (
    "%ProgramFiles%\LLVM"
    "%ProgramW6432%\LLVM"
    "C:\Program Files\LLVM"
) do (
    if exist "%%~P\bin\clang.exe" (
        set "LLVM_DIR=%%~P"
        goto :found_llvm
    )
)
where clang >nul 2>&1
if %ERRORLEVEL% equ 0 goto :found_llvm_path
echo ERROR: LLVM/Clang not found.
echo   Install with: winget install LLVM.LLVM
exit /b 1

:found_llvm_path
echo   Found clang on PATH
goto :setup_paths

:found_llvm
echo   Found LLVM: %LLVM_DIR%
set "PATH=%LLVM_DIR%\bin;%PATH%"

:setup_paths
REM ---- Find Visual Studio ----
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" (
    echo ERROR: Visual Studio not found. Install VS Build Tools or VS Community.
    exit /b 1
)
for /f "delims=" %%i in ('"%VSWHERE%" -latest -property installationPath') do set "VS_PATH=%%i"
echo   Found VS: %VS_PATH%

REM ---- Find MSVC version ----
set "MSVC_VER="
for /f "delims=" %%v in ('dir /b "%VS_PATH%\VC\Tools\MSVC" 2^>nul') do set "MSVC_VER=%%v"
if "%MSVC_VER%"=="" (
    echo ERROR: MSVC tools not found
    exit /b 1
)
set "MSVC_INC=%VS_PATH%\VC\Tools\MSVC\%MSVC_VER%\include"
set "MSVC_LIB=%VS_PATH%\VC\Tools\MSVC\%MSVC_VER%\lib\x64"

REM ---- Find Windows SDK ----
set "SDK_VER="
for /f "delims=" %%s in ('dir /b "%ProgramFiles(x86)%\Windows Kits\10\Include" 2^>nul') do (
    echo %%s | findstr /b "10." >nul 2>&1
    if not errorlevel 1 set "SDK_VER=%%s"
)
if "%SDK_VER%"=="" (
    echo ERROR: Windows SDK not found
    exit /b 1
)
set "UCRT_INC=%ProgramFiles(x86)%\Windows Kits\10\Include\%SDK_VER%\ucrt"
set "UM_INC=%ProgramFiles(x86)%\Windows Kits\10\Include\%SDK_VER%\um"
set "SHARED_INC=%ProgramFiles(x86)%\Windows Kits\10\Include\%SDK_VER%\shared"
set "UCRT_LIB=%ProgramFiles(x86)%\Windows Kits\10\Lib\%SDK_VER%\ucrt\x64"
set "UM_LIB=%ProgramFiles(x86)%\Windows Kits\10\Lib\%SDK_VER%\um\x64"

echo   MSVC %MSVC_VER%, SDK %SDK_VER%

REM ---- Find LLVM-C headers ----
set "LLVM_INC="
if exist "%~dp0build\llvm-include\llvm-c\Core.h" (
    set "LLVM_INC=%~dp0build\llvm-include"
) else (
    echo ERROR: LLVM-C headers not found in build\llvm-include\
    echo   Run this from WSL first:
    echo     mkdir -p build/llvm-include/llvm-c/Transforms build/llvm-include/llvm/Config
    echo     cp /usr/include/llvm-c-*/llvm-c/*.h build/llvm-include/llvm-c/
    echo     cp /usr/include/llvm-c-*/llvm-c/Transforms/*.h build/llvm-include/llvm-c/Transforms/
    exit /b 1
)

if not exist build mkdir build

REM ---- Compile seven.exe ----
echo.
echo [1/3] Compiling seven.exe...
clang -O2 src\llvm_main.c src\llvm_lexer.c src\llvm_codegen.c -o build\seven.exe -I"%LLVM_INC%" -Isrc -I"%MSVC_INC%" -I"%UCRT_INC%" -I"%UM_INC%" -I"%SHARED_INC%" -L"%LLVM_DIR%\lib" -L"%MSVC_LIB%" -L"%UCRT_LIB%" -L"%UM_LIB%" -lLLVM-C -w
if %ERRORLEVEL% neq 0 (
    echo ERROR: Compilation failed
    exit /b 1
)

REM ---- Compile runtime ----
echo [2/3] Compiling runtime...
clang -O2 -c src\llvm_runtime.c -o build\seven_runtime_win.o -I"%MSVC_INC%" -I"%UCRT_INC%" -I"%UM_INC%" -I"%SHARED_INC%" -w
if %ERRORLEVEL% neq 0 (
    echo ERROR: Runtime compilation failed
    exit /b 1
)

REM ---- Verify ----
echo [3/3] Verifying...
build\seven.exe --version
echo.
echo   Build successful!
echo   Binary: build\seven.exe
echo   Runtime: build\seven_runtime_win.o

echo.
echo ====================================
echo Usage:
echo   seven run app.seven
echo   seven build app.seven -o app.exe
echo ====================================

endlocal
