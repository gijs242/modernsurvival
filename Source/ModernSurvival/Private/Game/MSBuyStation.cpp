#include "Game/MSBuyStation.h"

#include "Combat/MSHealthComponent.h"
#include "Core/MSRules.h"
#include "Data/MSDataSubsystem.h"
#include "FX/MSFXLibrary.h"
#include "Game/MSGameState.h"
#include "Player/MSPlayerCharacter.h"
#include "Player/MSPlayerController.h"
#include "Player/MSPlayerState.h"
#include "Weapons/MSWeapon.h"
#include "Components/BoxComponent.h"
#include "Components/PointLightComponent.h"
#include "Components/StaticMeshComponent.h"
#include "Components/TextRenderComponent.h"
#include "Engine/World.h"
#include "Materials/MaterialInstanceDynamic.h"

#define LOCTEXT_NAMESPACE "MSShop"

AMSBuyStation::AMSBuyStation()
{
	Collision = CreateDefaultSubobject<UBoxComponent>(TEXT("Collision"));
	Collision->InitBoxExtent(FVector(60.f, 110.f, 55.f));
	Collision->SetCollisionProfileName(TEXT("BlockAll"));
	Collision->SetRelativeLocation(FVector(0.f, 0.f, 55.f));
	SetRootComponent(Collision);

	Sign = CreateDefaultSubobject<UTextRenderComponent>(TEXT("Sign"));
	Sign->SetupAttachment(Collision);
	Sign->SetRelativeLocation(FVector(62.f, 0.f, 95.f));
	Sign->SetHorizontalAlignment(EHTA_Center);
	Sign->SetVerticalAlignment(EVRTA_TextCenter);
	Sign->SetWorldSize(26.f);
	Sign->SetTextRenderColor(FColor(235, 235, 225));

	Light = CreateDefaultSubobject<UPointLightComponent>(TEXT("Light"));
	Light->SetupAttachment(Collision);
	Light->SetRelativeLocation(FVector(90.f, 0.f, 140.f));
	Light->SetIntensityUnits(ELightUnits::Candelas);
	Light->SetIntensity(25.f);
	Light->SetAttenuationRadius(450.f);
	Light->SetCastShadows(false);
}

FText AMSBuyStation::CategoryName(EMSShopCategory InCategory)
{
	switch (InCategory)
	{
	case EMSShopCategory::Weapons: return LOCTEXT("Weapons", "WEAPONS");
	case EMSShopCategory::Equipment: return LOCTEXT("Equipment", "EQUIPMENT");
	case EMSShopCategory::AirSupport: return LOCTEXT("AirSupport", "AIR SUPPORT");
	}
	return FText::GetEmpty();
}

void AMSBuyStation::OnConstruction(const FTransform& Transform)
{
	Super::OnConstruction(Transform);
	Sign->SetText(CategoryName(Category));
	const FLinearColor Color = Category == EMSShopCategory::Weapons ? FLinearColor(1.f, 0.75f, 0.4f)
		: Category == EMSShopCategory::Equipment ? FLinearColor(0.5f, 0.85f, 1.f) : FLinearColor(1.f, 0.4f, 0.35f);
	Light->SetLightColor(Color);
}

void AMSBuyStation::BeginPlay()
{
	Super::BeginPlay();
	BuildVisual();
}

