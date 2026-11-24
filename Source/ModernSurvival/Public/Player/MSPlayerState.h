#pragma once

#include "CoreMinimal.h"
#include "GameFramework/PlayerState.h"
#include "MSPlayerState.generated.h"

struct FMSCashEvent
{
	int32 Amount = 0;
	FText Reason;
	double Time = 0.0;
};

/**
 * Cash and stats, per player (co-op: each player earns and spends their own cash).
 * Server-authoritative and replicated; the "+100 / Headshot +50" popups reach the owner via ClientCashEvent.
 */
UCLASS()
class MODERNSURVIVAL_API AMSPlayerState : public APlayerState
{
	GENERATED_BODY()

public:
	virtual void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const override;

	/** Server. */
	UFUNCTION(BlueprintCallable, Category = "Cash") void AddCash(int32 Amount, const FText& Reason);
	/** Server. Returns false (and changes nothing) if the player can't afford it. */
	UFUNCTION(BlueprintCallable, Category = "Cash") bool TrySpend(int32 Amount);
	UFUNCTION(BlueprintPure, Category = "Cash") int32 GetCash() const { return Cash; }
	/** Server: once per player per match. */
	void GiveStartingCash(int32 Amount);

	void RecordKill(bool bHeadshot, bool bMelee) { ++Kills; Headshots += bHeadshot ? 1 : 0; MeleeKills += bMelee ? 1 : 0; }

	UPROPERTY(Replicated, BlueprintReadOnly, Category = "Stats") int32 Kills = 0;
	UPROPERTY(Replicated, BlueprintReadOnly, Category = "Stats") int32 Headshots = 0;
	UPROPERTY(Replicated, BlueprintReadOnly, Category = "Stats") int32 MeleeKills = 0;
	UPROPERTY(Replicated, BlueprintReadOnly, Category = "Stats") int32 CashEarned = 0;
	UPROPERTY(Replicated, BlueprintReadOnly, Category = "Stats") int32 CashSpent = 0;

	const TArray<FMSCashEvent>& GetRecentCash() const { return RecentCash; }

protected:
	UFUNCTION(Client, Unreliable) void ClientCashEvent(int32 Amount, const FText& Reason);
	void PushCashEvent(int32 Amount, const FText& Reason);

private:
	UPROPERTY(Replicated, VisibleAnywhere, Category = "Cash") int32 Cash = 0;
	bool bStartingCashGiven = false;
	TArray<FMSCashEvent> RecentCash;
};
