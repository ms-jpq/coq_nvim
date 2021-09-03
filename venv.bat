@echo off
cd /D "%~dp0"
%*
exit -b %ERRORLEVEL%
