@echo off
cd /d "%~dp0"
echo Starting MkDocs server...
echo http://127.0.0.1:8000/JinNate/
mkdocs serve
pause
