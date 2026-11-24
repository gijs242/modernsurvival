#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Pawn.h"
#include "Combat/MSCombatTypes.h"
#include "Weapons/MSWeaponHolder.h"
#include "MSAttackHelicopter.generated.h"

class USphereComponent;
class UMSHealthComponent;
class AMSWeapon;
class UAudioComponent;

UENUM()
enum class EMSHeliState : uint8
{
	Inbound,
	Orbit,
	Dying
};

/**
 * Attack helicopter: flies in from an air spawn point, orbits the player at altitude, strafes with
 * a minigun and fires rockets. Needs no navmesh. Placeholder body unless the DT_Enemies row has a
 * StaticMesh. Takes extra damage from explosives (launcher!).
 */
UCLASS()
class MODERNSURVIVAL_API AMSAttackHelicopter : public APawn, public IMSWeaponHolder
{
	GENERATED_BODY()

public:
	AMSAttackHelicopter();

	void InitFromRow(FName InEnemyRow, float HealthMultiplier, float DamageMultiplier, float AccuracyMultiplier);

	// IMSWeaponHolder
	virtual void GetAimRay(FVector& OutStart, FVector& OutDirection) const override;
	virtual EMSTeam GetHolderTeam() const override { return EMSTeam::Enemy; }
	virtual AController* GetHolderController() const override { return GetController(); }
	virtual float GetWeaponDamageScale() const override;
	virtual float GetExtraSpreadDegrees() const override { return AimError; }
	virtual bool HasInfiniteAmmo() const override { return true; }

	UMSHealthComponent* GetHealth() const { return Health; }
	virtual void Tick(float DeltaSeconds) override;

protected:
	virtual void BeginPlay() override;
	void BuildVisual();
	void UpdateTarget();
	void UpdateWeapons(float Dt);
	void FireRocket();

	UFUNCTION() void HandleDied(UMSHealthComponent* InHealth, const FMSDamageInfo& KillingBlow);

	UPROPERTY(VisibleAnywhere, Category = "Components") TObjectPtr<USphereComponent> Body;
	UPROPERTY(VisibleAnywhere, Category = "Components") TObjectPtr<UMSHealthComponent> Health;
	UPROPERTY(VisibleAnywhere, Category = "Components") TObjectPtr<USceneComponent> Visual;
	UPROPERTY(VisibleAnywhere, Category = "Components") TObjectPtr<USceneComponent> GunMount;
	UPROPERTY(Transient) TObjectPtr<USceneComponent> Rotor;
	UPROPERTY(Transient) TObjectPtr<AMSWeapon> Gun;
	UPROPERTY(Transient) TObjectPtr<UAudioComponent> RotorAudio;

	FName EnemyRowName;
	FMSEnemyRow Row;
	float DamageMultiplier = 1.f;
	float AccuracyMultiplier = 1.f;
	EMSHeliState State = EMSHeliState::Inbound;
	TWeakObjectPtr<AActor> Target;
	float OrbitAngle = 0.f;
	float OrbitDirection = 1.f;
	FVector Velocity = FVector::ZeroVector;
	float AimError = 3.f;
	float BurstLeft = 0.f;
	float PauseLeft = 2.f;
	float RocketLeft = 4.f;
	float DyingTime = 0.f;
	float TargetTimer = 0.f;
};
