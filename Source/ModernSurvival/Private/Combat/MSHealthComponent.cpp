#include "Combat/MSHealthComponent.h"

#include "Combat/MSCombatSubsystem.h"
#include "Core/MSRules.h"
#include "Engine/World.h"
#include "GameFramework/Actor.h"
#include "GameFramework/Controller.h"
#include "Net/UnrealNetwork.h"

UMSHealthComponent::UMSHealthComponent()
{
	PrimaryComponentTick.bCanEverTick = true;
	PrimaryComponentTick.TickInterval = 0.05f;
	SetIsReplicatedByDefault(true);
}

void UMSHealthComponent::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const
{
	Super::GetLifetimeReplicatedProps(OutLifetimeProps);
	DOREPLIFETIME(UMSHealthComponent, Team);
	DOREPLIFETIME(UMSHealthComponent, MaxHealth);
	DOREPLIFETIME(UMSHealthComponent, Health);
	DOREPLIFETIME(UMSHealthComponent, Armor);
	DOREPLIFETIME(UMSHealthComponent, MaxArmor);
	DOREPLIFETIME(UMSHealthComponent, bDead);
}

bool UMSHealthComponent::HasAuthorityOver() const
{
	const AActor* Owner = GetOwner();
	return Owner && Owner->HasAuthority();
}

void UMSHealthComponent::OnRep_Dead()
{
	if (bDead)
	{
		FMSDamageInfo Info;
		Info.SourceTeam = EMSTeam::Neutral;
		OnDied.Broadcast(this, Info);
	}
}

UMSHealthComponent* UMSHealthComponent::Find(const AActor* Actor)
{
	// Walk up the owner chain so hitting a weapon or attached part still damages its owner.
	for (const AActor* A = Actor; A; A = A->GetOwner())
	{
		if (UMSHealthComponent* H = A->FindComponentByClass<UMSHealthComponent>())
		{
			return H;
		}
		if (const AActor* Attach = A->GetAttachParentActor())
		{
			if (UMSHealthComponent* H = Attach->FindComponentByClass<UMSHealthComponent>())
			{
				return H;
			}
		}
	}
	return nullptr;
}

void UMSHealthComponent::BeginPlay()
{
	Super::BeginPlay();
	if (UMSCombatSubsystem* Combat = UMSCombatSubsystem::Get(this))
	{
		Combat->Register(this);
	}
}

void UMSHealthComponent::EndPlay(const EEndPlayReason::Type Reason)
{
	if (UMSCombatSubsystem* Combat = UMSCombatSubsystem::Get(this))
	{
		Combat->Unregister(this);
	}
	Super::EndPlay(Reason);
}

float UMSHealthComponent::GetTimeSinceDamage() const
{
	const UWorld* World = GetWorld();
	return World ? static_cast<float>(World->GetTimeSeconds() - LastDamageTime) : 1000.f;
}

float UMSHealthComponent::GetRecentDamage(float Window) const
{
	const UWorld* World = GetWorld();
	if (!World)
	{
		return 0.f;
	}
	const double Now = World->GetTimeSeconds();
	float Sum = 0.f;
	for (const FRecentHit& Hit : RecentHits)
	{
		if (Now - Hit.Time <= Window)
		{
			Sum += Hit.Amount;
		}
	}
	return Sum;
}

