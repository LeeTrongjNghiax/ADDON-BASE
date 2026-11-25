@echo off
REM =====================================================================
REM  dev.bat
REM
REM  Wrapper around build.bat: copies bp/rp to profile #1 (dev),
REM  renames the namespace, and runs with JSON obfuscation OFF (/OBF:0).
REM  No prompts at all.
REM
REM  Must sit in the SAME FOLDER as build.bat.
REM
REM  The numbers match the profile lists in build.bat (1=dev, 2=live,
REM  3=output by default). You can also pass ALL, or a comma list like
REM  /BP:1,3. Change /OBF: to 1 (obfuscate JSON) or 0 (keep it readable).
REM =====================================================================
call "%~dp0build.bat" /BP:1 /RP:1 /NS:rl_yn /OBF:0
pause
