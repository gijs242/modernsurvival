#include "Data/MSDataSubsystem.h"

#include "Data/MSSettings.h"
#include "ModernSurvival.h"
#include "Engine/CurveTable.h"
#include "Engine/DataTable.h"
#include "Engine/GameInstance.h"
#include "Engine/World.h"
#include "HAL/IConsoleManager.h"
#include "Kismet/GameplayStatics.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "UObject/StrongObjectPtr.h"

namespace MSDataKeys
{
	static const FName PlayerFeel("PlayerFeel");
	static const FName Weapons("Weapons");
	static const FName Enemies("Enemies");
	static const FName Waves("Waves");
	static const FName GameRules("GameRules");
	static const FName ShopItems("ShopItems");
	static const FName Equipment("Equipment");
	static const FName LookFeel("LookFeel");
	static const FName Acoustics("Acoustics");
	static const FName AIBehaviour("AIBehaviour");
}

UMSSettings::UMSSettings()
{
	CategoryName = TEXT("Game");
	SectionName = TEXT("Modern Survival");
}

static TStrongObjectPtr<UMSDataSubsystem>& DetachedInstance()
{
	// Used when there is no game instance (automation tests, editor utilities).
	static TStrongObjectPtr<UMSDataSubsystem> Instance;
	return Instance;
}

static FAutoConsoleCommandWithWorld GReloadDataCmd(
	TEXT("MS.ReloadData"),
	TEXT("Re-read every Modern Survival tuning table (and CSVs in editor)."),
	FConsoleCommandWithWorldDelegate::CreateLambda([](UWorld* World)
	{
		if (UMSDataSubsystem* Data = UMSDataSubsystem::Get(World))
		{
			Data->ReloadAll();
		}
	}));

void UMSDataSubsystem::Initialize(FSubsystemCollectionBase& Collection)
{
	Super::Initialize(Collection);
	ReloadAll();
}

UMSDataSubsystem* UMSDataSubsystem::Get(const UObject* WorldContext)
{
	if (WorldContext)
	{
		if (const UWorld* World = GEngine ? GEngine->GetWorldFromContextObject(WorldContext, EGetWorldErrorMode::ReturnNull) : nullptr)
		{
			if (UGameInstance* GI = World->GetGameInstance())
			{
				if (UMSDataSubsystem* Sub = GI->GetSubsystem<UMSDataSubsystem>())
				{
					return Sub;
				}
			}
		}
	}
	TStrongObjectPtr<UMSDataSubsystem>& Detached = DetachedInstance();
	if (!Detached.IsValid())
	{
		// Game instance subsystems must live inside a game instance (UCLASS Within=GameInstance).
		static TStrongObjectPtr<UGameInstance> DetachedOuter;
		if (!DetachedOuter.IsValid())
		{
			DetachedOuter.Reset(NewObject<UGameInstance>(GetTransientPackage(), NAME_None, RF_Transient));
		}
		Detached.Reset(NewObject<UMSDataSubsystem>(DetachedOuter.Get(), NAME_None, RF_Transient));
		Detached->ReloadAll();
	}
	return Detached.Get();
}

UDataTable* UMSDataSubsystem::LoadTable(FName Key, const TSoftObjectPtr<UDataTable>& Asset, UScriptStruct* RowStruct)
{
	const UMSSettings* Settings = UMSSettings::Get();
	UDataTable* Table = nullptr;

	if (!Settings->bPreferCSVInEditor || !WITH_EDITOR)
	{
		Table = Asset.IsNull() ? nullptr : Asset.LoadSynchronous();
		if (Table && Table->GetRowStruct() != RowStruct)
		{
			UE_LOG(LogMS, Error, TEXT("Table %s uses row struct %s, expected %s"), *Table->GetPathName(),
				Table->GetRowStruct() ? *Table->GetRowStruct()->GetName() : TEXT("None"), *RowStruct->GetName());
			Table = nullptr;
		}
	}

#if WITH_EDITOR
	if (!Table)
	{
		const FString CsvPath = FPaths::Combine(FPaths::ProjectDir(), TEXT("Data"), Key.ToString() + TEXT(".csv"));
		FString Csv;
		if (FFileHelper::LoadFileToString(Csv, *CsvPath))
		{
			Table = NewObject<UDataTable>(this, *FString::Printf(TEXT("DT_%s_CSV"), *Key.ToString()), RF_Transient);
			Table->RowStruct = RowStruct;
			const TArray<FString> Problems = Table->CreateTableFromCSVString(Csv);
			for (const FString& Problem : Problems)
			{
				UE_LOG(LogMS, Warning, TEXT("%s: %s"), *CsvPath, *Problem);
			}
			UE_LOG(LogMS, Log, TEXT("Loaded %s from CSV (%d rows). Run Scripts/setup_project.py to import it as an asset."),
				*Key.ToString(), Table->GetRowMap().Num());
		}
	}
#endif

	if (!Table)
	{
		UE_LOG(LogMS, Warning, TEXT("Tuning table %s is missing; using C++ defaults."), *Key.ToString());
	}
	return Table;
}

