# CPU 최적화

렌더링 관점에서의 CPU 최적화 기법을 다룹니다. Draw Call 감소, 컬링, 배칭, 스레딩 최적화를 포함합니다.

---

## 개요

CPU 병목은 주로 Draw Call 제출, 오브젝트 처리, 게임 로직에서 발생합니다.

```
┌─────────────────────────────────────────────────────────────────┐
│                     CPU 렌더링 워크로드                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Game Thread                    Render Thread                   │
│  ┌─────────────┐               ┌─────────────┐                 │
│  │ Tick        │               │ Visibility  │                 │
│  │ Physics     │ ────────────▶ │ Setup       │                 │
│  │ Animation   │               │ Culling     │                 │
│  │ AI          │               │ Sorting     │                 │
│  └─────────────┘               │ Batching    │                 │
│                                │ Submission  │                 │
│                                └──────┬──────┘                 │
│                                       │                         │
│                                       ▼                         │
│                                ┌─────────────┐                 │
│                                │ RHI Thread  │                 │
│                                │ API Calls   │                 │
│                                │ State Mgmt  │                 │
│                                └─────────────┘                 │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│                      주요 병목 포인트                            │
│                                                                 │
│  1. Draw Call 과다 (> 2000-3000)                               │
│  2. Visibility 계산 오버헤드                                    │
│  3. 동적 오브젝트 업데이트                                      │
│  4. RHI 상태 변경 비용                                          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Draw Call 최적화

### Draw Call 비용 이해

```
┌─────────────────────────────────────────────────────────────────┐
│                      Draw Call 비용 구조                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Draw Call당 비용:                                              │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                                                           │  │
│  │  검증/준비:     ~2-5 µs                                   │  │
│  │  상태 설정:     ~5-20 µs (PSO 변경 시)                     │  │
│  │  드라이버:      ~10-50 µs                                  │  │
│  │  ─────────────────────────────                            │  │
│  │  총합:          ~20-75 µs per Draw Call                   │  │
│  │                                                           │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
│  프레임 예산 (16.67ms at 60fps):                               │
│  - 최대 Draw Call: ~10,000 (이론상)                            │
│  - 권장 Draw Call: 2,000-3,000 (다른 작업 고려)                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Draw Call 분석

```cpp
// Draw Call 통계 확인
stat scenerendering

// 출력 분석
// Mesh draw calls: 2847
//   - Visible meshes: 1523
//   - Instanced: 890
//   - Dynamic: 434

// 상세 분석
stat initviews
stat lighting
```

### Instancing 활용

```cpp
// 블루프린트에서 Instanced Static Mesh 사용
UPROPERTY()
UInstancedStaticMeshComponent* InstancedMesh;

// 인스턴스 추가
FTransform InstanceTransform;
InstancedMesh->AddInstance(InstanceTransform);

// 대량 추가 시 배치 처리
TArray<FTransform> Transforms;
// ... transforms 채우기
InstancedMesh->AddInstances(Transforms, false);
InstancedMesh->MarkRenderStateDirty();
```

### Hierarchical Instanced Static Mesh (HISM)

```cpp
// HISM: LOD + 컬링 지원 인스턴싱
UPROPERTY()
UHierarchicalInstancedStaticMeshComponent* HISM;

// 설정
HISM->bDisableCollision = true;  // 콜리전 비활성화로 성능 향상
HISM->NumCustomDataFloats = 4;   // 인스턴스별 커스텀 데이터

// 폴리지 시스템이 내부적으로 HISM 사용
```

