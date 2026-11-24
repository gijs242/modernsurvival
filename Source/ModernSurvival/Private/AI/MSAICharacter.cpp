#include "AI/MSAICharacter.h"

#include "AI/MSAIController.h"
#include "Audio/MSAudioSubsystem.h"
#include "Combat/MSCombatLibrary.h"
#include "Combat/MSHealthComponent.h"
#include "Data/MSDataSubsystem.h"
#include "FX/MSFXLibrary.h"
#include "ModernSurvival.h"
#include "Weapons/MSWeapon.h"
#include "Animation/AnimInstance.h"
#include "BrainComponent.h"
#include "Components/AudioComponent.h"
#include "Components/CapsuleComponent.h"
#include "Components/SkeletalMeshComponent.h"
#include "Components/StaticMeshComponent.h"
#include "Engine/SkeletalMesh.h"
#include "Engine/World.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "Kismet/GameplayStatics.h"
#include "Net/UnrealNetwork.h"
#include "TimerManager.h"

AMSAICharacter::AMSAICharacter(const FObjectInitializer& ObjectInitializer)
	: Super(ObjectInitializer)
{
	PrimaryActorTick.bCanEverTick = true;
	AIControllerClass = AMSAIController::StaticClass();
	AutoPossessAI = EAutoPossessAI::PlacedInWorldOrSpawned;

	bUseControllerRotationYaw = false;
	UCharacterMovementComponent* Move = GetCharacterMovement();
	Move->bOrientRotationToMovement = false;
	Move->bUseControllerDesiredRotation = true;
	Move->RotationRate = FRotator(0.f, 540.f, 0.f);
	Move->GetNavAgentPropertiesRef().bCanCrouch = true;
	Move->bCanWalkOffLedgesWhenCrouching = true;
	Move->SetCrouchedHalfHeight(60.f);
	Move->MaxWalkSpeedCrouched = 160.f;

	GetCapsuleComponent()->SetCollisionResponseToChannel(ECC_MSWeapon, ECR_Ignore);
	GetMesh()->SetRelativeLocation(FVector(0.f, 0.f, -90.f));
	GetMesh()->SetCollisionEnabled(ECollisionEnabled::NoCollision);

	Health = CreateDefaultSubobject<UMSHealthComponent>(TEXT("Health"));
	WeaponAnchor = CreateDefaultSubobject<USceneComponent>(TEXT("WeaponAnchor"));
	WeaponAnchor->SetupAttachment(GetMesh());
	WeaponAnchor->SetRelativeLocation(FVector(30.f, 18.f, 135.f));
}

void AMSAICharacter::BeginPlay()
{
	Super::BeginPlay();
	Health->OnDamaged.AddDynamic(this, &AMSAICharacter::HandleDamaged);
	Health->OnDied.AddDynamic(this, &AMSAICharacter::HandleDied);
	if (!HasAuthority())
	{
		return;   // clients set up from the replicated row (OnRep_EnemyRow)
	}
	// Placed in a level by hand (nobody called InitFromRow this frame): default to a rifleman.
	GetWorldTimerManager().SetTimerForNextTick(FTimerDelegate::CreateWeakLambda(this, [this]()
	{
		if (!bInitialized)
		{
			InitFromRow(TEXT("Rifleman"), 1.f, 1.f, 1.f, EMSTeam::Enemy);
		}
	}));
}

void AMSAICharacter::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const
{
	Super::GetLifetimeReplicatedProps(OutLifetimeProps);
	DOREPLIFETIME(AMSAICharacter, EnemyRowName);
	DOREPLIFETIME(AMSAICharacter, Team);
}

void AMSAICharacter::OnRep_EnemyRow()
{
	const UMSDataSubsystem* Data = UMSDataSubsystem::Get(this);
	const FMSEnemyRow* Found = Data ? Data->FindEnemy(EnemyRowName) : nullptr;
	EnemyRow = Found ? *Found : FMSEnemyRow();
	bInitialized = true;
	ApplyRowLocally();
}

