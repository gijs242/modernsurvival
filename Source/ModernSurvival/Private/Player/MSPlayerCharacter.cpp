#include "Player/MSPlayerCharacter.h"

#include "Audio/MSAudioSubsystem.h"
#include "Combat/MSCombatLibrary.h"
#include "Combat/MSHealthComponent.h"
#include "Core/MSRules.h"
#include "Data/MSDataSubsystem.h"
#include "Equipment/MSAirstrike.h"
#include "Equipment/MSClaymore.h"
#include "Equipment/MSGrenade.h"
#include "Equipment/MSSentryGun.h"
#include "FX/MSFXLibrary.h"
#include "Game/MSGameMode.h"
#include "Game/MSGameState.h"
#include "Game/MSInteractable.h"
#include "ModernSurvival.h"
#include "Player/MSCameraFeelComponent.h"
#include "Player/MSPlayerController.h"
#include "Player/MSViewModelComponent.h"
#include "Weapons/MSWeapon.h"
#include "Camera/CameraComponent.h"
#include "Components/CapsuleComponent.h"
#include "Components/SkeletalMeshComponent.h"
#include "Components/StaticMeshComponent.h"
#include "EnhancedInputComponent.h"
#include "Engine/World.h"
#include "EngineUtils.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "InputActionValue.h"
#include "Kismet/GameplayStatics.h"
#include "Net/UnrealNetwork.h"

AMSPlayerCharacter::AMSPlayerCharacter(const FObjectInitializer& ObjectInitializer)
	: Super(ObjectInitializer)
{
	PrimaryActorTick.bCanEverTick = true;
	bUseControllerRotationYaw = true;
	bUseControllerRotationPitch = false;
	bUseControllerRotationRoll = false;

	UCapsuleComponent* Capsule = GetCapsuleComponent();
	Capsule->InitCapsuleSize(34.f, 90.f);
	Capsule->SetCollisionResponseToChannel(ECC_MSWeapon, ECR_Ignore);

	Camera = CreateDefaultSubobject<UCameraComponent>(TEXT("FirstPersonCamera"));
	Camera->SetupAttachment(Capsule);
	Camera->SetRelativeLocation(FVector(0.f, 0.f, 70.f));
	Camera->bUsePawnControlRotation = false;   // MSCameraFeelComponent sets rotation (control + shake)

	WeaponPivot = CreateDefaultSubobject<USceneComponent>(TEXT("WeaponPivot"));
	WeaponPivot->SetupAttachment(Camera);

	Hitbox = CreateDefaultSubobject<UCapsuleComponent>(TEXT("Hitbox"));
	Hitbox->SetupAttachment(Capsule);
	Hitbox->InitCapsuleSize(30.f, 86.f);
	Hitbox->SetCollisionEnabled(ECollisionEnabled::QueryOnly);
	Hitbox->SetCollisionResponseToAllChannels(ECR_Ignore);
	Hitbox->SetCollisionResponseToChannel(ECC_MSWeapon, ECR_Block);
	Hitbox->SetCanEverAffectNavigation(false);

	Health = CreateDefaultSubobject<UMSHealthComponent>(TEXT("Health"));
	Health->Team = EMSTeam::Player;
	CameraFeel = CreateDefaultSubobject<UMSCameraFeelComponent>(TEXT("CameraFeel"));
	ViewModel = CreateDefaultSubobject<UMSViewModelComponent>(TEXT("ViewModel"));

	// No skeletal body yet: the mesh component only anchors the placeholder third-person body.
	GetMesh()->SetCollisionEnabled(ECollisionEnabled::NoCollision);
	GetMesh()->SetRelativeLocation(FVector(0.f, 0.f, -90.f));

	UCharacterMovementComponent* Move = GetCharacterMovement();
	Move->GetNavAgentPropertiesRef().bCanCrouch = true;
	Move->bCanWalkOffLedgesWhenCrouching = true;
	Move->SetCrouchedHalfHeight(56.f);
	Move->bOrientRotationToMovement = false;
	// Co-op: trust the owning client's position so sprint/slide/ADS speeds never rubber-band.
	Move->bIgnoreClientMovementErrorChecksAndCorrection = true;
	Move->bServerAcceptClientAuthoritativePosition = true;

	EquipmentCounts.Init(0, static_cast<int32>(EMSEquipmentSlot::Count));
}

void AMSPlayerCharacter::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const
{
	Super::GetLifetimeReplicatedProps(OutLifetimeProps);
	DOREPLIFETIME(AMSPlayerCharacter, Weapons);
	DOREPLIFETIME(AMSPlayerCharacter, CurrentWeaponIndex);
	DOREPLIFETIME(AMSPlayerCharacter, LastStandWeapon);
	DOREPLIFETIME_CONDITION(AMSPlayerCharacter, EquipmentCounts, COND_OwnerOnly);
	DOREPLIFETIME(AMSPlayerCharacter, bDowned);
	DOREPLIFETIME(AMSPlayerCharacter, bSelfRevive);
	DOREPLIFETIME(AMSPlayerCharacter, DownedTimeLeft);
	DOREPLIFETIME(AMSPlayerCharacter, ReviveProgress);
	DOREPLIFETIME_CONDITION(AMSPlayerCharacter, LastStandsLeft, COND_OwnerOnly);
}

void AMSPlayerCharacter::BeginPlay()
{
	Super::BeginPlay();
	CameraFeel->SetCamera(Camera);
	ViewModel->SetPivot(WeaponPivot);
	ApplyFeelToMovement();
	BuildThirdPersonBody();
	Health->OnDied.AddDynamic(this, &AMSPlayerCharacter::HandleDied);

	if (HasAuthority())
	{
		const FMSPlayerFeelRow& Feel = UMSDataSubsystem::Get(this)->GetPlayerFeel();
		Health->SetMaxHealth(Feel.MaxHealth, true);
		Health->ConfigureRegen(Feel.RegenDelay, Feel.RegenRate);
		Health->ArmorAbsorb = Feel.ArmorAbsorb;
		Health->Team = EMSTeam::Player;
		Health->LethalDamageInterceptor.BindUObject(this, &AMSPlayerCharacter::HandleLethalDamage);
		Health->OnDamaged.AddDynamic(this, &AMSPlayerCharacter::HandleDamaged);
		LastStandsLeft = Feel.LastStandsPerGame;
	}
}

void AMSPlayerCharacter::PossessedBy(AController* NewController)
{
	Super::PossessedBy(NewController);
	// After possession so IsLocallyControlled() is right for the host's first-person weapons.
	if (Weapons.Num() == 0)
	{
		GiveStartingLoadout();
	}
}

void AMSPlayerCharacter::GiveStartingLoadout()
{
	if (!HasAuthority())
	{
		return;
	}
	const FMSGameRulesRow& Rules = UMSDataSubsystem::Get(this)->GetRules();
	GiveWeapon(Rules.StartingWeapon, false);
	if (!Rules.StartingPrimary.IsNone() && Rules.StartingPrimary != Rules.StartingWeapon)
	{
		GiveWeapon(Rules.StartingPrimary, true);
	}
	else
	{
		EquipWeaponIndex(0);
	}
	AddEquipment(EMSEquipmentSlot::Frag, Rules.StartingFrags);
}

void AMSPlayerCharacter::EndPlay(const EEndPlayReason::Type Reason)
{
	if (HasAuthority())
	{
		for (AMSWeapon* W : Weapons)
		{
			if (W)
			{
				W->Destroy();
			}
		}
		if (LastStandWeapon)
		{
			LastStandWeapon->Destroy();
		}
	}
	Super::EndPlay(Reason);
}

