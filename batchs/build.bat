@echo off
setlocal enabledelayedexpansion

REM =====================================================================
REM  Command-line overrides (for wrapper .bat files):
REM    copy-parent-folder.bat [/BP:selection] [/RP:selection] [/NS:namespace]
REM
REM  selection = comma-separated profile numbers, or ALL, e.g. /BP:1,3
REM  Passing any of these switches runs the WHOLE script in one-click mode
REM  (every other setting uses its default, no prompts) and uses the
REM  given value instead of the default for that setting.
REM  A source with no /BP:/RP: switch still defaults to profile 1.
REM  With no /NS: switch, the namespace default (your_namespace, i.e. no
REM  actual rename) is used.
REM
REM  Example wrapper:
REM    call copy-parent-folder.bat /BP:2 /RP:2 /NS:acme_addon
REM =====================================================================
set "CLI_BP_SELECTION="
set "CLI_RP_SELECTION="
set "CLI_NAMESPACE="
for %%A in (%*) do (
    set "ARG=%%~A"
    if /I "!ARG:~0,4!"=="/BP:" set "CLI_BP_SELECTION=!ARG:~4!"
    if /I "!ARG:~0,4!"=="/RP:" set "CLI_RP_SELECTION=!ARG:~4!"
    if /I "!ARG:~0,4!"=="/NS:" set "CLI_NAMESPACE=!ARG:~4!"
)

