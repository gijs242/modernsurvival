#include "Player/MSPlayerController.h"

#include "Audio/MSAudioSubsystem.h"
#include "Combat/MSHealthComponent.h"
#include "Data/MSDataSubsystem.h"
#include "Data/MSSettings.h"
#include "Game/MSGameInstance.h"
#include "Game/MSGameMode.h"
#include "Game/MSMenuGameMode.h"
#include "ModernSurvival.h"
#include "Player/MSPlayerCharacter.h"
#include "Player/MSPlayerState.h"
#include "UI/MSMenuWidgets.h"
#include "Weapons/MSWeapon.h"
#include "EnhancedInputComponent.h"
#include "EnhancedInputSubsystems.h"
#include "Engine/LocalPlayer.h"
#include "Engine/World.h"
#include "InputAction.h"
#include "InputMappingContext.h"
#include "InputModifiers.h"
#include "Kismet/GameplayStatics.h"

AMSPlayerController::AMSPlayerController()
{
	bShowMouseCursor = false;
}

const FMSInputActions& AMSPlayerController::GetInputActions()
{
	BuildInput();
	return Actions;
}

void AMSPlayerController::BuildInput()
{
	if (bInputBuilt)
	{
		return;
	}
	bInputBuilt = true;

	auto MakeAction = [this](const TCHAR* Name, EInputActionValueType Type)
	{
		UInputAction* A = NewObject<UInputAction>(this, Name);
		A->ValueType = Type;
		return A;
	};
	Actions.Move = MakeAction(TEXT("IA_Move"), EInputActionValueType::Axis2D);
	Actions.Look = MakeAction(TEXT("IA_Look"), EInputActionValueType::Axis2D);
	Actions.LookGamepad = MakeAction(TEXT("IA_LookGamepad"), EInputActionValueType::Axis2D);
	Actions.Jump = MakeAction(TEXT("IA_Jump"), EInputActionValueType::Boolean);
	Actions.Sprint = MakeAction(TEXT("IA_Sprint"), EInputActionValueType::Boolean);
	Actions.Crouch = MakeAction(TEXT("IA_Crouch"), EInputActionValueType::Boolean);
	Actions.Fire = MakeAction(TEXT("IA_Fire"), EInputActionValueType::Boolean);
	Actions.ADS = MakeAction(TEXT("IA_ADS"), EInputActionValueType::Boolean);
	Actions.Reload = MakeAction(TEXT("IA_Reload"), EInputActionValueType::Boolean);
	Actions.Interact = MakeAction(TEXT("IA_Interact"), EInputActionValueType::Boolean);
	Actions.SwitchWeapon = MakeAction(TEXT("IA_SwitchWeapon"), EInputActionValueType::Axis1D);
	Actions.Weapon1 = MakeAction(TEXT("IA_Weapon1"), EInputActionValueType::Boolean);
	Actions.Weapon2 = MakeAction(TEXT("IA_Weapon2"), EInputActionValueType::Boolean);
	Actions.Melee = MakeAction(TEXT("IA_Melee"), EInputActionValueType::Boolean);
	Actions.Grenade = MakeAction(TEXT("IA_Grenade"), EInputActionValueType::Boolean);
	Actions.Claymore = MakeAction(TEXT("IA_Claymore"), EInputActionValueType::Boolean);
	Actions.Sentry = MakeAction(TEXT("IA_Sentry"), EInputActionValueType::Boolean);
	Actions.Airstrike = MakeAction(TEXT("IA_Airstrike"), EInputActionValueType::Boolean);
	Actions.Squad = MakeAction(TEXT("IA_Squad"), EInputActionValueType::Boolean);
	Actions.SkipBreak = MakeAction(TEXT("IA_SkipBreak"), EInputActionValueType::Boolean);
	Actions.Pause = MakeAction(TEXT("IA_Pause"), EInputActionValueType::Boolean);
	Actions.Pause->bTriggerWhenPaused = true;

	Mapping = NewObject<UInputMappingContext>(this, TEXT("IMC_ModernSurvival"));
	auto Map = [this](UInputAction* Action, const FKey& Key) -> FEnhancedActionKeyMapping&
	{
		return Mapping->MapKey(Action, Key);
	};
	auto Swizzle = [this]()
	{
		UInputModifierSwizzleAxis* M = NewObject<UInputModifierSwizzleAxis>(Mapping);
		M->Order = EInputAxisSwizzle::YXZ;
		return M;
	};
	auto Negate = [this](bool bX, bool bY)
	{
		UInputModifierNegate* M = NewObject<UInputModifierNegate>(Mapping);
		M->bX = bX;
		M->bY = bY;
		M->bZ = false;
		return M;
	};
	auto DeadZone = [this]()
	{
		UInputModifierDeadZone* M = NewObject<UInputModifierDeadZone>(Mapping);
		M->LowerThreshold = 0.15f;
		M->UpperThreshold = 1.f;
		M->Type = EDeadZoneType::Radial;
		return M;
	};

	// Movement: WASD (W/S on the Y axis) + left stick.
	Map(Actions.Move, EKeys::W).Modifiers.Add(Swizzle());
	{
		FEnhancedActionKeyMapping& S = Map(Actions.Move, EKeys::S);
		S.Modifiers.Add(Swizzle());
		S.Modifiers.Add(Negate(true, true));
	}
	Map(Actions.Move, EKeys::A).Modifiers.Add(Negate(true, false));
	Map(Actions.Move, EKeys::D);
	Map(Actions.Move, EKeys::Gamepad_Left2D).Modifiers.Add(DeadZone());

	// Look: mouse (degrees scaled in the character from DT_PlayerFeel) + right stick (rate).
	Map(Actions.Look, EKeys::Mouse2D);
	Map(Actions.LookGamepad, EKeys::Gamepad_Right2D).Modifiers.Add(DeadZone());

	Map(Actions.Jump, EKeys::SpaceBar);
	Map(Actions.Jump, EKeys::Gamepad_FaceButton_Bottom);
	Map(Actions.Sprint, EKeys::LeftShift);
	Map(Actions.Sprint, EKeys::Gamepad_LeftThumbstick);
	Map(Actions.Crouch, EKeys::C);
	Map(Actions.Crouch, EKeys::LeftControl);
	Map(Actions.Crouch, EKeys::Gamepad_FaceButton_Right);
	Map(Actions.Fire, EKeys::LeftMouseButton);
	Map(Actions.Fire, EKeys::Gamepad_RightTrigger);
	Map(Actions.ADS, EKeys::RightMouseButton);
	Map(Actions.ADS, EKeys::Gamepad_LeftTrigger);
	Map(Actions.Reload, EKeys::R);
	Map(Actions.Reload, EKeys::Gamepad_FaceButton_Left);
	Map(Actions.Interact, EKeys::E);
	Map(Actions.Interact, EKeys::Gamepad_DPad_Down);
	Map(Actions.SwitchWeapon, EKeys::MouseWheelAxis);
	Map(Actions.SwitchWeapon, EKeys::Gamepad_FaceButton_Top);
	Map(Actions.Weapon1, EKeys::One);
	Map(Actions.Weapon2, EKeys::Two);
	Map(Actions.Melee, EKeys::V);
	Map(Actions.Melee, EKeys::Gamepad_RightThumbstick);
	Map(Actions.Grenade, EKeys::G);
	Map(Actions.Grenade, EKeys::Gamepad_RightShoulder);
	Map(Actions.Claymore, EKeys::Three);
	Map(Actions.Claymore, EKeys::Gamepad_LeftShoulder);
	Map(Actions.Sentry, EKeys::Four);
	Map(Actions.Sentry, EKeys::Gamepad_DPad_Left);
	Map(Actions.Airstrike, EKeys::Five);
	Map(Actions.Airstrike, EKeys::Gamepad_DPad_Up);
	Map(Actions.Squad, EKeys::Six);
	Map(Actions.Squad, EKeys::Gamepad_DPad_Right);
	Map(Actions.SkipBreak, EKeys::N);
	Map(Actions.SkipBreak, EKeys::Gamepad_Special_Left);
	Map(Actions.Pause, EKeys::Escape);
	Map(Actions.Pause, EKeys::P);
	Map(Actions.Pause, EKeys::Gamepad_Special_Right);
}

