using UnrealBuildTool;

public class ModernSurvivalEditor : ModuleRules
{
	public ModernSurvivalEditor(ReadOnlyTargetRules Target) : base(Target)
	{
		PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;

		PublicDependencyModuleNames.AddRange(new string[] { "Core", "CoreUObject", "Engine" });
		PrivateDependencyModuleNames.AddRange(new string[]
		{
			"ModernSurvival", "UnrealEd", "AssetTools", "AssetRegistry",
			"StateTreeModule", "StateTreeEditorModule", "GameplayStateTreeModule",
			"AIModule", "GameplayTags"
		});
	}
}
