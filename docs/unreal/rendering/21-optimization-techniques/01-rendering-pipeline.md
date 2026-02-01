# 렌더링 파이프라인 최적화

드로우콜, 셰이더, 컬링 등 렌더링 파이프라인 최적화 기법을 분석합니다.

---

## 드로우콜 최적화

```
┌─────────────────────────────────────────────────────────────────┐
│                   Draw Call Optimization                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  드로우콜 = CPU가 GPU에게 렌더링 명령을 전달하는 단위            │
│                                                                 │
│  문제점:                                                        │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  CPU                              GPU                    │   │
│  │  ┌─────┐                         ┌─────┐                │   │
│  │  │Draw1│──────────────────────►  │     │                │   │
│  │  │Draw2│──────────────────────►  │Idle │ (대기)         │   │
│  │  │Draw3│──────────────────────►  │     │                │   │
│  │  │ ... │                         └─────┘                │   │
│  │  └─────┘                                                 │   │
│  │  CPU Bound: 드로우콜 오버헤드로 GPU가 대기               │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  해결책:                                                        │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         │
│  │ Instancing   │  │ Mesh Merge   │  │ Batching     │         │
│  │ 동일 메시    │  │ 정적 메시    │  │ 동적 배칭    │         │
│  │ 다중 렌더링  │  │ 병합         │  │ (UI, 스프라이트)│       │
│  └──────────────┘  └──────────────┘  └──────────────┘         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 인스턴싱

```cpp
// Instanced Static Mesh 사용
UCLASS()
class AInstancedFoliage : public AActor
{
    GENERATED_BODY()

public:
    AInstancedFoliage()
    {
        // Instanced Static Mesh Component
        InstancedMesh = CreateDefaultSubobject<UInstancedStaticMeshComponent>(
            TEXT("InstancedMesh")
        );
        InstancedMesh->SetupAttachment(RootComponent);

        // 인스턴싱 설정
        InstancedMesh->SetCollisionEnabled(ECollisionEnabled::QueryOnly);
        InstancedMesh->SetCastShadow(true);
    }

    void SpawnInstances(int32 Count)
    {
        for (int32 i = 0; i < Count; ++i)
        {
            FTransform InstanceTransform;
            InstanceTransform.SetLocation(GetRandomLocation());
            InstanceTransform.SetRotation(FQuat(FRotator(0, FMath::RandRange(0, 360), 0)));
            InstanceTransform.SetScale3D(FVector(FMath::RandRange(0.8f, 1.2f)));

            InstancedMesh->AddInstance(InstanceTransform);
        }
    }

private:
    UPROPERTY(VisibleAnywhere)
    UInstancedStaticMeshComponent* InstancedMesh;
};

// Hierarchical Instanced Static Mesh (HISM) - 컬링 지원
UPROPERTY()
UHierarchicalInstancedStaticMeshComponent* HISMComponent;
// 자동으로 LOD와 오클루전 컬링 적용
```

### 메시 병합

```cpp
// Actor Merging (에디터)
// Window → Developer Tools → Merge Actors

// 프로그래매틱 병합
void MergeStaticMeshActors(TArray<AActor*> ActorsToMerge)
{
    FMeshMergingSettings MergeSettings;
    MergeSettings.bMergePhysicsData = true;
    MergeSettings.bBakeVertexDataToMesh = true;
    MergeSettings.LODSelectionType = EMeshLODSelectionType::CalculateLOD;

    // 머티리얼 아틀라스 설정
    MergeSettings.bMergeMaterials = true;
    MergeSettings.MaterialSettings.TextureSize = FIntPoint(2048, 2048);

    TArray<UObject*> AssetsToSync;
    FVector MergedActorLocation;

    const IMeshMergeUtilities& MeshUtilities =
        FModuleManager::Get().LoadModuleChecked<IMeshMergeModule>("MeshMergeUtilities")
        .GetUtilities();

    MeshUtilities.MergeComponentsToStaticMesh(
        ComponentsToMerge,
        GetWorld(),
        MergeSettings,
        nullptr,
        GetTransientPackage(),
        TEXT("MergedMesh"),
        AssetsToSync,
        MergedActorLocation,
        1.0f,
        false
    );
}
```

---

## 셰이더 복잡도 관리

```
┌─────────────────────────────────────────────────────────────────┐
│                  Shader Complexity                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  셰이더 복잡도 시각화: ViewMode → Shader Complexity             │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  초록    노랑    주황    빨강    흰색                    │   │
│  │  ────────────────────────────────────────────►          │   │
│  │  낮음    보통    높음    매우높음 위험                   │   │
│  │                                                          │   │
│  │  Instruction Count:                                      │   │
│  │  <100    100-200  200-400  400-800  800+                │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  복잡도 증가 요인:                                              │
│  • 텍스처 샘플링 수                                             │
│  • 수학 연산 복잡도                                             │
│  • 동적 분기문                                                  │
│  • 레이어 블렌딩                                                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 셰이더 최적화 기법

