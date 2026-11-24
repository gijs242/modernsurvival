#include "AI/MSEnvQuery.h"

#include "AI/MSCombatBrainComponent.h"
#include "Data/MSSettings.h"
#include "ModernSurvival.h"
#include "AIController.h"
#include "Engine/World.h"
#include "EnvironmentQuery/EnvQuery.h"
#include "EnvironmentQuery/EnvQueryOption.h"
#include "EnvironmentQuery/EnvQueryTypes.h"
#include "EnvironmentQuery/Items/EnvQueryItemType_Point.h"
#include "EnvironmentQuery/Items/EnvQueryItemType_VectorBase.h"
#include "GameFramework/Pawn.h"
#include "NavigationSystem.h"
#include "UObject/UnrealType.h"

namespace
{
	UMSCombatBrainComponent* BrainFromQuerier(const FEnvQueryInstance& QueryInstance)
	{
		const APawn* Pawn = Cast<APawn>(QueryInstance.Owner.Get());
		const AController* C = Pawn ? Pawn->GetController() : nullptr;
		return C ? C->FindComponentByClass<UMSCombatBrainComponent>() : nullptr;
	}

	FVector EyeOf(const AActor* Actor)
	{
		if (const APawn* Pawn = Cast<APawn>(Actor))
		{
			return Pawn->GetPawnViewLocation();
		}
		return Actor ? Actor->GetActorLocation() + FVector(0, 0, 100) : FVector::ZeroVector;
	}

	bool BlockedByWorld(const UWorld* World, const FVector& A, const FVector& B)
	{
		FCollisionObjectQueryParams Objects;
		Objects.AddObjectTypesToQuery(ECC_WorldStatic);
		Objects.AddObjectTypesToQuery(ECC_WorldDynamic);
		return World->LineTraceTestByObjectType(A, B, Objects, FCollisionQueryParams(SCENE_QUERY_STAT(MSCoverTest), false));
	}
}

// ---------------------------------------------------------------------------------------- generator

UMSEnvQueryGenerator_Candidates::UMSEnvQueryGenerator_Candidates(const FObjectInitializer& ObjectInitializer)
	: Super(ObjectInitializer)
{
	ItemType = UEnvQueryItemType_Point::StaticClass();
}

void UMSEnvQueryGenerator_Candidates::GenerateItems(FEnvQueryInstance& QueryInstance) const
{
	const APawn* Pawn = Cast<APawn>(QueryInstance.Owner.Get());
	UMSCombatBrainComponent* Brain = BrainFromQuerier(QueryInstance);
	UWorld* World = Pawn ? Pawn->GetWorld() : nullptr;
	UNavigationSystemV1* Nav = World ? FNavigationSystem::GetCurrent<UNavigationSystemV1>(World) : nullptr;
	if (!Pawn || !Brain || !Nav)
	{
		return;
	}
	const FMSAIBehaviourRow& B = Brain->GetBehaviour();
	const AActor* Target = Brain->GetTarget();
	const FVector Origin = Pawn->GetActorLocation();

	TArray<FVector> Raw;
	if (bFlank && Target)
	{
		const FVector Center = Target->GetActorLocation();
		for (const float RadiusScale : {0.65f, 1.0f, 1.3f})
		{
			const float Radius = B.CoverPreferredDistance * RadiusScale;
			for (int32 I = 0; I < 24; ++I)
			{
				const float Angle = 2.f * PI * I / 24.f;
				const FVector P = Center + FVector(FMath::Cos(Angle), FMath::Sin(Angle), 0.f) * Radius;
				if (FVector::Dist2D(P, Origin) <= B.FlankSearchRadius)
				{
					Raw.Add(P);
				}
			}
		}
	}
	else
	{
		const float Spacing = FMath::Max(60.f, B.CoverGridSpacing);
		const int32 Steps = FMath::Clamp(FMath::FloorToInt(B.CoverSearchRadius / Spacing), 1, 20);
		for (int32 X = -Steps; X <= Steps; ++X)
		{
			for (int32 Y = -Steps; Y <= Steps; ++Y)
			{
				const FVector Offset(X * Spacing, Y * Spacing, 0.f);
				if (Offset.Size2D() <= B.CoverSearchRadius)
				{
					Raw.Add(Origin + Offset);
				}
			}
		}
	}

	const FVector Extent(150.f, 150.f, 400.f);
	for (const FVector& P : Raw)
	{
		FNavLocation Projected;
		if (Nav->ProjectPointToNavigation(P, Projected, Extent))
		{
			QueryInstance.AddItemData<UEnvQueryItemType_Point>(FNavLocation(Projected.Location, Projected.NodeRef));
		}
	}
}

// ---------------------------------------------------------------------------------------- test

