// Engine-free gameplay rules.
//
// Everything in here is plain C++ (no Unreal headers) so it can be unit tested outside the
// engine: see Tests/Rules/rules_test.cpp, which CI compiles with g++. The Unreal code converts
// its types and calls these functions, so the numbers you see in tests are the numbers in game.
// All tuning values come in through the parameter structs, which are filled from DataTables.

#pragma once

#include <algorithm>
#include <cmath>
#include <cstdint>

namespace MSRules
{
	constexpr float Pi = 3.14159265358979323846f;

	inline float Clamp(float V, float Lo, float Hi) { return V < Lo ? Lo : (V > Hi ? Hi : V); }
	inline float Lerp(float A, float B, float T) { return A + (B - A) * T; }
	inline float DegToRad(float D) { return D * Pi / 180.f; }
	inline float RadToDeg(float R) { return R * 180.f / Pi; }

	struct FVec3
	{
		float X = 0.f, Y = 0.f, Z = 0.f;
		FVec3() = default;
		FVec3(float InX, float InY, float InZ) : X(InX), Y(InY), Z(InZ) {}
		FVec3 operator-(const FVec3& O) const { return {X - O.X, Y - O.Y, Z - O.Z}; }
		FVec3 operator+(const FVec3& O) const { return {X + O.X, Y + O.Y, Z + O.Z}; }
		FVec3 operator*(float S) const { return {X * S, Y * S, Z * S}; }
		float Dot(const FVec3& O) const { return X * O.X + Y * O.Y + Z * O.Z; }
		float Length() const { return std::sqrt(X * X + Y * Y + Z * Z); }
		FVec3 Normal() const
		{
			const float L = Length();
			return L > 1e-6f ? FVec3{X / L, Y / L, Z / L} : FVec3{};
		}
	};

	// ---------------------------------------------------------------- Waves

	enum EEnemyKind : int32_t
	{
		Rifleman = 0,
		Rusher,
		Dog,
		Juggernaut,
		Helicopter,
		EnemyKindCount
	};

	struct FWave
	{
		int32_t Count[EnemyKindCount] = {0, 0, 0, 0, 0};
		float HealthMultiplier = 1.f;
		float DamageMultiplier = 1.f;
		float AccuracyMultiplier = 1.f;
		int32_t MaxAlive = 12;
		float SpawnInterval = 1.f;
		int32_t ClearBonus = 0;

		int32_t Total() const
		{
			int32_t T = 0;
			for (int32_t I = 0; I < EnemyKindCount; ++I) T += Count[I];
			return T;
		}
	};

	// How waves keep growing once the hand-authored wave table runs out.
	struct FEndlessParams
	{
		float CountGrowthPerWave = 0.08f;     // +8% enemies per wave past the table
		float HealthGrowthPerWave = 0.06f;
		float DamageGrowthPerWave = 0.03f;
		float AccuracyGrowthPerWave = 0.02f;
		float MaxHealthMultiplier = 4.f;
		float MaxDamageMultiplier = 2.5f;
		float MaxAccuracyMultiplier = 1.8f;
		int32_t MaxAliveCap = 32;
		int32_t ClearBonusGrowth = 50;
		int32_t HelicopterEveryNWaves = 5;    // past the table, a helicopter every N waves
	};

