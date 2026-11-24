#pragma once

#include "CoreMinimal.h"
#include "GameFramework/GameModeBase.h"
#include "MSMenuGameMode.generated.h"

/** Main menu level: no pawn, the controller shows the main menu widget. */
UCLASS()
class MODERNSURVIVAL_API AMSMenuGameMode : public AGameModeBase
{
	GENERATED_BODY()

public:
	AMSMenuGameMode();
	virtual void StartPlay() override;
};