void AMSPlayerController::AddMappingContexts()
{
	BuildInput();
	if (UEnhancedInputLocalPlayerSubsystem* Sub = ULocalPlayer::GetSubsystem<UEnhancedInputLocalPlayerSubsystem>(GetLocalPlayer()))
	{
		if (!Sub->HasMappingContext(Mapping))
		{
			Sub->AddMappingContext(Mapping, 0);
		}
		if (UInputMappingContext* Override = OverrideMappingContext.LoadSynchronous())
		{
			if (!Sub->HasMappingContext(Override))
			{
				Sub->AddMappingContext(Override, 1);
			}
		}
	}
}

void AMSPlayerController::SetupInputComponent()
{
	Super::SetupInputComponent();
	BuildInput();
	if (UEnhancedInputComponent* EIC = Cast<UEnhancedInputComponent>(InputComponent))
	{
		EIC->BindAction(Actions.Pause, ETriggerEvent::Started, this, &AMSPlayerController::TogglePause);
	}
}

void AMSPlayerController::BeginPlay()
{
	Super::BeginPlay();
	if (!IsLocalController())
	{
		return;
	}
	AddMappingContexts();
	if (GetWorld()->GetAuthGameMode<AMSMenuGameMode>())
	{
		ShowMainMenu();
	}
	else
	{
		SetMenuInputMode(false, false);
	}
}