void AMSAICharacter::ApplyRowLocally()
{
	GetCapsuleComponent()->SetCapsuleSize(EnemyRow.CapsuleRadius, EnemyRow.CapsuleHalfHeight);
	GetMesh()->SetRelativeLocation(FVector(0.f, 0.f, -EnemyRow.CapsuleHalfHeight));
	GetCharacterMovement()->MaxWalkSpeed = EnemyRow.WalkSpeed;
	// The placeholder parts double as hitboxes, so they're built on the server too.
	BuildVisual();
	if (GetNetMode() != NM_DedicatedServer)
	{
		if (!LoopAudio)
		{
			if (USoundBase* Loop = EnemyRow.LoopSound.LoadSynchronous())
			{
				LoopAudio = UGameplayStatics::SpawnSoundAttached(Loop, GetRootComponent());
			}
		}
	}
}

void AMSAICharacter::OnStartCrouch(float HalfHeightAdjust, float ScaledHalfHeightAdjust)
{
	Super::OnStartCrouch(HalfHeightAdjust, ScaledHalfHeightAdjust);
	// Placeholder bodies have no animation: squash them to read as crouched (runs on every machine).
	if (bPlaceholder && GetMesh())
	{
		GetMesh()->SetRelativeScale3D(FVector(1.f, 1.f, 0.62f));
	}
}

void AMSAICharacter::OnEndCrouch(float HalfHeightAdjust, float ScaledHalfHeightAdjust)
{
	Super::OnEndCrouch(HalfHeightAdjust, ScaledHalfHeightAdjust);
	if (bPlaceholder && GetMesh())
	{
		GetMesh()->SetRelativeScale3D(FVector::OneVector);
	}
}

void AMSAICharacter::EndPlay(const EEndPlayReason::Type Reason)
{
	if (Weapon)
	{
		Weapon->Destroy();
	}
	Super::EndPlay(Reason);
}

void AMSAICharacter::InitFromRow(FName InEnemyRow, float HealthMultiplier, float InDamageMultiplier, float InAccuracyMultiplier, EMSTeam InTeam)
{
	const UMSDataSubsystem* Data = UMSDataSubsystem::Get(this);
	const FMSEnemyRow* Found = Data ? Data->FindEnemy(InEnemyRow) : nullptr;
	EnemyRowName = InEnemyRow;
	EnemyRow = Found ? *Found : FMSEnemyRow();
	Team = InTeam;
	DamageMultiplier = InDamageMultiplier;
	AccuracyMultiplier = FMath::Max(0.1f, InAccuracyMultiplier);
	bInitialized = true;

	ApplyRowLocally();

	Health->Team = Team;
	Health->SetMaxHealth(EnemyRow.Health * HealthMultiplier, true);
	Health->DamageReduction = EnemyRow.DamageReduction;
	Health->HeadshotScale = EnemyRow.HeadshotMultiplierScale;
	Health->ExplosiveScale = EnemyRow.ExplosiveDamageScale;
	if (EnemyRow.Archetype == EMSEnemyArchetype::FriendlySoldier)
	{
		Health->ConfigureRegen(5.f, 25.f);
	}

	if (Weapon)
	{
		Weapon->Destroy();
		Weapon = nullptr;
	}
	if (!EnemyRow.Weapon.IsNone())
	{
		FActorSpawnParameters Params;
		Params.Owner = this;
		Params.Instigator = this;
		Params.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
		Weapon = GetWorld()->SpawnActor<AMSWeapon>(AMSWeapon::StaticClass(), GetActorTransform(), Params);
		if (Weapon)
		{
			Weapon->Setup(EnemyRow.Weapon, this, false);
			Weapon->AttachToComponent(WeaponAnchor, FAttachmentTransformRules::SnapToTargetNotIncludingScale);
			Weapon->SetEquipped(true);
		}
	}

	if (AMSAIController* AIC = Cast<AMSAIController>(GetController()))
	{
		AIC->ConfigureFromPawn();
	}
}

void AMSAICharacter::SetupHitbox(UPrimitiveComponent* Comp, bool bHead)
{
	if (!Comp)
	{
		return;
	}
	Comp->SetCollisionEnabled(ECollisionEnabled::QueryOnly);
	Comp->SetCollisionResponseToAllChannels(ECR_Ignore);
	Comp->SetCollisionResponseToChannel(ECC_MSWeapon, ECR_Block);
	Comp->SetCollisionResponseToChannel(ECC_Visibility, ECR_Ignore);
	Comp->SetCanEverAffectNavigation(false);
	if (bHead)
	{
		Comp->ComponentTags.AddUnique(TEXT("Head"));
	}
	PlaceholderParts.Add(Comp);
}

