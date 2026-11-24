#pragma once

#include "CoreMinimal.h"
#include "GameFramework/PlayerController.h"
#include "GenericTeamAgentInterface.h"
#include "Data/MSDataTypes.h"
#include "Game/MSGameState.h"
#include "MSPlayerController.generated.h"

class UInputAction;
class UInputMappingContext;
class UMSPauseMenuWidget;
class UMSGameOverWidget;
class UMSShopWidget;
class UMSMainMenuWidget;

/**
 * Input actions created at runtime so the game works without any editor-authored input assets.
 * To rebind keys, edit AMSPlayerController::BuildInput (or assign an asset-based mapping context
 * in OverrideMappingContext; its actions must be the same UInputAction objects).
 */
USTRUCT()
struct MODERNSURVIVAL_API FMSInputActions
{
	GENERATED_BODY()

	UPROPERTY() TObjectPtr<UInputAction> Move;
	UPROPERTY() TObjectPtr<UInputAction> Look;
	UPROPERTY() TObjectPtr<UInputAction> LookGamepad;
	UPROPERTY() TObjectPtr<UInputAction> Jump;
	UPROPERTY() TObjectPtr<UInputAction> Sprint;
	UPROPERTY() TObjectPtr<UInputAction> Crouch;
	UPROPERTY() TObjectPtr<UInputAction> Fire;
	UPROPERTY() TObjectPtr<UInputAction> ADS;
	UPROPERTY() TObjectPtr<UInputAction> Reload;
	UPROPERTY() TObjectPtr<UInputAction> Interact;
	UPROPERTY() TObjectPtr<UInputAction> SwitchWeapon;
	UPROPERTY() TObjectPtr<UInputAction> Weapon1;
	UPROPERTY() TObjectPtr<UInputAction> Weapon2;
	UPROPERTY() TObjectPtr<UInputAction> Melee;
	UPROPERTY() TObjectPtr<UInputAction> Grenade;
	UPROPERTY() TObjectPtr<UInputAction> Claymore;
	UPROPERTY() TObjectPtr<UInputAction> Sentry;
	UPROPERTY() TObjectPtr<UInputAction> Airstrike;
	UPROPERTY() TObjectPtr<UInputAction> Squad;
	UPROPERTY() TObjectPtr<UInputAction> SkipBreak;
	UPROPERTY() TObjectPtr<UInputAction> Pause;
};

UCLASS()
class MODERNSURVIVAL_API AMSPlayerController : public APlayerController, public IGenericTeamAgentInterface
{
	GENERATED_BODY()

public:
	AMSPlayerController();

	const FMSInputActions& GetInputActions();

	virtual FGenericTeamId GetGenericTeamId() const override { return FGenericTeamId(static_cast<uint8>(EMSTeam::Player)); }

	// --- UI
	void OpenShop(EMSShopCategory Category);
	void CloseShop();
	bool IsShopOpen() const;
	UFUNCTION(BlueprintCallable, Category = "UI") void TogglePause();
	void ShowGameOver(const FMSGameOverStats& Stats);
	void ShowMainMenu();
	UFUNCTION(BlueprintCallable, Category = "UI") void RestartMatch();
	UFUNCTION(BlueprintCallable, Category = "UI") void ReturnToMainMenu();
	bool CanRestart() const { return GetNetMode() != NM_Client; }

	// --- Co-op sessions (listen server, direct IP; no online subsystem needed on LAN)
	UFUNCTION(BlueprintCallable, Category = "Coop") void HostGame(const FString& MapPath);
	UFUNCTION(BlueprintCallable, Category = "Coop") void JoinGame(const FString& Address);

	// --- Shop: purchases are decided on the server
	void RequestPurchase(FName ShopRow);
	UFUNCTION(Server, Reliable) void ServerPurchase(FName ShopRow);
	UFUNCTION(Client, Reliable) void ClientPurchaseResult(const FText& Message);
	/** Server -> each player: show the game-over screen and save the best wave on that machine. */
	UFUNCTION(Client, Reliable) void ClientGameOver(FMSGameOverStats Stats);

	// --- Debug / play-test cheats (console)
	UFUNCTION(Exec) void MSGiveCash(int32 Amount);
	UFUNCTION(Exec) void MSSkipWave();
	UFUNCTION(Exec) void MSSetWave(int32 Wave);
	UFUNCTION(Exec) void MSKillAll();
	UFUNCTION(Exec) void MSGod();
	UFUNCTION(Exec) void MSGiveWeapon(FName WeaponRow);
	UFUNCTION(Exec) void MSGiveAll();
	UFUNCTION(Exec) void MSAcoustics();

	/** Optional asset-based mapping context added on top of the runtime one. */
	UPROPERTY(EditDefaultsOnly, Category = "Input") TSoftObjectPtr<UInputMappingContext> OverrideMappingContext;

protected:
	virtual void BeginPlay() override;
	virtual void SetupInputComponent() override;
	virtual void OnPossess(APawn* InPawn) override;

	void BuildInput();
	void AddMappingContexts();
	void SetMenuInputMode(bool bMenu, bool bPauseGame);
	bool CheatAllowed();

	UPROPERTY(Transient) FMSInputActions Actions;
	UPROPERTY(Transient) TObjectPtr<UInputMappingContext> Mapping;
	UPROPERTY(Transient) TObjectPtr<UMSPauseMenuWidget> PauseMenu;
	UPROPERTY(Transient) TObjectPtr<UMSGameOverWidget> GameOverScreen;
	UPROPERTY(Transient) TObjectPtr<UMSShopWidget> ShopWidget;
	UPROPERTY(Transient) TObjectPtr<UMSMainMenuWidget> MainMenu;
	bool bInputBuilt = false;
};
