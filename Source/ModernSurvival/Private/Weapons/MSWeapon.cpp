#include "Weapons/MSWeapon.h"

#include "Audio/MSAudioSubsystem.h"
#include "Combat/MSCombatLibrary.h"
#include "Core/MSRules.h"
#include "Data/MSDataSubsystem.h"
#include "FX/MSFXLibrary.h"
#include "ModernSurvival.h"
#include "Perception/AISense_Hearing.h"
#include "Weapons/MSProjectile.h"
#include "Weapons/MSWeaponHolder.h"
#include "Weapons/MSWeaponVisualComponent.h"
#include "Components/PrimitiveComponent.h"
#include "Engine/World.h"
#include "GameFramework/Controller.h"
#include "GameFramework/Pawn.h"

AMSWeapon::AMSWeapon()
{
	PrimaryActorTick.bCanEverTick = true;
	PrimaryActorTick.TickGroup = TG_PrePhysics;
	SetRootComponent(CreateDefaultSubobject<USceneComponent>(TEXT("Root")));
	Visual = CreateDefaultSubobject<UMSWeaponVisualComponent>(TEXT("Visual"));
	Visual->SetupAttachment(GetRootComponent());
	VisualClass = UMSWeaponVisualComponent::StaticClass();
	SetActorEnableCollision(false);
}

IMSWeaponHolder* AMSWeapon::GetHolder() const
{
	return Holder ? Cast<IMSWeaponHolder>(Holder) : nullptr;
}

void AMSWeapon::Setup(FName InRowName, AActor* InHolder, bool bInFirstPerson)
{
	RowName = InRowName;
	Holder = InHolder;
	bFirstPerson = bInFirstPerson;
	SetOwner(InHolder);
	if (APawn* Pawn = Cast<APawn>(InHolder))
	{
		SetInstigator(Pawn);
	}

	const UMSDataSubsystem* Data = UMSDataSubsystem::Get(this);
	const FMSWeaponRow* Found = Data ? Data->FindWeapon(RowName) : nullptr;
	Row = Found ? *Found : FMSWeaponRow();
	if (!Found)
	{
		UE_LOG(LogMS, Warning, TEXT("Weapon row %s not found; using defaults."), *RowName.ToString());
	}

	if (VisualClass && Visual && Visual->GetClass() != VisualClass)
	{
		Visual->DestroyComponent();
		Visual = NewObject<UMSWeaponVisualComponent>(this, VisualClass, TEXT("VisualOverride"));
		Visual->SetupAttachment(GetRootComponent());
		Visual->RegisterComponent();
	}
	Visual->BuildVisual(Row, bFirstPerson);
	FillAmmo();
}

void AMSWeapon::FillAmmo()
{
	AmmoInMag = Row.MagazineSize;
	AmmoReserve = Row.MaxReserveAmmo;
}

void AMSWeapon::AddReserveAmmo(int32 Amount)
{
	AmmoReserve = FMath::Clamp(AmmoReserve + Amount, 0, Row.MaxReserveAmmo);
}

void AMSWeapon::BlockFiring(float Seconds)
{
	FireBlockedFor = FMath::Max(FireBlockedFor, Seconds);
}

void AMSWeapon::SetEquipped(bool bInEquipped)
{
	bEquipped = bInEquipped;
	SetActorHiddenInGame(!bInEquipped);
	if (bInEquipped)
	{
		EquipTimeLeft = Row.EquipTime;
	}
	else
	{
		CancelReload();
		SetTriggerHeld(false);
	}
}

void AMSWeapon::SetTriggerHeld(bool bHeld)
{
	if (bHeld && !bTriggerHeld)
	{
		bTriggerConsumed = false;
		if (Row.FireMode == EMSFireMode::Burst)
		{
			BurstShotsLeft = Row.BurstCount;
		}
	}
	bTriggerHeld = bHeld;
}

bool AMSWeapon::CanFire() const
{
	return bEquipped && !bReloading && EquipTimeLeft <= 0.f && FireBlockedFor <= 0.f && AmmoInMag > 0;
}

float AMSWeapon::GetReloadProgress() const
{
	return bReloading && ReloadDuration > 0.f ? FMath::Clamp(ReloadElapsed / ReloadDuration, 0.f, 1.f) : 0.f;
}

