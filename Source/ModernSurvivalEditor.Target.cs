using UnrealBuildTool;

public class ModernSurvivalEditorTarget : TargetRules
{
	public ModernSurvivalEditorTarget(TargetInfo Target) : base(Target)
	{
		Type = TargetType.Editor;
		DefaultBuildSettings = BuildSettingsVersion.Latest;
		IncludeOrderVersion = EngineIncludeOrderVersion.Latest;
		ExtraModuleNames.AddRange(new string[] { "ModernSurvival", "ModernSurvivalEditor" });
	}
}
