#pragma once

#include "Runtime/Launch/Resources/Version.h"

// First-person rendering (separate view-model FOV + scale toward the eye) arrived in UE 5.6.
// Set to 0 to compile against older engines; the gun then renders with the world FOV.
#ifndef MS_WITH_FIRST_PERSON_RENDERING
#define MS_WITH_FIRST_PERSON_RENDERING (ENGINE_MAJOR_VERSION > 5 || (ENGINE_MAJOR_VERSION == 5 && ENGINE_MINOR_VERSION >= 6))
#endif
