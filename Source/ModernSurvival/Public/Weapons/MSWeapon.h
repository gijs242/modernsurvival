#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "Data/MSDataTypes.h"
#include "Combat/MSCombatTypes.h"
#include "MSWeapon.generated.h"

class UMSWeaponVisualComponent;
class IMSWeaponHolder;

DECLARE_MULTICAST_DELEGATE(FMSWeaponEvent);

/**
 * One gun. All numbers come from a DT_Weapons row; the holder (player, AI, turret, helicopter)
 * supplies the aim ray and modifiers through IMSWeaponHolder. Hitscan with pellets, or a
 * projectile for launchers.
 *
 * Networking (co-op):
 * - The machine that controls the trigger fires: the owning client for players, the server for AI,
 *   turrets and the listen-server host. Recoil, muzzle flash, sound, tracer and impacts play there
 *   immediately (prediction).
 * - A client sends the exact shot directions to the server (ServerFire); the server re-traces them
 *   and applies damage (it trusts the client's aim: co-op, not anti-cheat).
 * - Everyone else sees the shot through MulticastFireFX.
 * - Ammo is simulated by the owner and the server; server-side refills are pushed with ClientSetAmmo.
 */
UCLASS()
class MODERNSURVIVAL_API AMSWeapon : public AActor
{
	GENERATED_BODY()

public:
	AMSWeapon();

	/** Server (or standalone): call right after spawning. Holder must implement IMSWeaponHolder. */
	void Setup(FName InRowName, AActor* InHolder, bool bFirstPerson);
	/** Rebuilds the visual as first-person (owning player's view) or world model. */
	void SetFirstPerson(bool bInFirstPerson);

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
	UFUNCTION(BlueprintPure, Category = "Weapon") bool IsEquipped() const { return bEquipped; }
	UFUNCTION(BlueprintPure, Category = "Weapon") bool CanFire() const;
	UFUNCTION(BlueprintPure, Category = "Weapon") bool IsTriggerHeld() const { return bTriggerHeld; }
	/** Current cone half-angle in degrees (crosshair uses this). */
	UFUNCTION(BlueprintPure, Category = "Weapon") float GetCurrentSpread() const;
	UFUNCTION(BlueprintPure, Category = "Weapon") FTransform GetMuzzleTransform() const;
	UMSWeaponVisualComponent* GetVisual() const { return Visual; }
	AActor* GetHolderActor() const { return Holder; }

	FMSWeaponEvent OnFired;
	FMSWeaponEvent OnReloadStarted;
	FMSWeaponEvent OnReloadFinished;
	FMSWeaponEvent OnDryFire;

	/** Visual class to use (swap in a Blueprint subclass for skeletal guns). */
	UPROPERTY(EditDefaultsOnly, Category = "Weapon") TSubclassOf<UMSWeaponVisualComponent> VisualClass;

	virtual void Tick(float DeltaSeconds) override;
	virtual void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const override;

protected:
	void LoadRowAndVisual();
	void FireShot();
	/** Traces each direction. With bApplyDamage (server only) deals damage. Returns combined hit report. */
	FMSHitReport TraceShots(const FVector& Start, const TArray<FVector>& Directions, bool bApplyDamage, bool bPlayImpacts, TArray<FVector>& OutEnds, bool& bOutFlesh);
	void SpawnProjectile(const FVector& Start, const FVector& Direction);
	void PlayLocalFireCosmetics(const TArray<FVector>& Ends, bool bLocalHolder);
	void FinishReload();
	IMSWeaponHolder* GetHolder() const;
	bool IsHolderLocallyControlled() const;
	void PushAmmoToOwner();

	UFUNCTION(Server, Reliable) void ServerFire(FVector_NetQuantize Start, const TArray<FVector_NetQuantizeNormal>& Directions);
	UFUNCTION(Server, Reliable) void ServerReload();
	UFUNCTION(NetMulticast, Unreliable) void MulticastFireFX(FVector_NetQuantize Muzzle, const TArray<FVector_NetQuantize>& Ends, bool bFlesh);
	UFUNCTION(Client, Reliable) void ClientSetAmmo(int32 InMag, int32 InReserve);

	UFUNCTION() void OnRep_Setup();
	UFUNCTION() void OnRep_Equipped();

	UPROPERTY(VisibleAnywhere, Category = "Weapon") TObjectPtr<UMSWeaponVisualComponent> Visual;
	UPROPERTY(ReplicatedUsing = OnRep_Setup) TObjectPtr<AActor> Holder;
	UPROPERTY(ReplicatedUsing = OnRep_Setup) FName RowName;
	UPROPERTY(Replicated) int32 AmmoInMag = 0;
	UPROPERTY(Replicated) int32 AmmoReserve = 0;
	UPROPERTY(ReplicatedUsing = OnRep_Equipped) bool bEquipped = false;

	FMSWeaponRow Row;
	bool bRowLoaded = false;
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
	float EquipTimeLeft = 0.f;
	float FireBlockedFor = 0.f;
	bool bFirstPerson = false;
	bool bVisualBuilt = false;
};
