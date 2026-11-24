#pragma once

#include "CoreMinimal.h"
#include "Subsystems/WorldSubsystem.h"
#include "Core/MSRules.h"
#include "MSAudioSubsystem.generated.h"

class USoundBase;
class USoundAttenuation;
class UReverbEffect;
struct FMSWeaponRow;
struct FMSAcousticRow;

/**
 * Gunshot audio with room-dependent echo.
 *
 * Every ProbeInterval it fires a ring of traces (plus one up) around the listener and classifies
 * the space as Outdoor / SmallRoom / LargeRoom (thresholds and reverb in DT_Acoustics). The class
 * drives a runtime-created reverb effect and the delay/volume/pitch of each gunshot's echo tail.
 */
UCLASS()
class MODERNSURVIVAL_API UMSAudioSubsystem : public UTickableWorldSubsystem
{
	GENERATED_BODY()

public:
	virtual void Tick(float DeltaTime) override;
	virtual TStatId GetStatId() const override { RETURN_QUICK_DECLARE_CYCLE_STAT(UMSAudioSubsystem, STATGROUP_Tickables); }
	virtual bool IsTickable() const override;
	virtual bool DoesSupportWorldType(const EWorldType::Type WorldType) const override;

	/** bLocal = fired by the local player (played 2D, louder, punchier). */
	void PlayGunshot(const FVector& Location, const FMSWeaponRow& Weapon, bool bLocal);
	void PlayExplosion(const FVector& Location, USoundBase* Sound);
	void PlayAt(const FVector& Location, USoundBase* Sound, float Volume = 1.f, float Pitch = 1.f);
	void Play2D(USoundBase* Sound, float Volume = 1.f, float Pitch = 1.f);

	MSRules::ERoomClass GetRoomClass() const { return RoomClass; }
	FName GetRoomRowName() const;
	const MSRules::FRoomProbe& GetLastProbe() const { return LastProbe; }

	/** Runs one probe immediately at Location (used by tests and the debug command). */
	MSRules::FRoomProbe ProbeAt(const FVector& Location, float Distance) const;

private:
	USoundAttenuation* GetAttenuation(float FalloffDistance);
	void ApplyReverb(const FMSAcousticRow& Row);
	void ScheduleEcho(USoundBase* Sound, const FVector& Location, float Delay, float Volume, float Pitch, bool b2D);

	UPROPERTY(Transient) TMap<int32, TObjectPtr<USoundAttenuation>> Attenuations;
	UPROPERTY(Transient) TObjectPtr<UReverbEffect> Reverb;

	MSRules::ERoomClass RoomClass = MSRules::Outdoor;
	MSRules::ERoomClass AppliedClass = MSRules::RoomClassCount;
	MSRules::FRoomProbe LastProbe;
	float ProbeTimer = 0.f;
	int32 StableCount = 0;
	MSRules::ERoomClass PendingClass = MSRules::Outdoor;
};