REM =====================================================================
REM  copy-parent-folder.bat
REM
REM  This script sits at the SAME LEVEL as FolderA and FolderB. Inside
REM  each of those, it copies ONE CHILD FOLDER (that you name) to a set
REM  of named DESTINATION PROFILES that you configure below. Each source
REM  (bp / rp) has its OWN independent list of profiles -- e.g. "dev",
REM  "test", "output" -- each pointing at a different parent folder.
REM
REM  Before anything is copied to any destination, the script:
REM    1) Copies bp/rp into a TEMP STAGING folder (excludes already applied).
REM    2) Runs rename-namespace.ps1 against the staged copy, which:
REM         - replaces every occurrence of "your_namespace" INSIDE file
REM           contents with the namespace you provide,
REM         - renames any FILE whose name contains "your_namespace",
REM         - renames any FOLDER whose name contains "your_namespace".
REM    3) Runs scripts\obfuscate-json.js against the staged copy, which
REM       strips whitespace from every .json file and re-encodes every
REM       key/string as \uXXXX escapes (set ENABLE_JSON_OBFUSCATION=0
REM       above to skip this).
REM    4) Copies FROM the staged, renamed, obfuscated folders to each
REM       selected destination profile (same as before).
REM    5) Deletes the staging folder when done.
REM
REM  This means your real bp/rp source folders are never modified --
REM  only the temporary staged copy is renamed, and that's what gets
REM  distributed to your destinations.
REM
REM  At run time you pick which profile(s) each source should be copied
REM  to (one, several, or ALL), and the namespace text to substitute.
REM  One-click mode always uses profile #1 for both sources and the
REM  default namespace (no rename) unless overridden via /BP:, /RP:, /NS:.
REM
REM  Example layout:
REM    project\
REM      copy-parent-folder.bat   <- this file lives here
REM      rename-namespace.ps1     <- helper script, must sit next to this file
REM      FolderA\
REM        childX\                <- this is what actually gets copied
REM      FolderB\
REM        childY\                <- this is what actually gets copied
REM
REM  Usage:
REM    Double-click this file. First it asks whether to run in ONE-CLICK
REM    mode (every setting uses its default below, profile #1 is used
REM    for both sources, any existing destination is deleted
REM    automatically without asking) or MANUAL mode (prompts for
REM    everything, press Enter to keep the default shown in [ ]).
REM    Manual mode also asks before deleting anything.
REM
REM  Adding/editing profiles:
REM    Each profile needs three lines: a NAME (shown in the picker), a
REM    PARENT folder (where the copy lands), and an optional FOLDERNAME
REM    (the name the copied folder gets inside that parent -- leave it
REM    blank, or type SAME at the prompt, to just reuse the source
REM    folder's own name, e.g. "bp" / "rp").
REM
REM    To add a 4th profile to a source, add its PROFILE_4_* lines and
REM    bump that source's PROFILE_COUNT.
REM =====================================================================

REM ======================= DEFAULTS =======================
REM Excludes and the source-delete flag are GLOBAL -- they apply the same
REM way to both source folders and every destination.
set "EXCLUDE_DIRS=.git .github .husky  batchs douments node_modules sources .vscode"
set "EXCLUDE_FILES=.gitignore .mcignore .prettierignore .prettierrc build.js commitlint.config.cjs eslint.config.ts package-lock.json package.json tsconfig.json *.zip *.md *.mcpack"
set "DELETE_SOURCE_AFTER_COPY=0"

REM Set to 0 to skip the JSON minify+obfuscate step below (e.g. while
REM debugging a destination copy and you want to read the JSON as-is).
set "ENABLE_JSON_OBFUSCATION=1"

REM Names of FolderA and FolderB (siblings of this script), and the name
REM of the CHILD folder inside each one that should actually be copied.
set "FOLDER_A_NAME_DEFAULT=..\sources\behavior_packs"
set "CHILD_A_NAME_DEFAULT=bp"
set "FOLDER_B_NAME_DEFAULT=..\sources\resource_packs"
set "CHILD_B_NAME_DEFAULT=rp"

REM Project name -- collected via prompt below. Reserved for future use.
set "PROJECT_NAME_DEFAULT=My Addon Project Source"

REM Namespace placeholder used throughout your source files/folders/file
REM names (this is what gets searched for -- normally leave this as-is).
set "PLACEHOLDER_NAMESPACE=your_namespace"

REM What to replace it with if you don't type anything at the prompt (and
REM in one-click mode, if /NS: isn't passed). Set this to your actual
REM go-to namespace so pressing Enter does something useful instead of
REM leaving "your_namespace" unchanged -- e.g. set "NAMESPACE_DEFAULT=acme_addon"
set "NAMESPACE_DEFAULT=acme_addon"

REM ---------------------------------------------------------------
REM  Destination profiles for SOURCE 1 (the child folder inside
REM  FolderA, e.g. "bp"). Add more by adding BP_PROFILE_4_* lines
REM  and raising BP_PROFILE_COUNT.
REM ---------------------------------------------------------------
set "BP_PROFILE_COUNT=3"

set "BP_PROFILE_1_NAME=dev"
set "BP_PROFILE_1_PARENT=C:\Users\Admin\AppData\Roaming\Minecraft Bedrock\Users\Shared\games\com.mojang\development_behavior_packs"
set "BP_PROFILE_1_FOLDERNAME=%PROJECT_NAME_DEFAULT% BP"

set "BP_PROFILE_2_NAME=live"
set "BP_PROFILE_2_PARENT=C:\Users\Admin\AppData\Roaming\Minecraft Bedrock\Users\Shared\games\com.mojang\behavior_packs"
set "BP_PROFILE_2_FOLDERNAME=%PROJECT_NAME_DEFAULT% BP"

set "BP_PROFILE_3_NAME=output"
set "BP_PROFILE_3_PARENT=C:\%PROJECT_NAME_DEFAULT%\Content\behavior_packs"
set "BP_PROFILE_3_FOLDERNAME=%CLI_NAMESPACE%_b"

REM ---------------------------------------------------------------
REM  Destination profiles for SOURCE 2 (the child folder inside
REM  FolderB, e.g. "rp"). Add more by adding RP_PROFILE_4_* lines
REM  and raising RP_PROFILE_COUNT.
REM ---------------------------------------------------------------
set "RP_PROFILE_COUNT=3"

set "RP_PROFILE_1_NAME=dev"
set "RP_PROFILE_1_PARENT=C:\Users\Admin\AppData\Roaming\Minecraft Bedrock\Users\Shared\games\com.mojang\development_resource_packs"
set "RP_PROFILE_1_FOLDERNAME=%PROJECT_NAME_DEFAULT% RP"

set "RP_PROFILE_2_NAME=live"
set "RP_PROFILE_2_PARENT=C:\Users\Admin\AppData\Roaming\Minecraft Bedrock\Users\Shared\games\com.mojang\resource_packs"
set "RP_PROFILE_2_FOLDERNAME=%PROJECT_NAME_DEFAULT% RP"

set "RP_PROFILE_3_NAME=output"
set "RP_PROFILE_3_PARENT=C:\%PROJECT_NAME_DEFAULT%\Content\resource_packs"
set "RP_PROFILE_3_FOLDERNAME=%CLI_NAMESPACE%_r"
REM ==========================================================

echo ============================================================
echo  Copy Configuration
echo ============================================================
echo.

if not "%CLI_BP_SELECTION%%CLI_RP_SELECTION%%CLI_NAMESPACE%"=="" (
    set "AUTO_MODE=Y"
    echo Profile/namespace switch^(es^) passed on the command line --
    echo running in ONE-CLICK mode automatically.
) else (
    set "AUTO_MODE=N"
    set /p "AUTO_MODE=Run with ALL default settings, profile 1 for both sources, no further prompts, and auto-delete existing destinations? (Y/N) [N]: "
)

if /I "%AUTO_MODE%"=="Y" (
    echo.
    echo Running in ONE-CLICK mode: every setting below uses its default,
    echo profile 1 is used for both bp and rp ^(unless overridden by /BP:
    echo or /RP: on the command line^), the namespace is left unchanged
    echo ^(unless overridden by /NS: on the command line^), and any
    echo existing destination folder will be deleted automatically
    echo without asking.
) else (
    echo.
    echo Running in MANUAL mode: press Enter at any prompt to keep the
    echo default shown in [ ], or type a new value.
)
echo.

if /I not "%AUTO_MODE%"=="Y" set /p "EXCLUDE_DIRS=Folders to exclude, space-separated [%EXCLUDE_DIRS%]: "
if /I not "%AUTO_MODE%"=="Y" set /p "EXCLUDE_FILES=Files to exclude, space-separated [%EXCLUDE_FILES%]: "
echo.

set "PROJECT_NAME=%PROJECT_NAME_DEFAULT%"
if /I not "%AUTO_MODE%"=="Y" set /p "PROJECT_NAME=Project name [%PROJECT_NAME%]: "
echo.

set "NAMESPACE=%NAMESPACE_DEFAULT%"
if not "%CLI_NAMESPACE%"=="" set "NAMESPACE=%CLI_NAMESPACE%"
if /I not "%AUTO_MODE%"=="Y" if "%CLI_NAMESPACE%"=="" set /p "NAMESPACE=Namespace to replace '%PLACEHOLDER_NAMESPACE%' with [%NAMESPACE%]: "
echo   Using namespace: %NAMESPACE%
echo.

set "FOLDER_A_NAME=%FOLDER_A_NAME_DEFAULT%"
if /I not "%AUTO_MODE%"=="Y" set /p "FOLDER_A_NAME=Folder A name [%FOLDER_A_NAME%]: "
set "CHILD_A_NAME=%CHILD_A_NAME_DEFAULT%"
if /I not "%AUTO_MODE%"=="Y" set /p "CHILD_A_NAME=  Child folder inside Folder A to copy [%CHILD_A_NAME%]: "
echo.
set "FOLDER_B_NAME=%FOLDER_B_NAME_DEFAULT%"
if /I not "%AUTO_MODE%"=="Y" set /p "FOLDER_B_NAME=Folder B name [%FOLDER_B_NAME%]: "
set "CHILD_B_NAME=%CHILD_B_NAME_DEFAULT%"
if /I not "%AUTO_MODE%"=="Y" set /p "CHILD_B_NAME=  Child folder inside Folder B to copy [%CHILD_B_NAME%]: "
echo.

REM BASE_DIR = this script's own folder (FolderA and FolderB are siblings
REM of it, in the same directory).
for %%I in ("%~dp0") do set "BASE_DIR=%%~fI"
if "%BASE_DIR:~-1%"=="\" set "BASE_DIR=%BASE_DIR:~0,-1%"

