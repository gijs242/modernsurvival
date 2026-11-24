#include "MSEditorBuildLibrary.h"

#include "AI/MSStateTreeNodes.h"
#include "AssetRegistry/AssetRegistryModule.h"
#include "Components/StateTreeAIComponentSchema.h"
#include "HAL/IConsoleManager.h"
#include "Misc/PackageName.h"
#include "Modules/ModuleManager.h"
#include "StateTree.h"
#include "StateTreeCompiler.h"
#include "StateTreeCompilerLog.h"
#include "StateTreeEditorData.h"
#include "StateTreeState.h"
#include "UObject/Package.h"
#include "UObject/SavePackage.h"

IMPLEMENT_MODULE(FDefaultModuleImpl, ModernSurvivalEditor);

DEFINE_LOG_CATEGORY_STATIC(LogMSEditor, Log, All);

namespace
{
	void AddQuery(UStateTreeState& State, EMSBrainQuery Query, bool bInvert = false)
	{
		auto& Node = State.AddEnterCondition<FMSStateTreeCondition_Brain>();
		Node.GetNode().Query = Query;
		Node.GetNode().bInvertResult = bInvert;
	}

	void AddActivity(UStateTreeState& State, EMSBrainActivity Activity)
	{
		auto& Node = State.AddTask<FMSStateTreeTask_Activity>();
		Node.GetNode().Activity = Activity;
	}

	void GoTo(UStateTreeState& From, EStateTreeTransitionTrigger Trigger, const UStateTreeState& To)
	{
		From.AddTransition(Trigger, EStateTreeTransitionType::GotoState, &To);
	}
}

bool UMSEditorBuildLibrary::BuildEnemyStateTree(const FString& InPackagePath, FString& OutLog)
{
	const FString PackagePath = InPackagePath.IsEmpty() ? FString(TEXT("/Game/AI/ST_Enemy")) : InPackagePath;
	const FString AssetName = FPackageName::GetShortName(PackagePath);
	UPackage* Package = CreatePackage(*PackagePath);
	Package->FullyLoad();

	UStateTree* Tree = FindObject<UStateTree>(Package, *AssetName);
	if (!Tree)
	{
		Tree = NewObject<UStateTree>(Package, *AssetName, RF_Public | RF_Standalone | RF_Transactional);
		FAssetRegistryModule::AssetCreated(Tree);
	}

	UStateTreeEditorData* Editor = NewObject<UStateTreeEditorData>(Tree, NAME_None, RF_Transactional);
	Editor->Schema = NewObject<UStateTreeAIComponentSchema>(Editor, NAME_None, RF_Transactional);
	Tree->EditorData = Editor;

	// Same priority order as UMSCombatBrainComponent::SelectActivity (the C++ fallback).
	UStateTreeState& Root = Editor->AddSubTree(TEXT("Root"));

	UStateTreeState& Dead = Root.AddChildState(TEXT("Dead"));
	AddQuery(Dead, EMSBrainQuery::IsDead);
	AddActivity(Dead, EMSBrainActivity::Dead);

	UStateTreeState& NoTarget = Root.AddChildState(TEXT("NoTarget"));
	AddQuery(NoTarget, EMSBrainQuery::HasTarget, true);
	UStateTreeState& Follow = NoTarget.AddChildState(TEXT("FollowPlayer"));
	AddQuery(Follow, EMSBrainQuery::IsFriendly);
	AddActivity(Follow, EMSBrainActivity::Follow);
	UStateTreeState& Hunt = NoTarget.AddChildState(TEXT("Hunt"));
	AddActivity(Hunt, EMSBrainActivity::Hunt);

	UStateTreeState& Lost = Root.AddChildState(TEXT("LostTarget"));
	AddQuery(Lost, EMSBrainQuery::LostTarget);
	AddActivity(Lost, EMSBrainActivity::Hunt);

	UStateTreeState& Melee = Root.AddChildState(TEXT("Melee"));
	AddQuery(Melee, EMSBrainQuery::IsMeleeArchetype);
	AddActivity(Melee, EMSBrainActivity::Melee);

	UStateTreeState& Rush = Root.AddChildState(TEXT("Rush"));
	AddQuery(Rush, EMSBrainQuery::IsRusher);
	AddActivity(Rush, EMSBrainActivity::Rush);

	UStateTreeState& Advance = Root.AddChildState(TEXT("Advance"));
	AddQuery(Advance, EMSBrainQuery::UsesCover, true);
	AddActivity(Advance, EMSBrainActivity::Advance);

	UStateTreeState& Flank = Root.AddChildState(TEXT("Flank"));
	AddQuery(Flank, EMSBrainQuery::WantsFlank);
	AddActivity(Flank, EMSBrainActivity::Flank);

	UStateTreeState& Cover = Root.AddChildState(TEXT("Cover"));
	UStateTreeState& MoveToCover = Cover.AddChildState(TEXT("MoveToCover"));
	AddActivity(MoveToCover, EMSBrainActivity::TakeCover);
	UStateTreeState& HoldCover = Cover.AddChildState(TEXT("HoldCover"));
	AddActivity(HoldCover, EMSBrainActivity::HoldCover);
	UStateTreeState& Reposition = Cover.AddChildState(TEXT("Reposition"));
	AddActivity(Reposition, EMSBrainActivity::Reposition);

	// Transitions: every leaf goes back to Root (re-select) when done, except the cover sequence.
	for (UStateTreeState* Leaf : {&Follow, &Hunt, &Lost, &Melee, &Rush, &Advance, &HoldCover, &Reposition})
	{
		GoTo(*Leaf, EStateTreeTransitionTrigger::OnStateCompleted, Root);
	}
	GoTo(Flank, EStateTreeTransitionTrigger::OnStateSucceeded, HoldCover);
	GoTo(Flank, EStateTreeTransitionTrigger::OnStateFailed, Root);
	GoTo(MoveToCover, EStateTreeTransitionTrigger::OnStateSucceeded, HoldCover);
	GoTo(MoveToCover, EStateTreeTransitionTrigger::OnStateFailed, Reposition);

	FStateTreeCompilerLog Log;
	FStateTreeCompiler Compiler(Log);
	const bool bCompiled = Compiler.Compile(*Tree);
	OutLog = bCompiled ? TEXT("StateTree compiled.") : TEXT("StateTree compile FAILED (open the asset to see errors).");
	UE_LOG(LogMSEditor, Log, TEXT("%s %s"), *PackagePath, *OutLog);
	if (!bCompiled)
	{
		return false;
	}

	Package->MarkPackageDirty();
	const FString FileName = FPackageName::LongPackageNameToFilename(PackagePath, FPackageName::GetAssetPackageExtension());
	FSavePackageArgs Args;
	Args.TopLevelFlags = RF_Public | RF_Standalone;
	Args.SaveFlags = SAVE_NoError;
	const bool bSaved = UPackage::SavePackage(Package, Tree, *FileName, Args);
	OutLog += bSaved ? TEXT(" Saved to ") + FileName : TEXT(" (save failed)");
	return bSaved;
}

static FAutoConsoleCommand GBuildStateTreeCmd(
	TEXT("MS.BuildStateTree"),
	TEXT("Build and save the enemy StateTree asset (/Game/AI/ST_Enemy)."),
	FConsoleCommandDelegate::CreateLambda([]()
	{
		FString Log;
		UMSEditorBuildLibrary::BuildEnemyStateTree(TEXT("/Game/AI/ST_Enemy"), Log);
		UE_LOG(LogMSEditor, Display, TEXT("%s"), *Log);
	}));
