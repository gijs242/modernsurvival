#include "AI/MSAIController.h"

#include "AI/MSAICharacter.h"
#include "AI/MSCombatBrainComponent.h"
#include "Combat/MSCombatLibrary.h"
#include "Data/MSSettings.h"
#include "ModernSurvival.h"
#include "Components/StateTreeAIComponent.h"
#include "Perception/AIPerceptionComponent.h"
#include "Perception/AISenseConfig_Damage.h"
#include "Perception/AISenseConfig_Hearing.h"
#include "Perception/AISenseConfig_Sight.h"
#include "Perception/AISense_Hearing.h"
#include "StateTree.h"

AMSAIController::AMSAIController(const FObjectInitializer& ObjectInitializer)
	: Super(ObjectInitializer)
{
	Perception = CreateDefaultSubobject<UAIPerceptionComponent>(TEXT("Perception"));
	SightConfig = CreateDefaultSubobject<UAISenseConfig_Sight>(TEXT("SightConfig"));
	SightConfig->SightRadius = 6000.f;
	SightConfig->LoseSightRadius = 7000.f;
	SightConfig->PeripheralVisionAngleDegrees = 75.f;
	SightConfig->SetMaxAge(5.f);
	// Hostility is decided by our own team logic (UMSCombatLibrary::AreHostile), so perceive everyone.
	SightConfig->DetectionByAffiliation.bDetectEnemies = true;
	SightConfig->DetectionByAffiliation.bDetectNeutrals = true;
	SightConfig->DetectionByAffiliation.bDetectFriendlies = true;
	Perception->ConfigureSense(*SightConfig);

	HearingConfig = CreateDefaultSubobject<UAISenseConfig_Hearing>(TEXT("HearingConfig"));
	HearingConfig->HearingRange = 5000.f;
	HearingConfig->SetMaxAge(3.f);
	HearingConfig->DetectionByAffiliation.bDetectEnemies = true;
	HearingConfig->DetectionByAffiliation.bDetectNeutrals = true;
	HearingConfig->DetectionByAffiliation.bDetectFriendlies = true;
	Perception->ConfigureSense(*HearingConfig);

	DamageConfig = CreateDefaultSubobject<UAISenseConfig_Damage>(TEXT("DamageConfig"));
	DamageConfig->SetMaxAge(5.f);
	Perception->ConfigureSense(*DamageConfig);
	Perception->SetDominantSense(SightConfig->GetSenseImplementation());
	SetPerceptionComponent(*Perception);

	StateTree = CreateDefaultSubobject<UStateTreeAIComponent>(TEXT("StateTree"));
	StateTree->SetStartLogicAutomatically(false);

	Brain = CreateDefaultSubobject<UMSCombatBrainComponent>(TEXT("Brain"));
	bStartAILogicOnPossess = false;
}

void AMSAIController::OnPossess(APawn* InPawn)
{
	Super::OnPossess(InPawn);
	Perception->OnTargetPerceptionUpdated.AddUniqueDynamic(this, &AMSAIController::HandlePerception);
	ConfigureFromPawn();
}

void AMSAIController::ConfigureFromPawn()
{
	AMSAICharacter* P = Cast<AMSAICharacter>(GetPawn());
	if (!P)
	{
		return;
	}
	const FMSEnemyRow& Row = P->GetEnemyRow();
	SightConfig->SightRadius = Row.SightRadius;
	SightConfig->LoseSightRadius = FMath::Max(Row.LoseSightRadius, Row.SightRadius + 100.f);
	SightConfig->PeripheralVisionAngleDegrees = Row.PeripheralVisionHalfAngle;
	HearingConfig->HearingRange = Row.HearingRange;
	Perception->ConfigureSense(*SightConfig);
	Perception->ConfigureSense(*HearingConfig);

	Brain->Release();
	Brain->Possess(P);

	if (StateTree->IsRunning())
	{
		StateTree->StopLogic(TEXT("Reconfigure"));
	}
	UStateTree* Tree = UMSSettings::Get()->EnemyStateTree.LoadSynchronous();
	bUsingStateTree = Tree != nullptr;
	if (Tree)
	{
		StateTree->SetStateTree(Tree);
		StateTree->StartLogic();
		bUsingStateTree = StateTree->IsRunning();
	}
	if (!bUsingStateTree)
	{
		static bool bWarned = false;
		if (!bWarned)
		{
			bWarned = true;
			UE_LOG(LogMS, Warning, TEXT("Enemy StateTree not found/startable (%s). Using the C++ fallback brain. Run Scripts/setup_project.py or Tools > Modern Survival > Build Enemy StateTree."),
				*UMSSettings::Get()->EnemyStateTree.ToString());
		}
	}
	Brain->SetFallbackEnabled(!bUsingStateTree);
}

void AMSAIController::OnUnPossess()
{
	if (StateTree->IsRunning())
	{
		StateTree->StopLogic(TEXT("Unpossess"));
	}
	Brain->Release();
	Super::OnUnPossess();
}

void AMSAIController::OnPawnDied()
{
	if (StateTree->IsRunning())
	{
		StateTree->StopLogic(TEXT("Died"));
	}
	StopMovement();
	Brain->Release();
}

void AMSAIController::NotifyDamaged(const FMSDamageInfo& Info)
{
	Brain->NotifyDamaged(Info);
}

void AMSAIController::HandlePerception(AActor* Actor, FAIStimulus Stimulus)
{
	if (Stimulus.Type == UAISense::GetSenseID<UAISense_Hearing>() && Stimulus.WasSuccessfullySensed())
	{
		Brain->NotifyHeardNoise(Stimulus.StimulusLocation, Actor);
	}
}

FGenericTeamId AMSAIController::GetGenericTeamId() const
{
	const AMSAICharacter* P = Cast<AMSAICharacter>(GetPawn());
	return FGenericTeamId(static_cast<uint8>(P ? P->GetHolderTeam() : EMSTeam::Enemy));
}

ETeamAttitude::Type AMSAIController::GetTeamAttitudeTowards(const AActor& Other) const
{
	return UMSCombatLibrary::AreHostile(GetPawn(), &Other) ? ETeamAttitude::Hostile : ETeamAttitude::Friendly;
}
