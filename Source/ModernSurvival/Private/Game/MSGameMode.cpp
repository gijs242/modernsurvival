#include "Game/MSGameMode.h"

#include "AI/MSAICharacter.h"
#include "AI/MSAttackHelicopter.h"
#include "Combat/MSHealthComponent.h"
#include "Data/MSDataSubsystem.h"
#include "Game/MSGameInstance.h"
#include "Game/MSGameState.h"
#include "Game/MSSpawnPoint.h"
#include "Look/MSLookManager.h"
#include "ModernSurvival.h"
#include "Player/MSPlayerCharacter.h"
#include "Player/MSPlayerController.h"
#include "Player/MSPlayerState.h"
#include "UI/MSHUD.h"
#include "Camera/PlayerCameraManager.h"
#include "Engine/World.h"
#include "EngineUtils.h"
#include "Kismet/GameplayStatics.h"
#include "NavigationSystem.h"
#include "TimerManager.h"

#define LOCTEXT_NAMESPACE "MSGame"

AMSGameMode::AMSGameMode()
{
	PrimaryActorTick.bCanEverTick = true;
	DefaultPawnClass = AMSPlayerCharacter::StaticClass();
	PlayerControllerClass = AMSPlayerController::StaticClass();
	PlayerStateClass = AMSPlayerState::StaticClass();
	GameStateClass = AMSGameState::StaticClass();
	HUDClass = AMSHUD::StaticClass();
}

void AMSGameMode::StartPlay()
{
	Super::StartPlay();
	UWorld* World = GetWorld();
	for (TActorIterator<AMSSpawnPoint> It(World); It; ++It)
	{
		SpawnPoints.Add(*It);
	}
	if (SpawnPoints.Num() == 0)
	{
		UE_LOG(LogMS, Warning, TEXT("No MSSpawnPoint actors in this map: enemies will spawn at random navmesh points out of view."));
	}
	FActorSpawnParameters Params;
	Params.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
	World->SpawnActor<AMSLookManager>(AMSLookManager::StaticClass(), FTransform::Identity, Params);

	const UMSDataSubsystem* Data = UMSDataSubsystem::Get(this);
	const FMSGameRulesRow& Rules = Data->GetRules();
	for (FConstPlayerControllerIterator It = World->GetPlayerControllerIterator(); It; ++It)
	{
		if (AMSPlayerState* PS = It->Get() ? It->Get()->GetPlayerState<AMSPlayerState>() : nullptr)
		{
			if (PS->GetCash() == 0 && PS->CashEarned == 0)
			{
				PS->AddCash(Rules.StartingCash, LOCTEXT("Start", "Starting cash"));
			}
		}
	}
	if (AMSGameState* GS = GetGameState<AMSGameState>())
	{
		GS->MatchStartTime = World->GetTimeSeconds();
		GS->Wave = 0;
	}
	BeginIntermission(Rules.FirstIntermissionTime);
}

FName AMSGameMode::RowForKind(MSRules::EEnemyKind Kind) const
{
	return WaveRows[FMath::Clamp<int32>(Kind, 0, MSRules::EnemyKindCount - 1)];
}

