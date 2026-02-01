# 메모리 및 스트리밍

메모리 관리, 텍스처 스트리밍, 레벨 스트리밍 최적화를 분석합니다.

---

## 메모리 버짓 관리

```
┌─────────────────────────────────────────────────────────────────┐
│                   Memory Budget Management                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  플랫폼별 메모리 타겟:                                          │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Platform          Total RAM    Game Budget             │   │
│  │  ─────────────────────────────────────────────────      │   │
│  │  PS5               16 GB        ~12 GB                  │   │
│  │  Xbox Series X     16 GB        ~12 GB                  │   │
│  │  PC (Min)          8 GB         ~4 GB                   │   │
│  │  PC (Rec)          16 GB        ~8 GB                   │   │
│  │  Mobile (High)     4 GB         ~2 GB                   │   │
│  │  Mobile (Low)      2 GB         ~1 GB                   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  메모리 분배 예시 (8GB 버짓):                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Textures       │████████████████████│  3.5 GB (44%)    │   │
│  │  Meshes         │█████████████│        2.0 GB (25%)     │   │
│  │  Audio          │████│                 0.5 GB (6%)      │   │
│  │  Animation      │████│                 0.5 GB (6%)      │   │
│  │  Physics        │███│                  0.3 GB (4%)      │   │
│  │  Code/Overhead  │█████████│            1.2 GB (15%)     │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 메모리 모니터링

```cpp
// 메모리 통계 콘솔 명령
// stat memory          - 전체 메모리 개요
// stat memoryplatform  - 플랫폼별 메모리
// stat levels          - 레벨별 메모리
// obj list class=Texture2D  - 특정 클래스 메모리

// 코드에서 메모리 확인
void CheckMemoryUsage()
{
    FPlatformMemoryStats MemStats = FPlatformMemory::GetStats();

    UE_LOG(LogTemp, Log, TEXT("Physical Memory Used: %.2f MB"),
        MemStats.UsedPhysical / (1024.0 * 1024.0));
    UE_LOG(LogTemp, Log, TEXT("Peak Physical Memory: %.2f MB"),
        MemStats.PeakUsedPhysical / (1024.0 * 1024.0));
    UE_LOG(LogTemp, Log, TEXT("Virtual Memory Used: %.2f MB"),
        MemStats.UsedVirtual / (1024.0 * 1024.0));

    // 텍스처 메모리
    SIZE_T TextureMemory = 0;
    for (TObjectIterator<UTexture2D> It; It; ++It)
    {
        TextureMemory += It->CalcTextureMemorySizeEnum(TMC_ResidentMips);
    }

    UE_LOG(LogTemp, Log, TEXT("Resident Texture Memory: %.2f MB"),
        TextureMemory / (1024.0 * 1024.0));
}
```

---

## 텍스처 스트리밍

```
┌─────────────────────────────────────────────────────────────────┐
│                   Texture Streaming                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  스트리밍 시스템:                                               │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  Disk          Pool                Screen               │   │
│  │  ┌────┐       ┌──────────────┐    ┌────────┐           │   │
│  │  │Mip0│──────►│  Streaming   │───►│        │           │   │
│  │  │Mip1│       │     Pool     │    │ Visible│           │   │
│  │  │Mip2│       │              │    │ Mips   │           │   │
│  │  │... │       └──────────────┘    └────────┘           │   │
│  │  └────┘                                                 │   │
│  │                                                          │   │
│  │  거리 기반 밉 레벨 결정:                                 │   │
│  │  가까움 → Mip 0 (최고 해상도)                           │   │
│  │  멀어짐 → Mip 1, 2, 3... (낮은 해상도)                  │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  스트리밍 풀 설정:                                              │
│  r.Streaming.PoolSize = 1000 (MB)                               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 스트리밍 설정

