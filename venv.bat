@echo off
cd /D "%~dp0"
set path=%cd%\.vars\runtime\Scripts;%PATH%
%*
@echo on