MSRules::FWave AMSGameMode::BuildWave(const UObject* WorldContext, int32 Wave, FMSWaveRow& OutRow)
{
	const UMSDataSubsystem* Data = UMSDataSubsystem::Get(WorldContext);
	auto ToRules = [](const FMSWaveRow& Row)
	{
		MSRules::FWave W;
		W.Count[MSRules::Rifleman] = Row.Riflemen;
		W.Count[MSRules::Rusher] = Row.Rushers;
		W.Count[MSRules::Dog] = Row.Dogs;
		W.Count[MSRules::Juggernaut] = Row.Juggernauts;
		W.Count[MSRules::Helicopter] = Row.Helicopters;
		W.HealthMultiplier = Row.HealthMultiplier;
		W.DamageMultiplier = Row.DamageMultiplier;
		W.AccuracyMultiplier = Row.AccuracyMultiplier;
		W.MaxAlive = Row.MaxAlive;
		W.SpawnInterval = Row.SpawnInterval;
		W.ClearBonus = Row.ClearBonus;
		return W;
	};
	if (const FMSWaveRow* Row = Data ? Data->FindWave(Wave) : nullptr)
	{
		OutRow = *Row;
		return ToRules(*Row);
	}
	const int32 Last = Data ? Data->GetLastAuthoredWave() : 0;
	const FMSWaveRow* LastRow = Data && Last > 0 ? Data->FindWave(Last) : nullptr;
	OutRow = LastRow ? *LastRow : FMSWaveRow();
	const FMSGameRulesRow Rules = Data ? Data->GetRules() : FMSGameRulesRow();
	MSRules::FEndlessParams P;
	P.CountGrowthPerWave = Rules.CountGrowthPerWave;
	P.HealthGrowthPerWave = Rules.HealthGrowthPerWave;
	P.DamageGrowthPerWave = Rules.DamageGrowthPerWave;
	P.AccuracyGrowthPerWave = Rules.AccuracyGrowthPerWave;
	P.MaxHealthMultiplier = Rules.MaxHealthMultiplier;
	P.MaxDamageMultiplier = Rules.MaxDamageMultiplier;
	P.MaxAccuracyMultiplier = Rules.MaxAccuracyMultiplier;
	P.MaxAliveCap = Rules.MaxAliveCap;
	P.ClearBonusGrowth = Rules.ClearBonusGrowth;
	P.HelicopterEveryNWaves = Rules.HelicopterEveryNWaves;
	return MSRules::ExtrapolateWave(ToRules(OutRow), FMath::Max(1, Last), Wave, P);
}

void AMSGameMode::BeginIntermission(float Duration)
{
	AMSGameState* GS = GetGameState<AMSGameState>();
	if (!GS || bGameOver)
	{
		return;
	}
	GS->Phase = EMSMatchPhase::Intermission;
	GS->PhaseEndTime = GetWorld()->GetTimeSeconds() + Duration;
	GS->EnemiesRemaining = 0;
	GS->bRevealStragglers = false;
}

void AMSGameMode::BeginWave(int32 Wave)
{
	AMSGameState* GS = GetGameState<AMSGameState>();
	if (!GS || bGameOver)
	{
		return;
	}
	FMSWaveRow Row;
	CurrentWave = BuildWave(this, Wave, Row);
	WaveRows[MSRules::Rifleman] = Row.RiflemanRow;
	WaveRows[MSRules::Rusher] = Row.RusherRow;
	WaveRows[MSRules::Dog] = Row.DogRow;
	WaveRows[MSRules::Juggernaut] = Row.JuggernautRow;
	WaveRows[MSRules::Helicopter] = Row.HelicopterRow;
	WaveHealthMul = CurrentWave.HealthMultiplier;
	WaveDamageMul = CurrentWave.DamageMultiplier;
	WaveAccuracyMul = CurrentWave.AccuracyMultiplier;

	SpawnQueue.SetNum(CurrentWave.Total());
	const int32 N = MSRules::BuildSpawnOrder(CurrentWave, SpawnQueue.GetData(), SpawnQueue.Num());
	SpawnQueue.SetNum(N);
	QueueIndex = 0;
	SpawnTimer = 1.f;
	LastKillTime = GetWorld()->GetTimeSeconds();

	GS->Wave = Wave;
	GS->Phase = EMSMatchPhase::Combat;
	GS->EnemiesRemaining = N;
	GS->WaveBannerTime = GetWorld()->GetTimeSeconds();
	GS->bLastBannerWasClear = false;
	UE_LOG(LogMS, Log, TEXT("Wave %d: %d enemies (R%d S%d D%d J%d H%d) hp x%.2f"), Wave, N,
		CurrentWave.Count[0], CurrentWave.Count[1], CurrentWave.Count[2], CurrentWave.Count[3], CurrentWave.Count[4], CurrentWave.HealthMultiplier);
}

void AMSGameMode::EndWave()
{
	AMSGameState* GS = GetGameState<AMSGameState>();
	const FMSGameRulesRow& Rules = UMSDataSubsystem::Get(this)->GetRules();
	for (FConstPlayerControllerIterator It = GetWorld()->GetPlayerControllerIterator(); It; ++It)
	{
		if (AMSPlayerState* PS = It->Get() ? It->Get()->GetPlayerState<AMSPlayerState>() : nullptr)
		{
			PS->AddCash(CurrentWave.ClearBonus, LOCTEXT("WaveBonus", "Wave survived"));
		}
	}
	if (GS)
	{
		GS->WaveBannerTime = GetWorld()->GetTimeSeconds();
		GS->bLastBannerWasClear = true;
	}
	BeginIntermission(Rules.IntermissionTime);
}

