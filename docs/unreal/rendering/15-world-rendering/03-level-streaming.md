# 레벨 스트리밍

대규모 월드에서 콘텐츠를 동적으로 로드/언로드하는 스트리밍 시스템을 분석합니다.

---

## 아키텍처 개요

```
┌─────────────────────────────────────────────────────────────────┐
│                  Level Streaming 아키텍처                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                  Persistent Level                        │   │
│  │  • 항상 로드됨                                           │   │
│  │  • 플레이어, 게임 로직                                   │   │
│  │  • Streaming Volume 정의                                │   │
│  └────────────────────────────┬────────────────────────────┘   │
│                               │                                 │
│           ┌───────────────────┼───────────────────┐            │
│           ▼                   ▼                   ▼            │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐      │
│  │ Streaming    │    │ Streaming    │    │ Streaming    │      │
│  │  Level A     │    │  Level B     │    │  Level C     │      │
│  │              │    │              │    │              │      │
│  │ ┌──────────┐│    │ ┌──────────┐│    │ ┌──────────┐│      │
│  │ │ Loaded   ││    │ │Unloaded  ││    │ │ Loading  ││      │
│  │ │ Visible  ││    │ │          ││    │ │          ││      │
│  │ └──────────┘│    │ └──────────┘│    │ └──────────┘│      │
│  └──────────────┘    └──────────────┘    └──────────────┘      │
│                                                                 │
│  스트리밍 상태:                                                  │
│  • Unloaded → Loading → Loaded (Visible/Hidden)               │
│  • Visible → Hidden → Unloading → Unloaded                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 스트리밍 방식

### 1. Volume 기반 스트리밍

```cpp
// Level Streaming Volume
class ALevelStreamingVolume : public AVolume
{
    // 연결된 스트리밍 레벨들
    TArray<FName> StreamingLevelNames;

    // 스트리밍 조건
    EStreamingVolumeUsage StreamingUsage;
    // SVB_Loading          - 로딩 트리거
    // SVB_LoadingAndVisibility - 로딩 및 가시성
    // SVB_VisibilityBlockingOnLoad - 로드 시 가시성 차단
    // SVB_BlockingOnLoad   - 로드 완료까지 블로킹
    // SVB_LoadingNotVisible - 로드만, 가시성 별도
};

// 볼륨 진입 시 로딩
void OnActorEnterVolume(AActor* Actor)
{
    if (Actor->IsPlayerControlled())
    {
        for (const FName& LevelName : StreamingLevelNames)
        {
            ULevelStreaming* Level = FindStreamingLevel(LevelName);
            Level->SetShouldBeLoaded(true);
            Level->SetShouldBeVisible(StreamingUsage != SVB_LoadingNotVisible);
        }
    }
}
```

### 2. 거리 기반 스트리밍

```cpp
// 거리 기반 스트리밍 설정
class ULevelStreaming : public UObject
{
    // 스트리밍 거리
    UPROPERTY(EditAnywhere)
    float LevelStreamingDistance;

    // 언로드 거리 (로드 거리보다 커야 함 - 히스테리시스)
    UPROPERTY(EditAnywhere)
    float LevelUnloadDistance;

    // 거리 계산
    float GetDistanceToPlayer(const FVector& PlayerLocation)
    {
        FBox LevelBounds = GetLevelBounds();
        return FMath::Sqrt(LevelBounds.ComputeSquaredDistanceToPoint(PlayerLocation));
    }
};
```

### 3. 블루프린트 스트리밍

```cpp
// 블루프린트 또는 C++에서 레벨 로드
void LoadLevelDynamic()
{
    FLatentActionInfo LatentInfo;
    LatentInfo.CallbackTarget = this;
    LatentInfo.ExecutionFunction = "OnLevelLoaded";
    LatentInfo.Linkage = 0;
    LatentInfo.UUID = GetNextLatentActionUUID();

    UGameplayStatics::LoadStreamLevel(
        this,
        LevelName,
        true,   // bMakeVisibleAfterLoad
        false,  // bShouldBlockOnLoad
        LatentInfo
    );
}