void AMSPlayerCharacter::ApplyFeelToMovement()
{
	const UMSDataSubsystem* Data = UMSDataSubsystem::Get(this);
	if (!Data)
	{
		return;
	}
	const FMSPlayerFeelRow& Feel = Data->GetPlayerFeel();
	UCharacterMovementComponent* Move = GetCharacterMovement();
	GetCapsuleComponent()->SetCapsuleSize(Feel.CapsuleRadius, Feel.CapsuleHalfHeight);
	Hitbox->SetCapsuleSize(Feel.CapsuleRadius - 4.f, Feel.CapsuleHalfHeight - 4.f);
	GetMesh()->SetRelativeLocation(FVector(0.f, 0.f, -Feel.CapsuleHalfHeight));
	Move->SetCrouchedHalfHeight(Feel.CrouchedHalfHeight);
	Move->MaxAcceleration = Feel.Acceleration;
	Move->BrakingDecelerationWalking = Feel.BrakingDeceleration;
	Move->GroundFriction = Feel.GroundFriction;
	Move->JumpZVelocity = Feel.JumpZVelocity;
	Move->AirControl = Feel.AirControl;
	Move->MaxWalkSpeed = Feel.WalkSpeed;
	Move->MaxWalkSpeedCrouched = Feel.CrouchSpeed;
	BaseEyeHeight = Feel.StandEyeHeight;
	CrouchedEyeHeight = Feel.CrouchEyeHeight;
}

void AMSPlayerCharacter::BuildThirdPersonBody()
{
	if (bBodyBuilt || GetNetMode() == NM_DedicatedServer)
	{
		return;
	}
	bBodyBuilt = true;
	// Placeholder soldier for OTHER players to see (the owner never sees it). Replace with a real
	// mesh + animation blueprint later (GetMesh()).
	const FLinearColor Uniform(0.2f, 0.24f, 0.3f);
	const FLinearColor Gear = Uniform * 0.55f;
	auto Part = [&](FName Shape, const FVector& Loc, const FVector& Size, const FLinearColor& Color)
	{
		UStaticMeshComponent* C = UMSFXLibrary::AddPlaceholderShape(this, GetMesh(), Shape, FTransform(FRotator::ZeroRotator, Loc, Size / 100.f), Color, false);
		C->SetOwnerNoSee(true);
		C->SetCastShadow(true);
		BodyParts.Add(C);
	};
	Part(TEXT("Cylinder"), FVector(0, -11, 45), FVector(15, 15, 90), Uniform);
	Part(TEXT("Cylinder"), FVector(0, 11, 45), FVector(15, 15, 90), Uniform);
	Part(TEXT("Cube"), FVector(0, 0, 122), FVector(24, 42, 62), Uniform);
	Part(TEXT("Cube"), FVector(3, 0, 125), FVector(28, 44, 44), Gear);
	Part(TEXT("Cylinder"), FVector(14, -22, 128), FVector(10, 10, 50), Uniform);
	Part(TEXT("Cylinder"), FVector(14, 22, 128), FVector(10, 10, 50), Uniform);
	Part(TEXT("Sphere"), FVector(0, 0, 166), FVector(22, 22, 24), FLinearColor(0.45f, 0.33f, 0.25f));
	Part(TEXT("Sphere"), FVector(0, 0, 171), FVector(25, 25, 18), Gear);
}

// ------------------------------------------------------------------------------- weapon holder

void AMSPlayerCharacter::GetAimRay(FVector& OutStart, FVector& OutDirection) const
{
	OutStart = Camera->GetComponentLocation();
	OutDirection = Camera->GetForwardVector();
}

float AMSPlayerCharacter::GetMoveSpreadFraction() const
{
	const float Walk = UMSDataSubsystem::Get(this)->GetPlayerFeel().WalkSpeed;
	return Walk > 0.f ? FMath::Clamp(GetVelocity().Size2D() / Walk, 0.f, 1.5f) : 0.f;
}

bool AMSPlayerCharacter::IsAirborne() const
{
	return GetCharacterMovement()->IsFalling();
}

bool AMSPlayerCharacter::IsDead() const
{
	return Health && Health->IsDead();
}

void AMSPlayerCharacter::OnWeaponFired(const FMSWeaponRow& Row, int32 ShotIndex)
{
	const UMSDataSubsystem* Data = UMSDataSubsystem::Get(this);
	const float ADSMul = FMath::Lerp(1.f, Row.ADSRecoilMultiplier, ADSAlpha);
	const float FirstMul = ShotIndex == 0 ? Row.FirstShotRecoilMultiplier : 1.f;
	const float Pitch = FMath::FRandRange(Row.RecoilPitchMin, Row.RecoilPitchMax) * ADSMul * FirstMul;
	const float Pattern = Data ? Data->EvalCurve(Row.RecoilPatternCurve, static_cast<float>(FMath::Min(ShotIndex, 30)), 0.f) : 0.f;
	const float Yaw = (FMath::FRandRange(Row.RecoilYawMin, Row.RecoilYawMax) + Pattern) * ADSMul;
	CameraFeel->AddRecoil(Pitch, Yaw, Row.RecoilApplySpeed, Row.RecoilRecoverySpeed, Row.RecoilRecoveryFraction);
	CameraFeel->AddTrauma(Row.ShotTrauma * FMath::Lerp(1.f, 0.6f, ADSAlpha));
	ViewModel->OnShot(1.f);
	if (bSprinting)
	{
		StopSprint();
	}
}

void AMSPlayerCharacter::OnWeaponHit(const FMSHitReport& Report)
{
	if (IsLocallyControlled())
	{
		RecordHit(Report);
	}
	else
	{
		ClientNotifyHit(Report);   // server-side hit of a remote player's shot -> their hitmarker
	}
}

void AMSPlayerCharacter::ClientNotifyHit_Implementation(FMSHitReport Report)
{
	RecordHit(Report);
}

void AMSPlayerCharacter::RecordHit(const FMSHitReport& Report)
{
	LastHit.Time = GetWorld()->GetTimeSeconds();
	LastHit.bKilled = Report.bKilled;
	LastHit.bHeadshot = Report.bHeadshot;
	LastHit.bArmor = Report.bArmorHit;
	const UMSDataSubsystem* Data = UMSDataSubsystem::Get(this);
	UMSAudioSubsystem* Audio = GetWorld()->GetSubsystem<UMSAudioSubsystem>();
	if (Data && Audio)
	{
		const FMSLookRow& Look = Data->GetLook();
		USoundBase* Sound = Report.bKilled ? Look.KillSound.LoadSynchronous() : nullptr;
		if (!Sound)
		{
			Sound = Look.HitmarkerSound.LoadSynchronous();
		}
		Audio->Play2D(Sound, Look.HitmarkerVolume, Report.bHeadshot ? 1.15f : 1.f);
	}
}

// ------------------------------------------------------------------------------- inventory

AMSWeapon* AMSPlayerCharacter::GetCurrentWeapon() const
{
	if (bDowned && LastStandWeapon)
	{
		return LastStandWeapon;
	}
	return Weapons.IsValidIndex(CurrentWeaponIndex) ? Weapons[CurrentWeaponIndex].Get() : nullptr;
}

bool AMSPlayerCharacter::HasWeapon(FName WeaponRow) const
{
	return Weapons.ContainsByPredicate([WeaponRow](const AMSWeapon* W) { return W && W->GetRowName() == WeaponRow; });
}

AMSWeapon* AMSPlayerCharacter::GiveWeapon(FName WeaponRow, bool bEquip)
{
	if (WeaponRow.IsNone() || !HasAuthority())
	{
		return nullptr;
	}
	for (int32 I = 0; I < Weapons.Num(); ++I)
	{
		if (Weapons[I] && Weapons[I]->GetRowName() == WeaponRow)
		{
			Weapons[I]->FillAmmo();
			if (bEquip)
			{
				EquipWeaponIndex(I);
			}
			return Weapons[I];
		}
	}

	FActorSpawnParameters Params;
	Params.Owner = this;
	Params.Instigator = this;
	Params.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
	AMSWeapon* Weapon = GetWorld()->SpawnActor<AMSWeapon>(AMSWeapon::StaticClass(), GetActorTransform(), Params);
	if (!Weapon)
	{
		return nullptr;
	}
	Weapon->Setup(WeaponRow, this, IsLocallyControlled());
	Weapon->AttachToComponent(WeaponPivot, FAttachmentTransformRules::SnapToTargetNotIncludingScale);
	Weapon->SetEquipped(false);

	const int32 MaxCarried = FMath::Max(1, UMSDataSubsystem::Get(this)->GetRules().MaxWeaponsCarried);
	int32 Slot = Weapons.Num();
	if (Weapons.Num() >= MaxCarried)
	{
		// Full: the new gun replaces the one in your hands.
		Slot = CurrentWeaponIndex;
		if (AMSWeapon* Old = Weapons[Slot])
		{
			Old->Destroy();
		}
		Weapons[Slot] = Weapon;
	}
	else
	{
		Weapons.Add(Weapon);
	}
	if (bEquip || Weapons.Num() == 1)
	{
		CurrentWeaponIndex = -1;
		EquipWeaponIndex(Slot);
	}
	return Weapon;
}

