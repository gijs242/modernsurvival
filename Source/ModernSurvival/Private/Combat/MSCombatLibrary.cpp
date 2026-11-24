#include "Combat/MSCombatLibrary.h"

#include "Audio/MSAudioSubsystem.h"
#include "Combat/MSCombatSubsystem.h"
#include "Combat/MSHealthComponent.h"
#include "Core/MSRules.h"
#include "FX/MSFXLibrary.h"
#include "Player/MSCameraFeelComponent.h"
#include "ModernSurvival.h"
#include "Components/PrimitiveComponent.h"
#include "Engine/OverlapResult.h"
#include "Engine/World.h"
#include "GameFramework/Character.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "GameFramework/Controller.h"

FMSExplosionParams FMSExplosionParams::FromEquipment(const FMSEquipmentRow& Row)
{
	FMSExplosionParams P;
	P.Damage = Row.Damage;
	P.InnerRadius = Row.InnerRadius;
	P.OuterRadius = Row.OuterRadius;
	P.MinDamageFraction = Row.MinDamageFraction;
	P.SelfDamageScale = Row.SelfDamageScale;
	P.Trauma = Row.Trauma;
	P.TraumaRadius = Row.TraumaRadius;
	P.Impulse = Row.Impulse;
	P.Sound = Row.ExplosionSound.LoadSynchronous();
	P.FX = Row.ExplosionFX.LoadSynchronous();
	return P;
}

FMSExplosionParams FMSExplosionParams::FromWeapon(const FMSWeaponRow& Row)
{
	FMSExplosionParams P;
	P.Damage = Row.Damage;
	P.InnerRadius = Row.ExplosionInnerRadius;
	P.OuterRadius = FMath::Max(Row.ExplosionRadius, 1.f);
	P.MinDamageFraction = 0.1f;
	P.SelfDamageScale = 0.5f;
	P.Trauma = Row.ExplosionTrauma;
	P.TraumaRadius = Row.ExplosionRadius * 4.f;
	P.Impulse = Row.ImpactImpulse * 20.f;
	P.FX = Row.ImpactFX.LoadSynchronous();
	P.Sound = Row.ExplosionSound.LoadSynchronous();
	return P;
}

FMSHitReport UMSCombatLibrary::DealDamage(AActor* Target, const FMSDamageInfo& Info, UPrimitiveComponent* HitComponent)
{
	FMSHitReport Report;
	if (!Target)
	{
		return Report;
	}
	if (UMSHealthComponent* Health = UMSHealthComponent::Find(Target))
	{
		Report = Health->ApplyDamage(Info);
	}
	if (Info.Impulse > 0.f && HitComponent && HitComponent->IsSimulatingPhysics())
	{
		HitComponent->AddImpulseAtLocation(Info.ImpulseDirection.GetSafeNormal() * Info.Impulse, Info.HitLocation, Info.HitBone);
	}
	return Report;
}

bool UMSCombatLibrary::IsHeadshot(const FHitResult& Hit)
{
	if (const UPrimitiveComponent* Comp = Hit.GetComponent())
	{
		if (Comp->ComponentHasTag(TEXT("Head")))
		{
			return true;
		}
	}
	return !Hit.BoneName.IsNone() && Hit.BoneName.ToString().Contains(TEXT("head"), ESearchCase::IgnoreCase);
}

float UMSCombatLibrary::ComputeBulletDamage(const FMSWeaponRow& Weapon, float Distance, bool bHeadshot, float DamageScale)
{
	const float Falloff = MSRules::DamageFalloff(Distance, Weapon.FalloffStart, Weapon.FalloffEnd, Weapon.MinDamageFraction);
	return Weapon.Damage * Falloff * (bHeadshot ? Weapon.HeadshotMultiplier : 1.f) * DamageScale;
}

EMSTeam UMSCombatLibrary::GetTeam(const AActor* Actor)
{
	const UMSHealthComponent* H = UMSHealthComponent::Find(Actor);
	return H ? H->GetTeam() : EMSTeam::Neutral;
}

