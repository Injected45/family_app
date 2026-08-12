@echo off
REM ============================================================================
REM  run_emulator.bat - run the app on an Android emulator against Supabase.
REM
REM    run_emulator.bat                    use a running emulator, or start the
REM                                        first AVD found
REM    run_emulator.bat Pixel_4_API_30     start that AVD specifically
REM    run_emulator.bat --list             show the AVDs on this machine
REM    run_emulator.bat --release          release build
REM
REM ----------------------------------------------------------------------------
REM  FOUR WINDOWS-BATCH TRAPS THIS FILE AVOIDS. All four were hit while writing
REM  it, and every one failed silently or misleadingly.
REM
REM  1. `call flutter`, never bare `flutter`. On Windows flutter is flutter.bat,
REM     and invoking a .bat from a .bat WITHOUT `call` transfers control instead
REM     of calling it - the rest of the script simply never runs.
REM
REM  2. Capture output through a TEMP FILE, not
REM     `for /f ... in ('"C:\path\adb.exe" devices ^| findstr ...')`.
REM     When the command inside for /f begins with a quote, cmd's quote-stripping
REM     mangles the pipeline: it printed "The system cannot find the path
REM     specified" and returned nothing, so a running emulator looked absent.
REM
REM  3. No `$` anchors in findstr patterns. adb and flutter emit CRLF, so a piped
REM     line ends with a carriage return and `device$` matches nothing.
REM
REM  4. ASCII ONLY, with CRLF line endings. cmd parses a .bat in the console's OEM
REM     codepage, so UTF-8 text decodes to bytes that can include & and |, which
REM     splits the line and makes cmd run the following words as commands
REM     ("'the' is not recognized as an internal or external command").
REM ----------------------------------------------------------------------------
REM
REM  The URL and anon key below are NOT secrets. They ship inside every build of
REM  this app and can be read straight out of the APK. The database design assumes
REM  exactly that: every rule is enforced by RLS, CHECK constraints, triggers and
REM  SECURITY DEFINER functions, so a hostile holder of this key can do nothing an
REM  honest one could not.
REM
REM  The SERVICE ROLE key bypasses RLS and must never appear in this file.
REM
REM  There is no 10.0.2.2 here. That alias was for reaching a Node API on the host
REM  machine's loopback. Supabase is a public HTTPS host, so the emulator reaches
REM  it the way a real phone does - which also means the emulator needs working
REM  internet, and a cold-booted AVD sometimes has none for the first few seconds.
REM ============================================================================
setlocal EnableDelayedExpansion

cd /d "%~dp0app"
if errorlevel 1 (
  echo Could not find the app folder next to this script.
  exit /b 1
)

set "SUPABASE_URL=https://nomgavgvkjdlzjgwozuv.supabase.co"
set "SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5vbWdhdmd2a2pkbHpqZ3dvenV2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODY0Nzg1ODksImV4cCI6MjEwMjA1NDU4OX0.lPtS1ooNMn9kVji28x37qgjUG8jvMPxYoiWz4OLb7d8"

REM Development sign-in: an ordinary email/password account with NO special
REM privilege. Its role still comes from public.profiles like everyone else's. It
REM exists so the app is testable before the Google provider is switched on.
set "DEV_LOGIN_EMAIL=admin@fam.test"
set "DEV_LOGIN_PASSWORD=Fam-Dev-m6sG8tBTWs1"

set "MODE=--debug"
set "AVD="
set "TMPD=%TEMP%\family_app_run"
set "DEVLIST=%TMPD%\devices.txt"
set "AVDLIST=%TMPD%\avds.txt"
if not exist "%TMPD%" mkdir "%TMPD%" >nul 2>&1

:parse
if "%~1"=="" goto after_parse
if /i "%~1"=="--list" goto list_avds
if /i "%~1"=="--release" (
  set "MODE=--release"
  shift
  goto parse
)
if /i "%~1"=="--profile" (
  set "MODE=--profile"
  shift
  goto parse
)
set "AVD=%~1"
shift
goto parse
:after_parse

where flutter >nul 2>&1
if errorlevel 1 (
  echo.
  echo   flutter is not on PATH. Open a terminal where "flutter --version" works,
  echo   or add Flutter's bin folder to PATH.
  exit /b 1
)

REM ---- Find adb -------------------------------------------------------------
set "ADB="
if exist "%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe" set "ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe"
if not defined ADB if exist "%ANDROID_HOME%\platform-tools\adb.exe" set "ADB=%ANDROID_HOME%\platform-tools\adb.exe"
if not defined ADB if exist "%ANDROID_SDK_ROOT%\platform-tools\adb.exe" set "ADB=%ANDROID_SDK_ROOT%\platform-tools\adb.exe"
if not defined ADB (
  where adb >nul 2>&1
  if not errorlevel 1 set "ADB=adb"
)
if not defined ADB (
  echo.
  echo   Could not find adb.exe. Looked in:
  echo     %LOCALAPPDATA%\Android\Sdk\platform-tools\
  echo     ANDROID_HOME\platform-tools\ and ANDROID_SDK_ROOT\platform-tools\
  echo   Install Android Studio's platform-tools, or set ANDROID_HOME.
  exit /b 1
)
echo   adb: %ADB%

