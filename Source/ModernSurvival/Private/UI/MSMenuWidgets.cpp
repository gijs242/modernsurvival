#include "UI/MSMenuWidgets.h"

#include "Data/MSDataSubsystem.h"
#include "Data/MSSettings.h"
#include "Game/MSBuyStation.h"
#include "Game/MSGameInstance.h"
#include "Player/MSPlayerCharacter.h"
#include "Player/MSPlayerController.h"
#include "Player/MSPlayerState.h"
#include "Weapons/MSWeapon.h"
#include "Blueprint/WidgetTree.h"
#include "Components/Border.h"
#include "Components/Button.h"
#include "Components/EditableTextBox.h"
#include "Components/TextBlock.h"
#include "Components/VerticalBox.h"
#include "Components/VerticalBoxSlot.h"
#include "Kismet/GameplayStatics.h"
#include "Kismet/KismetSystemLibrary.h"
#include "Misc/PackageName.h"
#include "Styling/CoreStyle.h"

#define LOCTEXT_NAMESPACE "MSMenus"

// ---------------------------------------------------------------------------------------------- base

void UMSMenuWidgetBase::NativeOnInitialized()
{
	Super::NativeOnInitialized();
	RootBorder = WidgetTree->ConstructWidget<UBorder>(UBorder::StaticClass(), TEXT("RootBorder"));
	RootBorder->SetBrushColor(FLinearColor(0.01f, 0.012f, 0.01f, 0.78f));
	RootBorder->SetHorizontalAlignment(HAlign_Center);
	RootBorder->SetVerticalAlignment(VAlign_Center);
	Column = WidgetTree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), TEXT("Column"));
	RootBorder->SetContent(Column);
	WidgetTree->RootWidget = RootBorder;
	Build();
}

void UMSMenuWidgetBase::ClearColumn()
{
	if (Column)
	{
		Column->ClearChildren();
	}
	Proxies.Reset();
}

UTextBlock* UMSMenuWidgetBase::AddText(const FText& Text, int32 Size, const FLinearColor& Color, bool bBold)
{
	UTextBlock* Block = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass());
	Block->SetText(Text);
	Block->SetFont(FCoreStyle::GetDefaultFontStyle(bBold ? TEXT("Bold") : TEXT("Regular"), Size));
	Block->SetColorAndOpacity(FSlateColor(Color));
	Block->SetJustification(ETextJustify::Center);
	if (UVerticalBoxSlot* Slot = Column->AddChildToVerticalBox(Block))
	{
		Slot->SetPadding(FMargin(0.f, 4.f));
		Slot->SetHorizontalAlignment(HAlign_Center);
	}
	return Block;
}

UButton* UMSMenuWidgetBase::AddButton(const FText& Label, TFunction<void()> OnClick, UVerticalBox* Parent)
{
	UButton* Button = WidgetTree->ConstructWidget<UButton>(UButton::StaticClass());
	UTextBlock* Text = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass());
	Text->SetText(Label);
	Text->SetFont(FCoreStyle::GetDefaultFontStyle(TEXT("Bold"), 18));
	Text->SetColorAndOpacity(FSlateColor(FLinearColor(0.06f, 0.06f, 0.05f)));
	Button->AddChild(Text);
	Button->SetBackgroundColor(FLinearColor(0.85f, 0.83f, 0.74f));
	UMSClickProxy* Proxy = NewObject<UMSClickProxy>(this);
	Proxy->Callback = MoveTemp(OnClick);
	Button->OnClicked.AddDynamic(Proxy, &UMSClickProxy::Click);
	Proxies.Add(Proxy);
	UVerticalBox* Target = Parent ? Parent : Column.Get();
	if (UVerticalBoxSlot* Slot = Target->AddChildToVerticalBox(Button))
	{
		Slot->SetPadding(FMargin(0.f, 5.f));
		Slot->SetHorizontalAlignment(HAlign_Fill);
	}
	return Button;
}

// ---------------------------------------------------------------------------------------------- main menu