void AMSGameMode::RequestSkipIntermission()
{
	AMSGameState* GS = GetGameState<AMSGameState>();
	if (!GS || bGameOver || GS->Phase != EMSMatchPhase::Intermission)
	{
		return;
	}
	const FMSGameRulesRow& Rules = UMSDataSubsystem::Get(this)->GetRules();
	const int32 SecondsSkipped = FMath::FloorToInt(GS->GetPhaseTimeLeft());
	const int32 Bonus = SecondsSkipped * Rules.SkipBonusPerSecond;
	if (Bonus > 0)
	{
		for (FConstPlayerControllerIterator It = GetWorld()->GetPlayerControllerIterator(); It; ++It)
		{
			if (AMSPlayerState* PS = It->Get() ? It->Get()->GetPlayerState<AMSPlayerState>() : nullptr)
			{
				PS->AddCash(Bonus, LOCTEXT("Skip", "Early start"));
			}
		}
	}
	BeginWave(GS->Wave + 1);
}

// ------------------------------------------------------------------------------------------- spawning

FMSSpawnChoice AMSGameMode::ChooseSpawn(UWorld* World, const FVector& ViewLocation, const FRotator& ViewRotation, float ViewHalfFOV,
	const TArray<AMSSpawnPoint*>& Points, EMSSpawnKind Kind, int32 Wave, const FMSGameRulesRow& Rules, bool bAllowNavFallback)
{
	FMSSpawnChoice Best;
	if (!World)
	{
		return Best;
	}
	MSRules::FSpawnParams P;
	P.MinDistance = Rules.SpawnMinDistance;
	P.MaxDistance = Kind == EMSSpawnKind::Air ? Rules.SpawnMaxDistance * 2.f : Rules.SpawnMaxDistance;
	P.PreferredDistance = Kind == EMSSpawnKind::Air ? Rules.SpawnMaxDistance : Rules.SpawnPreferredDistance;
	P.ViewHalfAngleDeg = ViewHalfFOV;
	P.ViewMarginDeg = Rules.SpawnViewMarginDeg;
	P.BehindBonus = Rules.SpawnBehindBonus;

	// Horizontal test: flatten everything to the viewer's height.
	const FVector Fwd = FRotator(0.f, ViewRotation.Yaw, 0.f).Vector();
	const MSRules::FVec3 Eye(ViewLocation.X, ViewLocation.Y, 0.f);
	const MSRules::FVec3 Forward(Fwd.X, Fwd.Y, 0.f);
	const APlayerController* PC = World->GetFirstPlayerController();
	FCollisionQueryParams TraceParams(SCENE_QUERY_STAT(MSSpawnVisibility), false, PC ? PC->GetPawn() : nullptr);
	const double Now = World->GetTimeSeconds();

	auto Evaluate = [&](const FVector& Location, AMSSpawnPoint* Point)
	{
		const FVector Probe = Location + FVector(0.f, 0.f, Kind == EMSSpawnKind::Air ? 0.f : 120.f);
		const bool bVisible = !World->LineTraceTestByChannel(ViewLocation, Probe, ECC_Visibility, TraceParams);
		const float Score = MSRules::ScoreSpawnPoint(Eye, Forward, MSRules::FVec3(Location.X, Location.Y, 0.f), bVisible, P);
		if (Score > 0.f)
		{
			// Small random jitter so equal points take turns.
			const float Jittered = Score * FMath::FRandRange(0.85f, 1.f);
			if (Jittered > Best.Score)
			{
				Best.bValid = true;
				Best.Score = Jittered;
				Best.Location = Location;
				Best.Point = Point;
				Best.Rotation = FRotator(0.f, (ViewLocation - Location).Rotation().Yaw, 0.f);
			}
		}
	};

	for (AMSSpawnPoint* Point : Points)
	{
		if (!IsValid(Point) || !Point->bEnabled || Point->Kind != Kind || Point->MinWave > Wave || Now - Point->LastUsedTime < Rules.SpawnPointCooldown)
		{
			continue;
		}
		Evaluate(Point->GetActorLocation(), Point);
	}
	if (Best.bValid || !bAllowNavFallback)
	{
		return Best;
	}

	if (Kind == EMSSpawnKind::Air)
	{
		// Behind the player, high up.
		for (int32 I = 0; I < 8; ++I)
		{
			const float Yaw = ViewRotation.Yaw + 180.f + FMath::FRandRange(-70.f, 70.f);
			Evaluate(ViewLocation + FRotator(0.f, Yaw, 0.f).Vector() * P.PreferredDistance + FVector(0, 0, 2500.f), nullptr);
		}
		return Best;
	}
	if (UNavigationSystemV1* Nav = FNavigationSystem::GetCurrent<UNavigationSystemV1>(World))
	{
		for (int32 I = 0; I < 24; ++I)
		{
			FNavLocation Out;
			if (Nav->GetRandomReachablePointInRadius(ViewLocation - FVector(0, 0, 150.f), P.MaxDistance, Out))
			{
				Evaluate(Out.Location, nullptr);
			}
		}
	}
	return Best;
}