```
┌─────────────────────────────────────────────────────────────────┐
│                    인스턴싱 비교                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Static Mesh (개별):                                            │
│  ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐                                │
│  │ 1 │ │ 2 │ │ 3 │ │ 4 │ │ 5 │  = 5 Draw Calls                │
│  └───┘ └───┘ └───┘ └───┘ └───┘                                │
│                                                                 │
│  Instanced Static Mesh:                                         │
│  ┌─────────────────────────────┐                               │
│  │ 1 │ 2 │ 3 │ 4 │ 5          │  = 1 Draw Call                 │
│  └─────────────────────────────┘                               │
│                                                                 │
│  HISM (LOD 지원):                                               │
│  ┌───────────────────┐ ┌───────┐                               │
│  │ Near (LOD0)       │ │ Far   │  = 2 Draw Calls               │
│  │ 1 │ 2 │ 3         │ │ 4 │ 5 │    (LOD별 배칭)               │
│  └───────────────────┘ └───────┘                               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Mesh Merging

```cpp
// 에디터에서 메시 병합
// Actor > Merge Actors > Merge Meshes

// 런타임 메시 병합 (Proxy Geometry)
UMeshMergeLibrary::MergeStaticMeshComponents(
    SourceComponents,
    World,
    MergeSettings,
    OutMergedMesh
);

// HLOD (Hierarchical LOD)
// World Settings > LOD > Enable HLOD
```

---

## 컬링 시스템

### Frustum Culling

```cpp
// 뷰 프러스텀 컬링 (자동)
// 카메라 시야 밖 오브젝트 제외

// 커스텀 바운드 설정으로 최적화
UPROPERTY()
UBoxComponent* CustomBounds;

StaticMeshComponent->SetCullDistance(5000.0f);
```

```
┌─────────────────────────────────────────────────────────────────┐
│                     Frustum Culling                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│                          Near Plane                             │
│                         ┌─────────┐                             │
│                        /           \                            │
│                       /             \                           │
│                      /    Visible    \                          │
│          [Camera]   /     Objects     \                         │
│              ◉────▶ ─────────────────── Far Plane              │
│                      \               /                          │
│                       \             /                           │
│          [Culled] ✕    \           /    [Culled] ✕             │
│                         └─────────┘                             │
│                                                                 │
│  Frustum 밖의 오브젝트는 렌더링에서 제외                        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Occlusion Culling

```cpp
// 하드웨어 오클루전 쿼리 설정
r.HZBOcclusion 1          // HZB 기반 오클루전
r.AllowOcclusionQueries 1  // 오클루전 쿼리 활성화

// 오브젝트 설정
StaticMeshComponent->bUseAsOccluder = true;  // 가리는 역할
StaticMeshComponent->bAffectDistanceFieldLighting = true;
```

```
┌─────────────────────────────────────────────────────────────────┐
│                    Occlusion Culling                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Without Occlusion:                                             │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │     [Wall]              [Hidden Object]                 │    │
│  │        ██████████████                                   │    │
│  │   ◉ ──▶██████████████──▶ ○○○○  (Rendered!)            │    │
│  │        ██████████████                                   │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                 │
│  With Occlusion:                                                │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │     [Wall]              [Hidden Object]                 │    │
│  │        ██████████████                                   │    │
│  │   ◉ ──▶██████████████   ✕✕✕✕  (Culled!)               │    │
│  │        ██████████████                                   │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Distance Culling

```cpp
// 거리 기반 컬링
StaticMeshComponent->LDMaxDrawDistance = 5000.0f;
StaticMeshComponent->CachedMaxDrawDistance = 5000.0f;

// Cull Distance Volumes
// 특정 영역에서 컬링 거리 조정
UCullDistanceVolume* CullVolume;
CullVolume->CullDistances.Add(FCullDistanceSizePair(100.0f, 1000.0f));
CullVolume->CullDistances.Add(FCullDistanceSizePair(500.0f, 5000.0f));
```

### Precomputed Visibility

```cpp
// 사전 계산 가시성 (실내 환경에 효과적)
// World Settings > Precompute Visibility

// Visibility Cells 배치
// Place Actor > Precomputed Visibility Volume

// 빌드
// Build > Build Lighting Only (Visibility도 함께 빌드)
```

---

## 배칭 최적화

### Static Batching

```cpp
// 정적 배칭 (빌드 타임)
// Mesh Settings > Use Static Batching

// 조건:
// - 동일한 머티리얼
// - 정적 오브젝트
// - Mobility: Static
```

### Dynamic Batching

```cpp
// 동적 배칭 설정
r.DynamicBatching 1