REM ---- Is an emulator already up? -------------------------------------------
call :find_device
if defined DEVICE (
  echo   Using the emulator already running: !DEVICE!
  goto have_device
)

REM ---- Otherwise start one --------------------------------------------------
if not defined AVD (
  call flutter emulators > "%AVDLIST%" 2>nul
  for /f "tokens=1" %%A in ('findstr /r /c:"  android" "%AVDLIST%"') do (
    if not defined AVD set "AVD=%%A"
  )
)
if not defined AVD (
  echo.
  echo   No Android emulator is running and no AVD was found.
  echo   What adb sees:
  if exist "%DEVLIST%" type "%DEVLIST%"
  echo   Create one:   flutter emulators --create
  echo   Or list them: run_emulator.bat --list
  exit /b 1
)

echo   Starting emulator: !AVD!
start "" cmd /c flutter emulators --launch !AVD!

echo   Waiting for it to come up. A cold boot can take a minute.
"%ADB%" wait-for-device
REM wait-for-device returns as soon as adb can SEE the device, well before Android
REM has finished booting. Installing an APK before sys.boot_completed fails with a
REM confusing INSTALL_FAILED, so poll for the real signal.
set /a TRIES=0
:wait_boot
set /a TRIES+=1
set "BOOTED="
"%ADB%" shell getprop sys.boot_completed > "%TMPD%\boot.txt" 2>nul
for /f "usebackq tokens=1" %%B in ("%TMPD%\boot.txt") do set "BOOTED=%%B"
if "!BOOTED!"=="1" goto booted
if !TRIES! GEQ 90 (
  echo.
  echo   The emulator did not finish booting after about 3 minutes. Start it from
  echo   Android Studio's Device Manager, then run this script again.
  exit /b 1
)
timeout /t 2 /nobreak >nul
goto wait_boot
:booted
echo   Emulator booted.
call :find_device

:have_device
if not defined DEVICE (
  echo   Could not identify the emulator device id. What adb sees:
  if exist "%DEVLIST%" type "%DEVLIST%"
  exit /b 1
)

REM ---- A cold-booted emulator often has no DNS for a few seconds ------------
REM Checked because that failure is otherwise silent and looks like a bad key:
REM the app starts, the sign-in button works, and every request times out.
echo   Checking the emulator can reach Supabase...
set /a NET=0
:wait_net
set /a NET+=1
"%ADB%" -s !DEVICE! shell ping -c 1 -W 2 nomgavgvkjdlzjgwozuv.supabase.co >nul 2>&1
if not errorlevel 1 goto online
if !NET! GEQ 10 (
  echo   WARNING: the emulator could not resolve the Supabase host.
  echo            Running anyway. If every call fails, check the emulator's
  echo            network: cold boot it, or Extended Controls then Cellular.
  goto online
)
timeout /t 2 /nobreak >nul
goto wait_net
:online

echo.
echo   ============================================================
echo    device   !DEVICE!
echo    mode     !MODE!
echo    project  %SUPABASE_URL%
echo    dev user %DEV_LOGIN_EMAIL%
echo   ============================================================
echo.
echo    On the sign-in screen use the SECOND button - the outlined one below
echo    "Sign in with Google" - for the dev account. Google sign-in needs the
echo    provider enabled in the Supabase dashboard first.
echo.
echo    In the console below: r = hot reload, R = hot restart, q = quit.
echo.

call flutter run %MODE% -d !DEVICE! ^
  --dart-define=SUPABASE_URL=%SUPABASE_URL% ^
  --dart-define=SUPABASE_ANON_KEY=%SUPABASE_ANON_KEY% ^
  --dart-define=DEV_LOGIN=true ^
  --dart-define=DEV_LOGIN_EMAIL=%DEV_LOGIN_EMAIL% ^
  --dart-define=DEV_LOGIN_PASSWORD=%DEV_LOGIN_PASSWORD%

set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" (
  echo.
  echo   flutter run exited with %RC%.
  echo   If that was an INSTALL_FAILED, the emulator may be out of space:
  echo     adb shell pm uninstall ly.rhalla.family_app
  echo   then try again.
)
endlocal & exit /b %RC%

REM ---------------------------------------------------------------------------
REM  Writes the first running emulator's id into DEVICE.
REM
REM  Through a temp file on purpose - see trap 2 in the header. Piping adb's
REM  quoted path inside for /f returns nothing and prints a path error.
:find_device
set "DEVICE="
"%ADB%" devices > "%DEVLIST%" 2>nul
for /f "tokens=1" %%D in ('findstr /r /c:"^emulator-.*device" "%DEVLIST%"') do (
  if not defined DEVICE set "DEVICE=%%D"
)
exit /b 0

:list_avds
echo.
call flutter emulators
echo.
echo   Pass one of the Ids above as the first argument, e.g.
echo     run_emulator.bat Pixel_4_API_30
endlocal & exit /b 0