AActor* AMSGameMode::SpawnEnemy(MSRules::EEnemyKind Kind)
{
	UWorld* World = GetWorld();
	APlayerController* PC = World->GetFirstPlayerController();
	if (!PC)
	{
		return nullptr;
	}
	FVector ViewLoc;
	FRotator ViewRot;
	PC->GetPlayerViewPoint(ViewLoc, ViewRot);
	const float HalfFOV = PC->PlayerCameraManager ? PC->PlayerCameraManager->GetFOVAngle() * 0.5f : 45.f;
	const UMSDataSubsystem* Data = UMSDataSubsystem::Get(this);
	const FMSGameRulesRow& Rules = Data->GetRules();
	const AMSGameState* GS = GetGameState<AMSGameState>();
	const EMSSpawnKind SpawnKind = Kind == MSRules::Helicopter ? EMSSpawnKind::Air : EMSSpawnKind::Ground;

	TArray<AMSSpawnPoint*> Points;
	for (AMSSpawnPoint* P : SpawnPoints)
	{
		Points.Add(P);
	}
	const FMSSpawnChoice Choice = ChooseSpawn(World, ViewLoc, ViewRot, HalfFOV, Points, SpawnKind, GS ? GS->Wave : 1, Rules, true);
	if (!Choice.bValid)
	{
		return nullptr;
	}
	if (Choice.Point.IsValid())
	{
		Choice.Point->LastUsedTime = World->GetTimeSeconds();
	}

	const FName Row = RowForKind(Kind);
	FActorSpawnParameters Params;
	Params.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AdjustIfPossibleButAlwaysSpawn;
	AActor* Spawned = nullptr;
	if (Kind == MSRules::Helicopter)
	{
		if (AMSAttackHelicopter* Heli = World->SpawnActor<AMSAttackHelicopter>(Choice.Location, Choice.Rotation, Params))
		{
			Heli->InitFromRow(Row, WaveHealthMul, WaveDamageMul, WaveAccuracyMul);
			Heli->GetHealth()->OnDied.AddDynamic(this, &AMSGameMode::HandleEnemyDied);
			Spawned = Heli;
		}
	}
	else
	{
		const FVector2D Jitter = FMath::RandPointInCircle(Rules.SpawnJitterRadius);
		const FVector Loc = Choice.Location + FVector(Jitter.X, Jitter.Y, 100.f);
		if (AMSAICharacter* Enemy = World->SpawnActor<AMSAICharacter>(AMSAICharacter::StaticClass(), Loc, Choice.Rotation, Params))
		{
			Enemy->InitFromRow(Row, WaveHealthMul, WaveDamageMul, WaveAccuracyMul, EMSTeam::Enemy);
			Enemy->GetHealth()->OnDied.AddDynamic(this, &AMSGameMode::HandleEnemyDied);
			Spawned = Enemy;
		}
	}
	if (Spawned)
	{
		const FMSEnemyRow* EnemyRow = Data->FindEnemy(Row);
		RewardByEnemy.Add(Spawned, EnemyRow ? EnemyRow->CashReward : 100);
		RowByEnemy.Add(Spawned, Row);
		AliveEnemies.Add(Spawned);
	}
	return Spawned;
}

bool AMSGameMode::SpawnNext()
{
	if (!SpawnQueue.IsValidIndex(QueueIndex))
	{
		return false;
	}
	if (SpawnEnemy(static_cast<MSRules::EEnemyKind>(SpawnQueue[QueueIndex])))
	{
		++QueueIndex;
		return true;
	}
	return false;
}

