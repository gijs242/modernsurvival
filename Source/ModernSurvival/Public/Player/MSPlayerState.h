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

/** Cash and stats. The HUD reads RecentCash for the "+100 / Headshot +50" popups. */
UCLASS()
class MODERNSURVIVAL_API AMSPlayerState : public APlayerState
{
	GENERATED_BODY()

public:
	UFUNCTION(BlueprintCallable, Category = "Cash") void AddCash(int32 Amount, const FText& Reason);
	/** Returns false (and changes nothing) if the player can't afford it. */
	UFUNCTION(BlueprintCallable, Category = "Cash") bool TrySpend(int32 Amount);
	UFUNCTION(BlueprintPure, Category = "Cash") int32 GetCash() const { return Cash; }

	void RecordKill(bool bHeadshot, bool bMelee) { ++Kills; Headshots += bHeadshot ? 1 : 0; MeleeKills += bMelee ? 1 : 0; }
	void RecordShotHit() { ++ShotsHit; }

	UPROPERTY(BlueprintReadOnly, Category = "Stats") int32 Kills = 0;
	UPROPERTY(BlueprintReadOnly, Category = "Stats") int32 Headshots = 0;
	UPROPERTY(BlueprintReadOnly, Category = "Stats") int32 MeleeKills = 0;
	UPROPERTY(BlueprintReadOnly, Category = "Stats") int32 ShotsHit = 0;
	UPROPERTY(BlueprintReadOnly, Category = "Stats") int32 CashEarned = 0;
	UPROPERTY(BlueprintReadOnly, Category = "Stats") int32 CashSpent = 0;

	const TArray<FMSCashEvent>& GetRecentCash() const { return RecentCash; }

private:
	UPROPERTY(VisibleAnywhere, Category = "Cash") int32 Cash = 0;
	TArray<FMSCashEvent> RecentCash;
};
