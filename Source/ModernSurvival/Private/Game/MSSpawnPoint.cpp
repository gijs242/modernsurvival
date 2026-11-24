#include "Game/MSSpawnPoint.h"

#include "Components/ArrowComponent.h"
#include "Components/BillboardComponent.h"

AMSSpawnPoint::AMSSpawnPoint()
{
	SetRootComponent(CreateDefaultSubobject<USceneComponent>(TEXT("Root")));
#if WITH_EDITORONLY_DATA
	Sprite = CreateEditorOnlyDefaultSubobject<UBillboardComponent>(TEXT("Sprite"));
	if (Sprite)
	{
		Sprite->SetupAttachment(GetRootComponent());
		Sprite->SetRelativeLocation(FVector(0, 0, 90));
	}
	Arrow = CreateEditorOnlyDefaultSubobject<UArrowComponent>(TEXT("Arrow"));
	if (Arrow)
	{
		Arrow->SetupAttachment(GetRootComponent());
		Arrow->ArrowColor = FColor(255, 60, 40);
	}
#endif
	SetActorHiddenInGame(true);
}