void AMSGameMode::HandleEnemyDied(UMSHealthComponent* Health, const FMSDamageInfo& KillingBlow)
{
	AActor* Enemy = Health ? Health->GetOwner() : nullptr;
	if (!Enemy)
	{
		return;
	}
	AliveEnemies.Remove(Enemy);
	LastKillTime = GetWorld()->GetTimeSeconds();
	const int32 BaseReward = RewardByEnemy.FindRef(Enemy);
	RewardByEnemy.Remove(Enemy);
	RowByEnemy.Remove(Enemy);
	if (Cast<AMSAICharacter>(Enemy))
	{
		TrackCorpse(Enemy);
	}

	APlayerController* PC = Cast<APlayerController>(KillingBlow.Instigator);
	AMSPlayerState* PS = PC ? PC->GetPlayerState<AMSPlayerState>() : nullptr;
	if (!PS)
	{
		return;
	}
	const FMSGameRulesRow& Rules = UMSDataSubsystem::Get(this)->GetRules();
	MSRules::FCashParams Cash;
	Cash.HeadshotBonus = Rules.HeadshotBonus;
	Cash.MeleeBonus = Rules.MeleeBonus;
	Cash.ExplosiveBonus = Rules.ExplosiveBonus;
	Cash.CashMultiplier = Rules.CashMultiplier;
	const bool bMelee = KillingBlow.Kind == EMSDamageKind::Melee;
	const bool bExplosive = KillingBlow.Kind == EMSDamageKind::Explosive;
	const int32 Total = MSRules::KillReward(BaseReward, KillingBlow.bHeadshot, bMelee, bExplosive, Cash);
	const int32 Base = MSRules::KillReward(BaseReward, false, false, false, Cash);
	PS->AddCash(Base, LOCTEXT("Kill", "Kill"));
	if (Total > Base)
	{
		PS->AddCash(Total - Base, KillingBlow.bHeadshot ? LOCTEXT("Headshot", "Headshot") : bMelee ? LOCTEXT("Melee", "Melee") : LOCTEXT("Explosive", "Explosive"));
	}
	PS->RecordKill(KillingBlow.bHeadshot, bMelee);
}

void AMSGameMode::TrackCorpse(AActor* Corpse)
{
	Corpses.Add(Corpse);
	const int32 Max = UMSDataSubsystem::Get(this)->GetRules().MaxCorpses;
	Corpses.RemoveAll([](const TObjectPtr<AActor>& A) { return !IsValid(A); });
	while (Corpses.Num() > Max)
	{
		if (AActor* Oldest = Corpses[0])
		{
			Oldest->Destroy();
		}
		Corpses.RemoveAt(0);
	}
}

void AMSGameMode::UpdateStragglers()
{
	AMSGameState* GS = GetGameState<AMSGameState>();
	const FMSGameRulesRow& Rules = UMSDataSubsystem::Get(this)->GetRules();
	GS->bRevealStragglers = QueueIndex >= SpawnQueue.Num() && AliveEnemies.Num() <= Rules.StragglerCount
		&& GetWorld()->GetTimeSeconds() - LastKillTime > Rules.StragglerRevealTime;
}

void AMSGameMode::Tick(float DeltaSeconds)
{
	Super::Tick(DeltaSeconds);
	AMSGameState* GS = GetGameState<AMSGameState>();
	if (!GS || bGameOver)
	{
		return;
	}
	AliveEnemies.RemoveAll([](const TObjectPtr<AActor>& A) { return !IsValid(A); });

	if (GS->Phase == EMSMatchPhase::Intermission)
	{
		if (GetWorld()->GetTimeSeconds() >= GS->PhaseEndTime)
		{
			BeginWave(GS->Wave + 1);
		}
		return;
	}
	if (GS->Phase != EMSMatchPhase::Combat)
	{
		return;
	}
	SpawnTimer -= DeltaSeconds;
	if (SpawnTimer <= 0.f && QueueIndex < SpawnQueue.Num() && AliveEnemies.Num() < CurrentWave.MaxAlive)
	{
		// Retry quickly if no spawn point is currently valid (player looking at all of them).
		SpawnTimer = SpawnNext() ? CurrentWave.SpawnInterval : 0.4f;
	}
	GS->EnemiesAlive = AliveEnemies.Num();
	GS->EnemiesRemaining = (SpawnQueue.Num() - QueueIndex) + AliveEnemies.Num();
	UpdateStragglers();
	if (QueueIndex >= SpawnQueue.Num() && AliveEnemies.Num() == 0)
	{
		EndWave();
	}
}

