#pragma once

#include "CoreMinimal.h"

MODERNSURVIVAL_API DECLARE_LOG_CATEGORY_EXTERN(LogMS, Log, All);

/** Bullet trace channel ("Weapon" in DefaultEngine.ini). Capsules ignore it; meshes and hitboxes block it. */
#define ECC_MSWeapon ECC_GameTraceChannel1
