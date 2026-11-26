@echo off
cd /d "%~dp0"
set ASPNETCORE_ENVIRONMENT=Development
dotnet restore
if errorlevel 1 exit /b 1
dotnet build --no-restore
if errorlevel 1 exit /b 1
dotnet run --no-build --urls http://localhost:5080