// ------------------------------------------------------------------------------------------- player

void AMSGameMode::OnPlayerKilled(AMSPlayerCharacter* Player, const FMSDamageInfo& KillingBlow)
{
	if (bGameOver)
	{
		return;
	}
	bGameOver = true;
	AMSGameState* GS = GetGameState<AMSGameState>();
	AMSPlayerController* PC = Player ? Cast<AMSPlayerController>(Player->GetController()) : nullptr;
	const AMSPlayerState* PS = PC ? PC->GetPlayerState<AMSPlayerState>() : nullptr;
	FMSGameOverStats Stats;
	Stats.WaveReached = GS ? GS->Wave : 0;
	Stats.Kills = PS ? PS->Kills : 0;
	Stats.Headshots = PS ? PS->Headshots : 0;
	Stats.CashEarned = PS ? PS->CashEarned : 0;
	Stats.TimeSurvived = GS ? static_cast<float>(GetWorld()->GetTimeSeconds() - GS->MatchStartTime) : 0.f;
	if (UMSGameInstance* GI = GetGameInstance<UMSGameInstance>())
	{
		const FString Map = UGameplayStatics::GetCurrentLevelName(this, true);
		Stats.bNewBest = GI->SubmitWave(Map, Stats.WaveReached);
		Stats.BestWave = GI->GetBestWave(Map);
	}
	if (GS)
	{
		GS->Phase = EMSMatchPhase::GameOver;
		GS->FinalStats = Stats;
	}
	const float Delay = UMSDataSubsystem::Get(this)->GetRules().GameOverDelay;
	TWeakObjectPtr<AMSPlayerController> WeakPC(PC);
	FTimerHandle Handle;
	GetWorldTimerManager().SetTimer(Handle, FTimerDelegate::CreateLambda([WeakPC, Stats]()
	{
		if (WeakPC.IsValid())
		{
			WeakPC->ShowGameOver(Stats);
		}
	}), FMath::Max(0.1f, Delay), false);
}

int32 AMSGameMode::SpawnSquad(AMSPlayerCharacter* Caller, FName EquipmentRow)
{
	if (!Caller)
	{
		return 0;
	}
	const FMSEquipmentRow& Row = UMSDataSubsystem::Get(this)->GetEquipment(EquipmentRow);
	UNavigationSystemV1* Nav = FNavigationSystem::GetCurrent<UNavigationSystemV1>(GetWorld());
	int32 Spawned = 0;
	for (int32 I = 0; I < Row.SquadSize; ++I)
	{
		FVector Loc = Caller->GetActorLocation() - Caller->GetActorForwardVector() * 250.f + FVector(0, (I - 0.5f) * 150.f, 0);
		FNavLocation NavLoc;
		if (Nav && Nav->GetRandomReachablePointInRadius(Loc, 300.f, NavLoc))
		{
			Loc = NavLoc.Location;
		}
		FActorSpawnParameters Params;
		Params.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AdjustIfPossibleButAlwaysSpawn;
		if (AMSAICharacter* Soldier = GetWorld()->SpawnActor<AMSAICharacter>(AMSAICharacter::StaticClass(), Loc + FVector(0, 0, 100.f), Caller->GetActorRotation(), Params))
		{
			Soldier->InitFromRow(Row.SquadEnemyRow, 1.f, 1.f, 1.f, EMSTeam::Player);
			++Spawned;
		}
	}
	return Spawned;
}

void AMSGameMode::DebugKillAll(APawn* Killer)
{
	TArray<TObjectPtr<AActor>> Copy = AliveEnemies;
	for (AActor* Enemy : Copy)
	{
		if (UMSHealthComponent* H = UMSHealthComponent::Find(Enemy))
		{
			FMSDamageInfo Info;
			Info.Instigator = Killer ? Killer->GetController() : nullptr;
			Info.SourceTeam = EMSTeam::Player;
			Info.Amount = 1e6f;
			H->Kill(Info);
		}
	}
	QueueIndex = SpawnQueue.Num();
}

void AMSGameMode::DebugSetWave(int32 Wave)
{
	DebugKillAll(nullptr);
	if (AMSGameState* GS = GetGameState<AMSGameState>())
	{
		GS->Wave = FMath::Max(0, Wave - 1);
	}
	BeginIntermission(3.f);
}

#undef LOCTEXT_NAMESPACE
