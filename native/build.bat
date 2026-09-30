@echo off
REM Use the same pinned version and feature tags as build_all.ps1.
pushd "%~dp0.."
call dart run tools/prebuild.dart --force
set "SBOX_BUILD_RESULT=%ERRORLEVEL%"
popd
exit /b %SBOX_BUILD_RESULT%
