# 애니메이션 최적화

LOD, 애니메이션 버짓, 멀티스레드 평가, 프로파일링을 분석합니다.

---

## 애니메이션 LOD

### LOD 시스템 개요

```
┌─────────────────────────────────────────────────────────────────┐
│                   Animation LOD System                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  거리별 최적화:                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  LOD 0 (근거리)     LOD 1          LOD 2      LOD 3     │   │
│  │  ┌──────────┐     ┌────────┐     ┌──────┐   ┌────┐      │   │
│  │  │ 풀 퀄리티 │     │ 간소화  │     │ 최소  │   │ 컬링│     │   │
│  │  └──────────┘     └────────┘     └──────┘   └────┘      │   │
│  │                                                          │   │
│  │  • 60 FPS 평가    • 30 FPS      • 15 FPS    • 스킵      │   │
│  │  • 풀 IK          • 간소화 IK   • IK 없음               │   │
│  │  • 모든 본        • 80% 본      • 50% 본                │   │
│  │  • 클로스 시뮬    • 클로스 ✗    • 클로스 ✗              │   │
│  │  • 페이셜         • 페이셜 ✗    • 페이셜 ✗              │   │
│  │                                                          │   │
│  │  0-10m            10-30m        30-70m      70m+         │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### LOD 설정

```cpp
// 애니메이션 LOD 설정
UPROPERTY(EditAnywhere, Category = "LOD")
TArray<FAnimationLODSettings> AnimLODSettings;

struct FAnimationLODSettings
{
    // 화면 크기 임계값
    float ScreenSize;

    // 업데이트 빈도 (1 = 매 프레임, 2 = 격프레임)
    int32 UpdateRate;

    // 본 LOD
    int32 BoneLODLevel;

    // 기능 토글
    bool bEnableIK;
    bool bEnableCloth;
    bool bEnableMorphTargets;
    bool bEnableRootMotion;

    // 보간 설정
    bool bInterpolateSkippedFrames;
};

// LOD 적용
void USkeletalMeshComponent::ApplyAnimationLOD()
{
    float ScreenSize = GetScreenSize();
    int32 LODLevel = GetLODLevelFromScreenSize(ScreenSize);

    const FAnimationLODSettings& Settings = AnimLODSettings[LODLevel];

    // 업데이트 레이트 설정
    SetUpdateRateMultiplier(Settings.UpdateRate);

    // 기능 토글
    bEnableIK = Settings.bEnableIK;
    bEnableClothSimulation = Settings.bEnableCloth;

    // 본 LOD
    SetForcedLOD(Settings.BoneLODLevel);
}
```

---

## 애니메이션 버짓

### 버짓 시스템

```
┌─────────────────────────────────────────────────────────────────┐
│                   Animation Budget System                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  프레임 버짓 할당:                                              │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  Total Frame Budget: 16.67ms (60 FPS)                    │   │
│  │  ├── Rendering: 8ms                                      │   │
│  │  ├── Game Logic: 4ms                                     │   │
│  │  ├── Animation: 3ms  ◄── 애니메이션 버짓                 │   │
│  │  └── Physics: 1.67ms                                     │   │
│  │                                                          │   │
│  │  애니메이션 버짓 분배 (3ms):                             │   │
│  │  ┌─────────────────────────────────────────────────┐    │   │
│  │  │ 중요도 높음 (플레이어): 1.5ms                    │    │   │
│  │  │ 중요도 중간 (NPC 근거리): 1.0ms                  │    │   │
│  │  │ 중요도 낮음 (NPC 원거리): 0.5ms                  │    │   │
│  │  └─────────────────────────────────────────────────┘    │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  초과 시 대응:                                                  │
│  • 낮은 중요도 캐릭터 업데이트 스킵                             │
│  • LOD 강제 상향                                                │
│  • 보간으로 대체                                                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 버짓 관리 코드

