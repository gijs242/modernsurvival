#include "Audio/MSAudioSubsystem.h"

#include "Data/MSDataSubsystem.h"
#include "ModernSurvival.h"
#include "Components/AudioComponent.h"
#include "Engine/World.h"
#include "GameFramework/PlayerController.h"
#include "Kismet/GameplayStatics.h"
#include "Sound/ReverbEffect.h"
#include "Sound/SoundAttenuation.h"
#include "Sound/SoundBase.h"
#include "TimerManager.h"

static const FName GRoomRows[MSRules::RoomClassCount] = {TEXT("Outdoor"), TEXT("SmallRoom"), TEXT("LargeRoom")};

bool UMSAudioSubsystem::DoesSupportWorldType(const EWorldType::Type WorldType) const
{
	return WorldType == EWorldType::Game || WorldType == EWorldType::PIE;
}

bool UMSAudioSubsystem::IsTickable() const
{
	return !IsTemplate() && GetWorld() && GetWorld()->HasBegunPlay();
}

FName UMSAudioSubsystem::GetRoomRowName() const
{
	return GRoomRows[FMath::Clamp<int32>(RoomClass, 0, MSRules::RoomClassCount - 1)];
}

MSRules::FRoomProbe UMSAudioSubsystem::ProbeAt(const FVector& Location, float Distance) const
{
	MSRules::FRoomProbe Probe;
	const UWorld* World = GetWorld();
	if (!World)
	{
		return Probe;
	}
	FCollisionQueryParams Params(SCENE_QUERY_STAT(MSAcousticProbe), false);
	if (const APlayerController* PC = World->GetFirstPlayerController())
	{
		Params.AddIgnoredActor(PC->GetPawn());
	}
	constexpr int32 Rays = 12;
	int32 Hits = 0;
	float DistSum = 0.f;
	for (int32 I = 0; I < Rays; ++I)
	{
		// Alternate slightly up and level so low walls and roofs both count.
		const float Yaw = 360.f * I / Rays;
		const float Pitch = (I % 2 == 0) ? 0.f : 25.f;
		const FVector Dir = FRotator(Pitch, Yaw, 0.f).Vector();
		FHitResult Hit;
		if (World->LineTraceSingleByChannel(Hit, Location, Location + Dir * Distance, ECC_Visibility, Params))
		{
			++Hits;
			DistSum += Hit.Distance;
		}
	}
	FHitResult Up;
	Probe.bCeiling = World->LineTraceSingleByChannel(Up, Location, Location + FVector(0, 0, Distance), ECC_Visibility, Params);
	Probe.HitFraction = static_cast<float>(Hits) / Rays;
	Probe.AverageDistance = Hits > 0 ? DistSum / Hits : Distance;
	if (Probe.bCeiling)
	{
		// Tall halls (sports hall, atrium) sound bigger than their footprint.
		Probe.AverageDistance = FMath::Max(Probe.AverageDistance, Up.Distance * 1.2f);
	}
	return Probe;
}

void UMSAudioSubsystem::Tick(float DeltaTime)
{
	UWorld* World = GetWorld();
	UMSDataSubsystem* Data = UMSDataSubsystem::Get(World);
	if (!World || !Data)
	{
		return;
	}
	const FMSAcousticRow& Thresholds = Data->GetAcoustics(TEXT("Outdoor"));
	ProbeTimer -= DeltaTime;
	if (ProbeTimer > 0.f)
	{
		return;
	}
	ProbeTimer = FMath::Max(0.05f, Thresholds.ProbeInterval);

	FVector ListenerLoc;
	FRotator ListenerRot;
	APlayerController* PC = World->GetFirstPlayerController();
	if (!PC)
	{
		return;
	}
	PC->GetPlayerViewPoint(ListenerLoc, ListenerRot);
	LastProbe = ProbeAt(ListenerLoc, Thresholds.ProbeDistance);
	const MSRules::ERoomClass NewClass = MSRules::ClassifyRoom(LastProbe, Thresholds.SmallRoomMaxDistance, Thresholds.EnclosedMinHitFraction);

	// Require two probes in a row to agree, so walking past a doorway does not flicker the reverb.
	if (NewClass == PendingClass)
	{
		++StableCount;
	}
	else
	{
		PendingClass = NewClass;
		StableCount = 0;
	}
	if (StableCount >= 1)
	{
		RoomClass = PendingClass;
	}
	if (RoomClass != AppliedClass)
	{
		AppliedClass = RoomClass;
		ApplyReverb(Data->GetAcoustics(GetRoomRowName()));
	}
}

