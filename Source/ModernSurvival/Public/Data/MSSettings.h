#pragma once

#include "CoreMinimal.h"
#include "Engine/DeveloperSettings.h"
#include "MSSettings.generated.h"

class UDataTable;
class UCurveTable;
class UStateTree;
class UEnvQuery;

USTRUCT(BlueprintType)
struct FMSPlayableMap
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Map") FString Map;
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Map") FText DisplayName;
};

/** Project Settings > Game > Modern Survival. Points the game at its tuning tables. */
UCLASS(Config = Game, DefaultConfig, meta = (DisplayName = "Modern Survival"))
class MODERNSURVIVAL_API UMSSettings : public UDeveloperSettings
{
	GENERATED_BODY()

public:
	UMSSettings();

	static const UMSSettings* Get() { return GetDefault<UMSSettings>(); }

	UPROPERTY(Config, EditAnywhere, Category = "Tables") TSoftObjectPtr<UDataTable> PlayerFeelTable;
	UPROPERTY(Config, EditAnywhere, Category = "Tables") TSoftObjectPtr<UDataTable> WeaponTable;
	UPROPERTY(Config, EditAnywhere, Category = "Tables") TSoftObjectPtr<UDataTable> EnemyTable;
	UPROPERTY(Config, EditAnywhere, Category = "Tables") TSoftObjectPtr<UDataTable> WaveTable;
	UPROPERTY(Config, EditAnywhere, Category = "Tables") TSoftObjectPtr<UDataTable> GameRulesTable;
	UPROPERTY(Config, EditAnywhere, Category = "Tables") TSoftObjectPtr<UDataTable> ShopTable;
	UPROPERTY(Config, EditAnywhere, Category = "Tables") TSoftObjectPtr<UDataTable> EquipmentTable;
	UPROPERTY(Config, EditAnywhere, Category = "Tables") TSoftObjectPtr<UDataTable> LookTable;
	UPROPERTY(Config, EditAnywhere, Category = "Tables") TSoftObjectPtr<UDataTable> AcousticsTable;
	UPROPERTY(Config, EditAnywhere, Category = "Tables") TSoftObjectPtr<UDataTable> AIBehaviourTable;
	UPROPERTY(Config, EditAnywhere, Category = "Tables") TSoftObjectPtr<UCurveTable> FeelCurves;

	/** Built by Tools > Modern Survival > Build Enemy StateTree (or Scripts/setup_project.py). */
	UPROPERTY(Config, EditAnywhere, Category = "AI") TSoftObjectPtr<UStateTree> EnemyStateTree;

	/** Optional EQS assets. Empty = the game builds equivalent queries at runtime (see UMSAISubsystem). */
	UPROPERTY(Config, EditAnywhere, Category = "AI") TSoftObjectPtr<UEnvQuery> CoverQueryOverride;
	UPROPERTY(Config, EditAnywhere, Category = "AI") TSoftObjectPtr<UEnvQuery> FlankQueryOverride;

	/** In editor builds, read Data/<Name>.csv when a table asset is missing (or always, if true). */
	UPROPERTY(Config, EditAnywhere, Category = "Tables") bool bPreferCSVInEditor = false;

	UPROPERTY(Config, EditAnywhere, Category = "Maps") FString MainMenuMap = TEXT("/Game/Maps/L_MainMenu");
	UPROPERTY(Config, EditAnywhere, Category = "Maps") TArray<FMSPlayableMap> PlayableMaps;
};
