// Standalone tests for Source/ModernSurvival/Public/Core/MSRules.h.
// Build & run:  g++ -std=c++20 -O1 -Wall -Wextra -Werror -I Source/ModernSurvival/Public Tests/Rules/rules_test.cpp -o Tests/build/rules_test && Tests/build/rules_test
// CI runs this on every push (.github/workflows/ci.yml).

#include "Core/MSRules.h"

#include <cstdio>
#include <cstdlib>

using namespace MSRules;

static int GFailures = 0;
static int GChecks = 0;

#define EXPECT(Cond)                                                                    \
	do                                                                                  \
	{                                                                                   \
		++GChecks;                                                                      \
		if (!(Cond))                                                                    \
		{                                                                               \
			++GFailures;                                                                \
			std::printf("FAIL %s:%d  %s\n", __FILE__, __LINE__, #Cond);                 \
		}                                                                               \
	} while (0)

#define EXPECT_NEAR(A, B, Tol) EXPECT(std::fabs((A) - (B)) <= (Tol))

static void TestWaves()
{
	FWave Last;
	Last.Count[Rifleman] = 20;
	Last.Count[Rusher] = 10;
	Last.Count[Dog] = 6;
	Last.Count[Juggernaut] = 2;
	Last.Count[Helicopter] = 1;
	Last.HealthMultiplier = 2.f;
	Last.MaxAlive = 24;
	Last.ClearBonus = 1000;

	FEndlessParams P;
	const FWave Same = ExtrapolateWave(Last, 20, 20, P);
	EXPECT(Same.Total() == Last.Total());

	const FWave W25 = ExtrapolateWave(Last, 20, 25, P);
	EXPECT(W25.Count[Rifleman] > Last.Count[Rifleman]);           // bigger
	EXPECT(W25.HealthMultiplier > Last.HealthMultiplier);         // tougher
	EXPECT(W25.Count[Helicopter] == 1);                           // 25 % 5 == 0
	EXPECT(ExtrapolateWave(Last, 20, 26, P).Count[Helicopter] == 0);
	EXPECT(W25.ClearBonus == 1000 + 5 * P.ClearBonusGrowth);

	const FWave W500 = ExtrapolateWave(Last, 20, 500, P);
	EXPECT(W500.HealthMultiplier <= P.MaxHealthMultiplier + 1e-4f);
	EXPECT(W500.MaxAlive <= P.MaxAliveCap);

	// Monotonic growth across endless waves.
	int Prev = Last.Total();
	for (int Wv = 21; Wv < 60; ++Wv)
	{
		const int T = ExtrapolateWave(Last, 20, Wv, P).Total() - ExtrapolateWave(Last, 20, Wv, P).Count[Helicopter];
		EXPECT(T >= Prev - 1);
		Prev = T;
	}
}

static void TestSpawnOrder()
{
	FWave W;
	W.Count[Rifleman] = 10;
	W.Count[Rusher] = 4;
	W.Count[Juggernaut] = 1;
	int Order[64];
	const int N = BuildSpawnOrder(W, Order, 64);
	EXPECT(N == 15);
	int Seen[EnemyKindCount] = {0, 0, 0, 0, 0};
	int JuggSlot = -1;
	for (int I = 0; I < N; ++I)
	{
		++Seen[Order[I]];
		if (Order[I] == Juggernaut) JuggSlot = I;
	}
	EXPECT(Seen[Rifleman] == 10 && Seen[Rusher] == 4 && Seen[Juggernaut] == 1);
	EXPECT(Order[0] == Rifleman);          // waves open with riflemen
	EXPECT(JuggSlot >= N / 3);             // heavies are not first
	// Rushers are spread out, not all in one clump.
	int FirstRusher = -1, LastRusher = -1;
	for (int I = 0; I < N; ++I)
	{
		if (Order[I] == Rusher)
		{
			if (FirstRusher < 0) FirstRusher = I;
			LastRusher = I;
		}
	}
	EXPECT(LastRusher - FirstRusher >= 6);

	// Truncation to MaxOut.
	EXPECT(BuildSpawnOrder(W, Order, 5) == 5);
	FWave Empty;
	EXPECT(BuildSpawnOrder(Empty, Order, 64) == 0);
}

static void TestEconomy()
{
	FCashParams P;
	EXPECT(KillReward(100, false, false, false, P) == 100);
	EXPECT(KillReward(100, true, false, false, P) == 150);
	EXPECT(KillReward(100, true, true, false, P) == 200);
	P.CashMultiplier = 1.5f;
	EXPECT(KillReward(100, false, false, false, P) == 150);
	EXPECT(CanAfford(500, 500));
	EXPECT(!CanAfford(499, 500));
	EXPECT(AmmoRefillPrice(400, 0, 100) == 400);
	EXPECT(AmmoRefillPrice(400, 50, 100) == 200);
	EXPECT(AmmoRefillPrice(400, 100, 100) == 0);
	EXPECT(AmmoRefillPrice(400, 99, 100) >= 1);
}

static void TestDamage()
{
	EXPECT_NEAR(DamageFalloff(500.f, 1000.f, 3000.f, 0.5f), 1.f, 1e-5f);
	EXPECT_NEAR(DamageFalloff(2000.f, 1000.f, 3000.f, 0.5f), 0.75f, 1e-5f);
	EXPECT_NEAR(DamageFalloff(9000.f, 1000.f, 3000.f, 0.5f), 0.5f, 1e-5f);

	float Armor = 50.f;
	const float HealthDmg = ApplyArmor(100.f, Armor, 0.8f);
	EXPECT_NEAR(Armor, 0.f, 1e-5f);
	EXPECT_NEAR(HealthDmg, 50.f, 1e-5f);
	Armor = 250.f;
	EXPECT_NEAR(ApplyArmor(100.f, Armor, 0.8f), 20.f, 1e-4f);
	EXPECT_NEAR(Armor, 170.f, 1e-4f);

	EXPECT_NEAR(RegenStep(50.f, 100.f, 1.f, 4.f, 40.f, 0.5f), 50.f, 1e-5f);   // still in delay
	EXPECT_NEAR(RegenStep(50.f, 100.f, 5.f, 4.f, 40.f, 0.5f), 70.f, 1e-5f);
	EXPECT_NEAR(RegenStep(99.f, 100.f, 5.f, 4.f, 40.f, 0.5f), 100.f, 1e-5f);
	EXPECT_NEAR(RegenStep(0.f, 100.f, 5.f, 4.f, 40.f, 0.5f), 0.f, 1e-5f);     // dead stays dead

	EXPECT_NEAR(RadialDamage(200.f, 50.f, 100.f, 600.f, 0.f), 200.f, 1e-4f);
	EXPECT_NEAR(RadialDamage(200.f, 350.f, 100.f, 600.f, 0.f), 100.f, 1e-4f);
	EXPECT_NEAR(RadialDamage(200.f, 700.f, 100.f, 600.f, 0.f), 0.f, 1e-4f);
}

static void TestSpawning()
{
	FSpawnParams P;
	const FVec3 Eye(0, 0, 160);
	const FVec3 Fwd(1, 0, 0);
	EXPECT(!IsOutsideViewCone(Eye, Fwd, FVec3(3000, 0, 160), P));          // dead ahead
	EXPECT(IsOutsideViewCone(Eye, Fwd, FVec3(-3000, 0, 160), P));          // behind
	EXPECT(IsOutsideViewCone(Eye, Fwd, FVec3(0, 3000, 160), P));           // 90 deg right (55+20 < 90)
	EXPECT(!IsOutsideViewCone(Eye, Fwd, FVec3(3000, 2000, 160), P));       // ~34 deg

	EXPECT(ScoreSpawnPoint(Eye, Fwd, FVec3(3000, 0, 160), true, P) < 0.f);   // visible in front: never
	EXPECT(ScoreSpawnPoint(Eye, Fwd, FVec3(3000, 0, 160), false, P) > 0.f);  // occluded in front: allowed
	EXPECT(ScoreSpawnPoint(Eye, Fwd, FVec3(-500, 0, 160), false, P) < 0.f);  // too close
	EXPECT(ScoreSpawnPoint(Eye, Fwd, FVec3(-50000, 0, 160), false, P) < 0.f);// too far
	// Behind beats occluded-in-front at the same distance.
	EXPECT(ScoreSpawnPoint(Eye, Fwd, FVec3(-3500, 0, 160), true, P) > ScoreSpawnPoint(Eye, Fwd, FVec3(3500, 0, 160), false, P));
}

static void TestFeel()
{
	EXPECT_NEAR(FireInterval(600.f), 0.1f, 1e-6f);
	float X = 10.f, V = 0.f;
	for (int I = 0; I < 240; ++I) SpringStep(X, V, 0.f, 200.f, 25.f, 1.f / 60.f);
	EXPECT(std::fabs(X) < 0.01f);                     // settles
	X = 10.f; V = 0.f;
	SpringStep(X, V, 0.f, 200.f, 25.f, 0.5f);         // huge dt is stable thanks to sub-steps
	EXPECT(std::isfinite(X) && std::fabs(X) < 20.f);

	EXPECT_NEAR(CurrentSpread(1.f, 2.f, 0.5f, 0.5f, 3.f, false, 10.f), 2.5f, 1e-5f);
	EXPECT_NEAR(CurrentSpread(1.f, 2.f, 1.f, 5.f, 3.f, true, 6.f), 6.f, 1e-5f);

	EXPECT_NEAR(TraumaToShake(0.5f, 2.f), 0.25f, 1e-5f);
	EXPECT_NEAR(TraumaToShake(2.f, 2.f), 1.f, 1e-5f);
	EXPECT_NEAR(ExplosionTrauma(1.f, 0.f, 1000.f), 1.f, 1e-5f);
	EXPECT_NEAR(ExplosionTrauma(1.f, 1000.f, 1000.f), 0.f, 1e-5f);

	// Damage indicator: X forward, Y right. A source to the right is +90.
	EXPECT_NEAR(DamageIndicatorAngle(FVec3(0, 0, 0), 0.f, FVec3(0, 100, 0)), 90.f, 1e-3f);
	EXPECT_NEAR(DamageIndicatorAngle(FVec3(0, 0, 0), 0.f, FVec3(-100, 0, 0)), 180.f, 1e-3f);
	EXPECT_NEAR(DamageIndicatorAngle(FVec3(0, 0, 0), 90.f, FVec3(0, 100, 0)), 0.f, 1e-3f);
	EXPECT_NEAR(DamageIndicatorAngle(FVec3(0, 0, 0), 170.f, FVec3(100, -10, 0)), -175.71f, 0.05f);

	EXPECT_NEAR(RecoilRecoveryStep(3.f, 10.f, 0.1f), 2.f, 1e-5f);
	EXPECT_NEAR(RecoilRecoveryStep(0.5f, 10.f, 0.1f), 0.f, 1e-5f);
}

static void TestAcoustics()
{
	FRoomProbe Out;
	Out.HitFraction = 0.2f;
	EXPECT(ClassifyRoom(Out, 800.f, 0.6f) == Outdoor);
	FRoomProbe Small{400.f, 1.f, true};
	EXPECT(ClassifyRoom(Small, 800.f, 0.6f) == SmallRoom);
	FRoomProbe Big{2000.f, 0.9f, true};
	EXPECT(ClassifyRoom(Big, 800.f, 0.6f) == LargeRoom);
	FRoomProbe Carport{300.f, 0.4f, true};                // roof but open sides
	EXPECT(ClassifyRoom(Carport, 800.f, 0.6f) == Outdoor);
}

static void TestCoop()
{
	FSpawnParams P;
	FViewer V[2];
	V[0].Position = FVec3(0, 0, 160);
	V[0].Forward = FVec3(1, 0, 0);
	V[1].Position = FVec3(-6000, 0, 160);
	V[1].Forward = FVec3(1, 0, 0);          // player 2 stands far behind, looking the same way
	const FVec3 BehindP1(-3000, 0, 160);    // behind player 1 but right in front of player 2
	V[0].bSeesPoint = true;
	V[1].bSeesPoint = true;
	EXPECT(ScoreSpawnPoint(V[0].Position, V[0].Forward, BehindP1, true, P) > 0.f);   // fine solo...
	EXPECT(ScoreSpawnPointMulti(V, 2, BehindP1, P) < 0.f);                            // ...not in co-op
	V[1].bSeesPoint = false;                                                          // a wall hides it from player 2
	EXPECT(ScoreSpawnPointMulti(V, 2, BehindP1, P) > 0.f);
	const FVec3 NearP2(-6500, 800, 160);                                              // too close to player 2
	EXPECT(ScoreSpawnPointMulti(V, 2, NearP2, P) < 0.f);
	EXPECT(ScoreSpawnPointMulti(V, 0, BehindP1, P) < 0.f);
	EXPECT(ScoreSpawnPointMulti(V, 1, BehindP1, P) == ScoreSpawnPoint(V[0].Position, V[0].Forward, BehindP1, true, P));

	EXPECT(CoopScale(10, 1, 0.6f) == 10);
	EXPECT(CoopScale(10, 2, 0.6f) == 16);
	EXPECT(CoopScale(0, 2, 0.6f) == 0);
	EXPECT(IsTeamWiped(0) && !IsTeamWiped(1));
	EXPECT_NEAR(ReviveStep(0.f, true, 3.f, 1.5f), 0.5f, 1e-5f);
	EXPECT_NEAR(ReviveStep(0.9f, true, 3.f, 1.f), 1.f, 1e-5f);
	EXPECT_NEAR(ReviveStep(0.9f, false, 3.f, 1.f), 0.f, 1e-5f);
}

int main()
{
	TestWaves();
	TestSpawnOrder();
	TestEconomy();
	TestDamage();
	TestSpawning();
	TestFeel();
	TestAcoustics();
	TestCoop();
	std::printf("%d checks, %d failures\n", GChecks, GFailures);
	return GFailures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
