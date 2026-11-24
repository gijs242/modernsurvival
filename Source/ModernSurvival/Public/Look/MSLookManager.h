#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "MSLookManager.generated.h"

class UPostProcessComponent;

/**
 * The game's colour grade: desaturated, high contrast, light film grain, vignette, plus dynamic
 * low-health desaturation and an ADS vignette. Every number is in DT_LookFeel. Spawned by the game
 * mode; an unbound post-process that blends on top of anything in the level.
 */
UCLASS()
class MODERNSURVIVAL_API AMSLookManager : public AActor
{
	GENERATED_BODY()

public:
	AMSLookManager();
	virtual void Tick(float DeltaSeconds) override;
	void ApplyBaseGrade();

	/** DT_LookFeel row for this map ("Default", "Abandoned", ...). Place one in a level to pick its grade. */
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Look") FName LookRow = TEXT("Default");

protected:
	virtual void BeginPlay() override;

	UPROPERTY(VisibleAnywhere, Category = "Look") TObjectPtr<UPostProcessComponent> PostProcess;
	float LowHealthBlend = 0.f;
};