bool AMSWeapon::StartReload()
{
	const IMSWeaponHolder* H = GetHolder();
	const bool bInfinite = H && H->HasInfiniteAmmo();
	if (bReloading || !bEquipped || AmmoInMag >= Row.MagazineSize || (AmmoReserve <= 0 && !bInfinite))
	{
		return false;
	}
	bReloading = true;
	ReloadElapsed = 0.f;
	ReloadDuration = Row.bReloadPerShell ? Row.ReloadPerShellTime : (AmmoInMag == 0 ? Row.ReloadEmptyTime : Row.ReloadTime);
	OnReloadStarted.Broadcast();
	if (UMSAudioSubsystem* Audio = GetWorld()->GetSubsystem<UMSAudioSubsystem>())
	{
		USoundBase* Sound = Row.ReloadSound.LoadSynchronous();
		if (H && H->IsLocalPlayerHolder())
		{
			Audio->Play2D(Sound, 0.7f);
		}
		else
		{
			Audio->PlayAt(GetActorLocation(), Sound, 0.8f);
		}
	}
	return true;
}

void AMSWeapon::CancelReload()
{
	bReloading = false;
	ReloadElapsed = 0.f;
}

void AMSWeapon::FinishReload()
{
	const IMSWeaponHolder* H = GetHolder();
	const bool bInfinite = H && H->HasInfiniteAmmo();
	if (Row.bReloadPerShell)
	{
		if (bInfinite || AmmoReserve > 0)
		{
			++AmmoInMag;
			if (!bInfinite)
			{
				--AmmoReserve;
			}
		}
		// Keep loading shells until full, out of ammo, or the player pulls the trigger.
		if (AmmoInMag < Row.MagazineSize && (bInfinite || AmmoReserve > 0) && !bTriggerHeld)
		{
			ReloadElapsed = 0.f;
			ReloadDuration = Row.ReloadPerShellTime;
			return;
		}
	}
	else
	{
		const int32 Needed = Row.MagazineSize - AmmoInMag;
		const int32 Taken = bInfinite ? Needed : FMath::Min(Needed, AmmoReserve);
		AmmoInMag += Taken;
		if (!bInfinite)
		{
			AmmoReserve -= Taken;
		}
	}
	bReloading = false;
	OnReloadFinished.Broadcast();
}

float AMSWeapon::GetCurrentSpread() const
{
	const IMSWeaponHolder* H = GetHolder();
	const float ADS = H ? H->GetADSAlpha() : 0.f;
	const float Base = FMath::Lerp(Row.HipSpread, Row.ADSSpread, ADS);
	const float Move = H ? H->GetMoveSpreadFraction() : 0.f;
	const bool bAir = H && H->IsAirborne();
	const float Spread = MSRules::CurrentSpread(Base, Row.MoveSpreadAdd * (1.f - 0.7f * ADS), Move, Bloom * (1.f - 0.5f * ADS), Row.AirSpreadAdd, bAir, Row.MaxSpread);
	return Spread + (H ? H->GetExtraSpreadDegrees() : 0.f);
}

FTransform AMSWeapon::GetMuzzleTransform() const
{
	return Visual ? Visual->GetMuzzleTransform() : GetActorTransform();
}

void AMSWeapon::Tick(float DeltaSeconds)
{
	Super::Tick(DeltaSeconds);
	const UWorld* World = GetWorld();
	const double Now = World->GetTimeSeconds();

	EquipTimeLeft = FMath::Max(0.f, EquipTimeLeft - DeltaSeconds);
	FireBlockedFor = FMath::Max(0.f, FireBlockedFor - DeltaSeconds);
	Bloom = FMath::Max(0.f, Bloom - Row.SpreadRecovery * DeltaSeconds);
	if (Now - LastFireTime > FMath::Max(0.25, MSRules::FireInterval(Row.RoundsPerMinute) * 2.5))
	{
		ShotIndex = 0;
	}

	if (bReloading)
	{
		ReloadElapsed += DeltaSeconds;
		if (ReloadElapsed >= ReloadDuration)
		{
			FinishReload();
		}
		// Shotguns: pulling the trigger mid-reload fires the shells you have.
		if (bReloading && Row.bReloadPerShell && bTriggerHeld && AmmoInMag > 0)
		{
			CancelReload();
		}
		return;
	}

	if (!bTriggerHeld || !bEquipped)
	{
		return;
	}
	if (AmmoInMag <= 0)
	{
		if (!bTriggerConsumed)
		{
			bTriggerConsumed = true;
			OnDryFire.Broadcast();
			if (UMSAudioSubsystem* Audio = World->GetSubsystem<UMSAudioSubsystem>())
			{
				Audio->Play2D(Row.DryFireSound.LoadSynchronous(), 0.6f);
			}
			StartReload();
		}
		return;
	}
	if (!CanFire() || Now < NextFireTime)
	{
		return;
	}
	const bool bSemi = Row.FireMode == EMSFireMode::Semi;
	const bool bBurst = Row.FireMode == EMSFireMode::Burst;
	if ((bSemi && bTriggerConsumed) || (bBurst && BurstShotsLeft <= 0))
	{
		return;
	}
	FireShot();
	NextFireTime = Now + MSRules::FireInterval(Row.RoundsPerMinute);
	if (bSemi)
	{
		bTriggerConsumed = true;
	}
	if (bBurst)
	{
		--BurstShotsLeft;
	}
}

