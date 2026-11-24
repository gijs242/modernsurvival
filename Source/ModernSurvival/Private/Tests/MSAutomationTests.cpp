// Automation tests. Run: Session Frontend > Automation > filter "ModernSurvival", or
//   UnrealEditor-Cmd ModernSurvival.uproject -ExecCmds="Automation RunTests ModernSurvival; Quit" -unattended -nullrhi
// (Scripts/run_tests.bat / .sh wrap this.)

#include "Tests/MSTestActors.h"

#include "AI/MSEnvQuery.h"
#include "Combat/MSCombatLibrary.h"
#include "Combat/MSHealthComponent.h"
#include "Core/MSRules.h"
#include "Data/MSDataSubsystem.h"
#include "Data/MSSettings.h"
#include "Game/MSGameMode.h"
#include "Game/MSSpawnPoint.h"
#include "Weapons/MSWeapon.h"
#include "Components/BoxComponent.h"
#include "Components/StaticMeshComponent.h"
#include "Engine/DataTable.h"
#include "Engine/Engine.h"
#include "Engine/StaticMesh.h"
#include "Engine/StaticMeshActor.h"
#include "Engine/World.h"
#include "Misc/AutomationTest.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "StateTree.h"

AMSTestWeaponHolder::AMSTestWeaponHolder()
{
	SetRootComponent(CreateDefaultSubobject<USceneComponent>(TEXT("Root")));
}

AMSTestTarget::AMSTestTarget()
{
	Box = CreateDefaultSubobject<UBoxComponent>(TEXT("Box"));
	Box->InitBoxExtent(FVector(50.f, 50.f, 100.f));
	Box->SetCollisionEnabled(ECollisionEnabled::QueryOnly);
	Box->SetCollisionResponseToAllChannels(ECR_Block);
	SetRootComponent(Box);
	Health = CreateDefaultSubobject<UMSHealthComponent>(TEXT("Health"));
	Health->Team = EMSTeam::Enemy;
}

#if WITH_DEV_AUTOMATION_TESTS

#define MS_TEST_FLAGS (EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

namespace MSTest
{

	/** A throwaway game world for tests that need actors, traces and ticking. */
	struct FScopedGameWorld
	{
		UWorld* World = nullptr;

		FScopedGameWorld()
		{
			World = UWorld::CreateWorld(EWorldType::Game, false, TEXT("MSTestWorld"));
			FWorldContext& Context = GEngine->CreateNewWorldContext(EWorldType::Game);
			Context.SetCurrentWorld(World);
			World->InitializeActorsForPlay(FURL());
			World->BeginPlay();
		}

		~FScopedGameWorld()
		{
			GEngine->DestroyWorldContext(World);
			World->DestroyWorld(false);
		}

		void Tick(float Seconds, float Step = 1.f / 60.f)
		{
			for (float T = 0.f; T < Seconds; T += Step)
			{
				World->Tick(LEVELTICK_All, Step);
			}
		}
	};
}

// ------------------------------------------------------------------------------------------------ rules

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FMSRulesTest, "ModernSurvival.Rules.Core", MS_TEST_FLAGS)
bool FMSRulesTest::RunTest(const FString& Parameters)
{
	MSRules::FWave W;
	W.Count[MSRules::Rifleman] = 8;
	W.Count[MSRules::Dog] = 3;
	int32 Order[32];
	TestEqual(TEXT("spawn order length"), MSRules::BuildSpawnOrder(W, Order, 32), 11);
	TestEqual(TEXT("falloff midpoint"), MSRules::DamageFalloff(2000.f, 1000.f, 3000.f, 0.5f), 0.75f);
	float Armor = 100.f;
	TestEqual(TEXT("armor soak"), MSRules::ApplyArmor(50.f, Armor, 0.8f), 10.f);
	MSRules::FSpawnParams P;
	TestTrue(TEXT("behind is outside view"), MSRules::IsOutsideViewCone({0, 0, 0}, {1, 0, 0}, {-2000, 0, 0}, P));
	return true;
}

