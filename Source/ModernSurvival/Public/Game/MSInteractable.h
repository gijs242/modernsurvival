#pragma once

#include "CoreMinimal.h"
#include "UObject/Interface.h"
#include "MSInteractable.generated.h"

class AMSPlayerCharacter;

UINTERFACE(MinimalAPI, meta = (CannotImplementInterfaceInBlueprint))
class UMSInteractable : public UInterface
{
	GENERATED_BODY()
};

/** Things the player can use with the Interact key (buy stations). */
class MODERNSURVIVAL_API IMSInteractable
{
	GENERATED_BODY()

public:
	virtual FText GetInteractPrompt(const AMSPlayerCharacter* Player) const = 0;
	virtual void Interact(AMSPlayerCharacter* Player) = 0;
	virtual bool CanInteract(const AMSPlayerCharacter* Player) const { return true; }
};
