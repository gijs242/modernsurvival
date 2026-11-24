#pragma once

#include "CoreMinimal.h"
#include "Kismet/BlueprintFunctionLibrary.h"
#include "MSEditorBuildLibrary.generated.h"

/**
 * Editor-only builders, callable from Python (unreal.MSEditorBuildLibrary.*) and the console.
 */
UCLASS()
class MODERNSURVIVALEDITOR_API UMSEditorBuildLibrary : public UBlueprintFunctionLibrary
{
	GENERATED_BODY()

public:
	/**
	 * Creates (or rebuilds) the enemy StateTree asset from the MS Activity / MS Brain Query nodes,
	 * compiles and saves it. Default path matches Project Settings > Modern Survival > EnemyStateTree.
	 * Console: MS.BuildStateTree
	 */
	UFUNCTION(BlueprintCallable, Category = "Modern Survival|Editor")
	static bool BuildEnemyStateTree(const FString& PackagePath, FString& OutLog);
};
