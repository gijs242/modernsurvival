@echo off
rem Compile, then run every ModernSurvival automation test headless.
rem Usage: set UE_ROOT=C:\Program Files\Epic Games\UE_5.8  then  Scripts\run_tests.bat
set PROJECT=%~dp0..\ModernSurvival.uproject
if "%UE_ROOT%"=="" set UE_ROOT=C:\Program Files\Epic Games\UE_5.8
call "%UE_ROOT%\Engine\Build\BatchFiles\Build.bat" ModernSurvivalEditor Win64 Development -Project="%PROJECT%" -WaitMutex || exit /b 1
"%UE_ROOT%\Engine\Binaries\Win64\UnrealEditor-Cmd.exe" "%PROJECT%" -ExecCmds="Automation RunTests ModernSurvival; Quit" -unattended -nullrhi -nosplash -log -ReportExportPath="%~dp0..\Saved\TestReport"
