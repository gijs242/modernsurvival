#include "AI/MSAttackHelicopter.h"

#include "Combat/MSCombatLibrary.h"
#include "Combat/MSCombatSubsystem.h"
#include "Combat/MSHealthComponent.h"
#include "Data/MSDataSubsystem.h"
#include "FX/MSFXLibrary.h"
#include "ModernSurvival.h"
#include "Weapons/MSProjectile.h"
#include "Weapons/MSWeapon.h"
#include "Components/AudioComponent.h"
#include "Components/SphereComponent.h"
#include "Components/StaticMeshComponent.h"
#include "Engine/StaticMesh.h"
#include "Engine/World.h"
#include "Kismet/GameplayStatics.h"
#include "TimerManager.h"

AMSAttackHelicopter::AMSAttackHelicopter()
{
	PrimaryActorTick.bCanEverTick = true;
	Body = CreateDefaultSubobject<USphereComponent>(TEXT("Body"));
	Body->InitSphereRadius(260.f);
	Body->SetCollisionProfileName(TEXT("Pawn"));
	Body->SetCollisionResponseToChannel(ECC_MSWeapon, ECR_Block);
	Body->SetCanEverAffectNavigation(false);
	SetRootComponent(Body);
	Visual = CreateDefaultSubobject<USceneComponent>(TEXT("Visual"));
	Visual->SetupAttachment(Body);
	GunMount = CreateDefaultSubobject<USceneComponent>(TEXT("GunMount"));
	GunMount->SetupAttachment(Body);
	GunMount->SetRelativeLocation(FVector(300.f, 0.f, -120.f));
	Health = CreateDefaultSubobject<UMSHealthComponent>(TEXT("Health"));
	Health->Team = EMSTeam::Enemy;
	AutoPossessAI = EAutoPossessAI::Disabled;
}

void AMSAttackHelicopter::BeginPlay()
{
	Super::BeginPlay();
	Health->OnDied.AddDynamic(this, &AMSAttackHelicopter::HandleDied);
	OrbitDirection = FMath::RandBool() ? 1.f : -1.f;
	GetWorldTimerManager().SetTimerForNextTick(FTimerDelegate::CreateWeakLambda(this, [this]()
	{
		if (EnemyRowName.IsNone())
		{
			InitFromRow(TEXT("AttackHelicopter"), 1.f, 1.f, 1.f);
		}
	}));
}

void AMSAttackHelicopter::InitFromRow(FName InEnemyRow, float HealthMultiplier, float InDamageMultiplier, float InAccuracyMultiplier)
{
	if (!EnemyRowName.IsNone())
	{
		return;   // already initialised
	}
	EnemyRowName = InEnemyRow;
	const UMSDataSubsystem* Data = UMSDataSubsystem::Get(this);
	const FMSEnemyRow* Found = Data ? Data->FindEnemy(InEnemyRow) : nullptr;
	Row = Found ? *Found : FMSEnemyRow();
	DamageMultiplier = InDamageMultiplier;
	AccuracyMultiplier = FMath::Max(0.1f, InAccuracyMultiplier);
	Health->SetMaxHealth(Row.Health * HealthMultiplier, true);
	Health->ExplosiveScale = Row.ExplosiveDamageScale;
	Health->HeadshotScale = 1.f;
	Health->DamageReduction = Row.DamageReduction;
	RocketLeft = Row.RocketInterval;
	BuildVisual();

	if (!Gun && !Row.Weapon.IsNone())
	{
		FActorSpawnParameters Params;
		Params.Owner = this;
		Params.Instigator = this;
		Gun = GetWorld()->SpawnActor<AMSWeapon>(AMSWeapon::StaticClass(), GetActorTransform(), Params);
		if (Gun)
		{
			Gun->Setup(Row.Weapon, this, false);
			Gun->AttachToComponent(GunMount, FAttachmentTransformRules::SnapToTargetNotIncludingScale);
			Gun->SetEquipped(true);
		}
	}
	if (USoundBase* Loop = Row.LoopSound.LoadSynchronous())
	{
		RotorAudio = UGameplayStatics::SpawnSoundAttached(Loop, GetRootComponent());
	}
}