void AMSPlayerCharacter::ApplyEquipLocally(int32 Index)
{
	for (int32 I = 0; I < Weapons.Num(); ++I)
	{
		if (Weapons[I])
		{
			Weapons[I]->SetEquipped(!bDowned && I == Index);
		}
	}
	if (LastStandWeapon)
	{
		LastStandWeapon->SetEquipped(bDowned);
	}
	if (AMSWeapon* W = GetCurrentWeapon())
	{
		ViewModel->SetWeaponRow(&W->GetRow());
	}
}

void AMSPlayerCharacter::EquipWeaponIndex(int32 Index)
{
	if (!Weapons.IsValidIndex(Index) || bDowned)
	{
		return;
	}
	const bool bChanged = Index != CurrentWeaponIndex;
	CurrentWeaponIndex = Index;
	ApplyEquipLocally(Index);
	if (bChanged && IsLocallyControlled())
	{
		ViewModel->OnEquip();
		if (UMSAudioSubsystem* Audio = GetWorld()->GetSubsystem<UMSAudioSubsystem>())
		{
			Audio->Play2D(LoadObject<USoundBase>(nullptr, TEXT("/Game/Audio/swap.swap")), 0.5f);
		}
	}
	if (!HasAuthority())
	{
		ServerEquipWeapon(Index);
	}
}

void AMSPlayerCharacter::ServerEquipWeapon_Implementation(int32 Index)
{
	EquipWeaponIndex(Index);
}

void AMSPlayerCharacter::OnRep_Weapons()
{
	// Inventory or equipped slot changed on the server: show the right gun on this machine.
	ApplyEquipLocally(CurrentWeaponIndex);
}

void AMSPlayerCharacter::CycleWeapon(int32 Direction)
{
	if (Weapons.Num() > 1)
	{
		EquipWeaponIndex((CurrentWeaponIndex + Direction + Weapons.Num()) % Weapons.Num());
	}
}

FName AMSPlayerCharacter::EquipmentRowFor(EMSEquipmentSlot Slot)
{
	switch (Slot)
	{
	case EMSEquipmentSlot::Frag: return TEXT("Frag");
	case EMSEquipmentSlot::Claymore: return TEXT("Claymore");
	case EMSEquipmentSlot::Sentry: return TEXT("Sentry");
	case EMSEquipmentSlot::Airstrike: return TEXT("Airstrike");
	case EMSEquipmentSlot::Squad: return TEXT("AISquad");
	default: return NAME_None;
	}
}

int32 AMSPlayerCharacter::GetEquipmentCount(EMSEquipmentSlot Slot) const
{
	const int32 I = static_cast<int32>(Slot);
	return EquipmentCounts.IsValidIndex(I) ? EquipmentCounts[I] : 0;
}

int32 AMSPlayerCharacter::GetEquipmentMax(EMSEquipmentSlot Slot) const
{
	const UMSDataSubsystem* Data = UMSDataSubsystem::Get(this);
	return Data ? Data->GetEquipment(EquipmentRowFor(Slot)).MaxCarried : 4;
}

int32 AMSPlayerCharacter::AddEquipment(EMSEquipmentSlot Slot, int32 Amount)
{
	const int32 I = static_cast<int32>(Slot);
	if (!EquipmentCounts.IsValidIndex(I) || !HasAuthority())
	{
		return 0;
	}
	const int32 Before = EquipmentCounts[I];
	EquipmentCounts[I] = FMath::Clamp(EquipmentCounts[I] + Amount, 0, GetEquipmentMax(Slot));
	return EquipmentCounts[I] - Before;
}

// ------------------------------------------------------------------------------- input

void AMSPlayerCharacter::SetupPlayerInputComponent(UInputComponent* PlayerInputComponent)
{
	Super::SetupPlayerInputComponent(PlayerInputComponent);
	UEnhancedInputComponent* EIC = Cast<UEnhancedInputComponent>(PlayerInputComponent);
	AMSPlayerController* PC = Cast<AMSPlayerController>(GetController());
	if (!EIC || !PC)
	{
		UE_LOG(LogMS, Error, TEXT("Player input needs AMSPlayerController + EnhancedInputComponent (see Config/DefaultInput.ini)."));
		return;
	}
	const FMSInputActions& A = PC->GetInputActions();
	EIC->BindAction(A.Move, ETriggerEvent::Triggered, this, &AMSPlayerCharacter::Input_Move);
	EIC->BindAction(A.Move, ETriggerEvent::Completed, this, &AMSPlayerCharacter::Input_MoveCompleted);
	EIC->BindAction(A.Look, ETriggerEvent::Triggered, this, &AMSPlayerCharacter::Input_Look);
	EIC->BindAction(A.LookGamepad, ETriggerEvent::Triggered, this, &AMSPlayerCharacter::Input_LookGamepad);
	EIC->BindAction(A.Jump, ETriggerEvent::Started, this, &AMSPlayerCharacter::Input_Jump);
	EIC->BindAction(A.Sprint, ETriggerEvent::Started, this, &AMSPlayerCharacter::Input_Sprint);
	EIC->BindAction(A.Crouch, ETriggerEvent::Started, this, &AMSPlayerCharacter::Input_Crouch);
	EIC->BindAction(A.Fire, ETriggerEvent::Started, this, &AMSPlayerCharacter::Input_FirePressed);
	EIC->BindAction(A.Fire, ETriggerEvent::Completed, this, &AMSPlayerCharacter::Input_FireReleased);
	EIC->BindAction(A.ADS, ETriggerEvent::Started, this, &AMSPlayerCharacter::Input_ADSPressed);
	EIC->BindAction(A.ADS, ETriggerEvent::Completed, this, &AMSPlayerCharacter::Input_ADSReleased);
	EIC->BindAction(A.Reload, ETriggerEvent::Started, this, &AMSPlayerCharacter::Input_Reload);
	EIC->BindAction(A.Interact, ETriggerEvent::Started, this, &AMSPlayerCharacter::Input_Interact);
	EIC->BindAction(A.Interact, ETriggerEvent::Completed, this, &AMSPlayerCharacter::Input_InteractReleased);
	EIC->BindAction(A.SwitchWeapon, ETriggerEvent::Started, this, &AMSPlayerCharacter::Input_SwitchWeapon);
	EIC->BindAction(A.Weapon1, ETriggerEvent::Started, this, &AMSPlayerCharacter::Input_Weapon1);
	EIC->BindAction(A.Weapon2, ETriggerEvent::Started, this, &AMSPlayerCharacter::Input_Weapon2);
	EIC->BindAction(A.Melee, ETriggerEvent::Started, this, &AMSPlayerCharacter::Input_Melee);
	EIC->BindAction(A.Grenade, ETriggerEvent::Started, this, &AMSPlayerCharacter::Input_GrenadePressed);
	EIC->BindAction(A.Grenade, ETriggerEvent::Completed, this, &AMSPlayerCharacter::Input_GrenadeReleased);
	EIC->BindAction(A.Claymore, ETriggerEvent::Started, this, &AMSPlayerCharacter::Input_Claymore);
	EIC->BindAction(A.Sentry, ETriggerEvent::Started, this, &AMSPlayerCharacter::Input_Sentry);
	EIC->BindAction(A.Airstrike, ETriggerEvent::Started, this, &AMSPlayerCharacter::Input_Airstrike);
	EIC->BindAction(A.Squad, ETriggerEvent::Started, this, &AMSPlayerCharacter::Input_Squad);
	EIC->BindAction(A.SkipBreak, ETriggerEvent::Started, this, &AMSPlayerCharacter::Input_SkipPressed);
	EIC->BindAction(A.SkipBreak, ETriggerEvent::Completed, this, &AMSPlayerCharacter::Input_SkipReleased);
}