// 언로드
void UnloadLevelDynamic()
{
    FLatentActionInfo LatentInfo;

    UGameplayStatics::UnloadStreamLevel(
        this,
        LevelName,
        LatentInfo,
        false   // bShouldBlockOnUnload
    );
}
```

---

## 비동기 로딩

### Async Loading Manager

```
┌─────────────────────────────────────────────────────────────────┐
│                   Async Loading 파이프라인                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    Loading Request                       │   │
│  │  LoadStreamLevel("SubLevel_01")                         │   │
│  └────────────────────────────┬────────────────────────────┘   │
│                               │                                 │
│                               ▼                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                   Priority Queue                         │   │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐        │   │
│  │  │Priority │ │Priority │ │Priority │ │Priority │        │   │
│  │  │  High   │ │ Normal  │ │ Normal  │ │  Low    │        │   │
│  │  └────┬────┘ └─────────┘ └─────────┘ └─────────┘        │   │
│  └───────┼─────────────────────────────────────────────────┘   │
│          │                                                      │
│          ▼                                                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              Streaming Thread (Async)                    │   │
│  │                                                          │   │
│  │  1. Package 로드                                         │   │
│  │  2. Object 직렬화                                        │   │
│  │  3. PostLoad 처리                                        │   │
│  └────────────────────────────┬────────────────────────────┘   │
│                               │                                 │
│                               ▼                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    Game Thread                           │   │
│  │                                                          │   │
│  │  • Actor 등록                                            │   │
│  │  • Component 초기화                                       │   │
│  │  • Level 가시성 설정                                      │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 로딩 우선순위

```cpp
// 스트리밍 우선순위 설정
enum class ELevelStreamingPriority : uint8
{
    Low = 0,       // 배경 레벨
    Normal = 50,   // 일반 레벨
    High = 100,    // 중요 레벨
    Immediate = 255 // 즉시 로드 (가능하면 블로킹)
};

// 우선순위 계산
float CalculateLoadingPriority(ULevelStreaming* Level, const FVector& PlayerPos)
{
    float Distance = Level->GetDistanceToPlayer(PlayerPos);

    float BasePriority = (float)Level->GetPriority();
    float DistancePriority = 1.0f - FMath::Clamp(Distance / MaxDistance, 0.0f, 1.0f);

    return BasePriority + DistancePriority * 100.0f;
}
```

---

## 스트리밍 상태 관리

### 레벨 상태

```cpp
enum class ELevelStreamingState : uint8
{
    Unloaded,           // 완전히 언로드됨
    FailedToLoad,       // 로드 실패
    Loading,            // 로딩 중
    LoadedNotVisible,   // 로드됨, 숨김
    MakingVisible,      // 가시성 전환 중
    LoadedVisible,      // 로드됨, 보임
    MakingInvisible,    // 숨김 전환 중
    Unloading           // 언로딩 중
};

// 상태 전환 다이어그램
/*
┌────────────────────────────────────────────────────────────────┐
│                                                                │
│   Unloaded ──────▶ Loading ──────▶ LoadedNotVisible           │
│       ▲                                   │                    │
│       │                                   ▼                    │
│   Unloading ◀──── MakingInvisible ◀── LoadedVisible           │
│                                           ▲                    │
│                                           │                    │
│                            MakingVisible ─┘                    │
│                                                                │
└────────────────────────────────────────────────────────────────┘
*/
```

### 콜백 처리