void AMSPlayerController::OnPossess(APawn* InPawn)
{
	Super::OnPossess(InPawn);
	AddMappingContexts();
}

void AMSPlayerController::SetMenuInputMode(bool bMenu, bool bPauseGame)
{
	bShowMouseCursor = bMenu;
	if (bMenu)
	{
		FInputModeGameAndUI Mode;
		Mode.SetLockMouseToViewportBehavior(EMouseLockMode::DoNotLock);
		Mode.SetHideCursorDuringCapture(false);
		SetInputMode(Mode);
	}
	else
	{
		SetInputMode(FInputModeGameOnly());
	}
	SetPause(bPauseGame);
	if (AMSPlayerCharacter* Player = GetPawn<AMSPlayerCharacter>())
	{
		Player->SetInputBlocked(bMenu);
	}
}

void AMSPlayerController::OpenShop(EMSShopCategory Category)
{
	if (!ShopWidget)
	{
		ShopWidget = CreateWidget<UMSShopWidget>(this, UMSShopWidget::StaticClass());
	}
	if (ShopWidget)
	{
		ShopWidget->SetCategory(Category);
		if (!ShopWidget->IsInViewport())
		{
			ShopWidget->AddToViewport(10);
		}
		SetMenuInputMode(true, false);
	}
}

void AMSPlayerController::CloseShop()
{
	if (ShopWidget && ShopWidget->IsInViewport())
	{
		ShopWidget->RemoveFromParent();
	}
	SetMenuInputMode(false, false);
}

bool AMSPlayerController::IsShopOpen() const
{
	return ShopWidget && ShopWidget->IsInViewport();
}

void AMSPlayerController::TogglePause()
{
	if (GetWorld()->GetAuthGameMode<AMSMenuGameMode>() || (GameOverScreen && GameOverScreen->IsInViewport()))
	{
		return;
	}
	if (IsShopOpen())
	{
		CloseShop();
		return;
	}
	if (!PauseMenu)
	{
		PauseMenu = CreateWidget<UMSPauseMenuWidget>(this, UMSPauseMenuWidget::StaticClass());
	}
	if (!PauseMenu)
	{
		return;
	}
	if (PauseMenu->IsInViewport())
	{
		PauseMenu->RemoveFromParent();
		SetMenuInputMode(false, false);
	}
	else
	{
		PauseMenu->AddToViewport(20);
		SetMenuInputMode(true, true);
	}
}