```cpp
// Animation Budget Allocator
class FAnimationBudgetAllocator
{
public:
    void AllocateBudget(float FrameBudgetMs)
    {
        // 중요도 정렬
        SortComponentsBySignificance();

        float RemainingBudget = FrameBudgetMs;
        float AccumulatedTime = 0.0f;

        for (FAnimBudgetEntry& Entry : BudgetEntries)
        {
            // 예상 비용 계산
            float EstimatedCost = EstimateAnimationCost(Entry.Component);

            if (AccumulatedTime + EstimatedCost <= RemainingBudget)
            {
                // 풀 업데이트
                Entry.UpdateRate = 1;
                AccumulatedTime += EstimatedCost;
            }
            else if (AccumulatedTime + EstimatedCost * 0.5f <= RemainingBudget)
            {
                // 격프레임 업데이트
                Entry.UpdateRate = 2;
                AccumulatedTime += EstimatedCost * 0.5f;
            }
            else
            {
                // 보간만
                Entry.UpdateRate = 0;
                Entry.bInterpolate = true;
            }
        }
    }

private:
    float EstimateAnimationCost(USkeletalMeshComponent* Comp)
    {
        float Cost = 0.0f;

        // 본 수 기반
        Cost += Comp->GetNumBones() * 0.001f;

        // 활성 노드 수
        if (UAnimInstance* Anim = Comp->GetAnimInstance())
        {
            Cost += Anim->GetActiveNodeCount() * 0.01f;
        }

        // 클로스
        if (Comp->ClothingSimulation)
        {
            Cost += 0.5f;
        }

        return Cost;
    }

    void SortComponentsBySignificance()
    {
        BudgetEntries.Sort([](const FAnimBudgetEntry& A, const FAnimBudgetEntry& B)
        {
            return A.Significance > B.Significance;
        });
    }
};
```

---

## 멀티스레드 평가

### 병렬 처리 아키텍처

```
┌─────────────────────────────────────────────────────────────────┐
│              Parallel Animation Evaluation                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Game Thread                                                    │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  PrepareForParallelEvaluation()                          │   │
│  │  • 애니메이션 입력 데이터 준비                           │   │
│  │  • 변수 스냅샷                                           │   │
│  └──────────────────────────┬──────────────────────────────┘   │
│                              │ Dispatch                         │
│                              ▼                                  │
│  Worker Threads                                                 │
│  ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌────────────┐  │
│  │ Character1 │ │ Character2 │ │ Character3 │ │ Character4 │  │
│  │            │ │            │ │            │ │            │  │
│  │ • AnimGraph│ │ • AnimGraph│ │ • AnimGraph│ │ • AnimGraph│  │
│  │ • Blending │ │ • Blending │ │ • Blending │ │ • Blending │  │
│  │ • IK Solve │ │ • IK Solve │ │ • IK Solve │ │ • IK Solve │  │
│  └────────────┘ └────────────┘ └────────────┘ └────────────┘  │
│         │              │              │              │         │
│         └──────────────┴──────┬───────┴──────────────┘         │
│                               │ Sync                            │
│                               ▼                                 │
│  Game Thread                                                    │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  CompleteParallelEvaluation()                            │   │
│  │  • 결과 적용                                             │   │
│  │  • 렌더 데이터 업데이트                                  │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 병렬 평가 코드

```cpp
// 병렬 애니메이션 평가
void USkeletalMeshComponent::DispatchParallelEvaluationTasks()
{
    if (!ShouldRunParallelEvaluation())
    {
        // 동기 평가
        EvaluateAnimation();
        return;
    }

    // 태스크 생성
    FGraphEventRef EvalTask = FFunctionGraphTask::CreateAndDispatchWhenReady(
        [this]()
        {
            // 워커 스레드에서 실행
            ParallelAnimationEvaluation();
        },
        TStatId(),
        nullptr,
        ENamedThreads::AnyHiPriThreadHiPriTask
    );

    // 태스크 저장 (나중에 동기화)
    ParallelEvaluationTask = EvalTask;
}

