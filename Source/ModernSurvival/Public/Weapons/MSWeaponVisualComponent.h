#pragma once

#include "CoreMinimal.h"
#include "Components/SceneComponent.h"
#include "Data/MSDataTypes.h"
#include "MSWeaponVisualComponent.generated.h"

class UStaticMeshComponent;

/**
 * The swappable "art" side of a weapon. Gameplay only ever asks it for the muzzle transform.
 *
 * - If the weapon row has a Mesh, that mesh is shown. Imported glTF/FBX guns are auto-oriented
 *   (barrel along +X) and auto-scaled (metres -> cm) from their bounds, so any free model works.
 * - Otherwise a placeholder gun is built from engine basic shapes.
 *
 * To use skeletal guns with animations later, subclass this in C++ or Blueprint, override
 * BuildVisual/GetMuzzleTransform, and set the subclass on the weapon (AMSWeapon::VisualClass).
 * The origin convention is: X forward, Z up, origin on the sight line above the grip.
 */
UCLASS(Blueprintable, ClassGroup = (ModernSurvival), meta = (BlueprintSpawnableComponent))
class MODERNSURVIVAL_API UMSWeaponVisualComponent : public USceneComponent
{
	GENERATED_BODY()

public:
	UMSWeaponVisualComponent();

	UFUNCTION(BlueprintNativeEvent, Category = "Weapon") void BuildVisual(const FMSWeaponRow& Row, bool bFirstPerson);
	UFUNCTION(BlueprintNativeEvent, BlueprintPure, Category = "Weapon") FTransform GetMuzzleTransform() const;
	UFUNCTION(BlueprintCallable, Category = "Weapon") void SetVisualHidden(bool bHidden);

	/** Small recoil animation of moving parts on the placeholder (slide/bolt). */
	void PlayFireAnim();
	virtual void TickComponent(float DeltaTime, ELevelTick TickType, FActorComponentTickFunction* ThisTickFunction) override;

protected:
	void ClearVisual();
	void MarkFirstPerson(UStaticMeshComponent* Comp, bool bFirstPerson);
	void BuildPlaceholder(const FMSWeaponRow& Row, bool bFirstPerson);

	UPROPERTY(Transient) TArray<TObjectPtr<UStaticMeshComponent>> Parts;
	UPROPERTY(Transient) TObjectPtr<UStaticMeshComponent> MovingPart;
	FVector MuzzleLocal = FVector(55.f, 0.f, -3.f);
	FVector MovingPartRest = FVector::ZeroVector;
	float MovingPartKick = 0.f;
};
