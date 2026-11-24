#include "Game/MSMenuGameMode.h"

#include "Look/MSLookManager.h"
#include "Player/MSPlayerController.h"
#include "Engine/World.h"
#include "EngineUtils.h"
#include "GameFramework/SpectatorPawn.h"

AMSMenuGameMode::AMSMenuGameMode()
{
	DefaultPawnClass = ASpectatorPawn::StaticClass();
	PlayerControllerClass = AMSPlayerController::StaticClass();
	HUDClass = nullptr;
}

void AMSMenuGameMode::StartPlay()
{
	Super::StartPlay();
	if (!TActorIterator<AMSLookManager>(GetWorld()))
	{
		FActorSpawnParameters Params;
		Params.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
		GetWorld()->SpawnActor<AMSLookManager>(AMSLookManager::StaticClass(), FTransform::Identity, Params);
	}
}