void AMSPlayerCharacter::SetInputBlocked(bool bBlocked)
{
	bInputBlocked = bBlocked;
	if (bBlocked)
	{
		MoveInput = FVector2D::ZeroVector;
		bFireHeld = false;
		bADSHeld = false;
		if (AMSWeapon* W = GetCurrentWeapon())
		{
			W->SetTriggerHeld(false);
		}
		StopSprint();
		if (bInteractHeld)
		{
			Input_InteractReleased(FInputActionValue());
		}
	}
}

void AMSPlayerCharacter::Input_Move(const FInputActionValue& Value)
{
	if (bInputBlocked || IsDead())
	{
		return;
	}
	MoveInput = Value.Get<FVector2D>();
	if (Controller)
	{
		const FRotator YawRot(0.f, Controller->GetControlRotation().Yaw, 0.f);
		AddMovementInput(FRotationMatrix(YawRot).GetUnitAxis(EAxis::X), MoveInput.Y);
		AddMovementInput(FRotationMatrix(YawRot).GetUnitAxis(EAxis::Y), MoveInput.X);
	}
}

void AMSPlayerCharacter::Input_MoveCompleted(const FInputActionValue& Value)
{
	MoveInput = FVector2D::ZeroVector;
}

void AMSPlayerCharacter::Input_Look(const FInputActionValue& Value)
{
	if (bInputBlocked || !Controller)
	{
		return;
	}
	const FMSPlayerFeelRow& Feel = UMSDataSubsystem::Get(this)->GetPlayerFeel();
	const float Sens = Feel.LookSensitivity * Feel.MouseDegreesPerUnit * FMath::Lerp(1.f, Feel.ADSSensitivityMultiplier, ADSAlpha);
	const FVector2D Delta = Value.Get<FVector2D>() * Sens;
	LookAccum += Delta;
	FRotator Rot = Controller->GetControlRotation();
	Rot.Yaw += Delta.X;
	Rot.Pitch = FMath::Clamp(FRotator::NormalizeAxis(Rot.Pitch + Delta.Y), -89.f, 89.f);
	Controller->SetControlRotation(Rot);
	CameraFeel->NotifyLookInput(Delta.Y);
}

void AMSPlayerCharacter::Input_LookGamepad(const FInputActionValue& Value)
{
	if (bInputBlocked || !Controller)
	{
		return;
	}
	const FMSPlayerFeelRow& Feel = UMSDataSubsystem::Get(this)->GetPlayerFeel();
	const float Dt = GetWorld()->GetDeltaSeconds();
	const float Rate = Feel.GamepadLookRate * Feel.LookSensitivity * FMath::Lerp(1.f, Feel.ADSSensitivityMultiplier, ADSAlpha);
	const FVector2D Stick = Value.Get<FVector2D>();
	// Response curve: fine aim near the centre, full speed at the edge.
	const FVector2D Curved(FMath::Sign(Stick.X) * Stick.X * Stick.X, FMath::Sign(Stick.Y) * Stick.Y * Stick.Y);
	const FVector2D Delta = Curved * Rate * Dt;
	LookAccum += Delta;
	FRotator Rot = Controller->GetControlRotation();
	Rot.Yaw += Delta.X;
	Rot.Pitch = FMath::Clamp(FRotator::NormalizeAxis(Rot.Pitch + Delta.Y), -89.f, 89.f);
	Controller->SetControlRotation(Rot);
	CameraFeel->NotifyLookInput(Delta.Y);
}

bool AMSPlayerCharacter::CanJumpInternal_Implementation() const
{
	return !bDowned && Super::CanJumpInternal_Implementation();
}

void AMSPlayerCharacter::Input_Jump(const FInputActionValue& Value)
{
	if (bInputBlocked || IsDead() || bDowned)
	{
		return;
	}
	if (bSliding)
	{
		EndSlide();
	}
	if (bIsCrouched)
	{
		UnCrouch();
		return;
	}
	Jump();
}

void AMSPlayerCharacter::Input_Sprint(const FInputActionValue& Value)
{
	if (bInputBlocked || bDowned)
	{
		return;
	}
	bSprintRequested = !bSprintRequested || !bSprinting;
	if (bIsCrouched && !bSliding)
	{
		UnCrouch();
	}
}

void AMSPlayerCharacter::Input_Crouch(const FInputActionValue& Value)
{
	if (bInputBlocked || bDowned)
	{
		return;
	}
	const FMSPlayerFeelRow& Feel = UMSDataSubsystem::Get(this)->GetPlayerFeel();
	const bool bCanSlide = bSprinting && GetCharacterMovement()->IsMovingOnGround()
		&& GetVelocity().Size2D() >= Feel.SlideMinSpeed && SlideCooldownLeft <= 0.f;
	if (bCanSlide)
	{
		StartSlide();
		return;
	}
	if (bSliding)
	{
		EndSlide();
		return;
	}
	if (bIsCrouched)
	{
		UnCrouch();
	}
	else
	{
		StopSprint();
		Crouch();
	}
}

void AMSPlayerCharacter::Input_FirePressed(const FInputActionValue& Value)
{
	if (bInputBlocked || IsDead())
	{
		return;
	}
	bFireHeld = true;
	if (AMSWeapon* W = GetCurrentWeapon())
	{
		if (bSprinting)
		{
			// Sprint-out time before the first shot: the core "commit to sprinting" trade-off.
			W->BlockFiring(UMSDataSubsystem::Get(this)->GetPlayerFeel().SprintToFireTime * SprintAlpha);
			StopSprint();
		}
		W->SetTriggerHeld(true);
	}
}

void AMSPlayerCharacter::Input_FireReleased(const FInputActionValue& Value)
{
	bFireHeld = false;
	if (AMSWeapon* W = GetCurrentWeapon())
	{
		W->SetTriggerHeld(false);
	}
}

void AMSPlayerCharacter::Input_ADSPressed(const FInputActionValue& Value)
{
	if (bInputBlocked || IsDead())
	{
		return;
	}
	bADSHeld = true;
	StopSprint();
}

void AMSPlayerCharacter::Input_ADSReleased(const FInputActionValue& Value)
{
	bADSHeld = false;
}

void AMSPlayerCharacter::Input_Reload(const FInputActionValue& Value)
{
	if (bInputBlocked)
	{
		return;
	}
	if (AMSWeapon* W = GetCurrentWeapon())
	{
		W->StartReload();
	}
}

void AMSPlayerCharacter::Input_Interact(const FInputActionValue& Value)
{
	if (bInputBlocked || bDowned || IsDead())
	{
		return;
	}
	// A downed teammate in reach takes priority: hold to revive.
	if (ReviveCandidate.IsValid())
	{
		bInteractHeld = true;
		if (AMSWeapon* W = GetCurrentWeapon())
		{
			W->SetTriggerHeld(false);
			W->BlockFiring(1000.f);
		}
		ServerSetReviving(true);
		return;
	}
	if (AActor* Target = FocusedInteractable.Get())
	{
		if (IMSInteractable* I = Cast<IMSInteractable>(Target))
		{
			if (I->CanInteract(this))
			{
				I->Interact(this);
			}
		}
	}
}

void AMSPlayerCharacter::Input_InteractReleased(const FInputActionValue& Value)
{
	if (bInteractHeld)
	{
		bInteractHeld = false;
		if (AMSWeapon* W = GetCurrentWeapon())
		{
			W->SetFireBlock(0.2f);
		}
		ServerSetReviving(false);
	}
}

void AMSPlayerCharacter::Input_SwitchWeapon(const FInputActionValue& Value)
{
	if (bInputBlocked || bDowned)
	{
		return;
	}
	const float Axis = Value.Get<float>();
	CycleWeapon(Axis < 0.f ? -1 : 1);
}

void AMSPlayerCharacter::Input_Melee(const FInputActionValue& Value)
{
	if (bInputBlocked || bDowned || MeleeCooldownLeft > 0.f || IsDead())
	{
		return;
	}
	const FMSPlayerFeelRow& Feel = UMSDataSubsystem::Get(this)->GetPlayerFeel();
	MeleeCooldownLeft = Feel.MeleeCooldown;
	ViewModel->OnMelee();
	StopSprint();
	if (AMSWeapon* W = GetCurrentWeapon())
	{
		W->BlockFiring(0.45f);
		W->CancelReload();
	}
	FVector Start, Dir;
	GetAimRay(Start, Dir);
	ServerMelee(Start, Dir);
}