void AMSAICharacter::BuildPlaceholderHumanoid(float Scale, bool bHeavy)
{
	USceneComponent* Root = GetMesh();
	const FLinearColor Uniform = EnemyRow.PlaceholderColor;
	const FLinearColor Gear = Uniform * 0.55f;
	const FLinearColor Skin(0.45f, 0.33f, 0.25f);
	const float S = Scale;
	auto Part = [&](FName Shape, const FVector& Loc, const FVector& Size, const FLinearColor& Color, bool bHit, bool bHead)
	{
		UStaticMeshComponent* C = UMSFXLibrary::AddPlaceholderShape(this, Root, Shape, FTransform(FRotator::ZeroRotator, Loc * S, Size * S / 100.f), Color, false);
		if (bHit)
		{
			SetupHitbox(C, bHead);
		}
		return C;
	};
	// Legs, torso, vest, arms, head + helmet. Z up from the feet (mesh origin).
	Part(TEXT("Cylinder"), FVector(0, -11, 45), FVector(15, 15, 90), Uniform, true, false);
	Part(TEXT("Cylinder"), FVector(0, 11, 45), FVector(15, 15, 90), Uniform, true, false);
	PlaceholderTorso = Part(TEXT("Cube"), FVector(0, 0, 122), FVector(24, 42, 62), Uniform, true, false);
	Part(TEXT("Cube"), FVector(3, 0, 125), FVector(28, 44, 44), Gear, false, false);
	Part(TEXT("Cylinder"), FVector(10, -26, 120), FVector(10, 10, 55), Uniform, true, false);
	Part(TEXT("Cylinder"), FVector(10, 26, 120), FVector(10, 10, 55), Uniform, true, false);
	Part(TEXT("Sphere"), FVector(0, 0, 166), FVector(22, 22, 24), bHeavy ? Gear : Skin, true, true);
	Part(TEXT("Sphere"), FVector(0, 0, 171), FVector(25, 25, 18), Gear, false, false);
	if (bHeavy)
	{
		// Juggernaut: bulky plates and a visor.
		Part(TEXT("Cube"), FVector(5, 0, 125), FVector(34, 52, 58), Gear * 0.8f, true, false);
		Part(TEXT("Cube"), FVector(0, -30, 148), FVector(22, 18, 16), Gear * 0.8f, false, false);
		Part(TEXT("Cube"), FVector(0, 30, 148), FVector(22, 18, 16), Gear * 0.8f, false, false);
		Part(TEXT("Cube"), FVector(11, 0, 166), FVector(6, 18, 6), FLinearColor(0.02f, 0.02f, 0.02f), false, false);
	}
	WeaponAnchor->SetRelativeLocation(FVector(30.f, 18.f, 132.f) * S);
}

void AMSAICharacter::BuildPlaceholderDog()
{
	USceneComponent* Root = GetMesh();
	const FLinearColor Fur = EnemyRow.PlaceholderColor;
	auto Part = [&](FName Shape, const FVector& Loc, const FVector& Size, bool bHit, bool bHead, const FRotator& Rot = FRotator::ZeroRotator)
	{
		UStaticMeshComponent* C = UMSFXLibrary::AddPlaceholderShape(this, Root, Shape, FTransform(Rot, Loc, Size / 100.f), Fur, false);
		if (bHit)
		{
			SetupHitbox(C, bHead);
		}
		return C;
	};
	PlaceholderTorso = Part(TEXT("Cube"), FVector(0, 0, 55), FVector(80, 26, 30), true, false);
	Part(TEXT("Sphere"), FVector(48, 0, 72), FVector(24, 20, 22), true, true);
	Part(TEXT("Cube"), FVector(64, 0, 66), FVector(18, 12, 10), false, false);
	for (const FVector& Leg : {FVector(28, -10, 22), FVector(28, 10, 22), FVector(-28, -10, 22), FVector(-28, 10, 22)})
	{
		Part(TEXT("Cylinder"), Leg, FVector(8, 8, 44), true, false);
	}
	Part(TEXT("Cylinder"), FVector(-48, 0, 66), FVector(5, 5, 30), false, false, FRotator(-50, 0, 0));
}