void UMSMainMenuWidget::Build()
{
	AddText(LOCTEXT("Title", "MODERN SURVIVAL"), 56, FLinearColor(0.95f, 0.95f, 0.9f), true);
	AddText(LOCTEXT("Subtitle", "Hold out against endless waves. Earn cash. Spend it wisely."), 16, FLinearColor(0.7f, 0.72f, 0.66f));
	AddText(FText::GetEmpty(), 12);

	const UMSGameInstance* GI = GetGameInstance<UMSGameInstance>();
	for (const FMSPlayableMap& Map : UMSSettings::Get()->PlayableMaps)
	{
		const FString MapPath = Map.Map;
		const FString ShortName = FPackageName::GetShortName(MapPath);
		const int32 Best = GI ? GI->GetBestWave(ShortName) : 0;
		const FText Label = Best > 0
			? FText::Format(LOCTEXT("PlayBest", "PLAY  {0}   (best: wave {1})"), Map.DisplayName, Best)
			: FText::Format(LOCTEXT("Play", "PLAY  {0}"), Map.DisplayName);
		TWeakObjectPtr<UMSMainMenuWidget> Weak(this);
		AddButton(Label, [Weak, MapPath]()
		{
			if (Weak.IsValid())
			{
				UGameplayStatics::OpenLevel(Weak.Get(), FName(*MapPath));
			}
		});
		AddButton(FText::Format(LOCTEXT("Host", "HOST CO-OP  {0}"), Map.DisplayName), [Weak, MapPath]()
		{
			if (AMSPlayerController* PC = Weak.IsValid() ? Cast<AMSPlayerController>(Weak->GetOwningPlayer()) : nullptr)
			{
				PC->HostGame(MapPath);
			}
		});
	}
	TWeakObjectPtr<UMSMainMenuWidget> Weak(this);

	// Join a friend's co-op game by IP (LAN / VPN / port 7777 forwarded).
	AddText(LOCTEXT("JoinHint", "Join a co-op game: host's IP address"), 14, FLinearColor(0.7f, 0.72f, 0.66f));
	AddressBox = WidgetTree->ConstructWidget<UEditableTextBox>(UEditableTextBox::StaticClass());
	AddressBox->SetHintText(LOCTEXT("IPHint", "e.g. 192.168.1.20"));
	AddressBox->SetText(FText::FromString(TEXT("127.0.0.1")));
	if (UVerticalBoxSlot* Slot = Column->AddChildToVerticalBox(AddressBox))
	{
		Slot->SetPadding(FMargin(0.f, 4.f));
		Slot->SetHorizontalAlignment(HAlign_Fill);
	}
	AddButton(LOCTEXT("Join", "JOIN CO-OP"), [Weak]()
	{
		if (!Weak.IsValid())
		{
			return;
		}
		if (AMSPlayerController* PC = Cast<AMSPlayerController>(Weak->GetOwningPlayer()))
		{
			PC->JoinGame(Weak->AddressBox ? Weak->AddressBox->GetText().ToString() : FString());
		}
	});
	AddButton(LOCTEXT("Quit", "QUIT"), [Weak]()
	{
		if (Weak.IsValid())
		{
			UKismetSystemLibrary::QuitGame(Weak.Get(), Weak->GetOwningPlayer(), EQuitPreference::Quit, false);
		}
	});
	AddText(FText::GetEmpty(), 12);
	AddText(LOCTEXT("Controls",
		"WASD move  ·  Mouse look  ·  LMB fire  ·  RMB aim  ·  Shift sprint  ·  C crouch / slide (while sprinting)  ·  Space jump\n"
		"R reload  ·  E use buy station  ·  1/2 or wheel switch  ·  V melee  ·  G frag (hold to cook)\n"
		"3 claymore  ·  4 sentry  ·  5 airstrike (aim at target)  ·  6 AI squad  ·  N hold to skip break  ·  Esc pause"),
		13, FLinearColor(0.6f, 0.62f, 0.57f));
}

// ---------------------------------------------------------------------------------------------- pause