void AMSPlayerCharacter::ServerMelee_Implementation(FVector_NetQuantize Start, FVector_NetQuantizeNormal Direction)
{
	const FMSPlayerFeelRow& Feel = UMSDataSubsystem::Get(this)->GetPlayerFeel();
	FHitResult Hit;
	FCollisionQueryParams Params(SCENE_QUERY_STAT(MSMelee), false, this);
	if (!GetWorld()->SweepSingleByChannel(Hit, Start, Start + FVector(Direction) * Feel.MeleeRange, FQuat::Identity, ECC_MSWeapon, FCollisionShape::MakeSphere(25.f), Params))
	{
		return;
	}
	FMSDamageInfo Info;
	Info.Amount = Feel.MeleeDamage;
	Info.Kind = EMSDamageKind::Melee;
	Info.HitLocation = Hit.ImpactPoint;
	Info.SourceLocation = Start;
	Info.ImpulseDirection = Direction;
	Info.Impulse = 30000.f;
	Info.Instigator = GetController();
	Info.Causer = this;
	Info.SourceTeam = EMSTeam::Player;
	const FMSHitReport Report = UMSCombatLibrary::DealDamage(Hit.GetActor(), Info, Hit.GetComponent());
	if (Report.bHitDamageable)
	{
		OnWeaponHit(Report);
	}
	UGameplayStatics::PlaySoundAtLocation(this, LoadObject<USoundBase>(nullptr, Report.bHitDamageable ? TEXT("/Game/Audio/impact_flesh.impact_flesh") : TEXT("/Game/Audio/impact.impact")), Hit.ImpactPoint);
}

void AMSPlayerCharacter::Input_GrenadePressed(const FInputActionValue& Value)
{
	if (bInputBlocked || bDowned || bCookingGrenade || GetEquipmentCount(EMSEquipmentSlot::Frag) <= 0)
	{
		return;
	}
	bCookingGrenade = true;
	GrenadeCookTime = 0.f;
	if (AMSWeapon* W = GetCurrentWeapon())
	{
		W->SetTriggerHeld(false);
		W->CancelReload();
		W->BlockFiring(10.f);
	}
}

void AMSPlayerCharacter::Input_GrenadeReleased(const FInputActionValue& Value)
{
	if (bCookingGrenade)
	{
		ThrowGrenade(false);
	}
}

void AMSPlayerCharacter::ThrowGrenade(bool bDropAtFeet)
{
	bCookingGrenade = false;
	if (AMSWeapon* W = GetCurrentWeapon())
	{
		W->SetFireBlock(0.45f);
	}
	ViewModel->OnThrow();
	const FMSEquipmentRow& Row = UMSDataSubsystem::Get(this)->GetEquipment(TEXT("Frag"));
	FVector Start, Dir;
	GetAimRay(Start, Dir);
	const FVector Right = Camera->GetRightVector();
	const FVector SpawnLoc = bDropAtFeet ? GetActorLocation() : Start + Dir * 40.f + Right * 15.f - FVector(0, 0, 10.f);
	const FVector Velocity = bDropAtFeet ? FVector::ZeroVector : (Dir + FVector(0, 0, 0.18f)).GetSafeNormal() * Row.ThrowSpeed + GetVelocity() * 0.5f;
	ServerThrowGrenade(SpawnLoc, Velocity, FMath::Max(0.05f, Row.FuseTime - GrenadeCookTime));
	GrenadeCookTime = 0.f;
}

void AMSPlayerCharacter::ServerThrowGrenade_Implementation(FVector_NetQuantize SpawnLocation, FVector_NetQuantize Velocity, float Fuse)
{
	if (GetEquipmentCount(EMSEquipmentSlot::Frag) <= 0 || IsDead())
	{
		return;
	}
	AddEquipment(EMSEquipmentSlot::Frag, -1);
	FActorSpawnParameters Params;
	Params.Owner = this;
	Params.Instigator = this;
	Params.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
	if (AMSGrenade* Grenade = GetWorld()->SpawnActor<AMSGrenade>(SpawnLocation, FRotator::ZeroRotator, Params))
	{
		Grenade->Arm(TEXT("Frag"), Velocity, Fuse, GetController(), EMSTeam::Player, this);
	}
}

bool AMSPlayerCharacter::FindGroundInFront(float Distance, FVector& OutLocation) const
{
	const FVector Fwd = FRotator(0.f, GetControlRotation().Yaw, 0.f).Vector();
	const FVector Probe = GetActorLocation() + Fwd * Distance;
	FHitResult Hit;
	FCollisionQueryParams Params(SCENE_QUERY_STAT(MSPlace), false, this);
	// Make sure nothing blocks the path to the spot first.
	if (GetWorld()->LineTraceTestByChannel(GetActorLocation(), Probe, ECC_Visibility, Params))
	{
		return false;
	}
	if (GetWorld()->LineTraceSingleByChannel(Hit, Probe + FVector(0, 0, 50), Probe - FVector(0, 0, 300), ECC_Visibility, Params))
	{
		OutLocation = Hit.ImpactPoint;
		return true;
	}
	return false;
}

void AMSPlayerCharacter::Input_Claymore(const FInputActionValue& Value)
{
	FVector Loc;
	if (bInputBlocked || bDowned || GetEquipmentCount(EMSEquipmentSlot::Claymore) <= 0 || !FindGroundInFront(70.f, Loc))
	{
		return;
	}
	ViewModel->OnThrow();
	ServerPlaceClaymore(Loc, GetControlRotation().Yaw);
}

void AMSPlayerCharacter::ServerPlaceClaymore_Implementation(FVector_NetQuantize Location, float Yaw)
{
	if (GetEquipmentCount(EMSEquipmentSlot::Claymore) <= 0 || bDowned)
	{
		return;
	}
	FActorSpawnParameters Params;
	Params.Owner = this;
	Params.Instigator = this;
	Params.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
	if (AMSClaymore* Claymore = GetWorld()->SpawnActor<AMSClaymore>(Location, FRotator(0.f, Yaw, 0.f), Params))
	{
		Claymore->Arm(TEXT("Claymore"), GetController(), EMSTeam::Player);
		AddEquipment(EMSEquipmentSlot::Claymore, -1);
	}
}

void AMSPlayerCharacter::Input_Sentry(const FInputActionValue& Value)
{
	FVector Loc;
	if (bInputBlocked || bDowned || GetEquipmentCount(EMSEquipmentSlot::Sentry) <= 0 || !FindGroundInFront(150.f, Loc))
	{
		return;
	}
	ServerPlaceSentry(Loc, GetControlRotation().Yaw);
}

void AMSPlayerCharacter::ServerPlaceSentry_Implementation(FVector_NetQuantize Location, float Yaw)
{
	if (GetEquipmentCount(EMSEquipmentSlot::Sentry) <= 0 || bDowned)
	{
		return;
	}
	FActorSpawnParameters Params;
	Params.Owner = this;
	Params.Instigator = this;
	Params.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AdjustIfPossibleButDontSpawnIfColliding;
	// Root box is 55 cm half-height: spawn its centre just above the ground.
	if (AMSSentryGun* Sentry = GetWorld()->SpawnActor<AMSSentryGun>(FVector(Location) + FVector(0.f, 0.f, 57.f), FRotator(0.f, Yaw, 0.f), Params))
	{
		Sentry->Deploy(TEXT("Sentry"), GetController(), EMSTeam::Player);
		AddEquipment(EMSEquipmentSlot::Sentry, -1);
	}
}

void AMSPlayerCharacter::Input_Airstrike(const FInputActionValue& Value)
{
	if (bInputBlocked || bDowned || GetEquipmentCount(EMSEquipmentSlot::Airstrike) <= 0)
	{
		return;
	}
	const FMSEquipmentRow& Row = UMSDataSubsystem::Get(this)->GetEquipment(TEXT("Airstrike"));
	FVector Start, Dir;
	GetAimRay(Start, Dir);
	FHitResult Hit;
	FCollisionQueryParams Params(SCENE_QUERY_STAT(MSDesignate), false, this);
	if (GetWorld()->LineTraceSingleByChannel(Hit, Start, Start + Dir * Row.DesignateRange, ECC_Visibility, Params))
	{
		ServerCallAirstrike(Hit.ImpactPoint, GetControlRotation().Yaw);
	}
}