```cpp
// 나쁜 예: 동적 분기
float3 Color;
if (MaterialType == 1)
{
    Color = Texture2DSample(Tex1, UV).rgb;
}
else if (MaterialType == 2)
{
    Color = Texture2DSample(Tex2, UV).rgb;
}
else
{
    Color = Texture2DSample(Tex3, UV).rgb;
}

// 좋은 예: 정적 스위치 또는 마스크
// Static Switch 사용 (컴파일 타임 분기)
// 또는 모든 텍스처 샘플링 후 lerp

float3 Color1 = Texture2DSample(Tex1, UV).rgb;
float3 Color2 = Texture2DSample(Tex2, UV).rgb;
float3 Color = lerp(Color1, Color2, Mask);

// 거리 기반 디테일 감소
float Distance = length(CameraPosition - WorldPosition);
float DetailFade = saturate((Distance - FadeStart) / (FadeEnd - FadeStart));

// 가까울 때만 디테일 샘플링
float3 DetailNormal = lerp(
    SampleDetailNormal(UV),
    float3(0, 0, 1),
    DetailFade
);
```

### 퀄리티 스위치

```
Material Editor에서 Quality Switch 노드 사용:
┌────────────────────────────────────────┐
│ Quality Switch                          │
├────────────────────────────────────────┤
│ High   → 풀 디테일 셰이더              │
│ Medium → 중간 복잡도                   │
│ Low    → 최소 복잡도                   │
│ Default → 기본 폴백                    │
└────────────────────────────────────────┘

Scalability 설정에 따라 자동 선택
```

---

## 오클루전 컬링

```
┌─────────────────────────────────────────────────────────────────┐
│                    Occlusion Culling                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  컬링 종류:                                                     │
│                                                                 │
│  1. Frustum Culling (뷰 프러스텀)                               │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │            ╱─────────────╲                              │   │
│  │     ◎────╱               ╲                              │   │
│  │   Camera ╲    View        ╱  ● 화면 밖 = 컬링           │   │
│  │           ╲   Frustum    ╱                              │   │
│  │            ╲─────────────╱                              │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  2. Distance Culling (거리)                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  ◎ ───────────────●──────────────────────────●          │   │
│  │  Camera    Visible        Max Distance = Culled        │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  3. Occlusion Culling (가림)                                    │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  ◎ ────────████──────────●                              │   │
│  │  Camera    Wall    Occluded Object = Culled             │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 컬링 설정

```cpp
// 거리 컬링 설정
UPROPERTY(EditAnywhere, Category = "Culling")
float MaxDrawDistance = 10000.0f;

// Actor에서 설정
void AMyActor::BeginPlay()
{
    Super::BeginPlay();

    // 컴포넌트별 거리 컬링
    if (UPrimitiveComponent* Prim = GetComponentByClass<UPrimitiveComponent>())
    {
        // LOD 거리와 연동
        Prim->SetCullDistance(MaxDrawDistance);

        // 또는 Detail Mode로 제어
        Prim->SetDetailMode(EDetailMode::High);
    }
}

// 프로젝트 설정에서 전역 컬링
// Project Settings → Engine → Rendering → Culling
// Min Screen Radius for Lights: 0.03
// Min Screen Radius for Cascaded Shadow Maps: 0.01
```

### Precomputed Visibility

```cpp
// Precomputed Visibility Volume 사용
// 에디터에서 볼륨 배치 후 빌드

// 프로젝트 설정
// Project Settings → Engine → Rendering → Culling
// Precomputed Visibility: Enabled

// 볼륨 설정
UCLASS()
class APrecomputedVisibilityVolume : public AVolume
{
    // 셀 크기 설정 (작을수록 정밀하지만 메모리 증가)
    // Cell Size: 200-400 units 권장
};

