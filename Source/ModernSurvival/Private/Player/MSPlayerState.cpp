#include "Player/MSPlayerState.h"

#include "Engine/World.h"
#include "GameFramework/PlayerController.h"
#include "Net/UnrealNetwork.h"

void AMSPlayerState::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const
{
	Super::GetLifetimeReplicatedProps(OutLifetimeProps);
	DOREPLIFETIME(AMSPlayerState, Cash);
	DOREPLIFETIME(AMSPlayerState, Kills);
	DOREPLIFETIME(AMSPlayerState, Headshots);
	DOREPLIFETIME(AMSPlayerState, MeleeKills);
	DOREPLIFETIME(AMSPlayerState, CashEarned);
	DOREPLIFETIME(AMSPlayerState, CashSpent);
}

void AMSPlayerState::GiveStartingCash(int32 Amount)
{
	if (!bStartingCashGiven && HasAuthority())
	{
		bStartingCashGiven = true;
		AddCash(Amount, NSLOCTEXT("MS", "StartCash", "Starting cash"));
	}
}

void AMSPlayerState::AddCash(int32 Amount, const FText& Reason)
{
	if (Amount == 0 || !HasAuthority())
	{
		return;
	}
	Cash = FMath::Max(0, Cash + Amount);
	if (Amount > 0)
	{
		CashEarned += Amount;
	}
	const APlayerController* PC = Cast<APlayerController>(GetOwner());
	if (PC && PC->IsLocalController())
	{
		PushCashEvent(Amount, Reason);
	}
	else
	{
		ClientCashEvent(Amount, Reason);
	}
}

void AMSPlayerState::ClientCashEvent_Implementation(int32 Amount, const FText& Reason)
{
	PushCashEvent(Amount, Reason);
}

void AMSPlayerState::PushCashEvent(int32 Amount, const FText& Reason)
{
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
	if (!HasAuthority() || Amount < 0 || Cash < Amount)
	{
		return false;
	}
	Cash -= Amount;
	CashSpent += Amount;
	return true;
}
