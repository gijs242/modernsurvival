#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "MSSpawnPoint.generated.h"

class UBillboardComponent;
class UArrowComponent;

UENUM(BlueprintType)
enum class EMSSpawnKind : uint8
{
	Ground,   // soldiers, rushers, dogs, juggernauts
	Air       // helicopters (place high, at the edge of the map)
};

/**
 * Enemy spawn location. The wave manager only uses a point when it is outside the player's view
 * cone (plus margin) or blocked from view, and between the min/max distances in DT_GameRules.
 * Place them behind buildings, round corners, at map edges.
 */
UCLASS()
class MODERNSURVIVAL_API AMSSpawnPoint : public AActor
{
	GENERATED_BODY()

public:
	AMSSpawnPoint();

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Spawn") EMSSpawnKind Kind = EMSSpawnKind::Ground;
	/** Only used from this wave on (lets you open up more of the map later). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Spawn") int32 MinWave = 1;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Spawn") bool bEnabled = true;

	double LastUsedTime = -1000.0;

#if WITH_EDITORONLY_DATA
	UPROPERTY() TObjectPtr<UBillboardComponent> Sprite;
	UPROPERTY() TObjectPtr<UArrowComponent> Arrow;
#endif
};
