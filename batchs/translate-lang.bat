@echo off
setlocal enabledelayedexpansion

REM =====================================================================
REM  translate-lang.bat
REM
REM  Sits inside the "batchs" folder at the project root (same place as
REM  build.bat / dev.bat / release.bat). For each texts folder listed below
REM  (bp\texts, rp\texts by default), it:
REM
REM    1. Duplicates the source .lang file (en_US.lang by default) into
REM       every target locale in the list.
REM    2. Machine-translates each duplicated file's values, leaving
REM       Minecraft formatting codes (section-sign codes), ~LINEBREAK~
REM       tokens, and any "protected words" (e.g. RP / BP) untouched.
REM    3. Updates that folder's languages.json to include every locale.
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

REM Semicolon-separated, relative to the project root.
REM "TEXTS_DIRS_DEFAULT=sources\behavior_packs\bp\texts;sources\resource_packs\rp\texts"
set "TEXTS_DIRS_DEFAULT=sources\resource_packs\rp\texts"

REM Space-separated whole words that must NEVER be translated.
set "PROTECTED_WORDS_DEFAULT=RP BP"

REM Space-separated. This is the full locale list the project ships with.
set "TARGET_LOCALES_DEFAULT=en_GB de_DE es_ES es_MX fr_FR fr_CA it_IT ja_JP ko_KR pt_BR pt_PT ru_RU zh_CN zh_TW nl_NL bg_BG cs_CZ da_DK el_GR fi_FI hu_HU id_ID nb_NO pl_PL sk_SK sv_SE tr_TR uk_UA"
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

set "TARGET_LOCALES=%TARGET_LOCALES_DEFAULT%"
if /I not "%AUTO_MODE%"=="Y" set /p "TARGET_LOCALES=Target locales to generate, space-separated [%TARGET_LOCALES%]: "
echo.

echo   Source locale   : %SOURCE_LOCALE%
echo   Texts folders    : %TEXTS_DIRS%
echo   Protected words  : %PROTECTED_WORDS%
echo   Target locales   : %TARGET_LOCALES%
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