```cpp
// 레벨 로드 완료 콜백
DECLARE_DYNAMIC_MULTICAST_DELEGATE(FLevelStreamingLoadedSignature);
DECLARE_DYNAMIC_MULTICAST_DELEGATE(FLevelStreamingVisibleSignature);
DECLARE_DYNAMIC_MULTICAST_DELEGATE(FLevelStreamingUnloadedSignature);

class ULevelStreaming : public UObject
{
    // 델리게이트
    FLevelStreamingLoadedSignature OnLevelLoaded;
    FLevelStreamingVisibleSignature OnLevelShown;
    FLevelStreamingVisibleSignature OnLevelHidden;
    FLevelStreamingUnloadedSignature OnLevelUnloaded;

    // C++ 바인딩
    void BindCallbacks()
    {
        OnLevelLoaded.AddDynamic(this, &ThisClass::HandleLevelLoaded);
        OnLevelShown.AddDynamic(this, &ThisClass::HandleLevelShown);
    }
};
```

---

## 스트리밍 최적화

### 히칭 방지

```
┌─────────────────────────────────────────────────────────────────┐
│                    Hitching 방지 전략                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. 프리로딩 (Pre-loading)                                      │
│     ┌─────────────────────────────────────────────────────┐    │
│     │ 플레이어 이동 방향 예측하여 미리 로드                  │    │
│     │                                                      │    │
│     │    Player ──▶ Direction                             │    │
│     │       │                                              │    │
│     │       │      ┌───────────┐                          │    │
│     │       └─────▶│Pre-load   │ (플레이어 도착 전 로드)   │    │
│     │              │  Zone     │                          │    │
│     │              └───────────┘                          │    │
│     └─────────────────────────────────────────────────────┘    │
│                                                                 │
│  2. 점진적 등록                                                  │
│     ┌─────────────────────────────────────────────────────┐    │
│     │ 모든 액터를 한 프레임에 등록하지 않음                   │    │
│     │                                                      │    │
│     │ Frame 1: Actor 1-50 등록                            │    │
│     │ Frame 2: Actor 51-100 등록                          │    │
│     │ Frame 3: Actor 101-150 등록                         │    │
│     │ ...                                                  │    │
│     └─────────────────────────────────────────────────────┘    │
│                                                                 │
│  3. 가시성 분리                                                  │
│     ┌─────────────────────────────────────────────────────┐    │
│     │ 로드와 가시성을 분리하여 부하 분산                     │    │
│     │                                                      │    │
│     │ t=0: Level 로드 시작 (비동기)                        │    │
│     │ t=1: 로드 완료, 가시성=Hidden                        │    │
│     │ t=2: 점진적으로 가시성 전환                          │    │
│     └─────────────────────────────────────────────────────┘    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 메모리 예산 관리

```cpp
// 스트리밍 메모리 예산
class FStreamingManager
{
    // 최대 로드 가능 레벨 수
    int32 MaxLoadedLevels;

    // 메모리 예산
    int64 MemoryBudget;
    int64 CurrentMemoryUsage;

    // 레벨 로드 결정
    bool ShouldLoadLevel(ULevelStreaming* Level)
    {
        int64 LevelSize = Level->GetEstimatedMemorySize();

        if (CurrentMemoryUsage + LevelSize > MemoryBudget)
        {
            // 예산 초과 - 불필요한 레벨 언로드 시도
            TryUnloadUnusedLevels(LevelSize);
        }

        return CurrentMemoryUsage + LevelSize <= MemoryBudget;
    }

