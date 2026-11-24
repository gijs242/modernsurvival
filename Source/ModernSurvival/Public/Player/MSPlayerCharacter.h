#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Character.h"
#include "Combat/MSCombatTypes.h"
#include "Weapons/MSWeaponHolder.h"
#include "MSPlayerCharacter.generated.h"

class UCameraComponent;
class UCapsuleComponent;
class UMSHealthComponent;
class UMSCameraFeelComponent;
class UMSViewModelComponent;
class AMSWeapon;
struct FInputActionValue;

UENUM(BlueprintType)
enum class EMSEquipmentSlot : uint8
{
	Frag,
	Claymore,
	Sentry,
	Airstrike,
	Squad,
	Count UMETA(Hidden)
};

/** Recent events the HUD reads every frame (no delegate lifetime issues). */
struct FMSRecentDamage
{
	FVector SourceLocation = FVector::ZeroVector;
	double Time = 0.0;
	float Amount = 0.f;
};

struct FMSRecentHit
{
	double Time = -100.0;
	bool bKilled = false;
	bool bHeadshot = false;
	bool bArmor = false;
};

UCLASS()
class MODERNSURVIVAL_API AMSPlayerCharacter : public ACharacter, public IMSWeaponHolder
{
	GENERATED_BODY()

public:
	AMSPlayerCharacter(const FObjectInitializer& ObjectInitializer);

	// --- IMSWeaponHolder
	virtual void GetAimRay(FVector& OutStart, FVector& OutDirection) const override;
	virtual EMSTeam GetHolderTeam() const override { return EMSTeam::Player; }
	virtual AController* GetHolderController() const override { return GetController(); }
	virtual float GetADSAlpha() const override { return ADSAlpha; }
	virtual float GetMoveSpreadFraction() const override;
	virtual bool IsAirborne() const override;
	virtual bool IsLocalPlayerHolder() const override { return IsLocallyControlled(); }
	virtual void OnWeaponFired(const FMSWeaponRow& Row, int32 ShotIndex) override;
	virtual void OnWeaponHit(const FMSHitReport& Report) override;

	// --- Inventory
	UFUNCTION(BlueprintCallable, Category = "Inventory") AMSWeapon* GiveWeapon(FName WeaponRow, bool bEquip = true);
	UFUNCTION(BlueprintPure, Category = "Inventory") AMSWeapon* GetCurrentWeapon() const;
	UFUNCTION(BlueprintPure, Category = "Inventory") bool HasWeapon(FName WeaponRow) const;
	UFUNCTION(BlueprintCallable, Category = "Inventory") void EquipWeaponIndex(int32 Index);
	UFUNCTION(BlueprintCallable, Category = "Inventory") void CycleWeapon(int32 Direction);
	const TArray<TObjectPtr<AMSWeapon>>& GetWeapons() const { return Weapons; }

	UFUNCTION(BlueprintPure, Category = "Inventory") int32 GetEquipmentCount(EMSEquipmentSlot Slot) const;
	/** Adds up to the table's MaxCarried. Returns how many were actually added. */
	UFUNCTION(BlueprintCallable, Category = "Inventory") int32 AddEquipment(EMSEquipmentSlot Slot, int32 Amount);
	UFUNCTION(BlueprintPure, Category = "Inventory") int32 GetEquipmentMax(EMSEquipmentSlot Slot) const;
	static FName EquipmentRowFor(EMSEquipmentSlot Slot);

	// --- State for HUD / camera / AI
	UFUNCTION(BlueprintPure, Category = "State") bool IsSprinting() const { return bSprinting; }
	UFUNCTION(BlueprintPure, Category = "State") bool IsSliding() const { return bSliding; }
	UFUNCTION(BlueprintPure, Category = "State") bool IsDowned() const { return bDowned; }
	UFUNCTION(BlueprintPure, Category = "State") bool IsDead() const;
	UFUNCTION(BlueprintPure, Category = "State") float GetLastStandTimeLeft() const { return LastStandTimeLeft; }
	UFUNCTION(BlueprintPure, Category = "State") int32 GetLastStandsLeft() const { return LastStandsLeft; }
	UFUNCTION(BlueprintPure, Category = "State") float GetGrenadeCookTime() const { return bCookingGrenade ? GrenadeCookTime : 0.f; }
	UFUNCTION(BlueprintPure, Category = "State") float GetSkipHoldFraction() const;
	AActor* GetFocusedInteractable() const { return FocusedInteractable.Get(); }
	FText GetInteractPrompt() const;
	const TArray<FMSRecentDamage>& GetRecentDamage() const { return RecentDamage; }
	const FMSRecentHit& GetLastHit() const { return LastHit; }

	UMSHealthComponent* GetHealth() const { return Health; }
	UCameraComponent* GetCamera() const { return Camera; }
	UMSCameraFeelComponent* GetCameraFeel() const { return CameraFeel; }

	/** Freezes gameplay input while a menu (shop) is open. */
	void SetInputBlocked(bool bBlocked);

