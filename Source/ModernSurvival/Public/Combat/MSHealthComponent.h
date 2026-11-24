#pragma once

#include "CoreMinimal.h"
#include "Components/ActorComponent.h"
#include "Combat/MSCombatTypes.h"
#include "MSHealthComponent.generated.h"

class UMSHealthComponent;

DECLARE_DYNAMIC_MULTICAST_DELEGATE_FourParams(FMSOnDamaged, UMSHealthComponent*, Health, const FMSDamageInfo&, Info, float, HealthDamage, float, ArmorDamage);
DECLARE_DYNAMIC_MULTICAST_DELEGATE_TwoParams(FMSOnDied, UMSHealthComponent*, Health, const FMSDamageInfo&, KillingBlow);
DECLARE_DYNAMIC_MULTICAST_DELEGATE_OneParam(FMSOnArmorBroken, UMSHealthComponent*, Health);

/** Asked before lethal damage is applied. Return true to keep the owner alive (last stand). */
DECLARE_DELEGATE_RetVal_OneParam(bool, FMSLethalDamageInterceptor, const FMSDamageInfo&);

/**
 * Health, armor, team and regeneration for anything that can be shot: players, enemies,
 * helicopters, sentries. Numbers are pushed in by the owner from DataTables.
 */
UCLASS(ClassGroup = (ModernSurvival), meta = (BlueprintSpawnableComponent))
class MODERNSURVIVAL_API UMSHealthComponent : public UActorComponent
{
	GENERATED_BODY()

public:
	UMSHealthComponent();

	static UMSHealthComponent* Find(const AActor* Actor);

	/** Applies damage (armor, reductions, team checks). Returns the hit report for hitmarkers. */
	UFUNCTION(BlueprintCallable, Category = "Health") FMSHitReport ApplyDamage(const FMSDamageInfo& Info);

	UFUNCTION(BlueprintCallable, Category = "Health") void SetMaxHealth(float NewMax, bool bFill = true);
	UFUNCTION(BlueprintCallable, Category = "Health") void SetHealth(float NewHealth);
	UFUNCTION(BlueprintCallable, Category = "Health") void AddArmor(float Amount, float Cap);
	UFUNCTION(BlueprintCallable, Category = "Health") void Kill(const FMSDamageInfo& Info);
	UFUNCTION(BlueprintCallable, Category = "Health") void Revive(float NewHealth);
	UFUNCTION(BlueprintCallable, Category = "Health") void ConfigureRegen(float Delay, float Rate) { RegenDelay = Delay; RegenRate = Rate; }

	UFUNCTION(BlueprintPure, Category = "Health") bool IsDead() const { return bDead; }
	UFUNCTION(BlueprintPure, Category = "Health") float GetHealth() const { return Health; }
	UFUNCTION(BlueprintPure, Category = "Health") float GetMaxHealth() const { return MaxHealth; }
	UFUNCTION(BlueprintPure, Category = "Health") float GetHealthFraction() const { return MaxHealth > 0.f ? Health / MaxHealth : 0.f; }
	UFUNCTION(BlueprintPure, Category = "Health") float GetArmor() const { return Armor; }
	UFUNCTION(BlueprintPure, Category = "Health") float GetMaxArmor() const { return MaxArmor; }
	UFUNCTION(BlueprintPure, Category = "Health") EMSTeam GetTeam() const { return Team; }
	UFUNCTION(BlueprintPure, Category = "Health") float GetTimeSinceDamage() const;
	UFUNCTION(BlueprintCallable, Category = "Health") void SetTeam(EMSTeam NewTeam) { Team = NewTeam; }

	/** Damage taken in the last Window seconds (AI uses this to decide it is being suppressed). */
	float GetRecentDamage(float Window) const;

	UPROPERTY(BlueprintAssignable, Category = "Health") FMSOnDamaged OnDamaged;
	UPROPERTY(BlueprintAssignable, Category = "Health") FMSOnDied OnDied;
	UPROPERTY(BlueprintAssignable, Category = "Health") FMSOnArmorBroken OnArmorBroken;
	FMSLethalDamageInterceptor LethalDamageInterceptor;

	virtual void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const override;

	// Tuning (set by the owner from DataTables) ------------------------------------------
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Replicated, Category = "Health") EMSTeam Team = EMSTeam::Enemy;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Health") float ArmorAbsorb = 0.8f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Health") float DamageReduction = 0.f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Health") float HeadshotScale = 1.f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Health") float ExplosiveScale = 1.f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Health") float SelfDamageScale = 1.f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Health") bool bInvulnerable = false;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Health") bool bAllowFriendlyFire = false;

protected:
	virtual void BeginPlay() override;
	virtual void EndPlay(const EEndPlayReason::Type Reason) override;
	virtual void TickComponent(float DeltaTime, ELevelTick TickType, FActorComponentTickFunction* ThisTickFunction) override;

private:
	// Server-authoritative; replicated so every client's HUD and effects see the same numbers.
	UPROPERTY(VisibleAnywhere, Replicated, Category = "Health") float MaxHealth = 100.f;
	UPROPERTY(VisibleAnywhere, Replicated, Category = "Health") float Health = 100.f;
	UPROPERTY(VisibleAnywhere, Replicated, Category = "Health") float Armor = 0.f;
	UPROPERTY(VisibleAnywhere, Replicated, Category = "Health") float MaxArmor = 0.f;
	UPROPERTY(VisibleAnywhere, ReplicatedUsing = OnRep_Dead, Category = "Health") bool bDead = false;
	float RegenDelay = 0.f;
	float RegenRate = 0.f;
	double LastDamageTime = -1000.0;

	/** Clients: fire OnDied locally so ragdolls, sounds and HUD react. */
	UFUNCTION() void OnRep_Dead();
	bool HasAuthorityOver() const;

	struct FRecentHit { double Time; float Amount; };
	TArray<FRecentHit> RecentHits;
};