void UMSPauseMenuWidget::Build()
{
	AddText(LOCTEXT("Paused", "PAUSED"), 44, FLinearColor::White, true);
	TWeakObjectPtr<UMSPauseMenuWidget> Weak(this);
	auto PC = [Weak]() { return Weak.IsValid() ? Cast<AMSPlayerController>(Weak->GetOwningPlayer()) : nullptr; };
	AddButton(LOCTEXT("Resume", "RESUME"), [PC]() { if (AMSPlayerController* C = PC()) { C->TogglePause(); } });
	const AMSPlayerController* Owner = Cast<AMSPlayerController>(GetOwningPlayer());
	if (!Owner || Owner->CanRestart())
	{
		AddButton(LOCTEXT("Restart", "RESTART"), [PC]() { if (AMSPlayerController* C = PC()) { C->RestartMatch(); } });
	}
	AddButton(LOCTEXT("Menu", "MAIN MENU"), [PC]() { if (AMSPlayerController* C = PC()) { C->ReturnToMainMenu(); } });
	AddButton(LOCTEXT("QuitGame", "QUIT GAME"), [Weak]()
	{
		if (Weak.IsValid())
		{
			UKismetSystemLibrary::QuitGame(Weak.Get(), Weak->GetOwningPlayer(), EQuitPreference::Quit, false);
		}
	});
}

// ---------------------------------------------------------------------------------------------- game over

void UMSGameOverWidget::SetStats(const FMSGameOverStats& InStats)
{
	Stats = InStats;
	ClearColumn();
	Build();
}

void UMSGameOverWidget::Build()
{
	AddText(LOCTEXT("Dead", "YOU DIED"), 56, FLinearColor(0.85f, 0.12f, 0.08f), true);
	AddText(FText::Format(LOCTEXT("Wave", "Survived to wave {0}"), Stats.WaveReached), 26, FLinearColor::White, true);
	if (Stats.bNewBest)
	{
		AddText(LOCTEXT("NewBest", "NEW BEST!"), 20, FLinearColor(1.f, 0.8f, 0.3f), true);
	}
	else if (Stats.BestWave > 0)
	{
		AddText(FText::Format(LOCTEXT("Best", "Best: wave {0}"), Stats.BestWave), 16, FLinearColor(0.7f, 0.72f, 0.66f));
	}
	const int32 Minutes = FMath::FloorToInt(Stats.TimeSurvived / 60.f);
	const int32 Seconds = FMath::FloorToInt(Stats.TimeSurvived) % 60;
	AddText(FText::Format(LOCTEXT("Stats", "Kills {0}   ·   Headshots {1}   ·   Cash earned ${2}   ·   Time {3}:{4}"),
		Stats.Kills, Stats.Headshots, Stats.CashEarned, Minutes, FText::FromString(FString::Printf(TEXT("%02d"), Seconds))), 16, FLinearColor(0.8f, 0.82f, 0.76f));
	AddText(FText::GetEmpty(), 10);
	TWeakObjectPtr<UMSGameOverWidget> Weak(this);
	auto PC = [Weak]() { return Weak.IsValid() ? Cast<AMSPlayerController>(Weak->GetOwningPlayer()) : nullptr; };
	const AMSPlayerController* Owner = Cast<AMSPlayerController>(GetOwningPlayer());
	if (!Owner || Owner->CanRestart())
	{
		AddButton(LOCTEXT("Again", "PLAY AGAIN"), [PC]() { if (AMSPlayerController* C = PC()) { C->RestartMatch(); } });
	}
	else
	{
		AddText(LOCTEXT("WaitHost", "Waiting for the host to restart..."), 16, FLinearColor(0.7f, 0.72f, 0.66f));
	}
	AddButton(LOCTEXT("ToMenu", "MAIN MENU"), [PC]() { if (AMSPlayerController* C = PC()) { C->ReturnToMainMenu(); } });
}

// ---------------------------------------------------------------------------------------------- shop

void UMSShopWidget::SetCategory(EMSShopCategory InCategory)
{
	Category = InCategory;
	LastMessage = FText::GetEmpty();
	Refresh();
}

void UMSShopWidget::ShowResult(const FText& Message)
{
	LastMessage = Message;
	Refresh();
}

