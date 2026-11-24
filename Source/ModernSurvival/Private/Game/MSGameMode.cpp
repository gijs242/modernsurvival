#include "Game/MSGameMode.h"

#include "AI/MSAICharacter.h"
#include "AI/MSAttackHelicopter.h"
#include "Combat/MSHealthComponent.h"
#include "Data/MSDataSubsystem.h"
#include "Game/MSGameInstance.h"
#include "Game/MSGameState.h"
#include "Game/MSSpawnPoint.h"
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
	// The colour grade (AMSLookManager) is spawned per machine by AMSPlayerController.
	const UMSDataSubsystem* Data = UMSDataSubsystem::Get(this);
	const FMSGameRulesRow& Rules = Data->GetRules();
	for (FConstPlayerControllerIterator It = World->GetPlayerControllerIterator(); It; ++It)
	{
		if (AMSPlayerState* PS = It->Get() ? It->Get()->GetPlayerState<AMSPlayerState>() : nullptr)
		{
			PS->GiveStartingCash(Rules.StartingCash);
		}
	}
	if (AMSGameState* GS = GetGameState<AMSGameState>())
	{
		GS->MatchStartTime = World->GetTimeSeconds();
		GS->Wave = 0;
	}
	BeginIntermission(Rules.FirstIntermissionTime);
}

void AMSGameMode::HandleStartingNewPlayer_Implementation(APlayerController* NewPlayer)
{
	Super::HandleStartingNewPlayer_Implementation(NewPlayer);
	// Players who join mid-game (co-op) get the starting cash too.
	if (AMSPlayerState* PS = NewPlayer ? NewPlayer->GetPlayerState<AMSPlayerState>() : nullptr)
	{
		PS->GiveStartingCash(UMSDataSubsystem::Get(this)->GetRules().StartingCash);
	}
	if (AMSGameState* GS = GetGameState<AMSGameState>())
	{
		GS->PlayersInMatch = GetNumPlayers();
	}
}

void AMSGameMode::Logout(AController* Exiting)
{
	Super::Logout(Exiting);
	ReadyPlayers.Remove(Exiting);
	if (AMSGameState* GS = GetGameState<AMSGameState>())
	{
		GS->PlayersInMatch = FMath::Max(1, GetNumPlayers() - 1);
	}
}

int32 AMSGameMode::CountActivePlayers() const
{
	int32 N = 0;
	for (FConstPlayerControllerIterator It = GetWorld()->GetPlayerControllerIterator(); It; ++It)
	{
		const AMSPlayerCharacter* P = It->Get() ? It->Get()->GetPawn<AMSPlayerCharacter>() : nullptr;
		N += (P && !P->IsDead()) ? 1 : 0;
	}
	return N;
}

int32 AMSGameMode::CountStandingPlayers(const AMSPlayerCharacter* Ignore) const
{
	int32 N = 0;
	for (FConstPlayerControllerIterator It = GetWorld()->GetPlayerControllerIterator(); It; ++It)
	{
		const AMSPlayerCharacter* P = It->Get() ? It->Get()->GetPawn<AMSPlayerCharacter>() : nullptr;
		N += (P && P != Ignore && !P->IsDead() && !P->IsDowned()) ? 1 : 0;
	}
	return N;
}

