@echo off
REM =====================================================================
REM  deploy-test.bat
REM
REM  Wrapper around copy-parent-folder.bat: always copies bp/rp to their
REM  "test" profile (profile #2 in the default config), with every other
REM  setting left at its default -- no prompts at all.
REM
REM  Must sit in the SAME FOLDER as copy-parent-folder.bat.
REM
REM  To make a wrapper for a different profile, just change the numbers
REM  below -- they match the numbered list copy-parent-folder.bat prints
REM  for each source (1=dev, 2=test, 3=output by default). You can also
REM  pass ALL, or a comma list like /BP:1,3.
REM =====================================================================
call "%~dp0build.bat" /BP:1 /RP:1 /NS:rl_yn
pause