```cpp
// 프로젝트 설정
// Project Settings → Engine → Streaming → Texture Streaming

// 콘솔 변수
r.Streaming.PoolSize = 1000      // 스트리밍 풀 크기 (MB)
r.Streaming.MaxTempMemoryAllowed = 50  // 임시 메모리 제한
r.Streaming.FullyLoadUsedTextures = 0  // 사용 텍스처 전체 로드 비활성화
r.Streaming.HLODStrategy = 2     // HLOD 스트리밍 전략

// 개별 텍스처 설정
void ConfigureTextureStreaming(UTexture2D* Texture)
{
    // 스트리밍 비활성화 (항상 최고 해상도)
    Texture->NeverStream = true;  // UI, 중요 텍스처

    // 또는 LOD 바이어스 설정
    Texture->LODBias = 0;  // 기본
    Texture->LODBias = 1;  // 한 단계 낮은 밉 사용

    // LOD 그룹 설정
    Texture->LODGroup = TEXTUREGROUP_World;        // 월드 텍스처
    Texture->LODGroup = TEXTUREGROUP_Character;    // 캐릭터
    Texture->LODGroup = TEXTUREGROUP_UI;           // UI (스트리밍 안 함)
}

// 텍스처 스트리밍 통계
// stat streaming
// stat streamingdetails
```

### 스트리밍 우선순위

```cpp
// 특정 위치 주변 텍스처 우선 로드
void PrioritizeTextureStreaming(FVector Location, float Radius)
{
    // 스트리밍 매니저에 포커스 위치 추가
    if (IStreamingManager* StreamingManager =
        IStreamingManager::Get().IsRenderAssetStreamingManager() ?
        &IStreamingManager::Get().GetRenderAssetStreamingManager() : nullptr)
    {
        // 뷰 정보 추가
        StreamingManager->AddViewInfoToArray(
            ViewInfos,
            Location,
            1.0f,           // Screen size
            1.0f,           // FOV
            1.0f,           // Boost factor
            true,           // Want mips
            120.0f,         // Duration
            nullptr         // Player
        );
    }
}

// 강제 로드
void ForceStreamTextures(AActor* Actor)
{
    TArray<UTexture*> Textures;

    // Actor의 모든 텍스처 수집
    TArray<UActorComponent*> Components;
    Actor->GetComponents(Components);

    for (UActorComponent* Component : Components)
    {
        if (UPrimitiveComponent* Prim = Cast<UPrimitiveComponent>(Component))
        {
            TArray<UMaterialInterface*> Materials;
            Prim->GetUsedMaterials(Materials);

            for (UMaterialInterface* Material : Materials)
            {
                TArray<UTexture*> UsedTextures;
                Material->GetUsedTextures(UsedTextures, EMaterialQualityLevel::Num,
                    true, ERHIFeatureLevel::Num, true);
                Textures.Append(UsedTextures);
            }
        }
    }

    // 스트리밍 요청
    for (UTexture* Texture : Textures)
    {
        if (UTexture2D* Tex2D = Cast<UTexture2D>(Texture))
        {
            Tex2D->SetForceMipLevelsToBeResident(30.0f);  // 30초간 유지
        }
    }
}
```

---

## 레벨 스트리밍

```
┌─────────────────────────────────────────────────────────────────┐
│                    Level Streaming                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  World Composition / World Partition:                           │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │    ┌───┬───┬───┬───┐                                    │   │
│  │    │ A │ B │ C │ D │  ◄── 그리드 셀                     │   │
│  │    ├───┼───┼───┼───┤                                    │   │
│  │    │ E │ F │ G │ H │                                    │   │
│  │    ├───┼───┼───┼───┤                                    │   │
│  │    │ I │ J │ K │ L │                                    │   │
│  │    └───┴───┴───┴───┘                                    │   │
│  │                                                          │   │
│  │    ◎ Player                                              │   │
│  │    └── 주변 셀만 로드 (F, G, J, K)                       │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  스트리밍 방식:                                                 │
│  • Blueprint: 수동 Load/Unload                                  │
│  • Volume: 트리거 볼륨 기반                                     │
│  • Distance: 거리 기반 자동                                     │
│  • Always Loaded: 항상 로드 (Persistent)                        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 레벨 스트리밍 구현

```cpp
// 레벨 스트리밍 볼륨 사용
// 레벨에 Level Streaming Volume 배치
// Details → Streaming Levels에 로드할 레벨 지정

