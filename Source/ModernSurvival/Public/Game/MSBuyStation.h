#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "Game/MSInteractable.h"
#include "Data/MSDataTypes.h"
#include "MSBuyStation.generated.h"

class UBoxComponent;
class UTextRenderComponent;
class UPointLightComponent;
class AMSPlayerCharacter;

UENUM(BlueprintType)
enum class EMSPurchaseResult : uint8
{
	Purchased,
	NotEnoughCash,
	Locked,
	AlreadyMaxed,
	Invalid
};

/** One of the three buy stations (weapons, equipment, air support). Press Interact to open its shop. */
UCLASS()
class MODERNSURVIVAL_API AMSBuyStation : public AActor, public IMSInteractable
{
	GENERATED_BODY()

public:
	AMSBuyStation();

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Shop") EMSShopCategory Category = EMSShopCategory::Weapons;

	virtual FText GetInteractPrompt(const AMSPlayerCharacter* Player) const override;
	virtual void Interact(AMSPlayerCharacter* Player) override;

	static FText CategoryName(EMSShopCategory Category);

	/** All purchase rules (price, unlock wave, capacity). Used by the shop UI and tests. */
	static EMSPurchaseResult TryPurchase(AMSPlayerCharacter* Player, FName ShopRow, FText& OutMessage);
	static EMSPurchaseResult CanPurchase(const AMSPlayerCharacter* Player, FName ShopRow, int32& OutPrice);

protected:
	virtual void OnConstruction(const FTransform& Transform) override;
	virtual void BeginPlay() override;
	void BuildVisual();

	UPROPERTY(VisibleAnywhere, Category = "Components") TObjectPtr<UBoxComponent> Collision;
	UPROPERTY(VisibleAnywhere, Category = "Components") TObjectPtr<UTextRenderComponent> Sign;
	UPROPERTY(VisibleAnywhere, Category = "Components") TObjectPtr<UPointLightComponent> Light;
	bool bVisualBuilt = false;
};