// 제한사항:
// - 작은 메시만 (< 900 버텍스)
// - 동일 머티리얼
// - 오버헤드 있음
```

### 머티리얼 배칭

```
┌─────────────────────────────────────────────────────────────────┐
│                    머티리얼 배칭 전략                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Before (머티리얼 분산):                                        │
│  ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐                          │
│  │ A │ │ B │ │ A │ │ C │ │ B │ │ A │  = 6 Draw Calls           │
│  └───┘ └───┘ └───┘ └───┘ └───┘ └───┘                          │
│                                                                 │
│  After (머티리얼 정렬):                                         │
│  ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐                          │
│  │ A │ │ A │ │ A │ │ B │ │ B │ │ C │  = 3 State Changes        │
│  └───┘ └───┘ └───┘ └───┘ └───┘ └───┘                          │
│                                                                 │
│  머티리얼 아틀라스:                                             │
│  ┌─────────────────────────────────────┐                       │
│  │ Combined Material (A+B+C)           │  = 1 Draw Call        │
│  │ ┌───┬───┬───┬───┬───┬───┐          │    (UV 조정 필요)      │
│  │ │   │   │   │   │   │   │          │                        │
│  │ └───┴───┴───┴───┴───┴───┘          │                        │
│  └─────────────────────────────────────┘                       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 텍스처 아틀라스

```cpp
// 텍스처 아틀라스로 머티리얼 통합
// 여러 텍스처를 하나로 합쳐 배칭 가능하게 함

// UV 스케일/오프셋으로 서브 텍스처 접근
float2 AtlasUV = UV * TileScale + TileOffset;
```

---

## 스레딩 최적화

### 병렬 렌더링

```cpp
// 렌더 스레드 병렬화 설정
r.RHICmdBypass 0         // RHI 커맨드 리스트 사용
r.RHIThread.Enable 1     // RHI 스레드 활성화

// 병렬 렌더링 통계
stat threading
```

```
┌─────────────────────────────────────────────────────────────────┐
│                    UE 스레딩 모델                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Frame N              Frame N+1            Frame N+2            │
│  ┌─────────┐         ┌─────────┐          ┌─────────┐          │
│  │ Game    │────────▶│ Game    │─────────▶│ Game    │          │
│  └─────────┘         └─────────┘          └─────────┘          │
│       │                   │                    │                │
│       ▼                   ▼                    ▼                │
│  ┌─────────┐         ┌─────────┐          ┌─────────┐          │
│  │ Render  │────────▶│ Render  │─────────▶│ Render  │          │
│  └─────────┘         └─────────┘          └─────────┘          │
│       │                   │                    │                │
│       ▼                   ▼                    ▼                │
│  ┌─────────┐         ┌─────────┐          ┌─────────┐          │
│  │ RHI     │────────▶│ RHI     │─────────▶│ RHI     │          │
│  └─────────┘         └─────────┘          └─────────┘          │
│       │                   │                    │                │
│       ▼                   ▼                    ▼                │
│  ┌─────────┐         ┌─────────┐          ┌─────────┐          │
│  │ GPU     │────────▶│ GPU     │─────────▶│ GPU     │          │
│  └─────────┘         └─────────┘          └─────────┘          │
│                                                                 │
│  → 파이프라이닝으로 스레드간 병렬 실행                          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Parallel For

```cpp
// 병렬 처리 활용
ParallelFor(Objects.Num(), [&](int32 Index)
{
    ProcessObject(Objects[Index]);
});

// 작업 분배 설정
ParallelFor(Objects.Num(), [&](int32 Index)
{
    ProcessObject(Objects[Index]);
}, EParallelForFlags::Unbalanced);
```

### Task Graph 활용

```cpp
// 렌더링 관련 태스크 생성
FGraphEventRef Task = FFunctionGraphTask::CreateAndDispatchWhenReady(
    [this]()
    {
        // 병렬 작업
        CalculateVisibility();
    },
    TStatId(),
    nullptr,
    ENamedThreads::AnyBackgroundThreadNormalTask
);