void AMSAICharacter::BuildVisual()
{
	for (UPrimitiveComponent* P : PlaceholderParts)
	{
		if (P)
		{
			P->DestroyComponent();
		}
	}
	PlaceholderParts.Reset();

	USkeletalMesh* Skel = EnemyRow.SkeletalMesh.IsNull() ? nullptr : EnemyRow.SkeletalMesh.LoadSynchronous();
	if (Skel)
	{
		bPlaceholder = false;
		USkeletalMeshComponent* MeshComp = GetMesh();
		MeshComp->SetSkeletalMesh(Skel);
		if (UClass* Anim = EnemyRow.AnimClass.LoadSynchronous())
		{
			MeshComp->SetAnimInstanceClass(Anim);
		}
		// MeshTransform first (e.g. yaw -90 for UE mannequins), then drop the feet to the capsule bottom.
		MeshComp->SetRelativeTransform(EnemyRow.MeshTransform * FTransform(FVector(0.f, 0.f, -EnemyRow.CapsuleHalfHeight)));
		MeshComp->SetCollisionEnabled(ECollisionEnabled::QueryOnly);
		MeshComp->SetCollisionResponseToAllChannels(ECR_Ignore);
		MeshComp->SetCollisionResponseToChannel(ECC_MSWeapon, ECR_Block);
		MeshComp->SetGenerateOverlapEvents(false);
		return;
	}
	bPlaceholder = true;
	switch (EnemyRow.Archetype)
	{
	case EMSEnemyArchetype::Dog:
		BuildPlaceholderDog();
		break;
	case EMSEnemyArchetype::Juggernaut:
		BuildPlaceholderHumanoid(EnemyRow.PlaceholderScale, true);
		break;
	default:
		BuildPlaceholderHumanoid(EnemyRow.PlaceholderScale, false);
		break;
	}
}

FVector AMSAICharacter::GetPawnViewLocation() const
{
	const float Eye = EnemyRow.Archetype == EMSEnemyArchetype::Dog ? 30.f : (bIsCrouched ? 40.f : 70.f);
	return GetActorLocation() + FVector(0.f, 0.f, Eye * EnemyRow.PlaceholderScale);
}

void AMSAICharacter::GetAimRay(FVector& OutStart, FVector& OutDirection) const
{
	OutStart = Weapon ? Weapon->GetMuzzleTransform().GetLocation() : GetPawnViewLocation();
	const FVector Target = AimPoint.IsNearlyZero() ? OutStart + GetActorForwardVector() * 1000.f : AimPoint;
	OutDirection = (Target - OutStart).GetSafeNormal();
}

float AMSAICharacter::GetWeaponDamageScale() const
{
	return EnemyRow.WeaponDamageScale * DamageMultiplier;
}

float AMSAICharacter::GetMoveSpreadFraction() const
{
	return FMath::Clamp(GetVelocity().Size2D() / FMath::Max(1.f, EnemyRow.RunSpeed), 0.f, 1.f) * 0.5f;
}

bool AMSAICharacter::IsDead() const
{
	return Health && Health->IsDead();
}

void AMSAICharacter::SetRunning(bool bRun)
{
	GetCharacterMovement()->MaxWalkSpeed = bRun ? EnemyRow.RunSpeed : EnemyRow.WalkSpeed;
}

void AMSAICharacter::SetCoverCrouch(bool bCrouch)
{
	if (EnemyRow.Archetype == EMSEnemyArchetype::Dog)
	{
		return;
	}
	if (bCrouch && !bIsCrouched)
	{
		Crouch();
	}
	else if (!bCrouch && bIsCrouched)
	{
		UnCrouch();
	}
}

bool AMSAICharacter::TryMelee(AActor* Target)
{
	if (!Target || MeleeCooldownLeft > 0.f || EnemyRow.MeleeDamage <= 0.f || IsDead())
	{
		return false;
	}
	const float Dist = FVector::Dist2D(GetActorLocation(), Target->GetActorLocation());
	if (Dist > EnemyRow.MeleeRange + 40.f)
	{
		return false;
	}
	MeleeCooldownLeft = EnemyRow.MeleeCooldown;
	const FVector Dir = (Target->GetActorLocation() - GetActorLocation()).GetSafeNormal2D();
	if (EnemyRow.MeleeLunge > 0.f)
	{
		LaunchCharacter(Dir * EnemyRow.MeleeLunge + FVector(0, 0, 150.f), true, false);
	}
	FMSDamageInfo Info;
	Info.Amount = EnemyRow.MeleeDamage * DamageMultiplier;
	Info.Kind = EMSDamageKind::Melee;
	Info.HitLocation = Target->GetActorLocation();
	Info.SourceLocation = GetActorLocation();
	Info.ImpulseDirection = Dir;
	Info.Instigator = GetController();
	Info.Causer = this;
	Info.SourceTeam = Team;
	UMSCombatLibrary::DealDamage(Target, Info);
	if (UMSAudioSubsystem* Audio = GetWorld()->GetSubsystem<UMSAudioSubsystem>())
	{
		Audio->PlayAt(GetActorLocation(), LoadObject<USoundBase>(nullptr, TEXT("/Game/Audio/impact_flesh.impact_flesh")));
	}
	return true;
}

