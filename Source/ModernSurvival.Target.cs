using UnrealBuildTool;

public class ModernSurvivalTarget : TargetRules
{
	public ModernSurvivalTarget(TargetInfo Target) : base(Target)
	{
		Type = TargetType.Game;
		DefaultBuildSettings = BuildSettingsVersion.Latest;
		IncludeOrderVersion = EngineIncludeOrderVersion.Latest;
		ExtraModuleNames.Add("ModernSurvival");
	}
}