// 대기
FTaskGraphInterface::Get().WaitUntilTaskCompletes(Task);
```

---

## 동적 오브젝트 최적화

### 업데이트 빈도 제어

```cpp
// Tick 최적화
PrimaryComponentTick.TickInterval = 0.1f;  // 10fps로 틱
SetActorTickEnabled(false);  // 틱 비활성화

// 조건부 틱
void AThing::Tick(float DeltaTime)
{
    if (!IsVisibleToCamera())
    {
        return;  // 안 보이면 틱 스킵
    }
    // ...
}
```

### 트랜스폼 업데이트 최소화

```cpp
// 배치 트랜스폼 업데이트
TArray<FTransform> NewTransforms;
for (int32 i = 0; i < InstanceCount; ++i)
{
    NewTransforms.Add(CalculateTransform(i));
}
InstancedMesh->BatchUpdateInstancesTransforms(
    0, NewTransforms, true, true, true);

// 불필요한 업데이트 방지
if (NewLocation != CachedLocation)
{
    SetActorLocation(NewLocation);
    CachedLocation = NewLocation;
}
```

### 스켈레탈 메시 최적화

```cpp
// LOD 기반 업데이트 빈도
SkeletalMeshComponent->VisibilityBasedAnimTickOption =
    EVisibilityBasedAnimTickOption::OnlyTickPoseWhenRendered;

// 본 업데이트 최적화
SkeletalMeshComponent->bNoSkeletonUpdate = true;  // 필요시만 업데이트

// 애니메이션 캐싱
SkeletalMeshComponent->bEnableUpdateRateOptimizations = true;
SkeletalMeshComponent->AnimUpdateRateParams->bShouldUseRenderLOD = true;
```

---

## 메모리 캐시 최적화

### 데이터 지역성

```cpp
// 캐시 친화적 데이터 구조
// BAD: Array of Structs (AoS)
struct FParticle { FVector Pos; FVector Vel; float Life; };
TArray<FParticle> Particles;

// GOOD: Struct of Arrays (SoA) - 캐시 효율적
struct FParticleSystem
{
    TArray<FVector> Positions;
    TArray<FVector> Velocities;
    TArray<float> Lifetimes;
};
```

### 프리페칭

```cpp
// 데이터 프리페치
for (int32 i = 0; i < Count; i += 4)
{
    // 4개 앞의 데이터 프리페치
    FPlatformMisc::Prefetch(Data + i + 4);

    ProcessData(Data[i]);
    ProcessData(Data[i + 1]);
    ProcessData(Data[i + 2]);
    ProcessData(Data[i + 3]);
}
```

---

## 콘솔 명령 요약

```cpp
// Draw Call 분석
stat scenerendering
stat initviews

// 컬링 디버깅
r.VisualizeOccludedPrimitives 1
freezerendering  // 렌더링 고정 (컬링 확인용)

// 배칭 확인
stat d3d12rhi  // D3D12 Draw Call 통계

// 스레딩 분석
stat threading
stat taskgraph

// 최적화 테스트
r.StaticMeshLODDistanceScale 0.25  // LOD 거리 조정
r.SkeletalMeshLODBias 2             // 스켈레탈 LOD 강제
```

---

## 요약

| 기법 | 효과 | 적용 대상 |
|------|------|----------|
| Instancing | Draw Call 90%+ 감소 | 반복 오브젝트 |
| Mesh Merging | Draw Call 감소 | 정적 환경 |
| Occlusion Culling | 불필요한 렌더링 제거 | 실내/복잡한 씬 |
| Distance Culling | 먼 오브젝트 제외 | 오픈 월드 |
| Material Batching | 상태 변경 감소 | 다양한 머티리얼 |
| 스레딩 | CPU 활용률 증가 | 모든 프로젝트 |

---

## 참고 자료

- [UE Performance Guidelines](https://docs.unrealengine.com/performance-guidelines/)
- [Instanced Static Mesh](https://docs.unrealengine.com/instanced-static-mesh/)
- [Visibility and Occlusion Culling](https://docs.unrealengine.com/visibility-culling/)