void AMSPlayerCharacter::ServerCallAirstrike_Implementation(FVector_NetQuantize Location, float Yaw)
{
	if (GetEquipmentCount(EMSEquipmentSlot::Airstrike) <= 0 || bDowned)
	{
		return;
	}
	FActorSpawnParameters Params;
	Params.Owner = this;
	Params.Instigator = this;
	Params.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
	if (AMSAirstrike* Strike = GetWorld()->SpawnActor<AMSAirstrike>(Location, FRotator(0.f, Yaw, 0.f), Params))
	{
		Strike->Begin(TEXT("Airstrike"), GetController(), EMSTeam::Player);
		AddEquipment(EMSEquipmentSlot::Airstrike, -1);
	}
}

void AMSPlayerCharacter::Input_Squad(const FInputActionValue& Value)
{
	if (!bInputBlocked && !bDowned && GetEquipmentCount(EMSEquipmentSlot::Squad) > 0)
	{
		ServerCallSquad();
	}
}

void AMSPlayerCharacter::ServerCallSquad_Implementation()
{
	if (GetEquipmentCount(EMSEquipmentSlot::Squad) <= 0 || bDowned)
	{
		return;
	}
	if (AMSGameMode* GM = GetWorld()->GetAuthGameMode<AMSGameMode>())
	{
		if (GM->SpawnSquad(this, TEXT("AISquad")) > 0)
		{
			AddEquipment(EMSEquipmentSlot::Squad, -1);
		}
	}
}

void AMSPlayerCharacter::Input_SkipPressed(const FInputActionValue& Value)
{
	bSkipHeld = true;
	SkipHeldTime = 0.f;
}

void AMSPlayerCharacter::Input_SkipReleased(const FInputActionValue& Value)
{
	bSkipHeld = false;
	SkipHeldTime = 0.f;
}

float AMSPlayerCharacter::GetSkipHoldFraction() const
{
	const float Hold = UMSDataSubsystem::Get(this)->GetRules().SkipHoldTime;
	return bSkipHeld && Hold > 0.f ? FMath::Clamp(SkipHeldTime / Hold, 0.f, 1.f) : 0.f;
}

void AMSPlayerCharacter::ServerSetSkipReady_Implementation(bool bReady)
{
	if (AMSGameMode* GM = GetWorld()->GetAuthGameMode<AMSGameMode>())
	{
		GM->SetPlayerReady(GetController(), bReady);
	}
}

// ------------------------------------------------------------------------------- movement (owner)

void AMSPlayerCharacter::StartSprint()
{
	bSprinting = true;
	if (AMSWeapon* W = GetCurrentWeapon())
	{
		W->SetTriggerHeld(false);
	}
}

void AMSPlayerCharacter::StopSprint()
{
	bSprinting = false;
	bSprintRequested = false;
}

void AMSPlayerCharacter::StartSlide()
{
	const FMSPlayerFeelRow& Feel = UMSDataSubsystem::Get(this)->GetPlayerFeel();
	UCharacterMovementComponent* Move = GetCharacterMovement();
	bSliding = true;
	SlideTimeLeft = Feel.SlideDuration;
	bSprinting = false;
	bSprintRequested = false;
	Crouch();
	Move->GroundFriction = Feel.SlideGroundFriction;
	Move->BrakingDecelerationWalking = Feel.SlideBraking;
	Move->MaxWalkSpeedCrouched = Feel.SlideMaxSpeed;
	Move->MaxAcceleration = Feel.Acceleration * 0.12f;   // steer a little, can't accelerate
	const FVector Flat = FVector(Move->Velocity.X, Move->Velocity.Y, 0.f);
	const float NewSpeed = FMath::Min(Feel.SlideMaxSpeed, Flat.Size() + Feel.SlideBoost);
	Move->Velocity = Flat.GetSafeNormal() * NewSpeed + FVector(0, 0, Move->Velocity.Z);
	CameraFeel->AddTrauma(Feel.SlideTrauma);
}

void AMSPlayerCharacter::EndSlide()
{
	if (!bSliding)
	{
		return;
	}
	bSliding = false;
	const FMSPlayerFeelRow& Feel = UMSDataSubsystem::Get(this)->GetPlayerFeel();
	SlideCooldownLeft = Feel.SlideCooldown;
	ApplyFeelToMovement();
	UnCrouch();
}

void AMSPlayerCharacter::UpdateMovementState(float Dt)
{
	const UMSDataSubsystem* Data = UMSDataSubsystem::Get(this);
	const FMSPlayerFeelRow& Feel = Data->GetPlayerFeel();
	UCharacterMovementComponent* Move = GetCharacterMovement();
	SlideCooldownLeft = FMath::Max(0.f, SlideCooldownLeft - Dt);
	MeleeCooldownLeft = FMath::Max(0.f, MeleeCooldownLeft - Dt);

	if (bSliding)
	{
		SlideTimeLeft -= Dt;
		const float Speed = GetVelocity().Size2D();
		if (SlideTimeLeft <= 0.f || Speed < Feel.CrouchSpeed * 1.1f || (!Move->IsMovingOnGround() && SlideTimeLeft < Feel.SlideDuration * 0.5f))
		{
			EndSlide();
		}
	}

	// Downed: stay low (crouch is driven by the owner for client-authoritative movement).
	if (bDowned && !bIsCrouched)
	{
		Crouch();
	}

	// Sprint: needs forward input, ground, no ADS, not downed. Holding fire cancels it.
	const bool bForward = MoveInput.Y >= Feel.SprintMinForwardInput;
	if (bSprintRequested && bForward && !bADSHeld && !bDowned && !bSliding && Move->IsMovingOnGround() && !bCookingGrenade && !bInteractHeld)
	{
		if (!bSprinting)
		{
			StartSprint();
		}
	}
	else if (bSprinting && (!bForward || bADSHeld || bDowned))
	{
		StopSprint();
	}
	SprintAlpha = FMath::FInterpTo(SprintAlpha, bSprinting ? 1.f : 0.f, Dt, 10.f);

	if (!bSliding)
	{
		const AMSWeapon* W = GetCurrentWeapon();
		const float WeaponMul = W ? W->GetRow().MoveSpeedMultiplier : 1.f;
		const float ADSMul = FMath::Lerp(1.f, Feel.ADSSpeedMultiplier, ADSAlpha);
		float Speed = bSprinting ? Feel.SprintSpeed : Feel.WalkSpeed;
		Speed *= WeaponMul * ADSMul;
		const float ReviveMul = bInteractHeld ? 0.3f : 1.f;
		Move->MaxWalkSpeed = bDowned ? Feel.LastStandMoveSpeed : Speed * ReviveMul;
		Move->MaxWalkSpeedCrouched = bDowned ? Feel.LastStandMoveSpeed : Feel.CrouchSpeed * WeaponMul * ADSMul * ReviveMul;
	}
}

void AMSPlayerCharacter::UpdateADS(float Dt)
{
	const AMSWeapon* W = GetCurrentWeapon();
	const bool bCanADS = W && bADSHeld && !bSprinting && !bSliding && !bCookingGrenade && !bInputBlocked && !bInteractHeld;
	const float Time = W ? FMath::Max(0.05f, W->GetRow().ADSTime) : 0.2f;
	ADSAlpha = FMath::Clamp(ADSAlpha + (bCanADS ? 1.f : -1.f) * Dt / Time, 0.f, 1.f);
}