void AMSBuyStation::BuildVisual()
{
	if (bVisualBuilt)
	{
		return;
	}
	bVisualBuilt = true;
	// Placeholder: a field table with a crate and a sign board. Swap for a Megascans prop set later.
	const FLinearColor Olive(0.16f, 0.17f, 0.11f);
	const FLinearColor Wood(0.28f, 0.2f, 0.12f);
	const FLinearColor Accent = Category == EMSShopCategory::Weapons ? FLinearColor(0.45f, 0.3f, 0.1f)
		: Category == EMSShopCategory::Equipment ? FLinearColor(0.12f, 0.25f, 0.35f) : FLinearColor(0.4f, 0.08f, 0.06f);
	UMSFXLibrary::AddPlaceholderShape(this, Collision, TEXT("Cube"), FTransform(FRotator::ZeroRotator, FVector(0, 0, 18), FVector(1.1f, 2.1f, 0.08f)), Wood, false);
	UMSFXLibrary::AddPlaceholderShape(this, Collision, TEXT("Cube"), FTransform(FRotator::ZeroRotator, FVector(0, -90, -20), FVector(0.9f, 0.08f, 0.7f)), Olive, false);
	UMSFXLibrary::AddPlaceholderShape(this, Collision, TEXT("Cube"), FTransform(FRotator::ZeroRotator, FVector(0, 90, -20), FVector(0.9f, 0.08f, 0.7f)), Olive, false);
	UMSFXLibrary::AddPlaceholderShape(this, Collision, TEXT("Cube"), FTransform(FRotator(0, 15, 0), FVector(-10, 40, 45), FVector(0.55f, 0.9f, 0.45f)), Olive, false);
	UMSFXLibrary::AddPlaceholderShape(this, Collision, TEXT("Cube"), FTransform(FRotator::ZeroRotator, FVector(50, 0, 95), FVector(0.05f, 1.8f, 0.45f)), Accent, false);
	UMSFXLibrary::AddPlaceholderShape(this, Collision, TEXT("Cylinder"), FTransform(FRotator::ZeroRotator, FVector(50, -85, 40), FVector(0.05f, 0.05f, 1.3f)), Olive, false);
	UMSFXLibrary::AddPlaceholderShape(this, Collision, TEXT("Cylinder"), FTransform(FRotator::ZeroRotator, FVector(50, 85, 40), FVector(0.05f, 0.05f, 1.3f)), Olive, false);
}

FText AMSBuyStation::GetInteractPrompt(const AMSPlayerCharacter* Player) const
{
	return FText::Format(LOCTEXT("Prompt", "[E] Open {0}"), CategoryName(Category));
}

void AMSBuyStation::Interact(AMSPlayerCharacter* Player)
{
	if (AMSPlayerController* PC = Player ? Cast<AMSPlayerController>(Player->GetController()) : nullptr)
	{
		PC->OpenShop(Category);
	}
}

// --------------------------------------------------------------------------------------- purchase rules

static EMSEquipmentSlot SlotForKind(EMSShopItemKind Kind)
{
	switch (Kind)
	{
	case EMSShopItemKind::FragGrenades: return EMSEquipmentSlot::Frag;
	case EMSShopItemKind::Claymores: return EMSEquipmentSlot::Claymore;
	case EMSShopItemKind::Sentry: return EMSEquipmentSlot::Sentry;
	case EMSShopItemKind::Airstrike: return EMSEquipmentSlot::Airstrike;
	case EMSShopItemKind::AISquad: return EMSEquipmentSlot::Squad;
	default: return EMSEquipmentSlot::Count;
	}
}

