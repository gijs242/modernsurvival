using UnrealBuildTool;

public class ModernSurvival : ModuleRules
{
	public ModernSurvival(ReadOnlyTargetRules Target) : base(Target)
	{
		PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;

		PublicDependencyModuleNames.AddRange(new string[]
		{
			"Core", "CoreUObject", "Engine", "InputCore", "EnhancedInput",
			"AIModule", "NavigationSystem", "GameplayTasks",
			"StateTreeModule", "GameplayStateTreeModule",
			"UMG", "Slate", "SlateCore",
			"Niagara", "DeveloperSettings", "PhysicsCore"
		});

		// Engine-free gameplay rules live in Public/Core/MSRules.h so they can be unit tested
		// outside Unreal (see Tests/Rules).
	}
}
