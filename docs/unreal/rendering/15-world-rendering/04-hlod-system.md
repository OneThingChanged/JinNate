# HLOD 시스템

Hierarchical Level of Detail (HLOD)은 원거리 오브젝트들을 병합하여 렌더링 효율을 높입니다.

---

## 아키텍처 개요

```
┌─────────────────────────────────────────────────────────────────┐
│                     HLOD 시스템 아키텍처                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  근거리 (Source Meshes)              원거리 (HLOD Proxy)        │
│  ┌─────────────────────┐            ┌─────────────────────┐    │
│  │ ┌───┐ ┌───┐ ┌───┐  │            │ ┌─────────────────┐ │    │
│  │ │ A │ │ B │ │ C │  │            │ │                 │ │    │
│  │ └───┘ └───┘ └───┘  │            │ │   Merged Mesh   │ │    │
│  │ ┌───┐ ┌───┐ ┌───┐  │   ──────▶  │ │    (A+B+C+      │ │    │
│  │ │ D │ │ E │ │ F │  │   Distance │ │     D+E+F)      │ │    │
│  │ └───┘ └───┘ └───┘  │            │ │                 │ │    │
│  │                     │            │ └─────────────────┘ │    │
│  │ 개별 Draw Calls     │            │ 단일 Draw Call      │    │
│  │ (6 calls)           │            │ (1 call)            │    │
│  └─────────────────────┘            └─────────────────────┘    │
│                                                                 │
│  HLOD 레벨:                                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  Camera    HLOD 0      HLOD 1         HLOD 2            │   │
│  │    │◀─────────▶│◀────────────▶│◀──────────────────▶│    │   │
│  │    │  Source   │  1차 병합     │    2차 병합         │    │   │
│  │    │  Meshes   │  (클러스터)   │    (대규모)         │    │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## HLOD 생성

### 빌드 프로세스

```cpp
// HLOD 빌드 설정
class UHierarchicalLODSettings : public UObject
{
    // HLOD 레벨 설정
    TArray<FHierarchicalSimplification> HierarchicalLODSetup;

    // 클러스터링 설정
    float ClusterRadius;
    float MinClusterSize;

    // 병합 설정
    bool bMergeActorMaterials;
    bool bBakeMaterials;
    int32 BakedMaterialMaxWidth;
    int32 BakedMaterialMaxHeight;
};

// HLOD 레벨 설정
struct FHierarchicalSimplification
{
    // 전환 거리
    float TransitionScreenSize;

    // 단순화 방법
    EHierarchicalSimplificationMethod SimplificationMethod;
    // Merge    - 메시 병합
    // Simplify - 단순화 후 병합
    // Proxy    - 프록시 메시 생성
    // Approximate - 근사 지오메트리

    // 프록시 설정
    FMeshProxySettings ProxySettings;

    // 병합 설정
    FMeshMergingSettings MergeSettings;
};
```

### 빌드 파이프라인

```
┌─────────────────────────────────────────────────────────────────┐
│                    HLOD 빌드 파이프라인                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. 클러스터링                                                   │
│     ┌─────────────────────────────────────────────────────┐    │
│     │                 Source Actors                        │    │
│     │  ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐           │    │
│     │  │A│ │B│ │C│ │D│ │E│ │F│ │G│ │H│ │I│ │J│           │    │
│     │  └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘           │    │
│     └────────────────────────┬────────────────────────────┘    │
│                              │ Spatial Clustering              │
│                              ▼                                  │
│  2. 그룹화                                                      │
│     ┌─────────────────────────────────────────────────────┐    │
│     │  ┌──────────────┐  ┌──────────────┐  ┌────────────┐│    │
│     │  │Cluster 1     │  │Cluster 2     │  │Cluster 3   ││    │
│     │  │ A, B, C, D   │  │ E, F, G      │  │ H, I, J    ││    │
│     │  └──────────────┘  └──────────────┘  └────────────┘│    │
│     └────────────────────────┬────────────────────────────┘    │
│                              │ Mesh Processing                 │
│                              ▼                                  │
│  3. 프록시 생성                                                  │
│     ┌─────────────────────────────────────────────────────┐    │
│     │  ┌──────────────┐  ┌──────────────┐  ┌────────────┐│    │
│     │  │Proxy Mesh 1  │  │Proxy Mesh 2  │  │Proxy Mesh 3││    │
│     │  │ • 병합 메시   │  │ • 병합 메시   │  │ • 병합 메시 ││    │
│     │  │ • 베이크 텍스처│  │ • 베이크 텍스처│  │ • 베이크    ││    │
│     │  └──────────────┘  └──────────────┘  └────────────┘│    │
│     └─────────────────────────────────────────────────────┘    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 프록시 메시 생성