void UMSAudioSubsystem::ApplyReverb(const FMSAcousticRow& Row)
{
	if (!Reverb)
	{
		Reverb = NewObject<UReverbEffect>(this, TEXT("MSRuntimeReverb"), RF_Transient);
	}
	Reverb->Density = Row.Density;
	Reverb->Diffusion = Row.Diffusion;
	Reverb->Gain = Row.Gain;
	Reverb->GainHF = Row.GainHF;
	Reverb->DecayTime = Row.DecayTime;
	Reverb->DecayHFRatio = Row.DecayHFRatio;
	Reverb->ReflectionsGain = Row.ReflectionsGain;
	Reverb->ReflectionsDelay = Row.ReflectionsDelay;
	Reverb->LateGain = Row.LateGain;
	Reverb->LateDelay = Row.LateDelay;
	Reverb->AirAbsorptionGainHF = Row.AirAbsorptionGainHF;
	UGameplayStatics::ActivateReverbEffect(GetWorld(), Reverb, TEXT("MSRoom"), 10.f, Row.ReverbVolume, Row.FadeTime);
	UE_LOG(LogMS, Verbose, TEXT("Acoustics: %s (avg %.0f cm, hits %.2f)"), *GetRoomRowName().ToString(), LastProbe.AverageDistance, LastProbe.HitFraction);
}

USoundAttenuation* UMSAudioSubsystem::GetAttenuation(float FalloffDistance)
{
	const int32 Key = FMath::RoundToInt(FalloffDistance / 500.f);
	if (TObjectPtr<USoundAttenuation>* Found = Attenuations.Find(Key))
	{
		return *Found;
	}
	USoundAttenuation* Att = NewObject<USoundAttenuation>(this, NAME_None, RF_Transient);
	FSoundAttenuationSettings& S = Att->Attenuation;
	S.bAttenuate = true;
	S.bSpatialize = true;
	S.AttenuationShape = EAttenuationShape::Sphere;
	S.AttenuationShapeExtents = FVector(300.f, 0.f, 0.f);
	S.FalloffDistance = FMath::Max(1000.f, FalloffDistance);
	S.DistanceAlgorithm = EAttenuationDistanceModel::NaturalSound;
	S.bAttenuateWithLPF = true;
	S.LPFRadiusMin = 1500.f;
	S.LPFRadiusMax = FalloffDistance;
	S.bEnableReverbSend = true;
	S.bEnableOcclusion = true;
	S.OcclusionLowPassFilterFrequency = 1200.f;
	S.OcclusionVolumeAttenuation = 0.45f;
	S.OcclusionInterpolationTime = 0.1f;
	Attenuations.Add(Key, Att);
	return Att;
}

void UMSAudioSubsystem::Play2D(USoundBase* Sound, float Volume, float Pitch)
{
	if (Sound)
	{
		UGameplayStatics::PlaySound2D(this, Sound, Volume, Pitch);
	}
}

void UMSAudioSubsystem::PlayAt(const FVector& Location, USoundBase* Sound, float Volume, float Pitch)
{
	if (Sound)
	{
		UGameplayStatics::PlaySoundAtLocation(this, Sound, Location, Volume, Pitch, 0.f, GetAttenuation(4000.f));
	}
}