FString UMSShopWidget::StateSignature() const
{
	// Everything the list shows: rebuild only when one of these changes (rebuilding mid-click eats the click).
	const APlayerController* Owner = GetOwningPlayer();
	const AMSPlayerCharacter* Player = Owner ? Owner->GetPawn<AMSPlayerCharacter>() : nullptr;
	const AMSPlayerState* PS = Owner ? Owner->GetPlayerState<AMSPlayerState>() : nullptr;
	const AMSGameState* GS = GetWorld() ? GetWorld()->GetGameState<AMSGameState>() : nullptr;
	FString Sig = FString::Printf(TEXT("%d|%d|"), PS ? PS->GetCash() : -1, GS ? GS->Wave : 0);
	if (Player)
	{
		for (int32 I = 0; I < static_cast<int32>(EMSEquipmentSlot::Count); ++I)
		{
			Sig += FString::Printf(TEXT("%d,"), Player->GetEquipmentCount(static_cast<EMSEquipmentSlot>(I)));
		}
		for (const AMSWeapon* W : Player->GetWeapons())
		{
			Sig += W ? FString::Printf(TEXT("%s:%d,"), *W->GetRowName().ToString(), W->GetReserveAmmo()) : FString(TEXT("-,"));
		}
	}
	return Sig;
}

void UMSShopWidget::NativeTick(const FGeometry& MyGeometry, float InDeltaTime)
{
	Super::NativeTick(MyGeometry, InDeltaTime);
	RefreshTimer -= InDeltaTime;
	if (RefreshTimer <= 0.f)
	{
		RefreshTimer = 0.25f;
		const FString Sig = StateSignature();
		if (Sig != LastSignature)
		{
			Refresh();
		}
	}
}

void UMSShopWidget::Refresh()
{
	LastSignature = StateSignature();
	ClearColumn();
	Build();
}

void UMSShopWidget::Build()
{
	APlayerController* Owner = GetOwningPlayer();
	AMSPlayerCharacter* Player = Owner ? Owner->GetPawn<AMSPlayerCharacter>() : nullptr;
	const AMSPlayerState* PS = Owner ? Owner->GetPlayerState<AMSPlayerState>() : nullptr;
	const UMSDataSubsystem* Data = UMSDataSubsystem::Get(this);
	if (!Data)
	{
		return;
	}
	AddText(AMSBuyStation::CategoryName(Category), 40, FLinearColor::White, true);
	AddText(FText::Format(LOCTEXT("Cash", "Cash: ${0}"), PS ? PS->GetCash() : 0), 22, FLinearColor(0.55f, 0.95f, 0.45f), true);
	if (!LastMessage.IsEmpty())
	{
		AddText(LastMessage, 16, FLinearColor(1.f, 0.85f, 0.4f));
	}
	AddText(FText::GetEmpty(), 6);

	TWeakObjectPtr<UMSShopWidget> Weak(this);
	for (const TPair<FName, const FMSShopItemRow*>& Pair : Data->GetShopItems(Category))
	{
		const FName RowName = Pair.Key;
		const FMSShopItemRow* Item = Pair.Value;
		int32 Price = Item->Price;
		const EMSPurchaseResult State = Player ? AMSBuyStation::CanPurchase(Player, RowName, Price) : EMSPurchaseResult::Invalid;
		FText Status;
		switch (State)
		{
		case EMSPurchaseResult::Locked: Status = FText::Format(LOCTEXT("LockedWave", "  [wave {0}]"), Item->UnlockWave); break;
		case EMSPurchaseResult::AlreadyMaxed: Status = LOCTEXT("Full", "  [full]"); break;
		case EMSPurchaseResult::NotEnoughCash: Status = LOCTEXT("Poor", "  [need more cash]"); break;
		default: break;
		}
		const FText Label = FText::Format(LOCTEXT("Item", "{0}   ${1}{2}"), Item->DisplayName, Price, Status);
		UButton* Button = AddButton(Label, [Weak, RowName]()
		{
			if (!Weak.IsValid())
			{
				return;
			}
			// The server decides; the result comes back through ShowResult().
			if (AMSPlayerController* PC = Cast<AMSPlayerController>(Weak->GetOwningPlayer()))
			{
				PC->RequestPurchase(RowName);
			}
		});
		Button->SetIsEnabled(State == EMSPurchaseResult::Purchased);
		Button->SetToolTipText(Item->Description);
	}
	AddText(FText::GetEmpty(), 6);
	AddButton(LOCTEXT("Close", "CLOSE  [Esc]"), [Weak]()
	{
		if (Weak.IsValid())
		{
			if (AMSPlayerController* PC = Cast<AMSPlayerController>(Weak->GetOwningPlayer()))
			{
				PC->CloseShop();
			}
		}
	});
}

#undef LOCTEXT_NAMESPACE