EMSPurchaseResult AMSBuyStation::CanPurchase(const AMSPlayerCharacter* Player, FName ShopRow, int32& OutPrice)
{
	OutPrice = 0;
	const UMSDataSubsystem* Data = Player ? UMSDataSubsystem::Get(Player) : nullptr;
	const FMSShopItemRow* Item = Data ? Data->FindShopItem(ShopRow) : nullptr;
	const AMSPlayerState* PS = Player ? Player->GetPlayerState<AMSPlayerState>() : nullptr;
	if (!Item || !PS)
	{
		return EMSPurchaseResult::Invalid;
	}
	const AMSGameState* GS = Player->GetWorld()->GetGameState<AMSGameState>();
	const int32 Wave = GS ? FMath::Max(1, GS->Wave) : 1;
	OutPrice = Item->Price;
	if (Wave < Item->UnlockWave)
	{
		return EMSPurchaseResult::Locked;
	}

	switch (Item->Kind)
	{
	case EMSShopItemKind::Weapon:
	{
		// Buying a gun you already carry refills its ammo for the ammo price.
		if (Player->HasWeapon(Item->WeaponRow))
		{
			for (const AMSWeapon* W : Player->GetWeapons())
			{
				if (W && W->GetRowName() == Item->WeaponRow)
				{
					OutPrice = MSRules::AmmoRefillPrice(W->GetRow().AmmoPrice, W->GetReserveAmmo(), W->GetMaxReserveAmmo());
					if (OutPrice <= 0)
					{
						return EMSPurchaseResult::AlreadyMaxed;
					}
				}
			}
		}
		break;
	}
	case EMSShopItemKind::Ammo:
	{
		const AMSWeapon* W = Player->GetCurrentWeapon();
		if (!W)
		{
			return EMSPurchaseResult::Invalid;
		}
		OutPrice = MSRules::AmmoRefillPrice(W->GetRow().AmmoPrice, W->GetReserveAmmo(), W->GetMaxReserveAmmo());
		if (OutPrice <= 0)
		{
			return EMSPurchaseResult::AlreadyMaxed;
		}
		break;
	}
	case EMSShopItemKind::Armor:
	{
		const FMSEquipmentRow& Row = Data->GetEquipment(Item->EquipmentRow);
		if (Player->GetHealth()->GetArmor() >= Row.ArmorAmount)
		{
			return EMSPurchaseResult::AlreadyMaxed;
		}
		break;
	}
	default:
	{
		const EMSEquipmentSlot Slot = SlotForKind(Item->Kind);
		if (Slot == EMSEquipmentSlot::Count)
		{
			return EMSPurchaseResult::Invalid;
		}
		if (Player->GetEquipmentCount(Slot) >= Player->GetEquipmentMax(Slot))
		{
			return EMSPurchaseResult::AlreadyMaxed;
		}
		break;
	}
	}
	return MSRules::CanAfford(PS->GetCash(), OutPrice) ? EMSPurchaseResult::Purchased : EMSPurchaseResult::NotEnoughCash;
}

EMSPurchaseResult AMSBuyStation::TryPurchase(AMSPlayerCharacter* Player, FName ShopRow, FText& OutMessage)
{
	int32 Price = 0;
	const EMSPurchaseResult Check = CanPurchase(Player, ShopRow, Price);
	switch (Check)
	{
	case EMSPurchaseResult::NotEnoughCash: OutMessage = LOCTEXT("NoCash", "Not enough cash"); return Check;
	case EMSPurchaseResult::Locked: OutMessage = LOCTEXT("Locked", "Unlocks in a later wave"); return Check;
	case EMSPurchaseResult::AlreadyMaxed: OutMessage = LOCTEXT("Maxed", "Already full"); return Check;
	case EMSPurchaseResult::Invalid: OutMessage = LOCTEXT("Invalid", "Not available"); return Check;
	default: break;
	}

	const UMSDataSubsystem* Data = UMSDataSubsystem::Get(Player);
	const FMSShopItemRow* Item = Data->FindShopItem(ShopRow);
	AMSPlayerState* PS = Player->GetPlayerState<AMSPlayerState>();
	if (!PS->TrySpend(Price))
	{
		OutMessage = LOCTEXT("NoCash", "Not enough cash");
		return EMSPurchaseResult::NotEnoughCash;
	}

	switch (Item->Kind)
	{
	case EMSShopItemKind::Weapon:
		Player->GiveWeapon(Item->WeaponRow, true);
		break;
	case EMSShopItemKind::Ammo:
		if (AMSWeapon* W = Player->GetCurrentWeapon())
		{
			W->AddReserveAmmo(W->GetMaxReserveAmmo());
		}
		break;
	case EMSShopItemKind::Armor:
	{
		const FMSEquipmentRow& Row = Data->GetEquipment(Item->EquipmentRow);
		Player->GetHealth()->AddArmor(Row.ArmorAmount, Row.ArmorAmount);
		break;
	}
	default:
		Player->AddEquipment(SlotForKind(Item->Kind), FMath::Max(1, Item->Quantity));
		break;
	}
	OutMessage = FText::Format(LOCTEXT("Bought", "Purchased {0}"), Item->DisplayName);
	return EMSPurchaseResult::Purchased;
}

#undef LOCTEXT_NAMESPACE