bool UMSCombatLibrary::AreHostile(const AActor* A, const AActor* B)
{
	const EMSTeam TA = GetTeam(A);
	const EMSTeam TB = GetTeam(B);
	return TA != TB && TA != EMSTeam::Neutral && TB != EMSTeam::Neutral;
}

void UMSCombatLibrary::Explode(const UObject* WorldContext, FVector Location, const FMSExplosionParams& Params, AController* Instigator, AActor* Causer, EMSTeam SourceTeam)
{
	UWorld* World = WorldContext ? WorldContext->GetWorld() : nullptr;
	if (!World)
	{
		return;
	}

	UMSFXLibrary::SpawnExplosion(World, Location, Params.OuterRadius, Params.FX);
	if (UMSAudioSubsystem* Audio = World->GetSubsystem<UMSAudioSubsystem>())
	{
		Audio->PlayExplosion(Location, Params.Sound);
	}
	UMSCameraFeelComponent::AddTraumaAtLocation(World, Location, Params.Trauma, Params.TraumaRadius);

	// Gather everything in range once: damageables get damage, physics bodies get pushed.
	TArray<FOverlapResult> Overlaps;
	FCollisionObjectQueryParams ObjectParams;
	ObjectParams.AddObjectTypesToQuery(ECC_Pawn);
	ObjectParams.AddObjectTypesToQuery(ECC_PhysicsBody);
	ObjectParams.AddObjectTypesToQuery(ECC_WorldDynamic);
	FCollisionQueryParams QueryParams(SCENE_QUERY_STAT(MSExplosion), false, Causer);
	World->OverlapMultiByObjectType(Overlaps, Location, FQuat::Identity, ObjectParams, FCollisionShape::MakeSphere(Params.OuterRadius), QueryParams);

	TSet<UMSHealthComponent*> Damaged;
	for (const FOverlapResult& Overlap : Overlaps)
	{
		AActor* Actor = Overlap.GetActor();
		UPrimitiveComponent* Comp = Overlap.GetComponent();
		if (!Actor)
		{
			continue;
		}
		const FVector Center = Comp ? Comp->Bounds.Origin : Actor->GetActorLocation();
		const float Distance = FVector::Dist(Location, Center);

		// Walls block blast damage.
		FCollisionQueryParams LosParams(SCENE_QUERY_STAT(MSExplosionLOS), false, Actor);
		LosParams.AddIgnoredActor(Causer);
		if (World->LineTraceTestByChannel(Location + FVector(0, 0, 20), Center, ECC_Visibility, LosParams))
		{
			continue;
		}

		if (Comp && Comp->IsSimulatingPhysics())
		{
			const float Push = Params.Impulse * FMath::Clamp(1.f - Distance / Params.OuterRadius, 0.f, 1.f);
			Comp->AddRadialImpulse(Location, Params.OuterRadius, Push, RIF_Linear, true);
		}

		UMSHealthComponent* Health = UMSHealthComponent::Find(Actor);
		if (!Health || Damaged.Contains(Health))
		{
			continue;
		}
		Damaged.Add(Health);

		FMSDamageInfo Info;
		Info.Amount = MSRules::RadialDamage(Params.Damage, Distance, Params.InnerRadius, Params.OuterRadius, Params.MinDamageFraction);
		Info.Kind = EMSDamageKind::Explosive;
		Info.HitLocation = Center;
		Info.SourceLocation = Location;
		Info.ImpulseDirection = (Center - Location).GetSafeNormal();
		Info.Impulse = Params.Impulse;
		Info.Instigator = Instigator;
		Info.Causer = Causer;
		Info.SourceTeam = SourceTeam;
		const float OldScale = Health->SelfDamageScale;
		Health->SelfDamageScale = Params.SelfDamageScale;
		Health->ApplyDamage(Info);
		Health->SelfDamageScale = OldScale;

		// Knock characters around a little.
		if (ACharacter* Character = Cast<ACharacter>(Health->GetOwner()))
		{
			const float Push = 600.f * FMath::Clamp(1.f - Distance / Params.OuterRadius, 0.f, 1.f);
			Character->LaunchCharacter(Info.ImpulseDirection * Push + FVector(0, 0, Push * 0.4f), false, false);
		}
	}
}
