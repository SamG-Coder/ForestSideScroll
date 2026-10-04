@echo off
cd /d "%~dp0"
start "" http://127.0.0.1:4327
node scripts/serve.mjs
pause