void USkeletalMeshComponent::ParallelAnimationEvaluation()
{
    SCOPE_CYCLE_COUNTER(STAT_ParallelAnimEvaluation);

    // AnimInstance 평가
    if (AnimScriptInstance)
    {
        AnimScriptInstance->ParallelUpdateAnimation();
    }

    // 포즈 계산
    EvaluatePostProcessMeshInstance();

    // 본 트랜스폼 계산
    FinalizeAnimationUpdate();
}

void USkeletalMeshComponent::CompleteParallelEvaluationTasks()
{
    if (ParallelEvaluationTask.IsValid())
    {
        // 태스크 완료 대기
        FTaskGraphInterface::Get().WaitUntilTaskCompletes(
            ParallelEvaluationTask);

        ParallelEvaluationTask = nullptr;
    }

    // 결과 적용
    SwapEvaluatedData();
    SendRenderDynamicData_Concurrent();
}
```

---

## URO (Update Rate Optimization)

### URO 시스템

```
┌─────────────────────────────────────────────────────────────────┐
│              Update Rate Optimization (URO)                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  화면 크기에 따른 업데이트 빈도:                                │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  Screen Size    Update Rate    Interpolation            │   │
│  │  ──────────────────────────────────────────────          │   │
│  │  > 0.5          Every Frame   None                       │   │
│  │  0.25 - 0.5     Every 2nd     Linear                     │   │
│  │  0.1 - 0.25     Every 4th     Linear                     │   │
│  │  0.05 - 0.1     Every 8th     Linear                     │   │
│  │  < 0.05         Every 16th    Linear                     │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  보간 처리:                                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  Frame:  1    2    3    4    5    6    7    8           │   │
│  │  ────────────────────────────────────────────            │   │
│  │  Eval:   ●              ●              ●                │   │
│  │  Interp:      ○    ○    ○    ○    ○    ○                │   │
│  │                                                          │   │
│  │  ● = 실제 평가, ○ = 보간된 포즈                          │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### URO 구현

```cpp
// URO 설정
UPROPERTY(EditAnywhere, Category = "Optimization")
FAnimUpdateRateParameters AnimUpdateRateParams;

struct FAnimUpdateRateParameters
{
    // 업데이트 스킵 설정
    TArray<float> BaseVisibleDistanceFactorThesholds;

    // 보간 활성화
    bool bInterpolateSkippedFrames = true;

    // 최대 스킵 프레임
    int32 MaxEvalRateForInterpolation = 4;

    // LOD 연동
    bool bShouldUseLodMap = true;
};

// URO 적용
void USkeletalMeshComponent::TickPose(float DeltaTime, bool bNeedsValidRootMotion)
{
    // 현재 업데이트 레이트 확인
    int32 UpdateRate = GetAnimUpdateRateShiftTag();

    if (UpdateRate > 1)
    {
        // 스킵 프레임
        FrameCounter++;
        if (FrameCounter % UpdateRate != 0)
        {
            // 보간만 수행
            if (AnimUpdateRateParams.bInterpolateSkippedFrames)
            {
                InterpolatePose(DeltaTime);
            }
            return;
        }
    }

    // 실제 애니메이션 평가
    EvaluateAnimation();
    FrameCounter = 0;
}

void USkeletalMeshComponent::InterpolatePose(float DeltaTime)
{
    // 이전/다음 포즈 사이 보간
    float Alpha = CalculateInterpolationAlpha();

    for (int32 BoneIndex = 0; BoneIndex < NumBones; ++BoneIndex)
    {
        FTransform& CurrentPose = BoneSpaceTransforms[BoneIndex];
        const FTransform& TargetPose = CachedBoneSpaceTransforms[BoneIndex];

        // 부드러운 보간
        CurrentPose.Blend(CurrentPose, TargetPose, Alpha);
    }
}
```

---

## 프로파일링

### 애니메이션 통계