set "SOURCE1_PATH=%BASE_DIR%\%FOLDER_A_NAME%\%CHILD_A_NAME%"
set "SOURCE1_NAME=%CHILD_A_NAME%"
set "SOURCE2_PATH=%BASE_DIR%\%FOLDER_B_NAME%\%CHILD_B_NAME%"
set "SOURCE2_NAME=%CHILD_B_NAME%"

if not exist "%SOURCE1_PATH%" (
    echo Child folder for Folder A does not exist: %SOURCE1_PATH%
    pause
    exit /b 1
)
if not exist "%SOURCE2_PATH%" (
    echo Child folder for Folder B does not exist: %SOURCE2_PATH%
    pause
    exit /b 1
)

REM =====================================================================
REM  STAGING + NAMESPACE RENAME
REM  Copy the real sources into a temp staging folder, then run the
REM  namespace rename/replace against the STAGED copy only. Everything
REM  downstream copies from the staged, renamed folders -- your real
REM  source folders are never touched by the rename step.
REM =====================================================================
set "STAGE_ROOT=%TEMP%\cpf_stage_%RANDOM%%RANDOM%"
set "COPY_SOURCE1_PATH=%STAGE_ROOT%\%SOURCE1_NAME%"
set "COPY_SOURCE2_PATH=%STAGE_ROOT%\%SOURCE2_NAME%"