void AMSPlayerCharacter::UpdateInteraction()
{
	FocusedInteractable = nullptr;
	ReviveCandidate = nullptr;
	if (bDowned || IsDead())
	{
		return;
	}
	// Downed teammates within reach.
	const float ReviveRange = UMSDataSubsystem::Get(this)->GetRules().ReviveRange;
	float Best = ReviveRange;
	for (TActorIterator<AMSPlayerCharacter> It(GetWorld()); It; ++It)
	{
		AMSPlayerCharacter* Other = *It;
		if (Other != this && Other->IsDowned() && !Other->IsDead())
		{
			const float D = FVector::Dist(Other->GetActorLocation(), GetActorLocation());
			if (D < Best)
			{
				Best = D;
				ReviveCandidate = Other;
			}
		}
	}
	if (ReviveCandidate.IsValid())
	{
		return;
	}
	const float Range = UMSDataSubsystem::Get(this)->GetPlayerFeel().InteractRange;
	FVector Start, Dir;
	GetAimRay(Start, Dir);
	TArray<FHitResult> Hits;
	FCollisionQueryParams Params(SCENE_QUERY_STAT(MSInteract), false, this);
	GetWorld()->SweepMultiByChannel(Hits, Start, Start + Dir * Range, FQuat::Identity, ECC_Visibility, FCollisionShape::MakeSphere(30.f), Params);
	for (const FHitResult& Hit : Hits)
	{
		AActor* Actor = Hit.GetActor();
		if (Actor && Actor->Implements<UMSInteractable>())
		{
			FocusedInteractable = Actor;
			return;
		}
	}
}

FText AMSPlayerCharacter::GetInteractPrompt() const
{
	if (ReviveCandidate.IsValid())
	{
		return NSLOCTEXT("MS", "Revive", "Hold [E] to revive");
	}
	if (const IMSInteractable* I = Cast<IMSInteractable>(FocusedInteractable.Get()))
	{
		return I->GetInteractPrompt(this);
	}
	return FText::GetEmpty();
}

void AMSPlayerCharacter::UpdateGrenade(float Dt)
{
	if (!bCookingGrenade)
	{
		return;
	}
	GrenadeCookTime += Dt;
	const FMSEquipmentRow& Row = UMSDataSubsystem::Get(this)->GetEquipment(TEXT("Frag"));
	if (GrenadeCookTime >= Row.FuseTime)
	{
		// Held too long: it goes off in your hand.
		ThrowGrenade(true);
	}
}

void AMSPlayerCharacter::UpdateSkip(float Dt)
{
	const AMSGameState* GS = GetWorld()->GetGameState<AMSGameState>();
	if (bSkipReadySent && (!GS || GS->Phase != EMSMatchPhase::Intermission))
	{
		bSkipReadySent = false;   // a new break needs a new ready-up
	}
	if (!bSkipHeld)
	{
		return;
	}
	SkipHeldTime += Dt;
	const float Hold = UMSDataSubsystem::Get(this)->GetRules().SkipHoldTime;
	if (SkipHeldTime >= Hold)
	{
		bSkipHeld = false;
		SkipHeldTime = 0.f;
		bSkipReadySent = !bSkipReadySent;   // hold again to un-ready
		ServerSetSkipReady(bSkipReadySent);
	}
}

// ------------------------------------------------------------------------------- health, downed, revive (server)

void AMSPlayerCharacter::RecordDamage(const FVector& Source, float Amount)
{
	FMSRecentDamage D;
	D.SourceLocation = Source;
	D.Time = GetWorld()->GetTimeSeconds();
	D.Amount = Amount;
	RecentDamage.Add(D);
	if (RecentDamage.Num() > 8)
	{
		RecentDamage.RemoveAt(0);
	}
	const FMSLookRow& Look = UMSDataSubsystem::Get(this)->GetLook();
	CameraFeel->AddTrauma(Amount * Look.DamageTraumaPerHP);
}

void AMSPlayerCharacter::HandleDamaged(UMSHealthComponent* InHealth, const FMSDamageInfo& Info, float HealthDamage, float ArmorDamage)
{
	if (IsLocallyControlled())
	{
		RecordDamage(Info.SourceLocation, HealthDamage + ArmorDamage);
	}
	else
	{
		ClientNotifyDamaged(Info.SourceLocation, HealthDamage + ArmorDamage);
	}
}

void AMSPlayerCharacter::ClientNotifyDamaged_Implementation(FVector_NetQuantize Source, float Amount)
{
	RecordDamage(Source, Amount);
}

bool AMSPlayerCharacter::HandleLethalDamage(const FMSDamageInfo& Info)
{
	if (bDowned)
	{
		return false;   // shot while down: dead
	}
	const AMSGameState* GS = GetWorld()->GetGameState<AMSGameState>();
	const bool bCoop = GS && GS->IsCoop();
	if (bCoop)
	{
		// Co-op: always go down; a remaining last stand lets you get up on your own.
		const bool bSelf = LastStandsLeft > 0;
		if (bSelf)
		{
			--LastStandsLeft;
		}
		EnterLastStand(bSelf);
		return true;
	}
	if (LastStandsLeft <= 0)
	{
		return false;
	}
	--LastStandsLeft;
	EnterLastStand(true);
	return true;
}

void AMSPlayerCharacter::EnterLastStand(bool bCanSelfRevive)
{
	const FMSPlayerFeelRow& Feel = UMSDataSubsystem::Get(this)->GetPlayerFeel();
	const FMSGameRulesRow& Rules = UMSDataSubsystem::Get(this)->GetRules();
	bDowned = true;
	bSelfRevive = bCanSelfRevive;
	DownedTimeLeft = bCanSelfRevive ? Feel.LastStandDuration : Rules.BleedOutTime;
	ReviveProgress = 0.f;
	LastStandInvulnLeft = Feel.LastStandInvulnerableTime;
	Health->SetHealth(Feel.LastStandHealth);
	Health->ConfigureRegen(0.f, 0.f);
	Health->bInvulnerable = true;

	WeaponIndexBeforeDown = CurrentWeaponIndex;
	if (!LastStandWeapon)
	{
		FActorSpawnParameters Params;
		Params.Owner = this;
		Params.Instigator = this;
		LastStandWeapon = GetWorld()->SpawnActor<AMSWeapon>(AMSWeapon::StaticClass(), GetActorTransform(), Params);
		if (LastStandWeapon)
		{
			LastStandWeapon->Setup(Feel.LastStandWeapon, this, IsLocallyControlled());
			LastStandWeapon->AttachToComponent(WeaponPivot, FAttachmentTransformRules::SnapToTargetNotIncludingScale);
		}
	}
	if (LastStandWeapon)
	{
		LastStandWeapon->FillAmmo();
	}
	OnRep_Downed();
	if (AMSGameMode* GM = GetWorld()->GetAuthGameMode<AMSGameMode>())
	{
		GM->OnPlayerDowned(this);
	}
	UE_LOG(LogMS, Log, TEXT("%s is down (%s)."), *GetName(), bCanSelfRevive ? TEXT("last stand") : TEXT("needs a revive"));
}

void AMSPlayerCharacter::ExitLastStand()
{
	const FMSPlayerFeelRow& Feel = UMSDataSubsystem::Get(this)->GetPlayerFeel();
	bDowned = false;
	bSelfRevive = false;
	ReviveProgress = 0.f;
	DownedTimeLeft = 0.f;
	Health->bInvulnerable = false;
	Health->SetHealth(Feel.LastStandReviveHealth);
	Health->ConfigureRegen(Feel.RegenDelay, Feel.RegenRate);
	CurrentWeaponIndex = FMath::Clamp(WeaponIndexBeforeDown, 0, FMath::Max(0, Weapons.Num() - 1));
	OnRep_Downed();
}

void AMSPlayerCharacter::ReviveFromTeammate()
{
	if (bDowned && !IsDead())
	{
		ExitLastStand();
	}
}

void AMSPlayerCharacter::OnRep_Downed()
{
	// Everyone: swap to the pistol / back, squash the third-person body. Owner: crouch & effects.
	ApplyEquipLocally(CurrentWeaponIndex);
	GetMesh()->SetRelativeScale3D(FVector(1.f, 1.f, bDowned ? 0.45f : 1.f));
	if (IsLocallyControlled())
	{
		if (bDowned)
		{
			bADSHeld = false;
			bFireHeld = false;
			EndSlide();
			StopSprint();
			bCookingGrenade = false;
			Crouch();
			CameraFeel->AddTrauma(0.6f);
			if (LastStandWeapon)
			{
				ViewModel->OnEquip();
			}
		}
		else
		{
			UnCrouch();
			ViewModel->OnEquip();
		}
	}
}