UMSEnvQueryTest_Cover::UMSEnvQueryTest_Cover(const FObjectInitializer& ObjectInitializer)
	: Super(ObjectInitializer)
{
	Cost = EEnvTestCost::High;
	ValidItemType = UEnvQueryItemType_VectorBase::StaticClass();
	SetWorkOnFloatValues(true);
	TestPurpose = EEnvTestPurpose::FilterAndScore;
	FilterType = EEnvTestFilterType::Minimum;
	ScoringEquation = EEnvTestScoreEquation::Linear;
	FloatValueMin.DefaultValue = 0.05f;
}

float UMSEnvQueryTest_Cover::ScoreCandidate(bool bHiddenLow, bool bCanPeek, float DistToTarget, float PreferredDist, float MinDist, float AllyCrowding, float FlankAngleDeg, float FlankMinAngle, bool bFlankMode)
{
	if (DistToTarget < MinDist)
	{
		return 0.f;
	}
	if (!bHiddenLow && !bFlankMode)
	{
		return 0.f;                                   // no protection: not cover
	}
	if (bFlankMode && FlankAngleDeg < FlankMinAngle)
	{
		return 0.f;                                   // still in front of the target: not a flank
	}
	float Score = bHiddenLow ? 0.5f : 0.15f;
	Score += bCanPeek ? 0.35f : 0.f;
	const float DistScore = 1.f - FMath::Min(1.f, FMath::Abs(DistToTarget - PreferredDist) / FMath::Max(1.f, PreferredDist));
	Score += 0.3f * DistScore;
	if (bFlankMode)
	{
		Score += 0.4f * FMath::Clamp((FlankAngleDeg - FlankMinAngle) / FMath::Max(1.f, 180.f - FlankMinAngle), 0.f, 1.f);
	}
	Score -= 0.6f * FMath::Clamp(AllyCrowding, 0.f, 1.f);
	return FMath::Max(0.f, Score);
}

void UMSEnvQueryTest_Cover::RunTest(FEnvQueryInstance& QueryInstance) const
{
	UObject* QueryOwner = QueryInstance.Owner.Get();
	UMSCombatBrainComponent* Brain = BrainFromQuerier(QueryInstance);
	const AActor* Target = Brain ? Brain->GetTarget() : nullptr;
	UWorld* World = QueryOwner ? QueryOwner->GetWorld() : nullptr;
	if (!Brain || !Target || !World)
	{
		return;
	}
	FloatValueMin.BindData(QueryOwner, QueryInstance.QueryID);
	FloatValueMax.BindData(QueryOwner, QueryInstance.QueryID);
	const float MinThreshold = FloatValueMin.GetValue();
	const float MaxThreshold = FloatValueMax.GetValue();

	const FMSAIBehaviourRow& B = Brain->GetBehaviour();
	const FVector TargetEye = EyeOf(Target);
	const FVector TargetLoc = Target->GetActorLocation();
	const FVector TargetFwd = Target->GetActorForwardVector().GetSafeNormal2D();
	UMSAISubsystem* AI = UMSAISubsystem::Get(World);
	TArray<FVector> Claimed;
	if (AI)
	{
		AI->GetClaimedLocations(Brain, Claimed);
	}

	for (FEnvQueryInstance::ItemIterator It(this, QueryInstance); It; ++It)
	{
		const FVector Item = GetItemLocation(QueryInstance, It.GetIndex());
		const float Dist = FVector::Dist2D(Item, TargetLoc);
		if (Dist < B.CoverMinDistanceToTarget)
		{
			It.SetScore(TestPurpose, FilterType, 0.f, MinThreshold, MaxThreshold);
			continue;
		}
		const FVector Low = Item + FVector(0, 0, B.CoverCrouchHeight);
		const FVector High = Item + FVector(0, 0, B.CoverPeekHeight);
		const bool bHiddenLow = BlockedByWorld(World, TargetEye, Low);
		bool bCanPeek = false;
		if (bHiddenLow)
		{
			bCanPeek = !BlockedByWorld(World, High, TargetEye);
			if (!bCanPeek)
			{
				const FVector Right = FVector::CrossProduct((TargetLoc - Item).GetSafeNormal2D(), FVector::UpVector);
				bCanPeek = !BlockedByWorld(World, High + Right * B.CoverPeekSideOffset, TargetEye)
					|| !BlockedByWorld(World, High - Right * B.CoverPeekSideOffset, TargetEye);
			}
		}
		float Crowding = 0.f;
		for (const FVector& C : Claimed)
		{
			const float D = FVector::Dist2D(C, Item);
			Crowding = FMath::Max(Crowding, 1.f - D / FMath::Max(1.f, B.CoverAllySpacing));
		}
		const FVector ToItem = (Item - TargetLoc).GetSafeNormal2D();
		const float FlankAngle = FMath::RadiansToDegrees(FMath::Acos(FMath::Clamp(FVector::DotProduct(TargetFwd, ToItem), -1.f, 1.f)));
		const float Score = ScoreCandidate(bHiddenLow, bCanPeek, Dist, B.CoverPreferredDistance, B.CoverMinDistanceToTarget, Crowding, FlankAngle, B.FlankMinAngle, bFlankMode);
		It.SetScore(TestPurpose, FilterType, Score, MinThreshold, MaxThreshold);
	}
}