	// Wave N (1-based) when N is beyond the last authored wave LastIndex.
	inline FWave ExtrapolateWave(const FWave& Last, int32_t LastIndex, int32_t Wave, const FEndlessParams& P)
	{
		FWave W = Last;
		const int32_t Extra = Wave - LastIndex;
		if (Extra <= 0)
		{
			return W;
		}
		const float ExtraF = static_cast<float>(Extra);
		const float CountScale = 1.f + P.CountGrowthPerWave * ExtraF;
		for (int32_t I = 0; I < EnemyKindCount; ++I)
		{
			if (I == Helicopter)
			{
				continue;
			}
			W.Count[I] = static_cast<int32_t>(std::lround(static_cast<float>(Last.Count[I]) * CountScale));
		}
		W.Count[Helicopter] = (P.HelicopterEveryNWaves > 0 && Wave % P.HelicopterEveryNWaves == 0)
			? std::max(1, Last.Count[Helicopter]) : 0;
		W.HealthMultiplier = std::min(P.MaxHealthMultiplier, Last.HealthMultiplier + P.HealthGrowthPerWave * ExtraF);
		W.DamageMultiplier = std::min(P.MaxDamageMultiplier, Last.DamageMultiplier + P.DamageGrowthPerWave * ExtraF);
		W.AccuracyMultiplier = std::min(P.MaxAccuracyMultiplier, Last.AccuracyMultiplier + P.AccuracyGrowthPerWave * ExtraF);
		W.MaxAlive = std::min(P.MaxAliveCap, Last.MaxAlive + Extra / 2);
		W.ClearBonus = Last.ClearBonus + P.ClearBonusGrowth * Extra;
		return W;
	}

	// Builds the spawn order for a wave: interleaves enemy kinds so every type shows up across the
	// wave instead of in one clump. Heavy types are pushed later. Writes up to MaxOut kinds into Out
	// and returns how many were written.
	inline int32_t BuildSpawnOrder(const FWave& W, int32_t* Out, int32_t MaxOut)
	{
		int32_t Remaining[EnemyKindCount];
		int32_t Total = 0;
		for (int32_t I = 0; I < EnemyKindCount; ++I)
		{
			Remaining[I] = std::max(0, W.Count[I]);
			Total += Remaining[I];
		}
		Total = std::min(Total, MaxOut);
		// Error-diffusion: each kind accumulates its share every slot; the biggest accumulator spawns.
		float Acc[EnemyKindCount] = {0, 0, 0, 0, 0};
		// Heavy kinds start behind so they appear in the second half of the wave.
		const float Delay[EnemyKindCount] = {0.f, -0.3f, -0.2f, -0.9f, -1.5f};
		for (int32_t I = 0; I < EnemyKindCount; ++I) Acc[I] = Delay[I];
		for (int32_t Slot = 0; Slot < Total; ++Slot)
		{
			int32_t Left = 0;
			for (int32_t I = 0; I < EnemyKindCount; ++I) Left += Remaining[I];
			if (Left <= 0)
			{
				return Slot;
			}
			int32_t Best = -1;
			for (int32_t I = 0; I < EnemyKindCount; ++I)
			{
				if (Remaining[I] <= 0) continue;
				Acc[I] += static_cast<float>(Remaining[I]) / static_cast<float>(Left);
				if (Best < 0 || Acc[I] > Acc[Best]) Best = I;
			}
			Acc[Best] -= 1.f;
			--Remaining[Best];
			Out[Slot] = Best;
		}
		return Total;
	}

	// ---------------------------------------------------------------- Economy

	struct FCashParams
	{
		int32_t HeadshotBonus = 50;
		int32_t MeleeBonus = 50;
		int32_t ExplosiveBonus = 0;
		float CashMultiplier = 1.f;
	};

	inline int32_t KillReward(int32_t BaseReward, bool bHeadshot, bool bMelee, bool bExplosive, const FCashParams& P)
	{
		int32_t R = BaseReward;
		if (bHeadshot) R += P.HeadshotBonus;
		if (bMelee) R += P.MeleeBonus;
		if (bExplosive) R += P.ExplosiveBonus;
		return static_cast<int32_t>(std::lround(static_cast<float>(R) * P.CashMultiplier));
	}

	inline bool CanAfford(int32_t Cash, int32_t Price) { return Price >= 0 && Cash >= Price; }

	// Ammo refill price scales with how empty the reserve is (never free unless full).
	inline int32_t AmmoRefillPrice(int32_t FullPrice, int32_t Current, int32_t Max)
	{
		if (Max <= 0 || Current >= Max) return 0;
		const float Missing = 1.f - static_cast<float>(Current) / static_cast<float>(Max);
		return std::max(1, static_cast<int32_t>(std::ceil(static_cast<float>(FullPrice) * Missing)));
	}