echo ============================================================
echo  Staging copy + namespace replace
echo  "%PLACEHOLDER_NAMESPACE%"  -^>  "%NAMESPACE%"
echo ============================================================
mkdir "%STAGE_ROOT%" >nul 2>nul

echo Copying source A to staging...
robocopy "%SOURCE1_PATH%" "%COPY_SOURCE1_PATH%" /E /XD %EXCLUDE_DIRS% /XF %EXCLUDE_FILES% /R:2 /W:2 /NFL /NDL
if !ERRORLEVEL! GEQ 8 (
    echo Staging copy of Folder A failed with error code !ERRORLEVEL!.
    pause
    exit /b 1
)

echo Copying source B to staging...
robocopy "%SOURCE2_PATH%" "%COPY_SOURCE2_PATH%" /E /XD %EXCLUDE_DIRS% /XF %EXCLUDE_FILES% /R:2 /W:2 /NFL /NDL
if !ERRORLEVEL! GEQ 8 (
    echo Staging copy of Folder B failed with error code !ERRORLEVEL!.
    pause
    exit /b 1
)

echo.
echo Applying namespace rename/replace in staged Folder A copy...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0rename-namespace.ps1" -StagePath "%COPY_SOURCE1_PATH%" -OldNamespace "%PLACEHOLDER_NAMESPACE%" -NewNamespace "%NAMESPACE%"
if errorlevel 1 (
    echo Namespace replace step failed for Folder A.
    pause
    exit /b 1
)

echo Applying namespace rename/replace in staged Folder B copy...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0rename-namespace.ps1" -StagePath "%COPY_SOURCE2_PATH%" -OldNamespace "%PLACEHOLDER_NAMESPACE%" -NewNamespace "%NAMESPACE%"
if errorlevel 1 (
    echo Namespace replace step failed for Folder B.
    pause
    exit /b 1
)
echo.