TArray<FMSViewer> AMSGameMode::GatherViewers() const
{
	TArray<FMSViewer> Viewers;
	for (FConstPlayerControllerIterator It = GetWorld()->GetPlayerControllerIterator(); It; ++It)
	{
		APlayerController* PC = It->Get();
		const APawn* Pawn = PC ? PC->GetPawn() : nullptr;
		if (!Pawn)
		{
			continue;
		}
		FMSViewer V;
		// Server-side view of each player: eyes + replicated aim. FOV: the camera's if local, else base FOV.
		V.Location = Pawn->GetPawnViewLocation();
		V.Rotation = Pawn->GetBaseAimRotation();
		V.HalfFOV = (PC->IsLocalController() && PC->PlayerCameraManager) ? PC->PlayerCameraManager->GetFOVAngle() * 0.5f
			: UMSDataSubsystem::Get(this)->GetPlayerFeel().BaseFOV * 0.5f + 5.f;
		Viewers.Add(V);
	}
	return Viewers;
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
	ReadyPlayers.Reset();
	GS->PlayersReady = 0;
	RespawnDeadPlayers();
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
	const FMSGameRulesRow& CoopRules = UMSDataSubsystem::Get(this)->GetRules();
	const int32 Players = FMath::Max(1, GetNumPlayers());
	for (int32 K = 0; K < MSRules::EnemyKindCount; ++K)
	{
		if (K != MSRules::Helicopter)
		{
			CurrentWave.Count[K] = MSRules::CoopScale(CurrentWave.Count[K], Players, CoopRules.CoopEnemiesPerExtraPlayer);
		}
	}
	CurrentWave.MaxAlive = MSRules::CoopScale(CurrentWave.MaxAlive, Players, CoopRules.CoopMaxAlivePerExtraPlayer);
	ReadyPlayers.Reset();
	GS->PlayersReady = 0;
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

void AMSGameMode::SetPlayerReady(AController* Player, bool bReady)
{
	AMSGameState* GS = GetGameState<AMSGameState>();
	if (!GS || !Player || GS->Phase != EMSMatchPhase::Intermission)
	{
		return;
	}
	if (bReady)
	{
		ReadyPlayers.Add(Player);
	}
	else
	{
		ReadyPlayers.Remove(Player);
	}
	ReadyPlayers.Remove(nullptr);
	GS->PlayersReady = ReadyPlayers.Num();
	if (ReadyPlayers.Num() >= FMath::Max(1, CountActivePlayers()))
	{
		RequestSkipIntermission();
	}
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

FMSSpawnChoice AMSGameMode::ChooseSpawn(UWorld* World, const TArray<FMSViewer>& Viewers,
	const TArray<AMSSpawnPoint*>& Points, EMSSpawnKind Kind, int32 Wave, const FMSGameRulesRow& Rules, bool bAllowNavFallback)
{
	FMSSpawnChoice Best;
	if (!World || Viewers.Num() == 0)
	{
		return Best;
	}
	MSRules::FSpawnParams P;
	P.MinDistance = Rules.SpawnMinDistance;
	P.MaxDistance = Kind == EMSSpawnKind::Air ? Rules.SpawnMaxDistance * 2.f : Rules.SpawnMaxDistance;
	P.PreferredDistance = Kind == EMSSpawnKind::Air ? Rules.SpawnMaxDistance : Rules.SpawnPreferredDistance;
	P.ViewMarginDeg = Rules.SpawnViewMarginDeg;
	P.BehindBonus = Rules.SpawnBehindBonus;

	// Ignore every player pawn in the visibility traces.
	FCollisionQueryParams TraceParams(SCENE_QUERY_STAT(MSSpawnVisibility), false);
	for (FConstPlayerControllerIterator It = World->GetPlayerControllerIterator(); It; ++It)
	{
		if (const APlayerController* PC = It->Get())
		{
			TraceParams.AddIgnoredActor(PC->GetPawn());
		}
	}
	const double Now = World->GetTimeSeconds();

	auto Evaluate = [&](const FVector& Location, AMSSpawnPoint* Point)
	{
		// Horizontal test: flatten to each viewer's height. Visibility by a real trace per viewer.
		const FVector Probe = Location + FVector(0.f, 0.f, Kind == EMSSpawnKind::Air ? 0.f : 120.f);
		TArray<MSRules::FViewer> RuleViewers;
		for (const FMSViewer& V : Viewers)
		{
			MSRules::FViewer RV;
			const FVector Fwd = FRotator(0.f, V.Rotation.Yaw, 0.f).Vector();
			RV.Position = MSRules::FVec3(V.Location.X, V.Location.Y, 0.f);
			RV.Forward = MSRules::FVec3(Fwd.X, Fwd.Y, 0.f);
			RV.HalfFovDeg = V.HalfFOV;
			RV.bSeesPoint = !World->LineTraceTestByChannel(V.Location, Probe, ECC_Visibility, TraceParams);
			RuleViewers.Add(RV);
		}
		const float Score = MSRules::ScoreSpawnPointMulti(RuleViewers.GetData(), RuleViewers.Num(), MSRules::FVec3(Location.X, Location.Y, 0.f), P);
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
				Best.Rotation = FRotator(0.f, (Viewers[0].Location - Location).Rotation().Yaw, 0.f);
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

	const FMSViewer& Anchor = Viewers[FMath::RandRange(0, Viewers.Num() - 1)];
	if (Kind == EMSSpawnKind::Air)
	{
		// Behind a player, high up.
		for (int32 I = 0; I < 8; ++I)
		{
			const float Yaw = Anchor.Rotation.Yaw + 180.f + FMath::FRandRange(-70.f, 70.f);
			Evaluate(Anchor.Location + FRotator(0.f, Yaw, 0.f).Vector() * P.PreferredDistance + FVector(0, 0, 2500.f), nullptr);
		}
		return Best;
	}
	if (UNavigationSystemV1* Nav = FNavigationSystem::GetCurrent<UNavigationSystemV1>(World))
	{
		for (int32 I = 0; I < 24; ++I)
		{
			FNavLocation Out;
			if (Nav->GetRandomReachablePointInRadius(Anchor.Location - FVector(0, 0, 150.f), P.MaxDistance, Out))
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
	const TArray<FMSViewer> Viewers = GatherViewers();
	if (Viewers.Num() == 0)
	{
		return nullptr;
	}
	const UMSDataSubsystem* Data = UMSDataSubsystem::Get(this);
	const FMSGameRulesRow& Rules = Data->GetRules();
	const AMSGameState* GS = GetGameState<AMSGameState>();
	const EMSSpawnKind SpawnKind = Kind == MSRules::Helicopter ? EMSSpawnKind::Air : EMSSpawnKind::Ground;

	TArray<AMSSpawnPoint*> Points;
	for (AMSSpawnPoint* P : SpawnPoints)
	{
		Points.Add(P);
	}
	const FMSSpawnChoice Choice = ChooseSpawn(World, Viewers, Points, SpawnKind, GS ? GS->Wave : 1, Rules, true);
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
	GS->PlayersInMatch = FMath::Max(1, GetNumPlayers());

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

void AMSGameMode::OnPlayerDowned(AMSPlayerCharacter* Player)
{
	// MW3 rule: if nobody is left standing, it's over (solo last stand counts as standing: it self-revives).
	if (!bGameOver && Player && !Player->CanSelfRevive() && MSRules::IsTeamWiped(CountStandingPlayers(Player)))
	{
		EndMatch();
	}
}

void AMSGameMode::OnPlayerKilled(AMSPlayerCharacter* Player, const FMSDamageInfo& KillingBlow)
{
	if (bGameOver)
	{
		return;
	}
	if (!MSRules::IsTeamWiped(CountStandingPlayers(Player)))
	{
		// Co-op: watch a teammate until the next break brings you back.
		APlayerController* PC = Player ? Cast<APlayerController>(Player->GetController()) : nullptr;
		for (FConstPlayerControllerIterator It = GetWorld()->GetPlayerControllerIterator(); It; ++It)
		{
			AMSPlayerCharacter* Mate = It->Get() ? It->Get()->GetPawn<AMSPlayerCharacter>() : nullptr;
			if (PC && Mate && Mate != Player && !Mate->IsDead())
			{
				PC->SetViewTargetWithBlend(Mate, 1.5f);
				break;
			}
		}
		return;
	}
	EndMatch();
}

void AMSGameMode::EndMatch()
{
	if (bGameOver)
	{
		return;
	}
	bGameOver = true;
	AMSGameState* GS = GetGameState<AMSGameState>();
	if (GS)
	{
		GS->Phase = EMSMatchPhase::GameOver;
	}
	const float Delay = UMSDataSubsystem::Get(this)->GetRules().GameOverDelay;
	for (FConstPlayerControllerIterator It = GetWorld()->GetPlayerControllerIterator(); It; ++It)
	{
		AMSPlayerController* PC = Cast<AMSPlayerController>(It->Get());
		const AMSPlayerState* PS = PC ? PC->GetPlayerState<AMSPlayerState>() : nullptr;
		if (!PC)
		{
			continue;
		}
		FMSGameOverStats Stats;
		Stats.WaveReached = GS ? GS->Wave : 0;
		Stats.Kills = PS ? PS->Kills : 0;
		Stats.Headshots = PS ? PS->Headshots : 0;
		Stats.CashEarned = PS ? PS->CashEarned : 0;
		Stats.TimeSurvived = GS ? static_cast<float>(GetWorld()->GetTimeSeconds() - GS->MatchStartTime) : 0.f;
		if (GS)
		{
			GS->FinalStats = Stats;
		}
		TWeakObjectPtr<AMSPlayerController> WeakPC(PC);
		FTimerHandle Handle;
		GetWorldTimerManager().SetTimer(Handle, FTimerDelegate::CreateLambda([WeakPC, Stats]()
		{
			if (WeakPC.IsValid())
			{
				WeakPC->ClientGameOver(Stats);   // each machine saves its own best wave
			}
		}), FMath::Max(0.1f, Delay), false);
	}
}

void AMSGameMode::RespawnDeadPlayers()
{
	if (!UMSDataSubsystem::Get(this)->GetRules().bRespawnDeadAtIntermission)
	{
		return;
	}
	for (FConstPlayerControllerIterator It = GetWorld()->GetPlayerControllerIterator(); It; ++It)
	{
		APlayerController* PC = It->Get();
		AMSPlayerCharacter* Old = PC ? PC->GetPawn<AMSPlayerCharacter>() : nullptr;
		if (!PC || (Old && !Old->IsDead()))
		{
			continue;
		}
		if (Old)
		{
			PC->UnPossess();
			Old->SetLifeSpan(5.f);
		}
		RestartPlayer(PC);   // fresh pawn at a PlayerStart with the starting loadout; cash is kept
	}
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