	// --- Input (bound by SetupPlayerInputComponent to the controller's runtime input actions)
	void Input_Move(const FInputActionValue& Value);
	void Input_MoveCompleted(const FInputActionValue& Value);
	void Input_Look(const FInputActionValue& Value);
	void Input_LookGamepad(const FInputActionValue& Value);
	void Input_Jump(const FInputActionValue& Value);
	void Input_Sprint(const FInputActionValue& Value);
	void Input_Crouch(const FInputActionValue& Value);
	void Input_FirePressed(const FInputActionValue& Value);
	void Input_FireReleased(const FInputActionValue& Value);
	void Input_ADSPressed(const FInputActionValue& Value);
	void Input_ADSReleased(const FInputActionValue& Value);
	void Input_Reload(const FInputActionValue& Value);
	void Input_Interact(const FInputActionValue& Value);
	void Input_SwitchWeapon(const FInputActionValue& Value);
	void Input_Weapon1(const FInputActionValue& Value) { EquipWeaponIndex(0); }
	void Input_Weapon2(const FInputActionValue& Value) { EquipWeaponIndex(1); }
	void Input_Melee(const FInputActionValue& Value);
	void Input_GrenadePressed(const FInputActionValue& Value);
	void Input_GrenadeReleased(const FInputActionValue& Value);
	void Input_Claymore(const FInputActionValue& Value);
	void Input_Sentry(const FInputActionValue& Value);
	void Input_Airstrike(const FInputActionValue& Value);
	void Input_Squad(const FInputActionValue& Value);
	void Input_SkipPressed(const FInputActionValue& Value);
	void Input_SkipReleased(const FInputActionValue& Value);

	virtual void Tick(float DeltaSeconds) override;

protected:
	virtual void BeginPlay() override;
	virtual void EndPlay(const EEndPlayReason::Type Reason) override;
	virtual void SetupPlayerInputComponent(UInputComponent* PlayerInputComponent) override;
	virtual void Landed(const FHitResult& Hit) override;
	virtual bool CanJumpInternal_Implementation() const override;

	void ApplyFeelToMovement();
	void UpdateMovementState(float Dt);
	void UpdateADS(float Dt);
	void UpdateInteraction();
	void UpdateGrenade(float Dt);
	void UpdateLastStand(float Dt);
	void UpdateSkip(float Dt);
	void FeedFeelComponents(float Dt);

	void StartSprint();
	void StopSprint();
	void StartSlide();
	void EndSlide();
	void ThrowGrenade(bool bDropAtFeet);
	bool FindGroundInFront(float Distance, FVector& OutLocation) const;

	bool HandleLethalDamage(const FMSDamageInfo& Info);
	void EnterLastStand();
	void ExitLastStand();
	UFUNCTION() void HandleDamaged(UMSHealthComponent* InHealth, const FMSDamageInfo& Info, float HealthDamage, float ArmorDamage);
	UFUNCTION() void HandleDied(UMSHealthComponent* InHealth, const FMSDamageInfo& KillingBlow);

	// --- Components
	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "Components") TObjectPtr<UCameraComponent> Camera;
	/** Everything first-person (arms, gun) hangs off this; MSViewModelComponent moves it. */
	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "Components") TObjectPtr<USceneComponent> WeaponPivot;
	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "Components") TObjectPtr<UMSHealthComponent> Health;
	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "Components") TObjectPtr<UMSCameraFeelComponent> CameraFeel;
	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "Components") TObjectPtr<UMSViewModelComponent> ViewModel;
	/** Blocks the Weapon trace channel so enemy bullets can hit the player (the capsule ignores it). */
	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "Components") TObjectPtr<UCapsuleComponent> Hitbox;

	UPROPERTY(Transient) TArray<TObjectPtr<AMSWeapon>> Weapons;
	UPROPERTY(Transient) TObjectPtr<AMSWeapon> LastStandWeapon;
	int32 CurrentWeaponIndex = 0;
	int32 Equipment[static_cast<int32>(EMSEquipmentSlot::Count)] = {0, 0, 0, 0, 0};

	// Movement state
	FVector2D MoveInput = FVector2D::ZeroVector;
	FVector2D LookRate = FVector2D::ZeroVector;
	FVector2D LookAccum = FVector2D::ZeroVector;
	bool bSprintRequested = false;
	bool bSprinting = false;
	float SprintAlpha = 0.f;
	bool bSliding = false;
	float SlideTimeLeft = 0.f;
	float SlideCooldownLeft = 0.f;
	bool bFireHeld = false;
	bool bADSHeld = false;
	float ADSAlpha = 0.f;
	float MeleeCooldownLeft = 0.f;
	bool bInputBlocked = false;

	// Grenade
	bool bCookingGrenade = false;
	float GrenadeCookTime = 0.f;

	// Last stand
	bool bDowned = false;
	int32 LastStandsLeft = 1;
	float LastStandTimeLeft = 0.f;
	float LastStandInvulnLeft = 0.f;
	int32 WeaponIndexBeforeDown = 0;

	// Skip break
	bool bSkipHeld = false;
	float SkipHeldTime = 0.f;

	TWeakObjectPtr<AActor> FocusedInteractable;
	float InteractionTimer = 0.f;
	TArray<FMSRecentDamage> RecentDamage;
	FMSRecentHit LastHit;
};