// ---------------------------------------------------------------------------------------- subsystem

UMSAISubsystem* UMSAISubsystem::Get(const UObject* WorldContext)
{
	const UWorld* World = WorldContext ? WorldContext->GetWorld() : nullptr;
	return World ? World->GetSubsystem<UMSAISubsystem>() : nullptr;
}

static void SetObjectArrayByReflection(UObject* Container, FName PropertyName, const TArray<UObject*>& Values)
{
	FArrayProperty* ArrayProp = FindFProperty<FArrayProperty>(Container->GetClass(), PropertyName);
	FObjectPropertyBase* Inner = ArrayProp ? CastField<FObjectPropertyBase>(ArrayProp->Inner) : nullptr;
	if (!ArrayProp || !Inner)
	{
		UE_LOG(LogMS, Error, TEXT("EQS: property %s not found on %s"), *PropertyName.ToString(), *Container->GetClass()->GetName());
		return;
	}
	FScriptArrayHelper Helper(ArrayProp, ArrayProp->ContainerPtrToValuePtr<void>(Container));
	Helper.EmptyValues();
	for (UObject* Value : Values)
	{
		const int32 Index = Helper.AddValue();
		Inner->SetObjectPropertyValue(Helper.GetRawPtr(Index), Value);
	}
}

static void SetObjectByReflection(UObject* Container, FName PropertyName, UObject* Value)
{
	if (FObjectPropertyBase* Prop = FindFProperty<FObjectPropertyBase>(Container->GetClass(), PropertyName))
	{
		Prop->SetObjectPropertyValue(Prop->ContainerPtrToValuePtr<void>(Container), Value);
	}
	else
	{
		UE_LOG(LogMS, Error, TEXT("EQS: property %s not found on %s"), *PropertyName.ToString(), *Container->GetClass()->GetName());
	}
}

UEnvQuery* UMSAISubsystem::BuildQuery(FName Name, bool bFlank)
{
	// UEnvQuery's option list is editor-authored data; we fill it through reflection so the game
	// needs no EQS assets. Assign assets in Project Settings to replace these.
	UEnvQuery* Query = NewObject<UEnvQuery>(this, Name, RF_Transient);
	UEnvQueryOption* Option = NewObject<UEnvQueryOption>(Query, NAME_None, RF_Transient);
	UMSEnvQueryGenerator_Candidates* Generator = NewObject<UMSEnvQueryGenerator_Candidates>(Option, NAME_None, RF_Transient);
	Generator->bFlank = bFlank;
	UMSEnvQueryTest_Cover* Test = NewObject<UMSEnvQueryTest_Cover>(Option, NAME_None, RF_Transient);
	Test->bFlankMode = bFlank;
	Test->TestOrder = 0;

	SetObjectByReflection(Option, TEXT("Generator"), Generator);
	SetObjectArrayByReflection(Option, TEXT("Tests"), {Test});
	SetObjectArrayByReflection(Query, TEXT("Options"), {Option});
	if (FNameProperty* NameProp = FindFProperty<FNameProperty>(UEnvQuery::StaticClass(), TEXT("QueryName")))
	{
		NameProp->SetPropertyValue_InContainer(Query, Name);
	}
	return Query;
}

UEnvQuery* UMSAISubsystem::GetCoverQuery()
{
	if (!CoverQuery)
	{
		CoverQuery = UMSSettings::Get()->CoverQueryOverride.LoadSynchronous();
		if (!CoverQuery)
		{
			CoverQuery = BuildQuery(TEXT("EQS_MSCover"), false);
		}
	}
	return CoverQuery;
}

UEnvQuery* UMSAISubsystem::GetFlankQuery()
{
	if (!FlankQuery)
	{
		FlankQuery = UMSSettings::Get()->FlankQueryOverride.LoadSynchronous();
		if (!FlankQuery)
		{
			FlankQuery = BuildQuery(TEXT("EQS_MSFlank"), true);
		}
	}
	return FlankQuery;
}

void UMSAISubsystem::GetClaimedLocations(const UMSCombatBrainComponent* Except, TArray<FVector>& Out) const
{
	for (const UMSCombatBrainComponent* Brain : Brains)
	{
		if (Brain && Brain != Except && Brain->IsActiveBrain())
		{
			Out.Add(Brain->GetClaimedLocation());
		}
	}
}

int32 UMSAISubsystem::CountFlankers() const
{
	int32 N = 0;
	for (const UMSCombatBrainComponent* Brain : Brains)
	{
		N += (Brain && Brain->IsFlanking()) ? 1 : 0;
	}
	return N;
}