void UMSAudioSubsystem::ScheduleEcho(USoundBase* Sound, const FVector& Location, float Delay, float Volume, float Pitch, bool b2D)
{
	UWorld* World = GetWorld();
	if (!World || !Sound || Volume <= 0.01f)
	{
		return;
	}
	TWeakObjectPtr<UMSAudioSubsystem> WeakThis(this);
	TWeakObjectPtr<USoundBase> WeakSound(Sound);
	FTimerHandle Handle;
	World->GetTimerManager().SetTimer(Handle, FTimerDelegate::CreateLambda([WeakThis, WeakSound, Location, Volume, Pitch, b2D]()
	{
		if (!WeakThis.IsValid() || !WeakSound.IsValid())
		{
			return;
		}
		if (b2D)
		{
			WeakThis->Play2D(WeakSound.Get(), Volume, Pitch);
		}
		else
		{
			UGameplayStatics::PlaySoundAtLocation(WeakThis.Get(), WeakSound.Get(), Location, Volume, Pitch, 0.f, WeakThis->GetAttenuation(12000.f));
		}
	}), FMath::Max(0.01f, Delay), false);
}

void UMSAudioSubsystem::PlayGunshot(const FVector& Location, const FMSWeaponRow& Weapon, bool bLocal)
{
	UWorld* World = GetWorld();
	UMSDataSubsystem* Data = UMSDataSubsystem::Get(World);
	if (!World || !Data)
	{
		return;
	}
	const FMSAcousticRow& Room = Data->GetAcoustics(GetRoomRowName());
	USoundBase* Near = Weapon.FireSound.LoadSynchronous();
	USoundBase* Far = Weapon.FireSoundFar.LoadSynchronous();
	if (!Far)
	{
		Far = Near;
	}
	const float PitchJitter = FMath::FRandRange(0.97f, 1.03f);
	const float Volume = Weapon.FireSoundVolume * Room.ShotVolumeScale;

	if (bLocal)
	{
		if (Near)
		{
			if (UAudioComponent* AC = UGameplayStatics::CreateSound2D(this, Near, Volume, PitchJitter))
			{
				if (Room.ShotLowPassHz < 19000.f)
				{
					AC->SetLowPassFilterEnabled(true);
					AC->SetLowPassFilterFrequency(Room.ShotLowPassHz);
				}
				AC->bAutoDestroy = true;
				AC->Play();
			}
		}
		ScheduleEcho(Far, Location, Room.EchoDelay, Volume * Room.EchoVolume, Room.EchoPitch * PitchJitter, true);
		return;
	}

	// Distant shots: crossfade between the close and far recordings by distance to the listener.
	FVector ListenerLoc = Location;
	if (APlayerController* PC = World->GetFirstPlayerController())
	{
		FRotator Unused;
		PC->GetPlayerViewPoint(ListenerLoc, Unused);
	}
	const float Dist = FVector::Dist(ListenerLoc, Location);
	const float FarAlpha = FMath::Clamp(Dist / FMath::Max(1.f, Weapon.FarSoundDistance), 0.f, 1.f);
	if (Near && FarAlpha < 0.98f)
	{
		UGameplayStatics::PlaySoundAtLocation(this, Near, Location, Volume * (1.f - FarAlpha) * 0.8f, PitchJitter, 0.f, GetAttenuation(6000.f));
	}
	if (Far)
	{
		UGameplayStatics::PlaySoundAtLocation(this, Far, Location, Volume * FMath::Max(0.25f, FarAlpha), PitchJitter, 0.f, GetAttenuation(20000.f));
	}
	ScheduleEcho(Far, Location, Room.EchoDelay + Dist / 34300.f, Volume * Room.EchoVolume * 0.6f, Room.EchoPitch * PitchJitter, false);
}

void UMSAudioSubsystem::PlayExplosion(const FVector& Location, USoundBase* Sound)
{
	if (!Sound)
	{
		return;
	}
	UGameplayStatics::PlaySoundAtLocation(this, Sound, Location, 1.f, FMath::FRandRange(0.94f, 1.04f), 0.f, GetAttenuation(25000.f));
	UMSDataSubsystem* Data = UMSDataSubsystem::Get(GetWorld());
	if (Data)
	{
		const FMSAcousticRow& Room = Data->GetAcoustics(GetRoomRowName());
		ScheduleEcho(Sound, Location, Room.EchoDelay * 1.5f, Room.EchoVolume * 0.7f, Room.EchoPitch * 0.9f, false);
	}
}
