#include "Player/MSPlayerState.h"

#include "Engine/World.h"

void AMSPlayerState::AddCash(int32 Amount, const FText& Reason)
{
	if (Amount == 0)
	{
		return;
	}
	Cash = FMath::Max(0, Cash + Amount);
	if (Amount > 0)
	{
		CashEarned += Amount;
	}
	FMSCashEvent Event;
	Event.Amount = Amount;
	Event.Reason = Reason;
	Event.Time = GetWorld() ? GetWorld()->GetTimeSeconds() : 0.0;
	RecentCash.Add(Event);
	if (RecentCash.Num() > 6)
	{
		RecentCash.RemoveAt(0);
	}
}

bool AMSPlayerState::TrySpend(int32 Amount)
{
	if (Amount < 0 || Cash < Amount)
	{
		return false;
	}
	Cash -= Amount;
	CashSpent += Amount;
	return true;
}