void AMSAttackHelicopter::BuildVisual()
{
	if (UStaticMesh* Mesh = Row.StaticMesh.IsNull() ? nullptr : Row.StaticMesh.LoadSynchronous())
	{
		UStaticMeshComponent* Comp = NewObject<UStaticMeshComponent>(this);
		Comp->SetStaticMesh(Mesh);
		Comp->SetupAttachment(Visual);
		Comp->SetRelativeTransform(Row.MeshTransform);
		Comp->SetCollisionEnabled(ECollisionEnabled::NoCollision);
		Comp->RegisterComponent();
		return;
	}
	const FLinearColor C = Row.PlaceholderColor;
	const FLinearColor Dark = C * 0.5f;
	auto Part = [&](FName Shape, const FVector& Loc, const FVector& Size, const FLinearColor& Color, const FRotator& Rot = FRotator::ZeroRotator)
	{
		return UMSFXLibrary::AddPlaceholderShape(this, Visual, Shape, FTransform(Rot, Loc, Size / 100.f), Color, false);
	};
	Part(TEXT("Sphere"), FVector(60, 0, 0), FVector(420, 200, 200), C);                       // cabin
	Part(TEXT("Sphere"), FVector(230, 0, -10), FVector(140, 120, 120), FLinearColor(0.05f, 0.07f, 0.08f)); // canopy
	Part(TEXT("Cylinder"), FVector(-330, 0, 30), FVector(50, 50, 420), C, FRotator(90, 0, 0));  // tail boom
	Part(TEXT("Cube"), FVector(-540, 0, 90), FVector(60, 10, 140), C);                         // fin
	Part(TEXT("Cube"), FVector(30, -150, -40), FVector(120, 40, 30), Dark);                    // stub wings
	Part(TEXT("Cube"), FVector(30, 150, -40), FVector(120, 40, 30), Dark);
	Part(TEXT("Cylinder"), FVector(30, -150, -75), FVector(30, 30, 110), Dark, FRotator(90, 0, 0)); // rocket pods
	Part(TEXT("Cylinder"), FVector(30, 150, -75), FVector(30, 30, 110), Dark, FRotator(90, 0, 0));
	Rotor = NewObject<USceneComponent>(this);
	Rotor->SetupAttachment(Visual);
	Rotor->SetRelativeLocation(FVector(40, 0, 130));
	Rotor->RegisterComponent();
	UMSFXLibrary::AddPlaceholderShape(this, Rotor, TEXT("Cube"), FTransform(FRotator::ZeroRotator, FVector::ZeroVector, FVector(11.f, 0.25f, 0.05f)), Dark, false);
	UMSFXLibrary::AddPlaceholderShape(this, Rotor, TEXT("Cube"), FTransform(FRotator(0, 90, 0), FVector::ZeroVector, FVector(11.f, 0.25f, 0.05f)), Dark, false);
}

float AMSAttackHelicopter::GetWeaponDamageScale() const
{
	return Row.WeaponDamageScale * DamageMultiplier;
}

void AMSAttackHelicopter::GetAimRay(FVector& OutStart, FVector& OutDirection) const
{
	OutStart = Gun ? Gun->GetMuzzleTransform().GetLocation() : GunMount->GetComponentLocation();
	const FVector Aim = Target.IsValid() ? UMSCombatSubsystem::GetAimPoint(Target.Get()) : OutStart + GetActorForwardVector() * 1000.f - FVector(0, 0, 500);
	OutDirection = (Aim - OutStart).GetSafeNormal();
}

void AMSAttackHelicopter::UpdateTarget()
{
	UMSCombatSubsystem* Combat = UMSCombatSubsystem::Get(this);
	if (!Combat)
	{
		return;
	}
	if (UMSHealthComponent* H = Combat->FindClosestHostile(EMSTeam::Enemy, GetActorLocation(), Row.SightRadius * 4.f, false, this))
	{
		Target = H->GetOwner();
	}
	else
	{
		Target = nullptr;
	}
}

void AMSAttackHelicopter::FireRocket()
{
	if (!Target.IsValid())
	{
		return;
	}
	const UMSDataSubsystem* Data = UMSDataSubsystem::Get(this);
	const FMSWeaponRow* RocketRow = Data ? Data->FindWeapon(Row.RocketWeapon) : nullptr;
	if (!RocketRow)
	{
		return;
	}
	FMSExplosionParams Params = FMSExplosionParams::FromEquipment(Data->GetEquipment(TEXT("HeliRocket")));
	Params.Damage *= DamageMultiplier;
	const FVector Start = GetActorLocation() + GetActorRightVector() * (FMath::RandBool() ? 150.f : -150.f) - FVector(0, 0, 90);
	const FVector Aim = Target->GetActorLocation() + FMath::VRand() * 250.f;
	FActorSpawnParameters SpawnParams;
	SpawnParams.Owner = this;
	SpawnParams.Instigator = this;
	SpawnParams.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
	if (AMSProjectile* Rocket = GetWorld()->SpawnActor<AMSProjectile>(Start, (Aim - Start).Rotation(), SpawnParams))
	{
		Rocket->Launch(Params, (Aim - Start).GetSafeNormal() * RocketRow->ProjectileSpeed, 0.f, nullptr, EMSTeam::Enemy, this);
	}
	UGameplayStatics::PlaySoundAtLocation(this, RocketRow->FireSound.LoadSynchronous(), Start);
}