### Mesh Proxy

```cpp
// 프록시 메시 설정
struct FMeshProxySettings
{
    // 스크린 사이즈 (디테일 수준)
    float ScreenSize;

    // Voxel 크기 (해상도)
    float VoxelSize;

    // 머티리얼 병합
    bool bMergeIdenticalMaterials;

    // 텍스처 베이킹
    bool bBakeTextures;
    int32 TextureWidth;
    int32 TextureHeight;

    // Normal Map 베이킹
    bool bBakeNormalMap;

    // 라이트맵
    int32 LightMapResolution;
};

// 프록시 생성 알고리즘
void GenerateProxyMesh(
    const TArray<UStaticMeshComponent*>& SourceMeshes,
    FMeshProxySettings& Settings,
    UStaticMesh*& OutProxyMesh)
{
    // 1. 메시 결합
    FMeshDescription CombinedMesh;
    CombineMeshes(SourceMeshes, CombinedMesh);

    // 2. 단순화 (선택적)
    if (Settings.ScreenSize < 1.0f)
    {
        SimplifyMesh(CombinedMesh, Settings.ScreenSize);
    }

    // 3. 텍스처 베이킹
    if (Settings.bBakeTextures)
    {
        BakeTextures(SourceMeshes, CombinedMesh,
                     Settings.TextureWidth, Settings.TextureHeight);
    }

    // 4. 결과 메시 생성
    OutProxyMesh = CreateStaticMesh(CombinedMesh);
}
```

### Imposter (빌보드)

```
┌─────────────────────────────────────────────────────────────────┐
│                    Imposter 시스템                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  3D 메시                         Imposter (2D 빌보드)           │
│  ┌─────────────────┐            ┌─────────────────────┐        │
│  │     ╱╲          │            │                     │        │
│  │    ╱  ╲         │   ──────▶  │    ┌───────────┐   │        │
│  │   ╱    ╲        │  원거리    │    │   Tree    │   │        │
│  │  ╱──────╲       │            │    │   Image   │   │        │
│  │  │      │       │            │    └───────────┘   │        │
│  │  └──────┘       │            │                     │        │
│  │                 │            │  • 카메라 방향 회전  │        │
│  │ 수천 폴리곤     │            │  • 수 개 폴리곤     │        │
│  └─────────────────┘            └─────────────────────┘        │
│                                                                 │
│  Octahedral Imposter:                                           │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  ┌────┬────┬────┬────┬────┬────┬────┬────┐              │   │
│  │  │    │    │    │    │    │    │    │    │              │   │
│  │  │ 00 │ 01 │ 02 │ 03 │ 04 │ 05 │ 06 │ 07 │  Frames     │   │
│  │  │    │    │    │    │    │    │    │    │              │   │
│  │  ├────┼────┼────┼────┼────┼────┼────┼────┤              │   │
│  │  │    │    │    │    │    │    │    │    │              │   │
│  │  │ 08 │ 09 │ 10 │ 11 │ 12 │ 13 │ 14 │ 15 │  ...        │   │
│  │  │    │    │    │    │    │    │    │    │              │   │
│  │  └────┴────┴────┴────┴────┴────┴────┴────┘              │   │
│  │                                                          │   │
│  │  • 각도별 캡처된 이미지                                   │   │
│  │  • 실시간 뷰 방향 보간                                    │   │
│  │  • 노말/깊이 정보 포함 가능                               │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## HLOD Actor

### ALODActor 구조

```cpp
// HLOD 액터
class ALODActor : public AActor
{
    // 프록시 메시 컴포넌트
    UStaticMeshComponent* StaticMeshComponent;

    // 대체되는 원본 액터들
    TArray<TWeakObjectPtr<AActor>> SubActors;

    // HLOD 레벨
    int32 LODLevel;

    // 전환 거리
    float TransitionScreenSize;

    // 스트리밍 설정
    bool bRequiresLevelUnload;