```
┌─────────────────────────────────────────────────────────────────┐
│                   Animation Profiling                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  주요 측정 지표:                                                │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  STAT Group: Anim                                        │   │
│  │  ────────────────────────────────────────────            │   │
│  │  AnimGameThreadTime:     1.2ms  ← 게임 스레드 시간       │   │
│  │  AnimSlaveGameThreadTime: 0.3ms ← 보조 컴포넌트          │   │
│  │  AnimEvalTime:           0.8ms  ← 평가 시간              │   │
│  │  AnimGraphTime:          0.5ms  ← AnimGraph 처리         │   │
│  │  AnimBlendTime:          0.2ms  ← 포즈 블렌딩            │   │
│  │  SkinnedMeshCompTick:    0.4ms  ← 컴포넌트 틱            │   │
│  │                                                          │   │
│  │  STAT Group: MorphTarget                                 │   │
│  │  ────────────────────────────────────────────            │   │
│  │  MorphTargetUpdate:      0.1ms                           │   │
│  │                                                          │   │
│  │  STAT Group: Cloth                                       │   │
│  │  ────────────────────────────────────────────            │   │
│  │  ClothTotalTime:         0.6ms                           │   │
│  │  ClothSimulation:        0.5ms                           │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 디버그 명령어

```cpp
// 콘솔 명령어
// stat anim              - 애니메이션 통계
// stat initviews        - 가시성 처리
// ShowDebug Animation   - 애니메이션 디버그 표시

// 애니메이션 디버그 그리기
void ACharacter::DisplayDebug(UCanvas* Canvas, const FDebugDisplayInfo& DebugDisplay)
{
    if (DebugDisplay.IsDisplayOn(TEXT("Animation")))
    {
        USkeletalMeshComponent* Mesh = GetMesh();
        if (UAnimInstance* Anim = Mesh->GetAnimInstance())
        {
            // 현재 상태
            Canvas->DrawText(FString::Printf(
                TEXT("Active Montage: %s"),
                *GetNameSafe(Anim->GetCurrentActiveMontage())));

            // 업데이트 레이트
            Canvas->DrawText(FString::Printf(
                TEXT("Update Rate: %d"),
                Mesh->GetAnimUpdateRateShiftTag()));

            // LOD
            Canvas->DrawText(FString::Printf(
                TEXT("LOD Level: %d"),
                Mesh->GetPredictedLODLevel()));

            // 본 수
            Canvas->DrawText(FString::Printf(
                TEXT("Active Bones: %d / %d"),
                Mesh->GetNumBones(),
                Mesh->SkeletalMesh->GetRefSkeleton().GetNum()));
        }
    }
}
```

---

## 최적화 체크리스트

```
┌─────────────────────────────────────────────────────────────────┐
│                Animation Optimization Checklist                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  메시 최적화:                                                   │
│  □ 본 수 최소화 (목표: 75개 이하)                               │
│  □ LOD 설정 (최소 3단계)                                        │
│  □ 불필요한 본 제거 (물리, 페이셜)                              │
│                                                                 │
│  애니메이션 에셋:                                               │
│  □ 압축 설정 확인 (ACL 권장)                                    │
│  □ 키프레임 리덕션                                              │
│  □ 루트 모션 최적화                                             │
│                                                                 │
│  런타임 설정:                                                   │
│  □ URO 활성화                                                   │
│  □ 병렬 평가 활성화                                             │
│  □ 애니메이션 버짓 설정                                         │
│  □ 클로스/페이셜 LOD                                            │
│                                                                 │
│  AnimBlueprint:                                                 │
│  □ Fast Path 사용 (가능한 경우)                                 │
│  □ 불필요한 노드 제거                                           │
│  □ 캐싱 활용 (Cached Pose)                                      │
│  □ Rule 기반 LOD                                                │
│                                                                 │
│  모니터링:                                                      │
│  □ stat anim 정기 확인                                          │
│  □ 프레임 버짓 내 유지                                          │
│  □ 병목 지점 파악                                               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 참고 자료

- [Animation Optimization](https://docs.unrealengine.com/animation-optimization/)
- [Skeletal Mesh LOD](https://docs.unrealengine.com/skeletal-mesh-lod/)
- [Animation Budget Allocator](https://docs.unrealengine.com/animation-budget/)
- [Parallel Animation Evaluation](https://docs.unrealengine.com/parallel-animation/)
