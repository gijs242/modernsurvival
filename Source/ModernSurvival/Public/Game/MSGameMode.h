#pragma once

#include "CoreMinimal.h"
#include "GameFramework/GameModeBase.h"
#include "Combat/MSCombatTypes.h"
#include "Core/MSRules.h"
#include "Game/MSSpawnPoint.h"
#include "MSGameMode.generated.h"

class AMSPlayerCharacter;
class UMSHealthComponent;
class AMSSpawnPoint;

/** A player's point of view for spawn checks. */
struct FMSViewer
{
	FVector Location = FVector::ZeroVector;
	FRotator Rotation = FRotator::ZeroRotator;
	float HalfFOV = 45.f;
};

/** Result of picking a spawn location (exposed for tests). */
struct FMSSpawnChoice
{
	bool bValid = false;
	FVector Location = FVector::ZeroVector;
	FRotator Rotation = FRotator::ZeroRotator;
	TWeakObjectPtr<AMSSpawnPoint> Point;
	float Score = -1.f;
};

/**
 * Wave survival rules: 30 s skippable break, then a wave built from DT_Waves (extrapolated past
 * the last row), enemies trickled in at out-of-view spawn points up to MaxAlive, cash per kill,
 * wave clear bonus, game over when the player dies (after their last stand).
 *
 * Co-op (listen server, up to GameSession MaxPlayers): waves scale with players, spawns must be
 * hidden from every player, downed players are revived by teammates, the dead respawn at the next
 * break, and the game ends when nobody is left standing.
 */
UCLASS()
class MODERNSURVIVAL_API AMSGameMode : public AGameModeBase
{
	GENERATED_BODY()

public:
	AMSGameMode();

	virtual void StartPlay() override;
	virtual void Tick(float DeltaSeconds) override;
	virtual void HandleStartingNewPlayer_Implementation(APlayerController* NewPlayer) override;
	virtual void Logout(AController* Exiting) override;

	void RequestSkipIntermission();
	/** Co-op ready-up: the break is skipped once every living player is ready. */
	void SetPlayerReady(AController* Player, bool bReady);
	void OnPlayerDowned(AMSPlayerCharacter* Player);
	void OnPlayerKilled(AMSPlayerCharacter* Player, const FMSDamageInfo& KillingBlow);
	/** Spawns the AI squad near the player. Returns how many spawned. */
	int32 SpawnSquad(AMSPlayerCharacter* Caller, FName EquipmentRow);

	void DebugKillAll(APawn* Killer);
	void DebugSetWave(int32 Wave);

	/** Wave definition for any wave number (table row or endless extrapolation). */
	static MSRules::FWave BuildWave(const UObject* WorldContext, int32 Wave, struct FMSWaveRow& OutRow);

	/**
	 * Picks the best spawn: outside the viewer's view cone (or occluded), within the distance band,
	 * off cooldown. Falls back to random navmesh points around the viewer if no spawn point works.
	 */
	static FMSSpawnChoice ChooseSpawn(UWorld* World, const TArray<FMSViewer>& Viewers,
		const TArray<AMSSpawnPoint*>& Points, EMSSpawnKind Kind, int32 Wave, const struct FMSGameRulesRow& Rules, bool bAllowNavFallback);

	/** Players currently on their feet (alive and not downed). */
	int32 CountStandingPlayers(const AMSPlayerCharacter* Ignore = nullptr) const;
	int32 CountActivePlayers() const;

protected:
	void BeginIntermission(float Duration);
	void BeginWave(int32 Wave);
	bool SpawnNext();
	AActor* SpawnEnemy(MSRules::EEnemyKind Kind);
	void EndWave();
	void UpdateStragglers();
	void TrackCorpse(AActor* Corpse);
	FName RowForKind(MSRules::EEnemyKind Kind) const;
	void EndMatch();
	void RespawnDeadPlayers();
	TArray<FMSViewer> GatherViewers() const;

	UFUNCTION() void HandleEnemyDied(UMSHealthComponent* Health, const FMSDamageInfo& KillingBlow);

	UPROPERTY(Transient) TArray<TObjectPtr<AMSSpawnPoint>> SpawnPoints;
	UPROPERTY(Transient) TArray<TObjectPtr<AActor>> AliveEnemies;
	UPROPERTY(Transient) TArray<TObjectPtr<AActor>> Corpses;

	MSRules::FWave CurrentWave;
	TArray<int32> SpawnQueue;
	int32 QueueIndex = 0;
	float SpawnTimer = 0.f;
	double LastKillTime = 0.0;
	bool bGameOver = false;
	TMap<TObjectPtr<AActor>, int32> RewardByEnemy;
	TMap<TObjectPtr<AActor>, FName> RowByEnemy;
	FName WaveRows[MSRules::EnemyKindCount];
	float WaveHealthMul = 1.f;
	float WaveDamageMul = 1.f;
	float WaveAccuracyMul = 1.f;
	TSet<TWeakObjectPtr<AController>> ReadyPlayers;
};