REM =====================================================================
REM  JSON MINIFY + OBFUSCATE
REM  Runs against the STAGED copies only (never the real source folders),
REM  after the namespace rename and before anything is copied out to a
REM  destination profile below. Every .json file's whitespace is
REM  stripped and every key/string value is re-encoded as \uXXXX escapes
REM  -- valid, functionally identical JSON that's just unreadable to a
REM  human glancing at the shipped files. See scripts\obfuscate-json.js.
REM =====================================================================
if "%ENABLE_JSON_OBFUSCATION%"=="1" (
    echo ============================================================
    echo  Obfuscating JSON in staged copies
    echo ============================================================
    node "%~dp0..\scripts\obfuscate-json.js" "%COPY_SOURCE1_PATH%" "%COPY_SOURCE2_PATH%"
    if errorlevel 1 (
        echo JSON obfuscation step failed.
        pause
        exit /b 1
    )
    echo.
)

call :process_source 1 "%COPY_SOURCE1_PATH%" "%SOURCE1_NAME%" BP
if errorlevel 1 (
    pause
    exit /b 1
)

call :process_source 2 "%COPY_SOURCE2_PATH%" "%SOURCE2_NAME%" RP
if errorlevel 1 (
    pause
    exit /b 1
)

echo ============================================================
echo All sources and selected profiles processed.
echo ============================================================

if "%DELETE_SOURCE_AFTER_COPY%"=="1" (
    echo.
    echo Deleting original source folders...
    echo   %SOURCE1_PATH%
    rmdir /s /q "%SOURCE1_PATH%"
    echo   %SOURCE2_PATH%
    rmdir /s /q "%SOURCE2_PATH%"
    echo Original sources deleted.
)

echo.
echo Cleaning up staging folder...
rmdir /s /q "%STAGE_ROOT%" 2>nul

echo.
echo ------------------------------------------
echo Done. You can close this window now.
echo ------------------------------------------
pause
exit /b 0

REM =====================================================================
REM  :process_source <source_index> <source_path> <source_name> <profile_prefix>
REM  <source_path> here is the STAGED (already namespace-renamed) copy.
REM  <profile_prefix> is BP or RP and selects which profile list
REM  (BP_PROFILE_* or RP_PROFILE_*) belongs to this source. Lists the
REM  profiles, asks which one(s) to use, then loops over the selected
REM  ones via :do_profile_target.
REM =====================================================================
:process_source
setlocal enabledelayedexpansion
set "S=%~1"
set "SRC_PATH=%~2"
set "SRC_NAME=%~3"
set "PREFIX=%~4"

call set "PCOUNT=%%!PREFIX!_PROFILE_COUNT%%"

echo ============================================================
echo  Source !S!: !SRC_PATH!
echo  Profile list: !PREFIX!
echo ============================================================
echo   Available profiles:
for /L %%P in (1,1,!PCOUNT!) do (
    set "IDX=%%P"
    call set "PNAME=%%!PREFIX!_PROFILE_!IDX!_NAME%%"
    echo     %%P^) !PNAME!
)
echo.

call set "CLI_SEL=%%CLI_!PREFIX!_SELECTION%%"

set "SELECTION=1"
if not "!CLI_SEL!"=="" (
    set "SELECTION=!CLI_SEL!"
    echo   Using command-line profile selection: !SELECTION!
) else if /I "!AUTO_MODE!"=="Y" (
    echo   Auto mode: defaulting to profile 1 only.
) else (
    set /p "SELECTION=Select profile(s) to copy to - comma-separated numbers, or ALL [1]: "
)
if "!SELECTION!"=="" set "SELECTION=1"

if /I "!SELECTION!"=="ALL" (
    set "SELECTION="
    for /L %%P in (1,1,!PCOUNT!) do set "SELECTION=!SELECTION!,%%P"
    set "SELECTION=!SELECTION:~1!"
)
set "SELECTION=!SELECTION:,= !"
echo   Selected profile(s): !SELECTION!
echo.

for %%N in (!SELECTION!) do (
    call :do_profile_target !S! %%N "!SRC_PATH!" "!SRC_NAME!" !PREFIX!
    if errorlevel 1 (
        echo.
        echo Stopped due to an error on source !S!, profile %%N.
        endlocal
        exit /b 1
    )
)

