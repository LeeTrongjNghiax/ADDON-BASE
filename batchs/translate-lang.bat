@echo off
setlocal enabledelayedexpansion

REM =====================================================================
REM  translate-lang.bat
REM
REM  Sits inside the "batchs" folder at the project root (same place as
REM  build.bat / dev.bat / release.bat). For each texts folder listed below
REM  (bp\texts, rp\texts by default), it:
REM
REM    1. Reads that folder's languages.json. It is the SOURCE OF TRUTH
REM       for which locales the pack ships, and this script never
REM       modifies it. Edit it by hand, or create one for a new project
REM       with:  npm run languages
REM    2. Duplicates the source .lang file (en_US.lang by default) into
REM       every other locale listed there.
REM    3. Machine-translates each duplicated file's values, leaving
REM       Minecraft formatting codes (section-sign codes), ~LINEBREAK~
REM       tokens, and any "protected words" (e.g. RP / BP) untouched.
REM
REM  Hand-written locales: put   # REGENERATE=0   on the FIRST line of a
REM  .lang file and it is never touched (no API call, no write). Every
REM  other existing locale file is regenerated, so mark the ones your
REM  team writes by hand before running this.
REM
REM  The actual work is done by scripts\translate-lang.js (Node.js).
REM  Requires Node.js 18+, an internet connection, and a Gemini API key
REM  (free tier available at https://aistudio.google.com/apikey).
REM
REM  The key is read from the GEMINI_API_KEY environment variable. The
REM  easiest way to set it: copy .env.example (project root) to .env and
REM  paste your key in there -- this script auto-loads .env if present
REM  and GEMINI_API_KEY isn't already set in your environment. .env is
REM  already in .gitignore, so it never gets committed.
REM
REM  Example layout:
REM    project\
REM      batchs\
REM        translate-lang.bat   <- this file lives here
REM      scripts\
REM        translate-lang.js
REM      sources\
REM        behavior_packs\bp\texts\en_US.lang
REM        resource_packs\rp\texts\en_US.lang
REM =====================================================================

REM ======================= DEFAULTS =======================
set "SOURCE_LOCALE_DEFAULT=en_US"

REM Semicolon-separated, relative to the project root. Both packs by
REM default: the behavior pack's pack name/description need translating
REM too.
set "TEXTS_DIRS_DEFAULT=sources\behavior_packs\bp\texts;sources\resource_packs\rp\texts"

REM Space-separated whole words that must NEVER be translated.
set "PROTECTED_WORDS_DEFAULT=RP BP"

REM ==========================================================

echo ============================================================
echo  Translate .lang Files - Configuration
echo ============================================================
echo.

set "AUTO_MODE=N"
set /p "AUTO_MODE=Run with ALL default settings, no further prompts? (Y/N) [N]: "

if /I "%AUTO_MODE%"=="Y" (
    echo.
    echo Running in ONE-CLICK mode: every setting below uses its default.
) else (
    echo.
    echo Running in MANUAL mode: press Enter at any prompt to keep the
    echo default shown in [ ], or type a new value.
)
echo.

set "SOURCE_LOCALE=%SOURCE_LOCALE_DEFAULT%"
if /I not "%AUTO_MODE%"=="Y" set /p "SOURCE_LOCALE=Source locale to translate FROM [%SOURCE_LOCALE%]: "

set "TEXTS_DIRS=%TEXTS_DIRS_DEFAULT%"
if /I not "%AUTO_MODE%"=="Y" set /p "TEXTS_DIRS=Texts folders, semicolon-separated, relative to project root [%TEXTS_DIRS%]: "

set "PROTECTED_WORDS=%PROTECTED_WORDS_DEFAULT%"
if /I not "%AUTO_MODE%"=="Y" set /p "PROTECTED_WORDS=Words to always leave untranslated, space-separated [%PROTECTED_WORDS%]: "

echo.

echo   Source locale   : %SOURCE_LOCALE%
echo   Texts folders    : %TEXTS_DIRS%
echo   Protected words  : %PROTECTED_WORDS%
echo   Target locales   : from each folder's languages.json
echo   Hand-written     : files starting with "# REGENERATE=0" are skipped
echo.

REM BASE_DIR = the project root, i.e. one level up from this script's
REM own folder (batchs\).
for %%I in ("%~dp0..") do set "BASE_DIR=%%~fI"
if "%BASE_DIR:~-1%"=="\" set "BASE_DIR=%BASE_DIR:~0,-1%"

set "SCRIPT_PATH=%BASE_DIR%\scripts\translate-lang.js"

if not exist "%SCRIPT_PATH%" (
    echo Could not find translate-lang.js at:
    echo   %SCRIPT_PATH%
    pause
    exit /b 1
)

where node >nul 2>&1
if errorlevel 1 (
    echo Node.js was not found on PATH. Install Node.js 18+ from
    echo https://nodejs.org and try again.
    pause
    exit /b 1
)

REM ---------------------------------------------------------------
REM  Load .env (project root) if present. Existing environment
REM  variables always win -- .env only fills in what isn't already
REM  set, so e.g. a CI pipeline setting GEMINI_API_KEY itself still
REM  works untouched.
REM ---------------------------------------------------------------
if exist "%BASE_DIR%\.env" (
    for /f "usebackq eol=# tokens=1,* delims==" %%K in ("%BASE_DIR%\.env") do (
        if not "%%K"=="" if not defined %%K set "%%K=%%L"
    )
)

if "%GEMINI_API_KEY%"=="" (
    echo GEMINI_API_KEY is not set. Get a free key at
    echo https://aistudio.google.com/apikey, then either:
    echo   - copy .env.example to .env and paste it in there, or
    echo   - run: set GEMINI_API_KEY=your-key-here
    pause
    exit /b 1
)

echo ============================================================
echo  Running translation
echo ============================================================
echo.

pushd "%BASE_DIR%"
node "%SCRIPT_PATH%"
set "NODE_EXIT=%ERRORLEVEL%"
popd

echo.
if not "%NODE_EXIT%"=="0" (
    echo ------------------------------------------
    echo Finished with errors -- see the log above.
    echo ------------------------------------------
    pause
    exit /b 1
)

echo ------------------------------------------
echo Done. You can close this window now.
echo ------------------------------------------
pause
exit /b 0