    // 사용하지 않는 레벨 언로드
    void TryUnloadUnusedLevels(int64 RequiredSpace)
    {
        TArray<ULevelStreaming*> LoadedLevels;
        GetLoadedLevels(LoadedLevels);

        // 거리순 정렬 (먼 것부터)
        LoadedLevels.Sort([](const ULevelStreaming& A, const ULevelStreaming& B)
        {
            return A.GetDistanceToPlayer() > B.GetDistanceToPlayer();
        });

        int64 FreedSpace = 0;
        for (ULevelStreaming* Level : LoadedLevels)
        {
            if (Level->CanBeUnloaded())
            {
                Level->SetShouldBeLoaded(false);
                FreedSpace += Level->GetEstimatedMemorySize();

                if (FreedSpace >= RequiredSpace)
                    break;
            }
        }
    }
};
```

---

## Level Instance

### Packed Level Instance

```
┌─────────────────────────────────────────────────────────────────┐
│                   Packed Level Instance                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  일반 서브레벨:                                                  │
│  ┌───────────────────────────────────────────────┐             │
│  │  Building.umap                                 │             │
│  │  • 단일 인스턴스                               │             │
│  │  • 고정 위치                                   │             │
│  └───────────────────────────────────────────────┘             │
│                                                                 │
│  Packed Level Instance:                                         │
│  ┌───────────────────────────────────────────────┐             │
│  │  Building_LevelInstance                        │             │
│  │                                                │             │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐       │             │
│  │  │Instance │  │Instance │  │Instance │  ...  │             │
│  │  │   1     │  │   2     │  │   3     │       │             │
│  │  │Transform│  │Transform│  │Transform│       │             │
│  │  └─────────┘  └─────────┘  └─────────┘       │             │
│  │                                                │             │
│  │  • 동일 레벨 다중 배치                          │             │
│  │  • 개별 Transform                             │             │
│  │  • 데이터 공유로 메모리 절약                    │             │
│  └───────────────────────────────────────────────┘             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Level Instance Actor

```cpp
// Level Instance 액터
class ALevelInstance : public AActor
{
    // 소스 레벨
    UPROPERTY(EditAnywhere)
    TSoftObjectPtr<UWorld> WorldAsset;

    // 레벨 인스턴스 로드
    void LoadLevelInstance()
    {
        FWorldPartitionLevelHelper::LoadLevelInstance(
            GetWorld(),
            WorldAsset.GetLongPackageName(),
            GetActorTransform(),
            LoadedLevelStreaming
        );
    }

    // Packed Level Actor 활용
    // 동일한 레벨을 여러 번 인스턴싱할 때 메모리 효율적
};
```

---

## 디버깅 도구

### 콘솔 명령어

```cpp
// 스트리밍 디버깅 명령어
stat levels              // 로드된 레벨 통계
stat levelstreaming      // 스트리밍 상태
log LogLevelStreaming    // 스트리밍 로그

// 시각화
ShowFlag.LevelStreaming 1
ShowFlag.StreamingBounds 1

// 강제 로드/언로드
streamlevel MyLevel 1    // 로드
streamlevel MyLevel 0    // 언로드
```

### 스트리밍 시각화

```
┌─────────────────────────────────────────────────────────────────┐
│                 스트리밍 디버그 시각화                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ShowFlag.LevelStreaming 1 활성화 시:                           │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                     Viewport                             │   │
│  │                                                          │   │
│  │     ┌───────────────┐     ┌───────────────┐             │   │
│  │     │ ██████████████│     │ ░░░░░░░░░░░░░░│             │   │
│  │     │ █ Loaded ████ │     │ ░ Loading ░░░░│             │   │
│  │     │ ██████████████│     │ ░░░░░░░░░░░░░░│             │   │
│  │     └───────────────┘     └───────────────┘             │   │
│  │                                                          │   │
│  │     ┌───────────────┐     ┌───────────────┐             │   │
│  │     │               │     │ ▒▒▒▒▒▒▒▒▒▒▒▒▒▒│             │   │
│  │     │   Unloaded    │     │ ▒ Hidden ▒▒▒▒▒│             │   │
│  │     │               │     │ ▒▒▒▒▒▒▒▒▒▒▒▒▒▒│             │   │
│  │     └───────────────┘     └───────────────┘             │   │
│  │                                                          │   │
│  │  Legend:                                                 │   │
│  │  ████ = Loaded & Visible                                │   │
│  │  ░░░░ = Loading                                         │   │
│  │  ▒▒▒▒ = Loaded & Hidden                                 │   │
│  │  (빈) = Unloaded                                        │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 다음 단계

- [HLOD 시스템](04-hlod-system.md)에서 원거리 LOD 최적화를 학습합니다.