void AMSWeapon::FireShot()
{
	IMSWeaponHolder* H = GetHolder();
	UWorld* World = GetWorld();
	if (!H || !World)
	{
		return;
	}
	FVector Start, Dir;
	H->GetAimRay(Start, Dir);
	const float Spread = GetCurrentSpread();

	if (!H->HasInfiniteAmmo() || Row.MagazineSize < 9999)
	{
		--AmmoInMag;
	}
	LastFireTime = World->GetTimeSeconds();
	++TotalShots;

	if (Row.bProjectile)
	{
		FireProjectile(Start, Dir, Spread);
	}
	else
	{
		FireHitscan(Start, Dir, Spread);
	}

	const FTransform Muzzle = GetMuzzleTransform();
	UMSFXLibrary::SpawnMuzzleFlash(World, Muzzle, Row.MuzzleFlashFX.LoadSynchronous(), Row.MuzzleLightIntensity, bFirstPerson ? Visual.Get() : nullptr);
	if (Visual)
	{
		Visual->PlayFireAnim();
	}
	if (UMSAudioSubsystem* Audio = World->GetSubsystem<UMSAudioSubsystem>())
	{
		Audio->PlayGunshot(Muzzle.GetLocation(), Row, H->IsLocalPlayerHolder());
	}
	// AI hearing: gunfire is loud.
	UAISense_Hearing::ReportNoiseEvent(World, Muzzle.GetLocation(), 1.f, GetInstigator() ? Cast<AActor>(GetInstigator()) : Holder.Get(), 6000.f, TEXT("Gunshot"));

	Bloom = FMath::Min(Row.MaxSpread, Bloom + Row.SpreadPerShot);
	H->OnWeaponFired(Row, ShotIndex);
	++ShotIndex;
	OnFired.Broadcast();

	if (AmmoInMag <= 0 && !H->IsLocalPlayerHolder())
	{
		StartReload();
	}
}

static FVector RandomInCone(const FVector& Dir, float HalfAngleDeg)
{
	if (HalfAngleDeg <= 0.f)
	{
		return Dir;
	}
	// Gaussian-ish: most shots near the centre, which feels better than uniform.
	const float R = FMath::Sqrt(FMath::FRand()) * FMath::FRandRange(0.5f, 1.f);
	const float Angle = FMath::DegreesToRadians(HalfAngleDeg) * R;
	const float Theta = FMath::FRandRange(0.f, 2.f * PI);
	const FVector Up = FMath::Abs(Dir.Z) < 0.99f ? FVector::UpVector : FVector::RightVector;
	const FVector Right = FVector::CrossProduct(Dir, Up).GetSafeNormal();
	const FVector Up2 = FVector::CrossProduct(Right, Dir);
	return (Dir * FMath::Cos(Angle) + (Right * FMath::Cos(Theta) + Up2 * FMath::Sin(Theta)) * FMath::Sin(Angle)).GetSafeNormal();
}

