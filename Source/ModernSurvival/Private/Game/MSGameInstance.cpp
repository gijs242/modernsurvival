#include "Game/MSGameInstance.h"

#include "Kismet/GameplayStatics.h"

static const TCHAR* GSaveSlot = TEXT("ModernSurvival");

void UMSGameInstance::Init()
{
	Super::Init();
	if (UGameplayStatics::DoesSaveGameExist(GSaveSlot, 0))
	{
		SaveData = Cast<UMSSaveGame>(UGameplayStatics::LoadGameFromSlot(GSaveSlot, 0));
	}
	if (!SaveData)
	{
		SaveData = Cast<UMSSaveGame>(UGameplayStatics::CreateSaveGameObject(UMSSaveGame::StaticClass()));
	}
}

int32 UMSGameInstance::GetBestWave(const FString& Map) const
{
	const int32* Found = SaveData ? SaveData->BestWave.Find(Map) : nullptr;
	return Found ? *Found : 0;
}

bool UMSGameInstance::SubmitWave(const FString& Map, int32 Wave)
{
	if (!SaveData)
	{
		return false;
	}
	int32& Best = SaveData->BestWave.FindOrAdd(Map);
	if (Wave <= Best)
	{
		return false;
	}
	Best = Wave;
	Save();
	return true;
}

void UMSGameInstance::Save()
{
	if (SaveData)
	{
		UGameplayStatics::SaveGameToSlot(SaveData, GSaveSlot, 0);
	}
}