void AMSAttackHelicopter::UpdateWeapons(float Dt)
{
	AActor* T = Target.Get();
	const bool bLOS = T && UMSCombatSubsystem::HasLineOfSight(GetWorld(), GunMount->GetComponentLocation(), T, this);
	AimError = (Row.AimErrorDegrees + 2.f * FMath::Clamp(T ? T->GetVelocity().Size() / 600.f : 0.f, 0.f, 1.5f)) / AccuracyMultiplier;

	RocketLeft -= Dt;
	if (RocketLeft <= 0.f)
	{
		RocketLeft = Row.RocketInterval;
		if (bLOS)
		{
			FireRocket();
		}
	}
	if (!Gun)
	{
		return;
	}
	if (!bLOS)
	{
		Gun->SetTriggerHeld(false);
		return;
	}
	if (PauseLeft > 0.f)
	{
		PauseLeft -= Dt;
		Gun->SetTriggerHeld(false);
		if (PauseLeft <= 0.f)
		{
			// Burst length in seconds from the shot counts in the row.
			BurstLeft = FMath::FRandRange(Row.BurstMin, Row.BurstMax) * 60.f / FMath::Max(1.f, Gun->GetRow().RoundsPerMinute);
		}
		return;
	}
	BurstLeft -= Dt;
	Gun->SetTriggerHeld(true);
	if (BurstLeft <= 0.f)
	{
		PauseLeft = FMath::FRandRange(Row.BurstPauseMin, Row.BurstPauseMax);
	}
	Gun->SetActorRotation((UMSCombatSubsystem::GetAimPoint(T) - Gun->GetActorLocation()).Rotation());
}

void AMSAttackHelicopter::Tick(float DeltaSeconds)
{
	Super::Tick(DeltaSeconds);
	if (Rotor)
	{
		Rotor->AddLocalRotation(FRotator(0.f, 1600.f * DeltaSeconds, 0.f));
	}
	if (State == EMSHeliState::Dying)
	{
		DyingTime += DeltaSeconds;
		Velocity += FVector(0, 0, -980.f) * DeltaSeconds;
		AddActorWorldRotation(FRotator(0.f, 220.f * DeltaSeconds, 0.f));
		FHitResult Hit;
		AddActorWorldOffset(Velocity * DeltaSeconds, true, &Hit);
		if (Hit.bBlockingHit || DyingTime > 6.f)
		{
			FMSExplosionParams Params = FMSExplosionParams::FromEquipment(UMSDataSubsystem::Get(this)->GetEquipment(TEXT("Airstrike")));
			Params.Damage *= 0.5f;
			UMSCombatLibrary::Explode(this, GetActorLocation(), Params, nullptr, this, EMSTeam::Neutral);
			Destroy();
		}
		return;
	}

	TargetTimer -= DeltaSeconds;
	if (TargetTimer <= 0.f)
	{
		TargetTimer = 0.5f;
		UpdateTarget();
	}
	const AActor* T = Target.Get();
	const FVector Center = T ? T->GetActorLocation() : GetActorLocation();
	const FVector Here = GetActorLocation();
	OrbitAngle += OrbitDirection * (Row.OrbitSpeed / FMath::Max(500.f, Row.OrbitRadius)) * DeltaSeconds;
	if (State == EMSHeliState::Inbound)
	{
		OrbitAngle = FMath::Atan2(Here.Y - Center.Y, Here.X - Center.X);
	}
	const FVector Desired = Center + FVector(FMath::Cos(OrbitAngle), FMath::Sin(OrbitAngle), 0.f) * Row.OrbitRadius + FVector(0, 0, Row.OrbitAltitude);
	const FVector ToDesired = Desired - Here;
	if (State == EMSHeliState::Inbound && ToDesired.Size() < Row.OrbitRadius * 0.5f)
	{
		State = EMSHeliState::Orbit;
	}
	const float MaxSpeed = State == EMSHeliState::Inbound ? Row.OrbitSpeed * 2.f : Row.OrbitSpeed;
	const FVector DesiredVel = ToDesired.GetClampedToMaxSize(MaxSpeed);
	Velocity = FMath::VInterpTo(Velocity, DesiredVel, DeltaSeconds, 1.2f);
	AddActorWorldOffset(Velocity * DeltaSeconds, true);

	// Face the target with a bank into the turn.
	const FVector Look = T ? (T->GetActorLocation() - Here) : Velocity;
	FRotator Rot = Look.Rotation();
	Rot.Pitch = FMath::Clamp(Rot.Pitch * 0.25f, -15.f, 10.f);
	Rot.Roll = FMath::Clamp(-FVector::DotProduct(Velocity, GetActorRightVector()) * 0.02f, -20.f, 20.f);
	SetActorRotation(FMath::RInterpTo(GetActorRotation(), Rot, DeltaSeconds, 2.f));

	if (State == EMSHeliState::Orbit)
	{
		UpdateWeapons(DeltaSeconds);
	}
}

void AMSAttackHelicopter::HandleDied(UMSHealthComponent* InHealth, const FMSDamageInfo& KillingBlow)
{
	State = EMSHeliState::Dying;
	if (Gun)
	{
		Gun->SetTriggerHeld(false);
		Gun->Destroy();
		Gun = nullptr;
	}
	UMSFXLibrary::SpawnExplosion(GetWorld(), GetActorLocation(), 400.f, nullptr);
	if (RotorAudio)
	{
		RotorAudio->SetPitchMultiplier(0.7f);
	}
	SetLifeSpan(8.f);
}