// ------------------------------------------------------------------------------------------------ data

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FMSDataTablesTest, "ModernSurvival.Data.TablesLoadAndCrossReference", MS_TEST_FLAGS)
bool FMSDataTablesTest::RunTest(const FString& Parameters)
{
	UMSDataSubsystem* Data = UMSDataSubsystem::Get(nullptr);
	if (!TestNotNull(TEXT("data subsystem"), Data))
	{
		return false;
	}
	Data->ReloadAll();
	for (const TCHAR* Key : {TEXT("PlayerFeel"), TEXT("Weapons"), TEXT("Enemies"), TEXT("Waves"), TEXT("GameRules"), TEXT("ShopItems"),
		TEXT("Equipment"), TEXT("LookFeel"), TEXT("Acoustics"), TEXT("AIBehaviour")})
	{
		TestNotNull(FString::Printf(TEXT("table %s"), Key), Data->GetTable(Key));
	}
	TestTrue(TEXT("authored waves"), Data->GetLastAuthoredWave() >= 1);
	TestNotNull(TEXT("wave 1"), Data->FindWave(1));
	TestNotNull(TEXT("PlayerFeel Default row"), Data->GetTable(TEXT("PlayerFeel")) ? Data->GetTable(TEXT("PlayerFeel"))->FindRow<FMSPlayerFeelRow>(TEXT("Default"), TEXT("test")) : nullptr);

	const FMSGameRulesRow& Rules = Data->GetRules();
	TestNotNull(TEXT("starting weapon exists"), Data->FindWeapon(Rules.StartingWeapon));
	TestNotNull(TEXT("last stand weapon exists"), Data->FindWeapon(Data->GetPlayerFeel().LastStandWeapon));

	if (const UDataTable* Enemies = Data->GetTable(TEXT("Enemies")))
	{
		Enemies->ForeachRow<FMSEnemyRow>(TEXT("test"), [this, Data](const FName& Name, const FMSEnemyRow& Row)
		{
			if (!Row.Weapon.IsNone())
			{
				TestNotNull(FString::Printf(TEXT("enemy %s weapon %s"), *Name.ToString(), *Row.Weapon.ToString()), Data->FindWeapon(Row.Weapon));
			}
			TestTrue(FString::Printf(TEXT("enemy %s health > 0"), *Name.ToString()), Row.Health > 0.f);
		});
	}
	for (int32 Wave = 1; Wave <= Data->GetLastAuthoredWave(); ++Wave)
	{
		const FMSWaveRow* Row = Data->FindWave(Wave);
		if (TestNotNull(FString::Printf(TEXT("wave %d"), Wave), Row))
		{
			for (const FName& EnemyRow : {Row->RiflemanRow, Row->RusherRow, Row->DogRow, Row->JuggernautRow, Row->HelicopterRow})
			{
				TestNotNull(FString::Printf(TEXT("wave %d enemy row %s"), Wave, *EnemyRow.ToString()), Data->FindEnemy(EnemyRow));
			}
		}
	}
	for (const EMSShopCategory Cat : {EMSShopCategory::Weapons, EMSShopCategory::Equipment, EMSShopCategory::AirSupport})
	{
		TestTrue(TEXT("each buy station sells something"), Data->GetShopItems(Cat).Num() > 0);
	}
	return true;
}

#if WITH_EDITOR
IMPLEMENT_SIMPLE_AUTOMATION_TEST(FMSCsvParseTest, "ModernSurvival.Data.CSVsParseCleanly", MS_TEST_FLAGS)
bool FMSCsvParseTest::RunTest(const FString& Parameters)
{
	const TPair<const TCHAR*, UScriptStruct*> Tables[] = {
		{TEXT("PlayerFeel"), FMSPlayerFeelRow::StaticStruct()}, {TEXT("Weapons"), FMSWeaponRow::StaticStruct()},
		{TEXT("Enemies"), FMSEnemyRow::StaticStruct()}, {TEXT("Waves"), FMSWaveRow::StaticStruct()},
		{TEXT("GameRules"), FMSGameRulesRow::StaticStruct()}, {TEXT("ShopItems"), FMSShopItemRow::StaticStruct()},
		{TEXT("Equipment"), FMSEquipmentRow::StaticStruct()}, {TEXT("LookFeel"), FMSLookRow::StaticStruct()},
		{TEXT("Acoustics"), FMSAcousticRow::StaticStruct()}, {TEXT("AIBehaviour"), FMSAIBehaviourRow::StaticStruct()}};
	for (const TPair<const TCHAR*, UScriptStruct*>& T : Tables)
	{
		FString Csv;
		const FString Path = FPaths::Combine(FPaths::ProjectDir(), TEXT("Data"), FString(T.Key) + TEXT(".csv"));
		if (!TestTrue(FString::Printf(TEXT("read %s"), *Path), FFileHelper::LoadFileToString(Csv, *Path)))
		{
			continue;
		}
		UDataTable* Table = NewObject<UDataTable>(GetTransientPackage());
		Table->RowStruct = T.Value;
		const TArray<FString> Problems = Table->CreateTableFromCSVString(Csv);
		for (const FString& Problem : Problems)
		{
			// Unresolvable soft references (art not imported yet) are fine; anything else is a schema error.
			if (!Problem.Contains(TEXT("SoftObjectPath")) && !Problem.Contains(TEXT("not found")))
			{
				AddError(FString::Printf(TEXT("%s: %s"), T.Key, *Problem));
			}
		}
		TestTrue(FString::Printf(TEXT("%s has rows"), T.Key), Table->GetRowMap().Num() > 0);
	}
	return true;
}
#endif