// 빌드
// Build → Precompute Static Visibility
```

---

## GPU 드리븐 렌더링

```
┌─────────────────────────────────────────────────────────────────┐
│                  GPU-Driven Rendering                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  전통적 렌더링:                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  CPU: Visibility → Sort → DrawCall → DrawCall → ...     │   │
│  │                                        │                 │   │
│  │  GPU: ────────────────────────────────Execute            │   │
│  │                                                          │   │
│  │  CPU가 모든 오브젝트를 순회하며 드로우콜 생성            │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  GPU 드리븐 렌더링 (Nanite):                                    │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  CPU: Submit All Data (한 번)                            │   │
│  │                    │                                     │   │
│  │  GPU: Visibility → Cull → Cluster → Rasterize           │   │
│  │       (컴퓨트 셰이더로 GPU에서 컬링)                     │   │
│  │                                                          │   │
│  │  GPU가 가시성 판단과 LOD 선택 수행                       │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Nanite 최적화

```cpp
// Nanite 활성화 조건
// Static Mesh → Nanite Settings → Enable Nanite

// 적합한 메시:
// - 고밀도 지오메트리 (10k+ 트라이앵글)
// - 정적 메시
// - Opaque 머티리얼

// 부적합한 메시:
// - 스켈레탈 메시
// - 머티리얼 애니메이션 (World Position Offset)
// - Masked/Translucent 머티리얼

// Fallback 설정
UPROPERTY(EditAnywhere, Category = "Nanite")
ENaniteFallbackTarget FallbackTarget = ENaniteFallbackTarget::Auto;

// Nanite 디버그
// r.Nanite.Visualize.Overview 1
// r.Nanite.Visualize.Triangles 1
// r.Nanite.Visualize.Clusters 1
```

---

## 오버드로 최적화

```
┌─────────────────────────────────────────────────────────────────┐
│                   Overdraw Optimization                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  오버드로 = 같은 픽셀을 여러 번 그리는 것                        │
│                                                                 │
│  시각화: ViewMode → Shader Complexity & Quads                   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │    ┌───────────────┐                                    │   │
│  │    │   Layer 1     │                                    │   │
│  │    │  ┌─────────┐  │                                    │   │
│  │    │  │ Layer 2 │  │  ◄── 2x 오버드로                   │   │
│  │    │  │  ┌───┐  │  │                                    │   │
│  │    │  │  │ 3 │  │  │  ◄── 3x 오버드로                   │   │
│  │    │  │  └───┘  │  │                                    │   │
│  │    │  └─────────┘  │                                    │   │
│  │    └───────────────┘                                    │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  최적화:                                                        │
│  • 투명 오브젝트 수 줄이기                                      │
│  • 파티클 크기/수 최적화                                        │
│  • 깊이 프리패스 활용                                           │
│  • Early-Z 활용 (앞에서 뒤로 렌더링)                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 깊이 프리패스

```cpp
// 프로젝트 설정
// Project Settings → Engine → Rendering → Optimizations
// Early Z-pass: Opaque and Masked Meshes

// 또는 콘솔 변수
r.EarlyZPass = 2  // 0: None, 1: Opaque Only, 2: Opaque and Masked

// 대형 Masked 메시에서 효과적
// 깊이만 먼저 그려서 이후 픽셀 셰이더 실행 최소화
```

---

## 배칭 전략

```
┌─────────────────────────────────────────────────────────────────┐
│                    Batching Strategies                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Static Batching:                                               │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  에디터에서 Static Mesh 병합                             │   │
│  │  + 런타임 오버헤드 없음                                  │   │
│  │  - 개별 컬링 불가                                        │   │
│  │  - 빌드 시간 증가                                        │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Dynamic Batching:                                              │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  런타임에 작은 메시 자동 병합                            │   │
│  │  + 자동 처리                                             │   │
│  │  - CPU 오버헤드 발생                                     │   │
│  │  - 조건 제한적 (버텍스 수, 동일 머티리얼)                │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  GPU Instancing:                                                │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  동일 메시를 단일 드로우콜로 다중 렌더링                 │   │
│  │  + 대량 오브젝트에 효과적                                │   │
│  │  + 개별 트랜스폼 가능                                    │   │
│  │  - 머티리얼 설정 필요                                    │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 주요 클래스 요약

| 클래스/설정 | 역할 |
|-------------|------|
| `UInstancedStaticMeshComponent` | GPU 인스턴싱 |
| `UHierarchicalInstancedStaticMeshComponent` | LOD 지원 인스턴싱 |
| `Merge Actors` | 정적 메시 병합 |
| `Precomputed Visibility Volume` | 사전 계산 가시성 |
| `Cull Distance Volume` | 거리 컬링 영역 |
| `r.EarlyZPass` | 깊이 프리패스 설정 |

---

## 참고 자료

- [Draw Call Optimization](https://docs.unrealengine.com/draw-call-optimization/)
- [GPU-Driven Rendering](https://docs.unrealengine.com/nanite/)
- [Visibility and Occlusion Culling](https://docs.unrealengine.com/visibility-culling/)
