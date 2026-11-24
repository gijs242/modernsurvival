#pragma once

#include "CoreMinimal.h"
#include "Subsystems/GameInstanceSubsystem.h"
#include "Data/MSDataTypes.h"
#include "MSDataSubsystem.generated.h"

class UDataTable;
class UCurveTable;

/**
 * Loads and caches every tuning table. Gameplay code asks this subsystem for rows instead of
 * holding table pointers, so swapping a table in Project Settings is all it takes to retune.
 *
 * Missing rows never crash: getters return a default-constructed row (the C++ defaults match the
 * shipped CSVs) and log a warning once per row.
 */
UCLASS()
class MODERNSURVIVAL_API UMSDataSubsystem : public UGameInstanceSubsystem
{
	GENERATED_BODY()

public:
	virtual void Initialize(FSubsystemCollectionBase& Collection) override;

	/** Works from any world-context object (actor, component, widget). */
	static UMSDataSubsystem* Get(const UObject* WorldContext);

	/** Re-reads all tables (console: MS.ReloadData). */
	UFUNCTION(BlueprintCallable, Category = "Data") void ReloadAll();

	const FMSPlayerFeelRow& GetPlayerFeel() const;
	const FMSWeaponRow* FindWeapon(FName Row) const;
	const FMSEnemyRow* FindEnemy(FName Row) const;
	const FMSAIBehaviourRow& GetBehaviour(FName Row) const;
	const FMSWaveRow* FindWave(int32 WaveNumber) const;
	int32 GetLastAuthoredWave() const { return LastAuthoredWave; }
	const FMSGameRulesRow& GetRules() const;
	const FMSShopItemRow* FindShopItem(FName Row) const;
	const FMSEquipmentRow& GetEquipment(FName Row) const;
	/** The active look row (set by the map's AMSLookManager), falling back to "Default". */
	const FMSLookRow& GetLook() const;
	void SetActiveLookRow(FName Row) { ActiveLookRow = Row.IsNone() ? FName(TEXT("Default")) : Row; }
	FName GetActiveLookRow() const { return ActiveLookRow; }
	const FMSAcousticRow& GetAcoustics(FName Row) const;

	/** All shop rows of a category, sorted by SortOrder then price. */
	TArray<TPair<FName, const FMSShopItemRow*>> GetShopItems(EMSShopCategory Category) const;
	TArray<FName> GetWeaponNames() const;

	/** Evaluate a curve from the FeelCurves curve table. Returns Fallback when the row is missing. */
	UFUNCTION(BlueprintPure, Category = "Data") float EvalCurve(FName CurveRow, float Time, float Fallback = 0.f) const;

	/** Weapon row with an override for convenience in Blueprint. */
	UFUNCTION(BlueprintPure, Category = "Data") bool GetWeaponRow(FName Row, FMSWeaponRow& OutRow) const;
	UFUNCTION(BlueprintPure, Category = "Data") bool GetEnemyRow(FName Row, FMSEnemyRow& OutRow) const;
	UFUNCTION(BlueprintPure, Category = "Data") FMSPlayerFeelRow GetPlayerFeelCopy() const { return GetPlayerFeel(); }

	UDataTable* GetTable(FName Key) const { return Tables.FindRef(Key); }

private:
	UDataTable* LoadTable(FName Key, const TSoftObjectPtr<UDataTable>& Asset, UScriptStruct* RowStruct);
	UCurveTable* LoadCurves(const TSoftObjectPtr<UCurveTable>& Asset);

	template <typename T>
	const T* FindRowIn(FName Key, FName Row) const;

	UPROPERTY(Transient) TMap<FName, TObjectPtr<UDataTable>> Tables;
	UPROPERTY(Transient) TObjectPtr<UCurveTable> Curves;

	int32 LastAuthoredWave = 0;
	FName ActiveLookRow = TEXT("Default");
	mutable TSet<FString> WarnedMissing;
};
