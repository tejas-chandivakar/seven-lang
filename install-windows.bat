@echo off
REM ============================================================
REM SEVEN Language — Windows Setup Script
REM Installs dependencies and builds SEVEN from source
REM ============================================================

setlocal enabledelayedexpansion

echo.
echo  SEVEN Language — Windows Setup
echo  ===============================
echo.

REM ---- Check for winget ----
where winget >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo ERROR: winget not found. Windows 10/11 with App Installer required.
    echo   Get it from: https://aka.ms/getwinget
    exit /b 1
)

REM ---- Install LLVM if missing ----
where clang >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo [1/3] Installing LLVM/Clang...
    winget install LLVM.LLVM --accept-package-agreements --accept-source-agreements
    if %ERRORLEVEL% neq 0 (
        echo ERROR: LLVM install failed
        exit /b 1
    )
    echo   LLVM installed. You may need to restart your terminal for PATH changes.
) else (
    echo [1/3] LLVM/Clang already installed — OK
)

REM ---- Install CMake if missing ----
where cmake >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo [2/3] Installing CMake...
    winget install Kitware.CMake --accept-package-agreements --accept-source-agreements
    if %ERRORLEVEL% neq 0 (
        echo ERROR: CMake install failed
        exit /b 1
    )
    echo   CMake installed.
) else (
    echo [2/3] CMake already installed — OK
)

REM ---- Refresh PATH ----
set "PATH=%ProgramFiles%\LLVM\bin;%ProgramFiles%\CMake\bin;%PATH%"

REM ---- Build ----
echo [3/3] Building SEVEN...
call build.bat
if %ERRORLEVEL% neq 0 (
    echo.
    echo Setup failed during build. If you just installed LLVM/CMake,
    echo try closing and reopening your terminal, then run build.bat again.
    exit /b 1
)

echo.
echo ===============================
echo  Setup complete!
echo  Run: seven --version
echo ===============================

endlocal