	// ---------------------------------------------------------------- Damage / health

	// Linear falloff between Start and End, clamped to MinFraction beyond End.
	inline float DamageFalloff(float Distance, float Start, float End, float MinFraction)
	{
		if (Distance <= Start || End <= Start) return 1.f;
		if (Distance >= End) return MinFraction;
		const float T = (Distance - Start) / (End - Start);
		return Lerp(1.f, MinFraction, T);
	}

	// Armor soaks AbsorbFraction of incoming damage until it runs out. Returns health damage.
	inline float ApplyArmor(float Damage, float& Armor, float AbsorbFraction)
	{
		if (Damage <= 0.f) return 0.f;
		if (Armor <= 0.f) return Damage;
		const float Soak = std::min(Armor, Damage * Clamp(AbsorbFraction, 0.f, 1.f));
		Armor -= Soak;
		return Damage - Soak;
	}

	// One regen tick: nothing until Delay seconds after the last hit, then Rate per second.
	inline float RegenStep(float Health, float MaxHealth, float TimeSinceDamage, float Delay, float Rate, float Dt)
	{
		if (Health <= 0.f || TimeSinceDamage < Delay) return Health;
		return std::min(MaxHealth, Health + Rate * Dt);
	}

	// Explosion damage with a full-damage inner radius and linear falloff to the outer radius.
	inline float RadialDamage(float BaseDamage, float Distance, float InnerRadius, float OuterRadius, float MinFraction)
	{
		if (Distance >= OuterRadius) return 0.f;
		if (Distance <= InnerRadius || OuterRadius <= InnerRadius) return BaseDamage;
		const float T = (Distance - InnerRadius) / (OuterRadius - InnerRadius);
		return BaseDamage * Lerp(1.f, MinFraction, T);
	}

	// ---------------------------------------------------------------- Spawning

	struct FSpawnParams
	{
		float MinDistance = 1500.f;       // cm
		float MaxDistance = 9000.f;
		float PreferredDistance = 3500.f;
		float ViewHalfAngleDeg = 55.f;    // half horizontal FOV of the player
		float ViewMarginDeg = 20.f;       // extra safety margin outside the view cone
		float BehindBonus = 0.5f;         // score bonus for points behind the player
	};

	// True when Point is outside the viewer's view cone (plus margin) or too close to ever be fair.
	// Line-of-sight is checked separately with a trace in the engine.
	inline bool IsOutsideViewCone(const FVec3& ViewerPos, const FVec3& ViewerForward, const FVec3& Point, const FSpawnParams& P)
	{
		const FVec3 To = Point - ViewerPos;
		const float Dist = To.Length();
		if (Dist < 1.f) return false;
		const float CosAngle = To.Normal().Dot(ViewerForward.Normal());
		const float Limit = std::cos(DegToRad(Clamp(P.ViewHalfAngleDeg + P.ViewMarginDeg, 0.f, 180.f)));
		return CosAngle < Limit;
	}

	// Higher is better. Negative means "not allowed".
	inline float ScoreSpawnPoint(const FVec3& ViewerPos, const FVec3& ViewerForward, const FVec3& Point, bool bVisibleByTrace, const FSpawnParams& P)
	{
		const float Dist = (Point - ViewerPos).Length();
		if (Dist < P.MinDistance || Dist > P.MaxDistance) return -1.f;
		const bool bOutside = IsOutsideViewCone(ViewerPos, ViewerForward, Point, P);
		if (!bOutside && bVisibleByTrace) return -1.f;     // in view and visible: never spawn here
		float Score = 1.f - std::fabs(Dist - P.PreferredDistance) / std::max(1.f, P.MaxDistance);
		const float Behind = -(Point - ViewerPos).Normal().Dot(ViewerForward.Normal()); // 1 = straight behind
		Score += P.BehindBonus * std::max(0.f, Behind);
		if (!bOutside) Score -= 0.5f;                       // in the cone but occluded: allowed, less wanted
		return std::max(0.001f, Score);
	}

