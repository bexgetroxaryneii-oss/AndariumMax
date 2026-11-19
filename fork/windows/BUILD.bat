@echo off
title AndariumMax - Build  (Made by Claude Strife - X)
cd /d "%~dp0"
echo ==========================================================
echo   AndariumMax - one-step build
echo   Made by Claude Strife - X
echo ==========================================================
echo.

set "SRC=%~dp0Kernarium\fork\tool"
if not exist "%SRC%\Cargo.toml" set "SRC=%~dp0..\tool"
if not exist "%SRC%\Cargo.toml" (
  echo   Can't find the tool's source next to this file - tell Claude "no source".
  pause
  exit /b 1
)

echo [1/4] Checking for Rust...
set "CARGO="
where cargo >nul 2>nul && set "CARGO=cargo"
if not defined CARGO if exist "%USERPROFILE%\.cargo\bin\cargo.exe" set "CARGO=%USERPROFILE%\.cargo\bin\cargo.exe"
if not defined CARGO (
  echo   Rust isn't installed - downloading the installer...
  curl -L --progress-bar -o "%TEMP%\rustup-init.exe" https://win.rustup.rs/x86_64
  "%TEMP%\rustup-init.exe" -y --profile minimal
  set "CARGO=%USERPROFILE%\.cargo\bin\cargo.exe"
)
echo   Using: %CARGO%
echo.

echo [2/4] Checking for adb (talks to Android inside Andarium)...
set "HAVEADB="
where adb >nul 2>nul && set "HAVEADB=1"
if exist "%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe" set "HAVEADB=1"
if exist "tools\platform-tools\adb.exe" set "HAVEADB=1"
if defined HAVEADB (
  echo   Already here.
) else (
  echo   Downloading Google's platform-tools - progress below...
  if not exist "tools" mkdir "tools"
  curl -L --progress-bar -o "tools\platform-tools.zip" https://dl.google.com/android/repository/platform-tools-latest-windows.zip
  if exist "tools\platform-tools.zip" (
    echo   Unpacking...
    tar -xf "tools\platform-tools.zip" -C "tools"
    del "tools\platform-tools.zip"
  )
  if exist "tools\platform-tools\adb.exe" (echo   adb ready.) else (echo   Couldn't get adb - tell Claude "no adb".)
)
echo.

echo [3/4] Finding the Visual C++ linker (link.exe)...
set "PF86=%ProgramFiles(x86)%"
set "VCVARS="
call :findvc
if not defined VCVARS (
  echo   Not found - installing the Visual C++ Build Tools with winget.
  echo   This is a big download ^(a few GB^); progress shows below. Click Yes if Windows asks.
  winget install -e --id Microsoft.VisualStudio.2022.BuildTools --accept-source-agreements --accept-package-agreements --override "--passive --wait --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
  call :findvc
)
if not defined VCVARS (
  echo   Still can't find link.exe - tell Claude "no linker".
  pause
  exit /b 1
)
echo   Using: %VCVARS%
call "%VCVARS%" >nul
echo.

echo [4/4] Building AndariumMax (under a minute, live output below)...
taskkill /im AndariumMax.exe /f >nul 2>&1
set "CARGO_TARGET_DIR=%~dp0build"
powershell -NoProfile -ExecutionPolicy Bypass -Command "& '%CARGO%' build --release --color never --manifest-path '%SRC%\Cargo.toml' 2>&1 | ForEach-Object { $_.ToString() } | Where-Object { $_ -ne 'System.Management.Automation.RemoteException' } | Tee-Object -FilePath 'build_log.txt'; exit $LASTEXITCODE"
if errorlevel 1 (
  echo.
  echo   BUILD FAILED. The details are saved in build_log.txt - tell Claude "build failed".
  pause
  exit /b 1
)
copy /y "build\release\AndariumMax.exe" "AndariumMax.exe" >nul
if not exist "AndariumMax.exe" (
  echo   Couldn't find the built program - see build_log.txt.
  pause
  exit /b 1
)
echo.
echo   Done! Opening AndariumMax v0.1. From now on just open AndariumMax.exe.
start "" "%~dp0AndariumMax.exe"
timeout /t 5 >nul
exit /b 0

rem ---- finds a Visual Studio / Build Tools install that really has link.exe
:findvc
set "VCVARS="
set "VSWHERE=%PF86%\Microsoft Visual Studio\Installer\vswhere.exe"
if exist "%VSWHERE%" (
  for /f "usebackq delims=" %%I in (`"%VSWHERE%" -all -products * -property installationPath`) do call :checkvc "%%I"
)
if defined VCVARS goto :eof
for %%V in (18 2022 2019) do for %%E in (Community BuildTools Professional Enterprise) do (
  call :checkvc "%ProgramFiles%\Microsoft Visual Studio\%%V\%%E"
  call :checkvc "%PF86%\Microsoft Visual Studio\%%V\%%E"
)
goto :eof

:checkvc
if defined VCVARS goto :eof
if not exist "%~1\VC\Auxiliary\Build\vcvars64.bat" goto :eof
for /d %%M in ("%~1\VC\Tools\MSVC\*") do if exist "%%M\bin\Hostx64\x64\link.exe" set "VCVARS=%~1\VC\Auxiliary\Build\vcvars64.bat"
goto :eof
