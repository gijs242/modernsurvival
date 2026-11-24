#!/usr/bin/env bash
# Compile, then run every ModernSurvival automation test headless.
# Usage: UE_ROOT=/path/to/UE_5.8 Scripts/run_tests.sh
set -euo pipefail
PROJECT="$(cd "$(dirname "$0")/.." && pwd)/ModernSurvival.uproject"
UE_ROOT="${UE_ROOT:?set UE_ROOT to your Unreal Engine 5.8 folder}"
"$UE_ROOT/Engine/Build/BatchFiles/Linux/Build.sh" ModernSurvivalEditor Linux Development -Project="$PROJECT" -WaitMutex
"$UE_ROOT/Engine/Binaries/Linux/UnrealEditor-Cmd" "$PROJECT" -ExecCmds="Automation RunTests ModernSurvival; Quit" \
  -unattended -nullrhi -nosplash -log -ReportExportPath="$(dirname "$PROJECT")/Saved/TestReport"
