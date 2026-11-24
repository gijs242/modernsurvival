#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "Data/MSDataTypes.h"
#include "MSWeapon.generated.h"

class UMSWeaponVisualComponent;
class IMSWeaponHolder;

DECLARE_MULTICAST_DELEGATE(FMSWeaponEvent);

/**
 * One gun. All numbers come from a DT_Weapons row; the holder (player, AI, turret, helicopter)
 * supplies the aim ray and modifiers through IMSWeaponHolder. Hitscan with pellets, or a
 * projectile for launchers.
 */
UCLASS()
class MODERNSURVIVAL_API AMSWeapon : public AActor
{
	GENERATED_BODY()

public:
	AMSWeapon();

	/** Must be called right after spawning. Holder must implement IMSWeaponHolder. */
	void Setup(FName InRowName, AActor* InHolder, bool bFirstPerson);

	UFUNCTION(BlueprintCallable, Category = "Weapon") void SetTriggerHeld(bool bHeld);
	UFUNCTION(BlueprintCallable, Category = "Weapon") bool StartReload();
	UFUNCTION(BlueprintCallable, Category = "Weapon") void CancelReload();
	UFUNCTION(BlueprintCallable, Category = "Weapon") void SetEquipped(bool bInEquipped);
	UFUNCTION(BlueprintCallable, Category = "Weapon") void FillAmmo();
	UFUNCTION(BlueprintCallable, Category = "Weapon") void AddReserveAmmo(int32 Amount);
	/** Blocks firing for Seconds (sprint-out, melee, grenade throw). */
	void BlockFiring(float Seconds);
	/** Sets the block to exactly Seconds (0 clears it). */
	void SetFireBlock(float Seconds) { FireBlockedFor = FMath::Max(0.f, Seconds); }

	UFUNCTION(BlueprintPure, Category = "Weapon") FName GetRowName() const { return RowName; }
	const FMSWeaponRow& GetRow() const { return Row; }
	UFUNCTION(BlueprintPure, Category = "Weapon") int32 GetAmmoInMag() const { return AmmoInMag; }
	UFUNCTION(BlueprintPure, Category = "Weapon") int32 GetReserveAmmo() const { return AmmoReserve; }
	UFUNCTION(BlueprintPure, Category = "Weapon") int32 GetMaxReserveAmmo() const { return Row.MaxReserveAmmo; }
	UFUNCTION(BlueprintPure, Category = "Weapon") bool IsReloading() const { return bReloading; }
	UFUNCTION(BlueprintPure, Category = "Weapon") float GetReloadProgress() const;
	UFUNCTION(BlueprintPure, Category = "Weapon") bool IsEquipping() const { return EquipTimeLeft > 0.f; }
	UFUNCTION(BlueprintPure, Category = "Weapon") bool CanFire() const;
	UFUNCTION(BlueprintPure, Category = "Weapon") bool IsTriggerHeld() const { return bTriggerHeld; }
	/** Current cone half-angle in degrees (crosshair uses this). */
	UFUNCTION(BlueprintPure, Category = "Weapon") float GetCurrentSpread() const;
	UFUNCTION(BlueprintPure, Category = "Weapon") FTransform GetMuzzleTransform() const;
	UMSWeaponVisualComponent* GetVisual() const { return Visual; }

	FMSWeaponEvent OnFired;
	FMSWeaponEvent OnReloadStarted;
	FMSWeaponEvent OnReloadFinished;
	FMSWeaponEvent OnDryFire;

	/** Visual class to use (swap in a Blueprint subclass for skeletal guns). */
	UPROPERTY(EditDefaultsOnly, Category = "Weapon") TSubclassOf<UMSWeaponVisualComponent> VisualClass;

	virtual void Tick(float DeltaSeconds) override;

protected:
	void FireShot();
	void FireHitscan(const FVector& Start, const FVector& Direction, float Spread);
	void FireProjectile(const FVector& Start, const FVector& Direction, float Spread);
	void FinishReload();
	IMSWeaponHolder* GetHolder() const;

	UPROPERTY(VisibleAnywhere, Category = "Weapon") TObjectPtr<UMSWeaponVisualComponent> Visual;
	UPROPERTY(Transient) TObjectPtr<AActor> Holder;

	FName RowName;
	FMSWeaponRow Row;
	int32 AmmoInMag = 0;
	int32 AmmoReserve = 0;
	bool bTriggerHeld = false;
	bool bTriggerConsumed = false;   // semi-auto needs a fresh press
	int32 BurstShotsLeft = 0;
	int32 ShotIndex = 0;             // shots in the current spray (recoil pattern)
	int32 TotalShots = 0;
	double NextFireTime = 0.0;
	double LastFireTime = -10.0;
	float Bloom = 0.f;
	bool bReloading = false;
	float ReloadElapsed = 0.f;
	float ReloadDuration = 0.f;
	bool bEquipped = false;
	float EquipTimeLeft = 0.f;
	float FireBlockedFor = 0.f;
	bool bFirstPerson = false;
};