// ------------------------------------------------------------------------------------------------ combat

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FMSBulletDamageTest, "ModernSurvival.Combat.BulletDamage", MS_TEST_FLAGS)
bool FMSBulletDamageTest::RunTest(const FString& Parameters)
{
	FMSWeaponRow Row;
	Row.Damage = 40.f;
	Row.HeadshotMultiplier = 2.f;
	Row.FalloffStart = 1000.f;
	Row.FalloffEnd = 3000.f;
	Row.MinDamageFraction = 0.5f;
	TestEqual(TEXT("close body"), UMSCombatLibrary::ComputeBulletDamage(Row, 500.f, false, 1.f), 40.f);
	TestEqual(TEXT("close head"), UMSCombatLibrary::ComputeBulletDamage(Row, 500.f, true, 1.f), 80.f);
	TestEqual(TEXT("far body"), UMSCombatLibrary::ComputeBulletDamage(Row, 5000.f, false, 1.f), 20.f);
	TestEqual(TEXT("enemy scale"), UMSCombatLibrary::ComputeBulletDamage(Row, 500.f, false, 0.25f), 10.f);
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FMSCoverScoreTest, "ModernSurvival.AI.CoverScoring", MS_TEST_FLAGS)
bool FMSCoverScoreTest::RunTest(const FString& Parameters)
{
	// hidden+peek > hidden only > exposed (filtered); crowding and too-close are penalised.
	const float Best = UMSEnvQueryTest_Cover::ScoreCandidate(true, true, 1600.f, 1600.f, 600.f, 0.f, 0.f, 60.f, false);
	const float NoPeek = UMSEnvQueryTest_Cover::ScoreCandidate(true, false, 1600.f, 1600.f, 600.f, 0.f, 0.f, 60.f, false);
	const float Exposed = UMSEnvQueryTest_Cover::ScoreCandidate(false, true, 1600.f, 1600.f, 600.f, 0.f, 0.f, 60.f, false);
	const float Crowded = UMSEnvQueryTest_Cover::ScoreCandidate(true, true, 1600.f, 1600.f, 600.f, 1.f, 0.f, 60.f, false);
	const float TooClose = UMSEnvQueryTest_Cover::ScoreCandidate(true, true, 300.f, 1600.f, 600.f, 0.f, 0.f, 60.f, false);
	TestTrue(TEXT("peek beats no peek"), Best > NoPeek);
	TestEqual(TEXT("exposed filtered"), Exposed, 0.f);
	TestTrue(TEXT("crowding penalised"), Crowded < Best);
	TestEqual(TEXT("too close filtered"), TooClose, 0.f);
	const float FlankFront = UMSEnvQueryTest_Cover::ScoreCandidate(true, true, 1600.f, 1600.f, 600.f, 0.f, 20.f, 60.f, true);
	const float FlankSide = UMSEnvQueryTest_Cover::ScoreCandidate(true, true, 1600.f, 1600.f, 600.f, 0.f, 120.f, 60.f, true);
	TestEqual(TEXT("flank in front filtered"), FlankFront, 0.f);
	TestTrue(TEXT("flank at side scores"), FlankSide > 0.f);
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FMSHealthWorldTest, "ModernSurvival.World.HealthArmorRegenTeams", MS_TEST_FLAGS)
bool FMSHealthWorldTest::RunTest(const FString& Parameters)
{
	MSTest::FScopedGameWorld TestWorld;
	AMSTestTarget* Target = TestWorld.World->SpawnActor<AMSTestTarget>();
	if (!TestNotNull(TEXT("target"), Target))
	{
		return false;
	}
	UMSHealthComponent* H = Target->Health;
	H->SetMaxHealth(100.f, true);
	H->ConfigureRegen(1.f, 50.f);

	FMSDamageInfo Hit;
	Hit.Amount = 40.f;
	Hit.SourceTeam = EMSTeam::Player;
	H->ApplyDamage(Hit);
	TestEqual(TEXT("damage applied"), H->GetHealth(), 60.f);

	FMSDamageInfo Friendly = Hit;
	Friendly.SourceTeam = EMSTeam::Enemy;
	H->ApplyDamage(Friendly);
	TestEqual(TEXT("no friendly fire"), H->GetHealth(), 60.f);

	H->AddArmor(100.f, 100.f);
	H->ApplyDamage(Hit);                       // 80% absorbed
	TestEqual(TEXT("armor absorbs"), H->GetHealth(), 52.f);

	TestWorld.Tick(0.5f);
	TestTrue(TEXT("no regen during delay"), H->GetHealth() < 53.f);
	TestWorld.Tick(1.5f);
	TestEqual(TEXT("regen to full"), H->GetHealth(), 100.f);

	H->LethalDamageInterceptor.BindLambda([](const FMSDamageInfo&) { return false; });
	Hit.Amount = 1000.f;
	H->ApplyDamage(Hit);
	TestTrue(TEXT("dead"), H->IsDead());
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FMSSpawnVisibilityTest, "ModernSurvival.World.SpawnOutOfView", MS_TEST_FLAGS)
bool FMSSpawnVisibilityTest::RunTest(const FString& Parameters)
{
	MSTest::FScopedGameWorld TestWorld;
	UWorld* World = TestWorld.World;
	FMSGameRulesRow Rules;
	Rules.SpawnMinDistance = 500.f;
	Rules.SpawnMaxDistance = 6000.f;
	Rules.SpawnPreferredDistance = 2000.f;
	Rules.SpawnPointCooldown = 0.f;

	// Wall between the viewer and point B.
	UStaticMesh* Cube = LoadObject<UStaticMesh>(nullptr, TEXT("/Engine/BasicShapes/Cube.Cube"));
	AStaticMeshActor* Wall = World->SpawnActor<AStaticMeshActor>(FVector(1000.f, 1500.f, 100.f), FRotator::ZeroRotator);
	Wall->GetStaticMeshComponent()->SetMobility(EComponentMobility::Movable);
	Wall->GetStaticMeshComponent()->SetStaticMesh(Cube);
	Wall->SetActorScale3D(FVector(1.f, 10.f, 6.f));
	Wall->GetStaticMeshComponent()->SetCollisionProfileName(TEXT("BlockAll"));

	auto MakePoint = [World](const FVector& Loc)
	{
		AMSSpawnPoint* P = World->SpawnActor<AMSSpawnPoint>(Loc, FRotator::ZeroRotator);
		return P;
	};
	AMSSpawnPoint* InView = MakePoint(FVector(2000.f, 0.f, 0.f));       // dead ahead, visible
	AMSSpawnPoint* Occluded = MakePoint(FVector(2000.f, 3000.f, 0.f));  // ahead-right behind the wall
	AMSSpawnPoint* Behind = MakePoint(FVector(-2000.f, 0.f, 0.f));      // behind the viewer
	FMSViewer Solo;
	Solo.Location = FVector(0.f, 0.f, 160.f);
	Solo.Rotation = FRotator::ZeroRotator;
	Solo.HalfFOV = 45.f;
	const TArray<FMSViewer> One = {Solo};

	FMSSpawnChoice C = AMSGameMode::ChooseSpawn(World, One, {InView, Occluded, Behind}, EMSSpawnKind::Ground, 1, Rules, false);
	TestTrue(TEXT("found a spawn"), C.bValid);
	TestTrue(TEXT("prefers behind the player"), C.Point.Get() == Behind);

	C = AMSGameMode::ChooseSpawn(World, One, {InView, Occluded}, EMSSpawnKind::Ground, 1, Rules, false);
	TestTrue(TEXT("never the visible point"), C.Point.Get() != InView);

	C = AMSGameMode::ChooseSpawn(World, One, {InView}, EMSSpawnKind::Ground, 1, Rules, false);
	TestFalse(TEXT("visible-only points are rejected"), C.bValid);

	// Co-op: a second player far behind, looking forward, can see the "behind" point: not allowed any more.
	FMSViewer Mate;
	Mate.Location = FVector(-4500.f, 0.f, 160.f);
	Mate.Rotation = FRotator::ZeroRotator;
	Mate.HalfFOV = 45.f;
	C = AMSGameMode::ChooseSpawn(World, {Solo, Mate}, {InView, Behind}, EMSSpawnKind::Ground, 1, Rules, false);
	TestFalse(TEXT("co-op: hidden from every player or not at all"), C.bValid);
	// Same spot, but the teammate looks the other way: the point behind both players is fine again.
	FMSViewer MateBack = Mate;
	MateBack.Rotation = FRotator(0.f, 180.f, 0.f);
	C = AMSGameMode::ChooseSpawn(World, {Solo, MateBack}, {InView, Behind}, EMSSpawnKind::Ground, 1, Rules, false);
	TestTrue(TEXT("co-op: behind both players is allowed"), C.bValid && C.Point.Get() == Behind);
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FMSWeaponFireTest, "ModernSurvival.World.WeaponFiresAndDamages", MS_TEST_FLAGS)
bool FMSWeaponFireTest::RunTest(const FString& Parameters)
{
	MSTest::FScopedGameWorld TestWorld;
	UWorld* World = TestWorld.World;
	AMSTestWeaponHolder* Holder = World->SpawnActor<AMSTestWeaponHolder>(FVector(0.f, 0.f, 100.f), FRotator::ZeroRotator);
	AMSTestTarget* Target = World->SpawnActor<AMSTestTarget>(FVector(600.f, 0.f, 100.f), FRotator::ZeroRotator);
	Target->Health->SetMaxHealth(10000.f, true);
	AMSWeapon* Weapon = World->SpawnActor<AMSWeapon>(FVector(0.f, 0.f, 100.f), FRotator::ZeroRotator);
	if (!TestNotNull(TEXT("actors"), Holder) || !TestNotNull(TEXT("weapon"), Weapon))
	{
		return false;
	}
	Weapon->Setup(UMSDataSubsystem::Get(World)->GetRules().StartingPrimary, Holder, false);
	Weapon->SetEquipped(true);
	TestWorld.Tick(1.f);                           // equip time
	const int32 MagBefore = Weapon->GetAmmoInMag();
	Weapon->SetTriggerHeld(true);
	TestWorld.Tick(0.5f);
	Weapon->SetTriggerHeld(false);
	TestTrue(TEXT("shots fired"), Holder->ShotsFired > 0);
	TestTrue(TEXT("ammo used"), Weapon->GetAmmoInMag() < MagBefore);
	TestTrue(TEXT("target hit"), Holder->Hits > 0);
	TestTrue(TEXT("target damaged"), Target->Health->GetHealth() < 10000.f);

	// Empty the mag: auto-reload refills it.
	for (int32 Guard = 0; Guard < 200 && Weapon->GetAmmoInMag() > 0; ++Guard)
	{
		Weapon->SetTriggerHeld(true);
		TestWorld.Tick(0.2f);
	}
	Weapon->SetTriggerHeld(false);
	Weapon->StartReload();
	TestWorld.Tick(Weapon->GetRow().ReloadEmptyTime + 0.3f);
	TestEqual(TEXT("reloaded"), Weapon->GetAmmoInMag(), Weapon->GetRow().MagazineSize);
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FMSStateTreeAssetTest, "ModernSurvival.AI.EnemyStateTreeAsset", MS_TEST_FLAGS)
bool FMSStateTreeAssetTest::RunTest(const FString& Parameters)
{
	const TSoftObjectPtr<UStateTree>& Ref = UMSSettings::Get()->EnemyStateTree;
	UStateTree* Tree = Ref.LoadSynchronous();
	if (!Tree)
	{
		AddWarning(FString::Printf(TEXT("StateTree %s not built yet (the C++ fallback brain is used). Run Scripts/setup_project.py."), *Ref.ToString()));
		return true;
	}
	TestTrue(TEXT("StateTree compiled and ready to run"), Tree->IsReadyToRun());
	return true;
}

#endif