FMSHitReport UMSHealthComponent::ApplyDamage(const FMSDamageInfo& InInfo)
{
	FMSHitReport Report;
	if (bDead || InInfo.Amount <= 0.f || !HasAuthorityOver())
	{
		return Report;   // damage is only ever applied on the server
	}

	// Friendly fire: same team never hurts unless it is self-damage from your own explosive.
	const AActor* InstigatorPawn = InInfo.Instigator ? InInfo.Instigator->GetPawn() : nullptr;
	const bool bSelf = InstigatorPawn && InstigatorPawn == GetOwner();
	if (!bSelf && !bAllowFriendlyFire && InInfo.SourceTeam == Team && Team != EMSTeam::Neutral)
	{
		return Report;
	}

	Report.bHitDamageable = true;
	Report.bHeadshot = InInfo.bHeadshot;
	if (bInvulnerable)
	{
		return Report;
	}

	float Amount = InInfo.Amount;
	if (InInfo.bHeadshot)
	{
		// The weapon already multiplied for the headshot; HeadshotScale dampens it for armored heads.
		Amount = Amount * HeadshotScale;
	}
	if (InInfo.Kind == EMSDamageKind::Explosive)
	{
		Amount *= ExplosiveScale;
	}
	if (bSelf)
	{
		Amount *= SelfDamageScale;
	}
	Amount *= (1.f - FMath::Clamp(DamageReduction, 0.f, 0.95f));

	const float ArmorBefore = Armor;
	const float HealthDamage = MSRules::ApplyArmor(Amount, Armor, ArmorAbsorb);
	const float ArmorDamage = ArmorBefore - Armor;
	Report.bArmorHit = ArmorDamage > 0.f;
	if (ArmorBefore > 0.f && Armor <= 0.f)
	{
		OnArmorBroken.Broadcast(this);
	}

	if (const UWorld* World = GetWorld())
	{
		LastDamageTime = World->GetTimeSeconds();
		RecentHits.Add({LastDamageTime, HealthDamage + ArmorDamage});
		if (RecentHits.Num() > 32)
		{
			RecentHits.RemoveAt(0, RecentHits.Num() - 32);
		}
	}

	if (Health - HealthDamage <= 0.f && LethalDamageInterceptor.IsBound() && LethalDamageInterceptor.Execute(InInfo))
	{
		// Owner took over (e.g. entered last stand and reset health). Still report the hit.
		Report.HealthDamage = HealthDamage;
		OnDamaged.Broadcast(this, InInfo, HealthDamage, ArmorDamage);
		return Report;
	}

	Health = FMath::Max(0.f, Health - HealthDamage);
	Report.HealthDamage = HealthDamage;
	OnDamaged.Broadcast(this, InInfo, HealthDamage, ArmorDamage);

	if (Health <= 0.f)
	{
		bDead = true;
		Report.bKilled = true;
		OnDied.Broadcast(this, InInfo);
	}
	return Report;
}

void UMSHealthComponent::SetMaxHealth(float NewMax, bool bFill)
{
	MaxHealth = FMath::Max(1.f, NewMax);
	Health = bFill ? MaxHealth : FMath::Min(Health, MaxHealth);
}

void UMSHealthComponent::SetHealth(float NewHealth)
{
	Health = FMath::Clamp(NewHealth, 0.f, MaxHealth);
}

void UMSHealthComponent::AddArmor(float Amount, float Cap)
{
	MaxArmor = FMath::Max(MaxArmor, Cap);
	Armor = FMath::Clamp(Armor + Amount, 0.f, Cap);
}

void UMSHealthComponent::Kill(const FMSDamageInfo& Info)
{
	if (bDead)
	{
		return;
	}
	Health = 0.f;
	bDead = true;
	OnDied.Broadcast(this, Info);
}

void UMSHealthComponent::Revive(float NewHealth)
{
	bDead = false;
	Health = FMath::Clamp(NewHealth, 1.f, MaxHealth);
	LastDamageTime = GetWorld() ? GetWorld()->GetTimeSeconds() : 0.0;
}

void UMSHealthComponent::TickComponent(float DeltaTime, ELevelTick TickType, FActorComponentTickFunction* ThisTickFunction)
{
	Super::TickComponent(DeltaTime, TickType, ThisTickFunction);
	if (!bDead && RegenRate > 0.f && Health < MaxHealth && HasAuthorityOver())
	{
		Health = MSRules::RegenStep(Health, MaxHealth, GetTimeSinceDamage(), RegenDelay, RegenRate, DeltaTime);
	}
}