// 코드에서 레벨 로드
void StreamInLevel(FName LevelName)
{
    FLatentActionInfo LatentInfo;
    LatentInfo.CallbackTarget = this;
    LatentInfo.ExecutionFunction = TEXT("OnLevelLoaded");
    LatentInfo.Linkage = 0;
    LatentInfo.UUID = GetUniqueID();

    UGameplayStatics::LoadStreamLevel(
        this,
        LevelName,
        true,       // Make visible after load
        false,      // Should block
        LatentInfo
    );
}

void StreamOutLevel(FName LevelName)
{
    FLatentActionInfo LatentInfo;
    LatentInfo.CallbackTarget = this;
    LatentInfo.ExecutionFunction = TEXT("OnLevelUnloaded");
    LatentInfo.Linkage = 0;
    LatentInfo.UUID = GetUniqueID();

    UGameplayStatics::UnloadStreamLevel(
        this,
        LevelName,
        LatentInfo,
        false      // Should block
    );
}

// 레벨 로드 상태 확인
bool IsLevelLoaded(FName LevelName)
{
    ULevelStreaming* Level = UGameplayStatics::GetStreamingLevel(this, LevelName);
    return Level && Level->IsLevelLoaded();
}
```

### World Partition

```cpp
// UE5 World Partition 설정
// World Settings → World Partition → Enable World Partition

// 스트리밍 소스 설정
UCLASS()
class AStreamingSourceActor : public AActor
{
    GENERATED_BODY()

public:
    AStreamingSourceActor()
    {
        // 스트리밍 소스 컴포넌트
        StreamingSource = CreateDefaultSubobject<UWorldPartitionStreamingSource>(
            TEXT("StreamingSource")
        );

        // 로딩 범위 설정
        StreamingSource->SetRadius(20000.0f);
        StreamingSource->Priority = EStreamingSourcePriority::Normal;
    }

private:
    UPROPERTY()
    UWorldPartitionStreamingSource* StreamingSource;
};

// 데이터 레이어
// Actor → Data Layers에서 레이어 할당
// 레이어 단위로 로드/언로드 제어
UDataLayerSubsystem* DataLayerSubsystem = GetWorld()->GetSubsystem<UDataLayerSubsystem>();
DataLayerSubsystem->SetDataLayerRuntimeState(DataLayerAsset, EDataLayerRuntimeState::Activated);
```

---

## 오브젝트 풀링

```
┌─────────────────────────────────────────────────────────────────┐
│                    Object Pooling                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  풀링 = 객체 재사용으로 할당/해제 오버헤드 제거                  │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  Without Pooling:                                        │   │
│  │  Spawn → Use → Destroy → Spawn → Use → Destroy → ...    │   │
│  │  (매번 메모리 할당/해제, GC 부하)                        │   │
│  │                                                          │   │
│  │  With Pooling:                                           │   │
│  │  ┌──────────────────────────────────────┐               │   │
│  │  │  Object Pool                          │               │   │
│  │  │  ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐      │               │   │
│  │  │  │ ○ │ │ ○ │ │ ● │ │ ○ │ │ ○ │      │               │   │
│  │  │  └───┘ └───┘ └───┘ └───┘ └───┘      │               │   │
│  │  │  ○=사용가능  ●=사용중               │               │   │
│  │  └──────────────────────────────────────┘               │   │
│  │  Get → Use → Return → Get → Use → Return → ...          │   │
│  │  (재사용, GC 최소화)                                     │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 액터 풀 구현