void AMSAICharacter::HandleDamaged(UMSHealthComponent* InHealth, const FMSDamageInfo& Info, float HealthDamage, float ArmorDamage)
{
	if (EnemyRow.bFlinches && HealthDamage > 0.f)
	{
		FlinchTimeLeft = 0.18f;
	}
	if (AMSAIController* AIC = Cast<AMSAIController>(GetController()))
	{
		AIC->NotifyDamaged(Info);
	}
}

void AMSAICharacter::HandleDied(UMSHealthComponent* InHealth, const FMSDamageInfo& KillingBlow)
{
	// Runs on the server (OnDied) and on clients (replicated death): game logic only on the server.
	if (HasAuthority())
	{
		if (Weapon)
		{
			Weapon->SetTriggerHeld(false);
			Weapon->DetachFromActor(FDetachmentTransformRules::KeepWorldTransform);
			Weapon->SetLifeSpan(5.f);
			Weapon = nullptr;
		}
		if (AController* C = GetController())
		{
			if (AMSAIController* AIC = Cast<AMSAIController>(C))
			{
				AIC->OnPawnDied();
			}
			C->UnPossess();
		}
	}
	if (LoopAudio)
	{
		LoopAudio->FadeOut(1.f, 0.f);
	}
	GetCharacterMovement()->DisableMovement();
	GetCapsuleComponent()->SetCollisionEnabled(ECollisionEnabled::NoCollision);

	const FVector Push = KillingBlow.ImpulseDirection.GetSafeNormal() * FMath::Max(KillingBlow.Impulse, 3000.f);
	if (!bPlaceholder)
	{
		USkeletalMeshComponent* MeshComp = GetMesh();
		MeshComp->SetCollisionProfileName(TEXT("Ragdoll"));
		MeshComp->SetSimulatePhysics(true);
		MeshComp->AddImpulseAtLocation(Push, KillingBlow.HitLocation, KillingBlow.HitBone);
	}
	else
	{
		// Placeholder "ragdoll": every part becomes a physics body.
		for (UPrimitiveComponent* P : PlaceholderParts)
		{
			if (!P)
			{
				continue;
			}
			P->SetCollisionProfileName(TEXT("PhysicsActor"));
			P->SetCollisionResponseToChannel(ECC_Pawn, ECR_Ignore);
			P->SetCollisionResponseToChannel(ECC_MSWeapon, ECR_Ignore);
			P->DetachFromComponent(FDetachmentTransformRules::KeepWorldTransform);
			P->SetSimulatePhysics(true);
			P->AddImpulse(Push * 0.02f + FMath::VRand() * 200.f, NAME_None, true);
		}
	}
	if (USoundBase* Death = EnemyRow.DeathSound.LoadSynchronous())
	{
		UGameplayStatics::PlaySoundAtLocation(this, Death, GetActorLocation());
	}
	if (HasAuthority())
	{
		const UMSDataSubsystem* Data = UMSDataSubsystem::Get(this);
		SetLifeSpan(Data ? Data->GetRules().CorpseLifetime : 20.f);
	}
}

void AMSAICharacter::Tick(float DeltaSeconds)
{
	Super::Tick(DeltaSeconds);
	MeleeCooldownLeft = FMath::Max(0.f, MeleeCooldownLeft - DeltaSeconds);
	FlinchTimeLeft = FMath::Max(0.f, FlinchTimeLeft - DeltaSeconds);
	if (Weapon && !IsDead() && HasAuthority())
	{
		// Keep the gun pointing at what we aim at.
		const FVector From = WeaponAnchor->GetComponentLocation();
		if (!AimPoint.IsNearlyZero())
		{
			Weapon->SetActorRotation((AimPoint - From).Rotation());
		}
	}
}
