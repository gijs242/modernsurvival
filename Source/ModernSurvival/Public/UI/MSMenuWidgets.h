#pragma once

#include "CoreMinimal.h"
#include "Blueprint/UserWidget.h"
#include "Data/MSDataTypes.h"
#include "Game/MSGameState.h"
#include "MSMenuWidgets.generated.h"

class UVerticalBox;
class UTextBlock;
class UButton;
class UBorder;

/** Lets a UButton call a C++ lambda (UMG click events need a UFUNCTION target). */
UCLASS()
class MODERNSURVIVAL_API UMSClickProxy : public UObject
{
	GENERATED_BODY()

public:
	TFunction<void()> Callback;
	UFUNCTION() void Click() { if (Callback) { Callback(); } }
};

/**
 * Menus are built in C++ (no Widget Blueprints needed): a dark full-screen border with a centred
 * column. To restyle, subclass in a Widget Blueprint or replace Build() — the game logic only calls
 * the public functions.
 */
UCLASS(Abstract)
class MODERNSURVIVAL_API UMSMenuWidgetBase : public UUserWidget
{
	GENERATED_BODY()

protected:
	virtual void NativeOnInitialized() override;
	virtual void Build() {}

	UTextBlock* AddText(const FText& Text, int32 Size, const FLinearColor& Color = FLinearColor(0.92f, 0.93f, 0.9f), bool bBold = false);
	UButton* AddButton(const FText& Label, TFunction<void()> OnClick, UVerticalBox* Parent = nullptr);
	void ClearColumn();

	UPROPERTY(Transient) TObjectPtr<UBorder> RootBorder;
	UPROPERTY(Transient) TObjectPtr<UVerticalBox> Column;
	UPROPERTY(Transient) TArray<TObjectPtr<UMSClickProxy>> Proxies;
};

UCLASS()
class MODERNSURVIVAL_API UMSMainMenuWidget : public UMSMenuWidgetBase
{
	GENERATED_BODY()

protected:
	virtual void Build() override;
};

UCLASS()
class MODERNSURVIVAL_API UMSPauseMenuWidget : public UMSMenuWidgetBase
{
	GENERATED_BODY()

protected:
	virtual void Build() override;
};

UCLASS()
class MODERNSURVIVAL_API UMSGameOverWidget : public UMSMenuWidgetBase
{
	GENERATED_BODY()

public:
	void SetStats(const FMSGameOverStats& InStats);

protected:
	virtual void Build() override;
	FMSGameOverStats Stats;
};

UCLASS()
class MODERNSURVIVAL_API UMSShopWidget : public UMSMenuWidgetBase
{
	GENERATED_BODY()

public:
	void SetCategory(EMSShopCategory InCategory);
	void Refresh();

protected:
	virtual void Build() override;

	EMSShopCategory Category = EMSShopCategory::Weapons;
	FText LastMessage;
};