endlocal
exit /b 0

REM =====================================================================
REM  :do_profile_target <source_index> <profile_index> <source_path> <source_name> <profile_prefix>
REM  Looks up the given profile's NAME/PARENT/FOLDERNAME, prompts to
REM  confirm/override (manual mode only), then copies the given source
REM  into it. Returns errorlevel 1 only on a real failure -- skipping
REM  (blank parent, or "don't delete") is not treated as an error, so
REM  the remaining selected profiles still run.
REM =====================================================================
:do_profile_target
setlocal enabledelayedexpansion
set "S=%~1"
set "N=%~2"
set "SRC_PATH=%~3"
set "SRC_NAME=%~4"
set "PREFIX=%~5"

call set "PNAME=%%!PREFIX!_PROFILE_!N!_NAME%%"
call set "PARENT_DEFAULT=%%!PREFIX!_PROFILE_!N!_PARENT%%"
call set "NAME_DEFAULT=%%!PREFIX!_PROFILE_!N!_FOLDERNAME%%"
if "!NAME_DEFAULT!"=="" set "NAME_DEFAULT=!SRC_NAME!"

if "!PNAME!"=="" (
    echo --- Profile #!N! for source !S! is not defined, skipping ---
    echo.
    endlocal
    exit /b 0
)

echo --- Profile "!PNAME!" for source !S! ^(!SRC_NAME!^) ---
set "PARENT_INPUT=!PARENT_DEFAULT!"
if /I not "!AUTO_MODE!"=="Y" set /p "PARENT_INPUT=  Parent folder [!PARENT_INPUT!]: "
set "NAME_INPUT=!NAME_DEFAULT!"
if /I not "!AUTO_MODE!"=="Y" set /p "NAME_INPUT=  Copied folder name, or type SAME to use the source's name [!NAME_INPUT!]: "
if /I "!AUTO_MODE!"=="Y" (
    echo   Parent folder: !PARENT_INPUT!
    echo   Copied folder name: !NAME_INPUT!
)
echo.

if /I "!NAME_INPUT!"=="SAME" set "NAME_INPUT=!SRC_NAME!"

if "!PARENT_INPUT!"=="" (
    echo   Skipped ^(no parent folder configured for this profile^).
    echo.
    endlocal
    exit /b 0
)

set "FOLDER_NAME=!NAME_INPUT!"
set "DEST=!PARENT_INPUT!\!FOLDER_NAME!"
if "!DEST:~-1!"=="\" set "DEST=!DEST:~0,-1!"

if exist "!DEST!" (
    echo   Destination already exists:
    echo     !DEST!
    if /I "!AUTO_MODE!"=="Y" (
        echo   Auto mode: deleting existing folder without asking.
        set "CONFIRM=Y"
    ) else (
        set "CONFIRM="
        set /p "CONFIRM=  Delete this folder and its contents before copying? (Y/N): "
    )
    if /I not "!CONFIRM!"=="Y" (
        echo   Skipped ^(not deleted, not copied^).
        echo.
        endlocal
        exit /b 0
    )
    echo   Deleting existing folder: !DEST!
    rmdir /s /q "!DEST!"
    if exist "!DEST!" (
        echo   Failed to delete existing destination. It may be open in
        echo   another program, or you may not have permission.
        endlocal
        exit /b 1
    )
    echo   Deleted.
)

echo   Copying to: !DEST!
robocopy "!SRC_PATH!" "!DEST!" /E /XD !EXCLUDE_DIRS! /XF !EXCLUDE_FILES! /R:2 /W:2 /NFL /NDL

REM robocopy exit codes 0-7 are all "success" (7 = files copied, some
REM mismatches skipped due to excludes -- that's expected here).
if !ERRORLEVEL! GEQ 8 (
    echo   Copy FAILED with error code !ERRORLEVEL!.
    endlocal
    exit /b 1
)

echo   Done: !DEST!
echo.
endlocal
exit /b 0