```cpp
// 간단한 액터 풀
UCLASS()
class AActorPool : public AActor
{
    GENERATED_BODY()

public:
    // 풀 초기화
    void InitializePool(TSubclassOf<AActor> ActorClass, int32 PoolSize)
    {
        for (int32 i = 0; i < PoolSize; ++i)
        {
            AActor* Actor = GetWorld()->SpawnActor<AActor>(ActorClass);
            Actor->SetActorHiddenInGame(true);
            Actor->SetActorEnableCollision(false);
            Actor->SetActorTickEnabled(false);

            Pool.Add(Actor);
            AvailableActors.Add(Actor);
        }
    }

    // 풀에서 액터 가져오기
    AActor* GetPooledActor()
    {
        if (AvailableActors.Num() > 0)
        {
            AActor* Actor = AvailableActors.Pop();
            ActiveActors.Add(Actor);

            // 활성화
            Actor->SetActorHiddenInGame(false);
            Actor->SetActorEnableCollision(true);
            Actor->SetActorTickEnabled(true);

            return Actor;
        }

        // 풀 비어있음 - 필요시 확장
        UE_LOG(LogTemp, Warning, TEXT("Pool exhausted!"));
        return nullptr;
    }

    // 풀로 액터 반환
    void ReturnToPool(AActor* Actor)
    {
        if (ActiveActors.Remove(Actor))
        {
            // 비활성화
            Actor->SetActorHiddenInGame(true);
            Actor->SetActorEnableCollision(false);
            Actor->SetActorTickEnabled(false);

            // 상태 초기화
            if (IPoolable* Poolable = Cast<IPoolable>(Actor))
            {
                Poolable->OnReturnToPool();
            }

            AvailableActors.Add(Actor);
        }
    }

private:
    UPROPERTY()
    TArray<AActor*> Pool;

    UPROPERTY()
    TArray<AActor*> AvailableActors;

    UPROPERTY()
    TArray<AActor*> ActiveActors;
};

// 풀링 가능 인터페이스
UINTERFACE()
class UPoolable : public UInterface
{
    GENERATED_BODY()
};

class IPoolable
{
    GENERATED_BODY()

public:
    virtual void OnGetFromPool() = 0;
    virtual void OnReturnToPool() = 0;
};
```

---

## Garbage Collection 최적화

```
┌─────────────────────────────────────────────────────────────────┐
│                GC Optimization                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  GC = 참조되지 않는 UObject 자동 수집 및 해제                    │
│                                                                 │
│  GC 히치 원인:                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • 대량의 UObject 생성/삭제                               │   │
│  │ • 많은 오브젝트 참조 스캔                                │   │
│  │ • 클러스터 해제                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  최적화 전략:                                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • 오브젝트 풀링 사용                                     │   │
│  │ • Incremental GC 활성화                                  │   │
│  │ • GC 클러스터 활용                                       │   │
│  │ • Soft/Weak 레퍼런스 사용                                │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### GC 설정

```cpp
// GC 콘솔 변수
gc.TimeBetweenPurgingPendingKillObjects = 60.0  // GC 간격 (초)
gc.MaxObjectsNotConsideredByGC = 1000000        // GC 제외 오브젝트 수
gc.NumRetriesBeforeForcingGC = 10               // 강제 GC 전 재시도 횟수

// Incremental GC (점진적 GC)
gc.IncrementalBeginDestroyEnabled = 1
gc.CreateGCClusters = 1                          // GC 클러스터 사용

// 수동 GC 트리거 (권장하지 않음, 특수 상황에서만)
void ForceGarbageCollection()
{
    // 전체 GC
    GEngine->ForceGarbageCollection(true);

    // 또는 비동기 GC
    GEngine->ForceGarbageCollection(false);
}

// Soft Object Reference (로드 지연)
UPROPERTY()
TSoftObjectPtr<UTexture2D> SoftTexture;

// 필요할 때 로드
UTexture2D* Texture = SoftTexture.LoadSynchronous();

// Weak Object Reference (소유권 없음)
TWeakObjectPtr<AActor> WeakActor;
if (WeakActor.IsValid())
{
    // 사용
}
```

---

## 주요 클래스 요약

| 클래스/설정 | 역할 |
|-------------|------|
| `IStreamingManager` | 텍스처 스트리밍 관리 |
| `ULevelStreaming` | 레벨 스트리밍 |
| `UWorldPartitionStreamingSource` | World Partition 스트리밍 |
| `UDataLayerSubsystem` | 데이터 레이어 관리 |
| `TSoftObjectPtr` | 소프트 레퍼런스 |
| `TWeakObjectPtr` | 위크 레퍼런스 |

---

## 참고 자료

- [Memory Management](https://docs.unrealengine.com/memory-management/)
- [Texture Streaming](https://docs.unrealengine.com/texture-streaming/)
- [Level Streaming](https://docs.unrealengine.com/level-streaming/)
- [World Partition](https://docs.unrealengine.com/world-partition/)