    // 가시성 결정
    bool ShouldShowLODActor(const FSceneView* View)
    {
        float ScreenSize = ComputeBoundsScreenSize(
            Bounds.Origin,
            Bounds.SphereRadius,
            View);

        return ScreenSize < TransitionScreenSize;
    }
};
```

### HLOD 가시성 전환

```
┌─────────────────────────────────────────────────────────────────┐
│                   HLOD 가시성 전환 로직                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Screen Size 기반 전환:                                          │
│                                                                 │
│  1.0 ┤                                                          │
│      │  ████████████████████████                                │
│  0.8 ┤  █ Source Actors Visible █                               │
│      │  ████████████████████████                                │
│  0.6 ┤           │                                              │
│      │           ▼                                              │
│  0.4 ┤  ┌───────────────────────                                │
│      │  │ Transition Zone       │                               │
│  0.2 ┤  └───────────────────────                                │
│      │           │              ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓            │
│  0.0 ┤           ▼              ▓ HLOD Actor Visible ▓          │
│      └──────────────────────────────────────────────────────    │
│       Near                                              Far     │
│                                                                 │
│  Dithering 전환:                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  Distance:  ════════════════════════════════════════▶   │   │
│  │                                                          │   │
│  │  Source:   100% ▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░  0%                │   │
│  │  HLOD:      0%  ░░░░░░░░░░░▓▓▓▓▓▓▓▓▓ 100%               │   │
│  │                     └──┘                                 │   │
│  │                  Blend Zone                              │   │
│  │                (Dithering)                               │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## World Partition HLOD

### UE5 HLOD 시스템

```
┌─────────────────────────────────────────────────────────────────┐
│                World Partition HLOD (UE5)                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                   World Partition Grid                   │   │
│  │  ┌────┬────┬────┬────┬────┬────┬────┬────┐              │   │
│  │  │ C0 │ C1 │ C2 │ C3 │ C4 │ C5 │ C6 │ C7 │  Cells      │   │
│  │  ├────┼────┼────┼────┼────┼────┼────┼────┤              │   │
│  │  │ C8 │ C9 │C10 │C11 │C12 │C13 │C14 │C15 │              │   │
│  │  └────┴────┴────┴────┴────┴────┴────┴────┘              │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│              ┌───────────────┼───────────────┐                 │
│              ▼               ▼               ▼                 │
│  ┌────────────────┐ ┌────────────────┐ ┌────────────────┐      │
│  │  HLOD Layer 0  │ │  HLOD Layer 1  │ │  HLOD Layer 2  │      │
│  │                │ │                │ │                │      │
│  │ 4 Cells → 1    │ │ 16 Cells → 1   │ │ 64 Cells → 1   │      │
│  │ HLOD Actor     │ │ HLOD Actor     │ │ HLOD Actor     │      │
│  └────────────────┘ └────────────────┘ └────────────────┘      │
│                                                                 │
│  특징:                                                          │
│  • 셀 기반 자동 HLOD 생성                                       │
│  • 다중 레이어 지원                                             │
│  • 스트리밍 통합                                                │
│  • Nanite HLOD 지원                                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### HLOD Layer 설정

```cpp
// HLOD Layer 에셋
class UHLODLayer : public UObject
{
    // 레이어 타입
    EHLODLayerType LayerType;
    // Instancing   - 인스턴싱만 (지오메트리 유지)
    // MeshMerge    - 메시 병합
    // MeshSimplify - 단순화
    // MeshApproximate - 근사 지오메트리
    // Custom       - 커스텀 생성

    // 셀 크기 (그리드 단위)
    int32 CellSize;

    // 빌드 설정
    TSoftObjectPtr<UHLODBuildData> HLODBuildDataClass;

    // 스트리밍 설정
    bool bIsSpatiallyLoaded;

    // 머티리얼 설정
    TSoftObjectPtr<UMaterialInterface> HLODMaterial;
};

// HLOD 빌드 데이터
class UHLODBuildData : public UObject
{
    // 소스 액터 필터
    TSubclassOf<AActor> ActorClass;

    // 빌드 설정
    FMeshProxySettings ProxySettings;
    FMeshMergingSettings MergeSettings;

    // Nanite 설정
    bool bEnableNanite;