void AMSPlayerController::ShowGameOver(const FMSGameOverStats& Stats)
{
	CloseShop();
	if (PauseMenu && PauseMenu->IsInViewport())
	{
		PauseMenu->RemoveFromParent();
	}
	if (!GameOverScreen)
	{
		GameOverScreen = CreateWidget<UMSGameOverWidget>(this, UMSGameOverWidget::StaticClass());
	}
	if (GameOverScreen)
	{
		GameOverScreen->SetStats(Stats);
		GameOverScreen->AddToViewport(30);
		SetMenuInputMode(true, false);
	}
}

void AMSPlayerController::ShowMainMenu()
{
	if (!MainMenu)
	{
		MainMenu = CreateWidget<UMSMainMenuWidget>(this, UMSMainMenuWidget::StaticClass());
	}
	if (MainMenu && !MainMenu->IsInViewport())
	{
		MainMenu->AddToViewport(0);
	}
	SetMenuInputMode(true, false);
}

void AMSPlayerController::RestartMatch()
{
	SetPause(false);
	UGameplayStatics::OpenLevel(this, FName(*UGameplayStatics::GetCurrentLevelName(this, true)));
}

void AMSPlayerController::ReturnToMainMenu()
{
	SetPause(false);
	UGameplayStatics::OpenLevel(this, FName(*UMSSettings::Get()->MainMenuMap));
}

// ------------------------------------------------------------------------------- cheats

void AMSPlayerController::MSGiveCash(int32 Amount)
{
	if (AMSPlayerState* PS = GetPlayerState<AMSPlayerState>())
	{
		PS->AddCash(Amount, NSLOCTEXT("MS", "Cheat", "Cheat"));
	}
}

void AMSPlayerController::MSSkipWave()
{
	if (AMSGameMode* GM = GetWorld()->GetAuthGameMode<AMSGameMode>())
	{
		GM->DebugKillAll(GetPawn());
		GM->RequestSkipIntermission();
	}
}

void AMSPlayerController::MSSetWave(int32 Wave)
{
	if (AMSGameMode* GM = GetWorld()->GetAuthGameMode<AMSGameMode>())
	{
		GM->DebugSetWave(Wave);
	}
}

void AMSPlayerController::MSKillAll()
{
	if (AMSGameMode* GM = GetWorld()->GetAuthGameMode<AMSGameMode>())
	{
		GM->DebugKillAll(GetPawn());
	}
}

void AMSPlayerController::MSGod()
{
	if (AMSPlayerCharacter* Player = GetPawn<AMSPlayerCharacter>())
	{
		Player->GetHealth()->bInvulnerable = !Player->GetHealth()->bInvulnerable;
		ClientMessage(Player->GetHealth()->bInvulnerable ? TEXT("God mode ON") : TEXT("God mode OFF"));
	}
}

void AMSPlayerController::MSGiveWeapon(FName WeaponRow)
{
	if (AMSPlayerCharacter* Player = GetPawn<AMSPlayerCharacter>())
	{
		Player->GiveWeapon(WeaponRow, true);
	}
}

void AMSPlayerController::MSGiveAll()
{
	if (AMSPlayerCharacter* Player = GetPawn<AMSPlayerCharacter>())
	{
		for (int32 I = 0; I < static_cast<int32>(EMSEquipmentSlot::Count); ++I)
		{
			Player->AddEquipment(static_cast<EMSEquipmentSlot>(I), 99);
		}
		Player->GetHealth()->AddArmor(250.f, 250.f);
	}
	MSGiveCash(50000);
}

void AMSPlayerController::MSAcoustics()
{
	if (const UMSAudioSubsystem* Audio = GetWorld()->GetSubsystem<UMSAudioSubsystem>())
	{
		const MSRules::FRoomProbe& P = Audio->GetLastProbe();
		ClientMessage(FString::Printf(TEXT("Room: %s  avg %.0f cm  hits %.0f%%  ceiling %s"),
			*Audio->GetRoomRowName().ToString(), P.AverageDistance, P.HitFraction * 100.f, P.bCeiling ? TEXT("yes") : TEXT("no")));
	}
}