UCurveTable* UMSDataSubsystem::LoadCurves(const TSoftObjectPtr<UCurveTable>& Asset)
{
	UCurveTable* Table = nullptr;
	if (!UMSSettings::Get()->bPreferCSVInEditor || !WITH_EDITOR)
	{
		Table = Asset.IsNull() ? nullptr : Asset.LoadSynchronous();
	}
#if WITH_EDITOR
	if (!Table)
	{
		const FString CsvPath = FPaths::Combine(FPaths::ProjectDir(), TEXT("Data"), TEXT("FeelCurves.csv"));
		FString Csv;
		if (FFileHelper::LoadFileToString(Csv, *CsvPath))
		{
			Table = NewObject<UCurveTable>(this, TEXT("CT_FeelCurves_CSV"), RF_Transient);
			const TArray<FString> Problems = Table->CreateTableFromCSVString(Csv, RCIM_Cubic);
			for (const FString& Problem : Problems)
			{
				UE_LOG(LogMS, Warning, TEXT("%s: %s"), *CsvPath, *Problem);
			}
		}
	}
#endif
	return Table;
}

void UMSDataSubsystem::ReloadAll()
{
	const UMSSettings* S = UMSSettings::Get();
	Tables.Reset();
	WarnedMissing.Reset();

	auto Add = [this](FName Key, const TSoftObjectPtr<UDataTable>& Asset, UScriptStruct* Struct)
	{
		if (UDataTable* T = LoadTable(Key, Asset, Struct))
		{
			Tables.Add(Key, T);
		}
	};
	Add(MSDataKeys::PlayerFeel, S->PlayerFeelTable, FMSPlayerFeelRow::StaticStruct());
	Add(MSDataKeys::Weapons, S->WeaponTable, FMSWeaponRow::StaticStruct());
	Add(MSDataKeys::Enemies, S->EnemyTable, FMSEnemyRow::StaticStruct());
	Add(MSDataKeys::Waves, S->WaveTable, FMSWaveRow::StaticStruct());
	Add(MSDataKeys::GameRules, S->GameRulesTable, FMSGameRulesRow::StaticStruct());
	Add(MSDataKeys::ShopItems, S->ShopTable, FMSShopItemRow::StaticStruct());
	Add(MSDataKeys::Equipment, S->EquipmentTable, FMSEquipmentRow::StaticStruct());
	Add(MSDataKeys::LookFeel, S->LookTable, FMSLookRow::StaticStruct());
	Add(MSDataKeys::Acoustics, S->AcousticsTable, FMSAcousticRow::StaticStruct());
	Add(MSDataKeys::AIBehaviour, S->AIBehaviourTable, FMSAIBehaviourRow::StaticStruct());
	Curves = LoadCurves(S->FeelCurves);

	LastAuthoredWave = 0;
	if (const UDataTable* Waves = Tables.FindRef(MSDataKeys::Waves))
	{
		for (const FName& Name : Waves->GetRowNames())
		{
			LastAuthoredWave = FMath::Max(LastAuthoredWave, FCString::Atoi(*Name.ToString()));
		}
	}
	UE_LOG(LogMS, Log, TEXT("Tuning data loaded: %d tables, %d authored waves."), Tables.Num(), LastAuthoredWave);
}

template <typename T>
const T* UMSDataSubsystem::FindRowIn(FName Key, FName Row) const
{
	if (Row.IsNone())
	{
		return nullptr;
	}
	if (const UDataTable* Table = Tables.FindRef(Key))
	{
		if (const T* Found = Table->FindRow<T>(Row, TEXT("MSData"), false))
		{
			return Found;
		}
	}
	const FString WarnKey = Key.ToString() + TEXT(".") + Row.ToString();
	if (!WarnedMissing.Contains(WarnKey))
	{
		WarnedMissing.Add(WarnKey);
		UE_LOG(LogMS, Warning, TEXT("Missing row %s in table %s"), *Row.ToString(), *Key.ToString());
	}
	return nullptr;
}

const FMSPlayerFeelRow& UMSDataSubsystem::GetPlayerFeel() const
{
	static const FMSPlayerFeelRow Defaults;
	const FMSPlayerFeelRow* Row = FindRowIn<FMSPlayerFeelRow>(MSDataKeys::PlayerFeel, "Default");
	return Row ? *Row : Defaults;
}

const FMSWeaponRow* UMSDataSubsystem::FindWeapon(FName Row) const
{
	return FindRowIn<FMSWeaponRow>(MSDataKeys::Weapons, Row);
}