    // 텍스처 설정
    int32 TextureSize;
    bool bBakeNormals;
};
```

---

## Nanite HLOD

### Nanite 통합

```
┌─────────────────────────────────────────────────────────────────┐
│                      Nanite HLOD                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  기존 HLOD                         Nanite HLOD                  │
│  ┌─────────────────┐              ┌─────────────────┐          │
│  │                 │              │                 │          │
│  │ • 고정 LOD 레벨 │              │ • 연속 LOD      │          │
│  │ • 수동 전환     │   ──────▶   │ • 자동 최적화   │          │
│  │ • 팝핑 가능     │              │ • 부드러운 전환 │          │
│  │                 │              │                 │          │
│  └─────────────────┘              └─────────────────┘          │
│                                                                 │
│  장점:                                                          │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • HLOD 프록시도 Nanite 가상 지오메트리 사용              │   │
│  │ • 원거리에서도 높은 디테일 유지 가능                     │   │
│  │ • LOD 전환 아티팩트 제거                                │   │
│  │ • 메모리 효율 향상                                      │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  설정:                                                          │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ HLOD Layer → Build Settings → Enable Nanite = true      │   │
│  │                                                          │   │
│  │ // C++ 설정                                              │   │
│  │ HLODLayer->ProxySettings.bEnableNanite = true;          │   │
│  │ HLODLayer->ProxySettings.NaniteSettings = {...};        │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 런타임 동작

### HLOD 스트리밍

```cpp
// HLOD 스트리밍 관리
class FHLODRuntimeManager
{
    // 로드된 HLOD 액터들
    TMap<FGuid, ALODActor*> LoadedHLODActors;

    // 매 프레임 업데이트
    void UpdateHLODVisibility(const TArray<FSceneView*>& Views)
    {
        for (auto& Pair : LoadedHLODActors)
        {
            ALODActor* HLODActor = Pair.Value;

            bool bShouldBeVisible = false;
            for (const FSceneView* View : Views)
            {
                if (HLODActor->ShouldShowLODActor(View))
                {
                    bShouldBeVisible = true;
                    break;
                }
            }

            // 가시성 전환
            if (bShouldBeVisible != HLODActor->IsVisible())
            {
                HLODActor->SetActorHiddenInGame(!bShouldBeVisible);

                // 소스 액터들 가시성 토글
                for (AActor* SubActor : HLODActor->SubActors)
                {
                    SubActor->SetActorHiddenInGame(bShouldBeVisible);
                }
            }
        }
    }
};
```

### 전환 애니메이션

```cpp
// Dithered 전환
void ApplyDitheredTransition(
    ALODActor* HLODActor,
    float TransitionAlpha)
{
    // HLOD 액터 디더링
    HLODActor->GetStaticMeshComponent()->SetCustomPrimitiveData(
        /*Index=*/0, TransitionAlpha);

    // 소스 액터들 디더링
    for (AActor* SubActor : HLODActor->SubActors)
    {
        if (UPrimitiveComponent* Prim = SubActor->FindComponentByClass<UPrimitiveComponent>())
        {
            Prim->SetCustomPrimitiveData(0, 1.0f - TransitionAlpha);
        }
    }
}

// 머티리얼에서 디더링 적용
// if (DitherAlpha < InterleavedGradientNoise())
//     discard;
```

---

## 최적화 가이드

### HLOD 빌드 최적화

```
┌─────────────────────────────────────────────────────────────────┐
│                  HLOD 최적화 체크리스트                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  빌드 시간 최적화                                                │
│  □ 적절한 클러스터 크기 설정                                    │
│    └── 너무 작으면: HLOD 수 증가, 빌드 오래 걸림               │
│    └── 너무 크면: 프록시 품질 저하                             │
│                                                                 │
│  □ 텍스처 해상도 최적화                                         │
│    └── 원거리용이므로 512-1024 권장                            │
│    └── 4K 텍스처는 불필요                                      │
│                                                                 │
│  □ 증분 빌드 활용                                               │
│    └── 변경된 영역만 재빌드                                    │
│                                                                 │
│  런타임 최적화                                                   │
│  □ 적절한 전환 거리                                             │
│    └── 너무 가까우면: 품질 저하 눈에 띔                        │
│    └── 너무 멀면: 성능 이점 감소                               │
│                                                                 │
│  □ 스트리밍 통합                                                 │
│    └── HLOD도 스트리밍 대상                                    │
│    └── 메모리 예산 고려                                        │
│                                                                 │
│  □ Nanite HLOD 검토                                             │
│    └── 고품질 원거리 표현                                      │
│    └── 전환 아티팩트 제거                                      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 권장 설정

| 항목 | 소규모 월드 | 대규모 월드 |
|------|-------------|-------------|
| **HLOD Layers** | 1-2 | 2-4 |
| **Cluster Size** | 50m | 100-200m |
| **Texture Size** | 512 | 1024 |
| **Transition** | 0.1-0.2 | 0.05-0.1 |
| **Nanite** | 선택적 | 권장 |

---

## 다음 단계

- [월드 파티션](05-world-partition.md)에서 UE5의 월드 관리 시스템을 학습합니다.
