#include "Game/MSGameState.h"

#include "Combat/MSCombatLibrary.h"
#include "Engine/World.h"
#include "Net/UnrealNetwork.h"

void AMSGameState::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const
{
	Super::GetLifetimeReplicatedProps(OutLifetimeProps);
	DOREPLIFETIME(AMSGameState, Phase);
	DOREPLIFETIME(AMSGameState, Wave);
	DOREPLIFETIME(AMSGameState, EnemiesRemaining);
	DOREPLIFETIME(AMSGameState, EnemiesAlive);
	DOREPLIFETIME(AMSGameState, PhaseEndTime);
	DOREPLIFETIME(AMSGameState, MatchStartTime);
	DOREPLIFETIME(AMSGameState, bRevealStragglers);
	DOREPLIFETIME(AMSGameState, WaveBannerTime);
	DOREPLIFETIME(AMSGameState, bLastBannerWasClear);
	DOREPLIFETIME(AMSGameState, PlayersReady);
	DOREPLIFETIME(AMSGameState, PlayersInMatch);
}

float AMSGameState::GetPhaseTimeLeft() const
{
	return FMath::Max(0.f, static_cast<float>(PhaseEndTime - GetServerWorldTimeSeconds()));
}

void AMSGameState::MulticastExplosionFX_Implementation(FVector_NetQuantize Location, float Radius, UNiagaraSystem* FX, USoundBase* Sound, float Trauma, float TraumaRadius)
{
	UMSCombatLibrary::PlayExplosionCosmetics(GetWorld(), Location, Radius, FX, Sound, Trauma, TraumaRadius);
}