void AMSWeapon::FireHitscan(const FVector& Start, const FVector& Direction, float Spread)
{
	UWorld* World = GetWorld();
	IMSWeaponHolder* H = GetHolder();
	const int32 Pellets = FMath::Max(1, Row.PelletCount);
	const FVector ShotDir = RandomInCone(Direction, Spread);
	const FVector MuzzleLoc = GetMuzzleTransform().GetLocation();

	FCollisionQueryParams Params(SCENE_QUERY_STAT(MSWeaponTrace), false, this);
	Params.AddIgnoredActor(Holder);
	Params.bReturnPhysicalMaterial = true;
	TArray<AActor*> HolderChildren;
	if (Holder)
	{
		Holder->GetAttachedActors(HolderChildren);
	}
	Params.AddIgnoredActors(HolderChildren);

	FMSHitReport Combined;
	for (int32 P = 0; P < Pellets; ++P)
	{
		const FVector PelletDir = Pellets > 1 ? RandomInCone(ShotDir, Row.PelletSpread) : ShotDir;
		const FVector End = Start + PelletDir * Row.Range;
		FHitResult Hit;
		const bool bHit = World->LineTraceSingleByChannel(Hit, Start, End, ECC_MSWeapon, Params);
		const FVector ImpactPoint = bHit ? Hit.ImpactPoint : End;

		if (P == 0 && Row.TracerEveryNth > 0 && TotalShots % Row.TracerEveryNth == 0)
		{
			UMSFXLibrary::SpawnTracer(World, MuzzleLoc, ImpactPoint, Row.TracerFX.LoadSynchronous());
		}
		if (!bHit)
		{
			continue;
		}

		AActor* HitActor = Hit.GetActor();
		const bool bHead = UMSCombatLibrary::IsHeadshot(Hit);
		FMSDamageInfo Info;
		Info.Amount = UMSCombatLibrary::ComputeBulletDamage(Row, Hit.Distance, bHead, H ? H->GetWeaponDamageScale() : 1.f);
		Info.Kind = EMSDamageKind::Bullet;
		Info.bHeadshot = bHead;
		Info.HitLocation = Hit.ImpactPoint;
		Info.SourceLocation = Start;
		Info.ImpulseDirection = PelletDir;
		Info.Impulse = Row.ImpactImpulse;
		Info.HitBone = Hit.BoneName;
		Info.Instigator = H ? H->GetHolderController() : nullptr;
		Info.Causer = this;
		Info.SourceTeam = H ? H->GetHolderTeam() : EMSTeam::Neutral;
		const FMSHitReport Report = UMSCombatLibrary::DealDamage(HitActor, Info, Hit.GetComponent());

		UMSFXLibrary::SpawnImpact(World, Hit, Row.ImpactFX.LoadSynchronous(), Report.bHitDamageable);
		if (Report.bHitDamageable)
		{
			Combined.bHitDamageable = true;
			Combined.bKilled |= Report.bKilled;
			Combined.bHeadshot |= Report.bHeadshot;
			Combined.bArmorHit |= Report.bArmorHit;
			Combined.HealthDamage += Report.HealthDamage;
		}
	}
	if (Combined.bHitDamageable && H)
	{
		H->OnWeaponHit(Combined);
	}
}

void AMSWeapon::FireProjectile(const FVector& Start, const FVector& Direction, float Spread)
{
	IMSWeaponHolder* H = GetHolder();
	const FVector Dir = RandomInCone(Direction, Spread);
	// Spawn from the muzzle but aim at what the crosshair points at.
	FVector Target = Start + Dir * 10000.f;
	FHitResult Hit;
	FCollisionQueryParams Params(SCENE_QUERY_STAT(MSProjectileAim), false, this);
	Params.AddIgnoredActor(Holder);
	if (GetWorld()->LineTraceSingleByChannel(Hit, Start, Target, ECC_MSWeapon, Params))
	{
		Target = Hit.ImpactPoint;
	}
	const FVector Muzzle = GetMuzzleTransform().GetLocation();
	const FVector LaunchDir = (Target - Muzzle).GetSafeNormal();
	FActorSpawnParameters SpawnParams;
	SpawnParams.Owner = this;
	SpawnParams.Instigator = GetInstigator();
	SpawnParams.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
	if (AMSProjectile* Projectile = GetWorld()->SpawnActor<AMSProjectile>(Muzzle, LaunchDir.Rotation(), SpawnParams))
	{
		Projectile->Launch(FMSExplosionParams::FromWeapon(Row), LaunchDir * Row.ProjectileSpeed, Row.ProjectileGravityScale,
			H ? H->GetHolderController() : nullptr, H ? H->GetHolderTeam() : EMSTeam::Neutral, Holder);
	}
}
