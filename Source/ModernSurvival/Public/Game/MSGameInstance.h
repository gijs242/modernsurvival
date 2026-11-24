#pragma once

#include "CoreMinimal.h"
#include "Engine/GameInstance.h"
#include "GameFramework/SaveGame.h"
#include "MSGameInstance.generated.h"

UCLASS()
class MODERNSURVIVAL_API UMSSaveGame : public USaveGame
{
	GENERATED_BODY()

public:
	/** Best wave reached per map package name. */
	UPROPERTY() TMap<FString, int32> BestWave;
	UPROPERTY() float LookSensitivity = 1.f;
};

UCLASS()
class MODERNSURVIVAL_API UMSGameInstance : public UGameInstance
{
	GENERATED_BODY()

public:
	virtual void Init() override;

	UFUNCTION(BlueprintPure, Category = "Save") int32 GetBestWave(const FString& Map) const;
	/** Returns true if this is a new record. */
	UFUNCTION(BlueprintCallable, Category = "Save") bool SubmitWave(const FString& Map, int32 Wave);

private:
	void Save();

	UPROPERTY(Transient) TObjectPtr<UMSSaveGame> SaveData;
};