void AMSPlayerCharacter::UpdateDowned(float Dt)
{
	if (!bDowned || !HasAuthority())
	{
		return;
	}
	if (LastStandInvulnLeft > 0.f)
	{
		LastStandInvulnLeft -= Dt;
		if (LastStandInvulnLeft <= 0.f)
		{
			Health->bInvulnerable = false;
		}
	}
	// Being revived pauses the bleed-out clock.
	if (!bBeingRevivedThisFrame)
	{
		ReviveProgress = 0.f;
		DownedTimeLeft -= Dt;
	}
	bBeingRevivedThisFrame = false;
	if (DownedTimeLeft <= 0.f && !Health->IsDead())
	{
		if (bSelfRevive)
		{
			ExitLastStand();
		}
		else
		{
			FMSDamageInfo BleedOut;
			BleedOut.SourceTeam = EMSTeam::Neutral;
			BleedOut.SourceLocation = GetActorLocation();
			Health->Kill(BleedOut);
		}
	}
}

void AMSPlayerCharacter::ServerSetReviving_Implementation(bool bHolding)
{
	bReviveHeldOnServer = bHolding;
}

void AMSPlayerCharacter::UpdateRevive(float Dt)
{
	if (!HasAuthority() || !bReviveHeldOnServer || bDowned || IsDead())
	{
		return;
	}
	const FMSGameRulesRow& Rules = UMSDataSubsystem::Get(this)->GetRules();
	AMSPlayerCharacter* Target = nullptr;
	float Best = Rules.ReviveRange + 30.f;   // a little slack for movement/latency
	for (TActorIterator<AMSPlayerCharacter> It(GetWorld()); It; ++It)
	{
		if (*It != this && It->IsDowned() && !It->IsDead())
		{
			const float D = FVector::Dist(It->GetActorLocation(), GetActorLocation());
			if (D < Best)
			{
				Best = D;
				Target = *It;
			}
		}
	}
	if (!Target)
	{
		return;
	}
	Target->bBeingRevivedThisFrame = true;
	Target->ReviveProgress = MSRules::ReviveStep(Target->ReviveProgress, true, Rules.ReviveTime, Dt);
	if (Target->ReviveProgress >= 1.f)
	{
		Target->ReviveFromTeammate();
		bReviveHeldOnServer = false;
	}
}

void AMSPlayerCharacter::HandleDied(UMSHealthComponent* InHealth, const FMSDamageInfo& KillingBlow)
{
	bDowned = false;
	for (AMSWeapon* W : Weapons)
	{
		if (W)
		{
			W->SetEquipped(false);
		}
	}
	if (LastStandWeapon)
	{
		LastStandWeapon->SetEquipped(false);
	}
	GetMesh()->SetRelativeScale3D(FVector(1.f, 1.f, 0.15f));
	if (IsLocallyControlled())
	{
		SetInputBlocked(true);
		CameraFeel->AddTrauma(1.f);
	}
	GetCharacterMovement()->DisableMovement();
	if (HasAuthority())
	{
		if (AMSGameMode* GM = GetWorld()->GetAuthGameMode<AMSGameMode>())
		{
			GM->OnPlayerKilled(this, KillingBlow);
		}
	}
}

void AMSPlayerCharacter::Landed(const FHitResult& Hit)
{
	Super::Landed(Hit);
	const float FallSpeed = -GetCharacterMovement()->Velocity.Z;
	if (IsLocallyControlled())
	{
		CameraFeel->NotifyLanded(FallSpeed);
	}
	const FMSPlayerFeelRow& Feel = UMSDataSubsystem::Get(this)->GetPlayerFeel();
	if (HasAuthority() && FallSpeed > Feel.FallDamageMinSpeed)
	{
		FMSDamageInfo Info;
		Info.Amount = (FallSpeed - Feel.FallDamageMinSpeed) * Feel.FallDamagePerSpeed;
		Info.Kind = EMSDamageKind::Fall;
		Info.SourceLocation = GetActorLocation() - FVector(0, 0, 100);
		Info.HitLocation = GetActorLocation();
		Info.SourceTeam = EMSTeam::Neutral;
		Health->ApplyDamage(Info);
	}
}

// ------------------------------------------------------------------------------- tick

void AMSPlayerCharacter::FeedFeelComponents(float Dt)
{
	const UMSDataSubsystem* Data = UMSDataSubsystem::Get(this);
	const FMSPlayerFeelRow& Feel = Data->GetPlayerFeel();
	const AMSWeapon* W = GetCurrentWeapon();

	FMSCameraFeelInput CamIn;
	CamIn.HorizontalSpeed = GetVelocity().Size2D();
	CamIn.WalkSpeed = Feel.WalkSpeed;
	CamIn.bGrounded = GetCharacterMovement()->IsMovingOnGround();
	CamIn.SprintAlpha = SprintAlpha;
	CamIn.bSliding = bSliding;
	CamIn.ADSAlpha = ADSAlpha;
	CamIn.ADSFOV = W ? W->GetRow().ADSFOV : Feel.BaseFOV;
	const float StandEye = Feel.CapsuleHalfHeight + Feel.StandEyeHeight;
	const float CrouchEye = Feel.CrouchedHalfHeight + Feel.CrouchEyeHeight;
	CamIn.EyeHeightAboveFeet = bDowned ? Feel.LastStandEyeHeight : (bIsCrouched ? CrouchEye : StandEye);
	CamIn.CapsuleHalfHeight = GetCapsuleComponent()->GetScaledCapsuleHalfHeight();
	CamIn.StrafeInput = MoveInput.X;
	CameraFeel->SetInput(CamIn);

	LookRate = Dt > 0.f ? LookAccum / Dt : FVector2D::ZeroVector;
	LookAccum = FVector2D::ZeroVector;

	FMSViewModelInput VMIn;
	VMIn.ADSAlpha = ADSAlpha;
	VMIn.SprintAlpha = SprintAlpha;
	VMIn.LookRate = LookRate;
	VMIn.LocalVelocity = Camera->GetComponentTransform().InverseTransformVectorNoScale(GetVelocity());
	VMIn.WalkSpeed = Feel.WalkSpeed;
	VMIn.bGrounded = CamIn.bGrounded;
	VMIn.bReloading = W && W->IsReloading();
	VMIn.ReloadProgress = W ? W->GetReloadProgress() : 0.f;
	VMIn.bDowned = bDowned;
	VMIn.BobPhase = CameraFeel->GetBobPhase();
	VMIn.BobAmount = CameraFeel->GetBobAmount();
	ViewModel->SetInput(VMIn);
}

void AMSPlayerCharacter::Tick(float DeltaSeconds)
{
	Super::Tick(DeltaSeconds);

	// Server-side rules.
	UpdateDowned(DeltaSeconds);
	UpdateRevive(DeltaSeconds);

	if (!IsLocallyControlled())
	{
		return;   // remote players: CameraFeel/ViewModel pose them from the replicated aim
	}
	// Weapons can replicate in before our controller does: make sure they render first-person.
	for (AMSWeapon* W : Weapons)
	{
		if (W)
		{
			W->SetFirstPerson(true);
		}
	}
	if (LastStandWeapon)
	{
		LastStandWeapon->SetFirstPerson(true);
	}
	if (IsDead())
	{
		FeedFeelComponents(DeltaSeconds);
		return;
	}
	UpdateMovementState(DeltaSeconds);
	UpdateADS(DeltaSeconds);
	UpdateGrenade(DeltaSeconds);
	UpdateSkip(DeltaSeconds);
	InteractionTimer -= DeltaSeconds;
	if (InteractionTimer <= 0.f)
	{
		InteractionTimer = 0.1f;
		UpdateInteraction();
	}
	if (bInteractHeld && !ReviveCandidate.IsValid())
	{
		Input_InteractReleased(FInputActionValue());
	}
	// Keep the trigger state in sync (after a sprint-out, menu close or weapon swap).
	if (AMSWeapon* W = GetCurrentWeapon())
	{
		if (bFireHeld && !bSprinting && !W->IsTriggerHeld() && !bCookingGrenade && !bInteractHeld)
		{
			W->SetTriggerHeld(true);
		}
	}
	FeedFeelComponents(DeltaSeconds);
}