const FMSEnemyRow* UMSDataSubsystem::FindEnemy(FName Row) const
{
	return FindRowIn<FMSEnemyRow>(MSDataKeys::Enemies, Row);
}

const FMSAIBehaviourRow& UMSDataSubsystem::GetBehaviour(FName Row) const
{
	static const FMSAIBehaviourRow Defaults;
	const FMSAIBehaviourRow* Found = FindRowIn<FMSAIBehaviourRow>(MSDataKeys::AIBehaviour, Row);
	if (!Found && Row != "Default")
	{
		Found = FindRowIn<FMSAIBehaviourRow>(MSDataKeys::AIBehaviour, "Default");
	}
	return Found ? *Found : Defaults;
}

const FMSWaveRow* UMSDataSubsystem::FindWave(int32 WaveNumber) const
{
	if (const UDataTable* Table = Tables.FindRef(MSDataKeys::Waves))
	{
		return Table->FindRow<FMSWaveRow>(*FString::FromInt(WaveNumber), TEXT("MSData"), false);
	}
	return nullptr;
}

const FMSGameRulesRow& UMSDataSubsystem::GetRules() const
{
	static const FMSGameRulesRow Defaults;
	const FMSGameRulesRow* Row = FindRowIn<FMSGameRulesRow>(MSDataKeys::GameRules, "Default");
	return Row ? *Row : Defaults;
}

const FMSShopItemRow* UMSDataSubsystem::FindShopItem(FName Row) const
{
	return FindRowIn<FMSShopItemRow>(MSDataKeys::ShopItems, Row);
}

const FMSEquipmentRow& UMSDataSubsystem::GetEquipment(FName Row) const
{
	static const FMSEquipmentRow Defaults;
	const FMSEquipmentRow* Found = FindRowIn<FMSEquipmentRow>(MSDataKeys::Equipment, Row);
	return Found ? *Found : Defaults;
}

const FMSLookRow& UMSDataSubsystem::GetLook() const
{
	static const FMSLookRow Defaults;
	const FMSLookRow* Row = ActiveLookRow != "Default" ? FindRowIn<FMSLookRow>(MSDataKeys::LookFeel, ActiveLookRow) : nullptr;
	if (!Row)
	{
		Row = FindRowIn<FMSLookRow>(MSDataKeys::LookFeel, "Default");
	}
	return Row ? *Row : Defaults;
}

const FMSAcousticRow& UMSDataSubsystem::GetAcoustics(FName Row) const
{
	static const FMSAcousticRow Defaults;
	const FMSAcousticRow* Found = FindRowIn<FMSAcousticRow>(MSDataKeys::Acoustics, Row);
	return Found ? *Found : Defaults;
}

TArray<TPair<FName, const FMSShopItemRow*>> UMSDataSubsystem::GetShopItems(EMSShopCategory Category) const
{
	TArray<TPair<FName, const FMSShopItemRow*>> Result;
	if (const UDataTable* Table = Tables.FindRef(MSDataKeys::ShopItems))
	{
		Table->ForeachRow<FMSShopItemRow>(TEXT("MSShop"), [&Result, Category](const FName& Name, const FMSShopItemRow& Row)
		{
			if (Row.Category == Category)
			{
				Result.Emplace(Name, &Row);
			}
		});
	}
	Result.Sort([](const TPair<FName, const FMSShopItemRow*>& A, const TPair<FName, const FMSShopItemRow*>& B)
	{
		return A.Value->SortOrder != B.Value->SortOrder ? A.Value->SortOrder < B.Value->SortOrder : A.Value->Price < B.Value->Price;
	});
	return Result;
}

TArray<FName> UMSDataSubsystem::GetWeaponNames() const
{
	const UDataTable* Table = Tables.FindRef(MSDataKeys::Weapons);
	return Table ? Table->GetRowNames() : TArray<FName>();
}

float UMSDataSubsystem::EvalCurve(FName CurveRow, float Time, float Fallback) const
{
	if (Curves && !CurveRow.IsNone())
	{
		if (const FRealCurve* Curve = Curves->FindCurve(CurveRow, TEXT("MSCurves"), false))
		{
			return Curve->Eval(Time, Fallback);
		}
	}
	return Fallback;
}

bool UMSDataSubsystem::GetWeaponRow(FName Row, FMSWeaponRow& OutRow) const
{
	if (const FMSWeaponRow* Found = FindWeapon(Row))
	{
		OutRow = *Found;
		return true;
	}
	return false;
}

bool UMSDataSubsystem::GetEnemyRow(FName Row, FMSEnemyRow& OutRow) const
{
	if (const FMSEnemyRow* Found = FindEnemy(Row))
	{
		OutRow = *Found;
		return true;
	}
	return false;
}