	// ---------------------------------------------------------------- Feel

	inline float FireInterval(float RoundsPerMinute) { return RoundsPerMinute > 0.f ? 60.f / RoundsPerMinute : 1.f; }

	// Critically/under-damped spring used for weapon kick and camera recoil return.
	inline void SpringStep(float& Value, float& Velocity, float Target, float Stiffness, float Damping, float Dt)
	{
		// Semi-implicit Euler, sub-stepped for stability at low frame rates.
		const int32_t Steps = Dt > 1.f / 120.f ? static_cast<int32_t>(std::ceil(Dt * 120.f)) : 1;
		const float H = Dt / static_cast<float>(Steps);
		for (int32_t I = 0; I < Steps; ++I)
		{
			const float Accel = -Stiffness * (Value - Target) - Damping * Velocity;
			Velocity += Accel * H;
			Value += Velocity * H;
		}
	}

	// Cone half-angle in degrees for the next shot.
	inline float CurrentSpread(float Base, float MoveAdd, float SpeedFraction, float Bloom, float AirAdd, bool bInAir, float MaxSpread)
	{
		const float S = Base + MoveAdd * Clamp(SpeedFraction, 0.f, 1.f) + Bloom + (bInAir ? AirAdd : 0.f);
		return Clamp(S, 0.f, MaxSpread);
	}

	// Shake amount from trauma (0..1). Squaring/cubing makes small hits subtle and big ones violent.
	inline float TraumaToShake(float Trauma, float Exponent)
	{
		return std::pow(Clamp(Trauma, 0.f, 1.f), std::max(0.1f, Exponent));
	}

	// Trauma added by an explosion at Distance (0 beyond Radius).
	inline float ExplosionTrauma(float MaxTrauma, float Distance, float Radius)
	{
		if (Radius <= 0.f || Distance >= Radius) return 0.f;
		const float T = 1.f - Distance / Radius;
		return MaxTrauma * T * T;
	}

	// Signed yaw angle (degrees, -180..180) from the viewer's facing to the source, clockwise positive
	// when seen from above with X forward, Y right (Unreal's convention). Used by the damage indicator.
	inline float DamageIndicatorAngle(const FVec3& ViewerPos, float ViewerYawDeg, const FVec3& SourcePos)
	{
		const float Dx = SourcePos.X - ViewerPos.X;
		const float Dy = SourcePos.Y - ViewerPos.Y;
		float A = RadToDeg(std::atan2(Dy, Dx)) - ViewerYawDeg;
		while (A > 180.f) A -= 360.f;
		while (A < -180.f) A += 360.f;
		return A;
	}

	// How much of the climbed recoil the camera gives back after you stop firing.
	inline float RecoilRecoveryStep(float Accumulated, float RecoverySpeedDegPerSec, float Dt)
	{
		if (Accumulated <= 0.f) return 0.f;
		return std::max(0.f, Accumulated - RecoverySpeedDegPerSec * Dt);
	}

	// ---------------------------------------------------------------- Acoustics

	struct FRoomProbe
	{
		float AverageDistance = 0.f;  // cm, of the traces that hit
		float HitFraction = 0.f;      // 0..1 of traces that hit something
		bool bCeiling = false;
	};

	enum ERoomClass : int32_t
	{
		Outdoor = 0,
		SmallRoom,
		LargeRoom,
		RoomClassCount
	};

	// Thresholds come from the Acoustics DataTable.
	inline ERoomClass ClassifyRoom(const FRoomProbe& P, float SmallRoomMaxDistance, float EnclosedMinHitFraction)
	{
		if (!P.bCeiling || P.HitFraction < EnclosedMinHitFraction) return Outdoor;
		return P.AverageDistance <= SmallRoomMaxDistance ? SmallRoom : LargeRoom;
	}
}
