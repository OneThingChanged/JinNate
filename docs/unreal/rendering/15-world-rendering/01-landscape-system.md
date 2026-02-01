# 랜드스케이프 시스템

UE의 랜드스케이프 시스템은 대규모 지형을 효율적으로 생성하고 렌더링합니다.

---

## 아키텍처 개요

```
┌─────────────────────────────────────────────────────────────────┐
│                  Landscape 시스템 아키텍처                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                   ALandscapeProxy                        │   │
│  │  • 랜드스케이프의 기본 액터                               │   │
│  │  • 월드에 배치되는 단위                                   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│          ┌───────────────────┴───────────────────┐             │
│          ▼                                       ▼             │
│  ┌──────────────────┐               ┌──────────────────┐       │
│  │   ALandscape     │               │ALandscapeStreaming│      │
│  │                  │               │     Proxy        │       │
│  │ • 단일 랜드스케이프│              │ • 스트리밍 가능   │       │
│  │ • 에디터에서 편집  │              │ • World Partition │       │
│  └────────┬─────────┘               └─────────┬────────┘       │
│           │                                    │                │
│           └────────────────┬───────────────────┘                │
│                            ▼                                    │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              ULandscapeComponent                         │   │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐        │   │
│  │  │ Section │ │ Section │ │ Section │ │ Section │  ...   │   │
│  │  │   0,0   │ │   0,1   │ │   1,0   │ │   1,1   │        │   │
│  │  └─────────┘ └─────────┘ └─────────┘ └─────────┘        │   │
│  │                                                          │   │
│  │  • 개별 렌더링 단위                                       │   │
│  │  • 독립적 LOD                                            │   │
│  │  • Collision 데이터                                      │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 컴포넌트 구조

### Landscape 계층

```cpp
// 랜드스케이프 기본 클래스
class ALandscapeProxy : public AActor
{
    // 컴포넌트 배열
    TArray<ULandscapeComponent*> LandscapeComponents;

    // 머티리얼
    UMaterialInterface* LandscapeMaterial;

    // 하이트맵 데이터
    ULandscapeHeightfieldCollisionComponent* CollisionComponents;

    // LOD 설정
    int32 StaticLightingLOD;
    float LOD0DistributionSetting;
    float LODDistributionSetting;
};

// 개별 컴포넌트
class ULandscapeComponent : public UPrimitiveComponent
{
    // 섹션 크기 (예: 63, 127, 255)
    int32 ComponentSizeQuads;

    // 서브섹션 수
    int32 SubsectionSizeQuads;
    int32 NumSubsections;

    // 하이트맵 텍스처
    UTexture2D* HeightmapTexture;

    // 웨이트맵 텍스처들
    TArray<UTexture2D*> WeightmapTextures;
};
```

### 사이즈 구성

| 설정 | 값 | 설명 |
|------|-----|------|
| **Section Size** | 63, 127, 255 | 섹션당 쿼드 수 |
| **Sections/Component** | 1x1, 2x2 | 컴포넌트당 섹션 수 |
| **Component Size** | 계산됨 | SectionSize × NumSections |

```
┌─────────────────────────────────────────────────────────────────┐
│                  컴포넌트 사이즈 예시 (2x2 섹션)                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Component (255 quads = 127 × 2)                               │
│  ┌───────────────────────────────────────────────┐             │
│  │  ┌─────────────────┬─────────────────┐        │             │
│  │  │                 │                 │        │             │
│  │  │   Section 0,0   │   Section 0,1   │        │             │
│  │  │   (127 quads)   │   (127 quads)   │        │             │
│  │  │                 │                 │        │             │
│  │  ├─────────────────┼─────────────────┤        │             │
│  │  │                 │                 │        │             │
│  │  │   Section 1,0   │   Section 1,1   │        │             │
│  │  │   (127 quads)   │   (127 quads)   │        │             │
│  │  │                 │                 │        │             │
│  │  └─────────────────┴─────────────────┘        │             │
│  └───────────────────────────────────────────────┘             │
│                                                                 │
│  총 쿼드: 255 × 255 = 65,025                                    │
│  총 버텍스: 256 × 256 = 65,536                                  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## LOD 시스템

### 거리 기반 테셀레이션

```cpp
// LOD 계산
float CalculateLOD(const FVector& ViewOrigin,
                   const ULandscapeComponent* Component)
{
    float Distance = FVector::Dist(ViewOrigin, Component->Bounds.Origin);

    // LOD 거리 설정
    float LOD0Distance = Component->LOD0DistributionSetting;
    float LODDistribution = Component->LODDistributionSetting;

    // LOD 레벨 계산
    float LODLevel = 0.0f;
    if (Distance > LOD0Distance)
    {
        LODLevel = FMath::Log2(Distance / LOD0Distance) /
                   FMath::Log2(LODDistribution);
    }

    return FMath::Clamp(LODLevel, 0.0f, (float)MaxLOD);
}
```

### LOD 전환 구조

```
┌─────────────────────────────────────────────────────────────────┐
│                    Landscape LOD 레벨                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  LOD 0 (최고 품질)                                              │
│  ┌─────────────────────────────────────────┐                   │
│  │ ▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪ │  Full Resolution   │
│  │ ▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪ │  모든 버텍스       │
│  └─────────────────────────────────────────┘                   │
│                                                                 │
│  LOD 1                                                          │
│  ┌─────────────────────────────────────────┐                   │
│  │ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ │  1/2 Resolution   │
│  │ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ │  버텍스 스킵      │
│  └─────────────────────────────────────────┘                   │
│                                                                 │
│  LOD 2                                                          │
│  ┌─────────────────────────────────────────┐                   │
│  │ ▪   ▪   ▪   ▪   ▪   ▪   ▪   ▪   ▪   ▪  │  1/4 Resolution   │
│  │ ▪   ▪   ▪   ▪   ▪   ▪   ▪   ▪   ▪   ▪  │                   │
│  └─────────────────────────────────────────┘                   │
│                                                                 │
│  LOD 3+                                                         │
│  ┌─────────────────────────────────────────┐                   │
│  │ ▪       ▪       ▪       ▪       ▪      │  1/8+ Resolution  │
│  └─────────────────────────────────────────┘                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 인접 LOD 스티칭

```cpp
// LOD 경계 스티칭 (크랙 방지)
void StitchLODBoundary(int32 CurrentLOD, int32 NeighborLOD,
                       ELandscapeEdge Edge)
{
    if (NeighborLOD > CurrentLOD)
    {
        // 더 높은 LOD(낮은 디테일) 이웃에 맞춤
        // 경계 버텍스를 이웃 LOD에 맞게 조정
        int32 LODDelta = NeighborLOD - CurrentLOD;
        int32 SkipVertices = 1 << LODDelta;

        // 스킵된 버텍스들을 보간
        for (int32 i = 0; i < EdgeVertexCount; i += SkipVertices)
        {
            InterpolateEdgeVertex(Edge, i, SkipVertices);
        }
    }
}
```

---

## 머티리얼 시스템

### 레이어 기반 블렌딩

```
┌─────────────────────────────────────────────────────────────────┐
│                  Landscape 머티리얼 레이어                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │   Layer 0   │  │   Layer 1   │  │   Layer 2   │             │
│  │   (Grass)   │  │   (Rock)    │  │   (Sand)    │             │
│  │  ┌───────┐  │  │  ┌───────┐  │  │  ┌───────┐  │             │
│  │  │Diffuse│  │  │  │Diffuse│  │  │  │Diffuse│  │             │
│  │  │Normal │  │  │  │Normal │  │  │  │Normal │  │             │
│  │  │Rough  │  │  │  │Rough  │  │  │  │Rough  │  │             │
│  │  └───────┘  │  │  └───────┘  │  │  └───────┘  │             │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘             │
│         │                │                │                     │
│         └────────────────┼────────────────┘                     │
│                          ▼                                      │
│  ┌───────────────────────────────────────────────┐             │
│  │              Weight Map Blending              │             │
│  │                                               │             │
│  │  Final = L0 * W0 + L1 * W1 + L2 * W2         │             │
│  │                                               │             │
│  │  W0 + W1 + W2 = 1.0 (정규화)                  │             │
│  └───────────────────────────────────────────────┘             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 머티리얼 구현

```cpp
// Landscape 머티리얼 노드 (HLSL)
// Weight 블렌딩
float3 BlendLandscapeLayers(
    Texture2D LayerTextures[MAX_LAYERS],
    float LayerWeights[MAX_LAYERS],
    float2 UV)
{
    float3 Result = 0;

    for (int i = 0; i < NumLayers; i++)
    {
        float3 LayerColor = LayerTextures[i].Sample(Sampler, UV).rgb;
        Result += LayerColor * LayerWeights[i];
    }

    return Result;
}

// Height-based 블렌딩 (더 자연스러운 전환)
float3 HeightBlendLayers(
    float3 Layer0Color, float Layer0Height, float Weight0,
    float3 Layer1Color, float Layer1Height, float Weight1)
{
    float BlendHeight = 0.2;

    float Height0 = Layer0Height + Weight0;
    float Height1 = Layer1Height + Weight1;

    float MaxHeight = max(Height0, Height1) - BlendHeight;

    float b0 = max(Height0 - MaxHeight, 0);
    float b1 = max(Height1 - MaxHeight, 0);

    return (Layer0Color * b0 + Layer1Color * b1) / (b0 + b1);
}
```

---

## Virtual Texture

### Runtime Virtual Texture (RVT)

```
┌─────────────────────────────────────────────────────────────────┐
│                Runtime Virtual Texture 구조                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                   Virtual Texture                        │   │
│  │  ┌────┬────┬────┬────┬────┬────┬────┬────┐              │   │
│  │  │    │    │    │    │    │    │    │    │   ...        │   │
│  │  ├────┼────┼────┼────┼────┼────┼────┼────┤              │   │
│  │  │    │ R  │ R  │    │    │    │    │    │   R=Resident │   │
│  │  ├────┼────┼────┼────┼────┼────┼────┼────┤              │   │
│  │  │    │ R  │ R  │ R  │    │    │    │    │              │   │
│  │  ├────┼────┼────┼────┼────┼────┼────┼────┤              │   │
│  │  │    │    │ R  │ R  │    │    │    │    │              │   │
│  │  └────┴────┴────┴────┴────┴────┴────┴────┘              │   │
│  │                                                          │   │
│  │  • 가시 영역만 실제 텍스처 로드                           │   │
│  │  • 페이지 단위 스트리밍                                   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│                              ▼                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                   Physical Cache                         │   │
│  │  ┌────┬────┬────┬────┬────┬────┐                        │   │
│  │  │Page│Page│Page│Page│Page│Page│  고정 크기 캐시        │   │
│  │  │ 0  │ 1  │ 2  │ 3  │ 4  │ 5  │                        │   │
│  │  └────┴────┴────┴────┴────┴────┘                        │   │
│  │                                                          │   │
│  │  • LRU 기반 페이지 교체                                  │   │
│  │  • 페이지 테이블로 매핑                                   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### RVT 설정

```cpp
// Virtual Texture Volume 설정
UPROPERTY(EditAnywhere, Category = "Virtual Texture")
class URuntimeVirtualTextureComponent
{
    // 가상 텍스처 에셋
    URuntimeVirtualTexture* VirtualTexture;

    // 영역 설정
    FBox Bounds;

    // 해상도 설정
    int32 TileCount;        // 타일 수
    int32 TileSize;         // 타일당 픽셀
    int32 TileBorderSize;   // 보더 픽셀

    // LOD 설정
    int32 NumLODs;
    bool bEnableScalability;
};
```

---

## Nanite Landscape (UE5.3+)

### Nanite 적용

```
┌─────────────────────────────────────────────────────────────────┐
│                  Nanite Landscape 구조                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  기존 Landscape                    Nanite Landscape             │
│  ┌─────────────────┐              ┌─────────────────┐          │
│  │ 고정 LOD 레벨   │              │ 가상 지오메트리  │          │
│  │                 │              │                 │          │
│  │ • LOD 0-7      │              │ • 연속 LOD     │          │
│  │ • 고정 테셀레이션│              │ • GPU Driven   │          │
│  │ • CPU LOD 선택  │   ────▶     │ • 픽셀 밀도 기반│          │
│  └─────────────────┘              └─────────────────┘          │
│                                                                 │
│  장점:                                                          │
│  • 무제한 디테일                                                 │
│  • 자동 LOD 선택                                                │
│  • 크랙 없음                                                    │
│                                                                 │
│  제한:                                                          │
│  • 메모리 사용량 증가                                            │
│  • 특정 기능 미지원 (Grass, Spline 등)                          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 활성화 방법

```cpp
// 프로젝트 설정에서 활성화
[/Script/Engine.RendererSettings]
r.Nanite.Landscape=1

// 또는 Landscape 설정
UPROPERTY(EditAnywhere, Category = "Nanite")
bool bEnableNanite;

// Nanite 머티리얼 요구사항
// - World Position Offset 미지원
// - Tessellation 미지원
// - Masked 블렌딩 모드 미지원
```

---

## 콜리전 시스템

### 하이트필드 콜리전

```cpp
// 콜리전 컴포넌트
class ULandscapeHeightfieldCollisionComponent : public UPrimitiveComponent
{
    // 콜리전 하이트 데이터
    TArray<uint16> CollisionHeightData;

    // 콜리전 해상도 (렌더링보다 낮음)
    int32 CollisionSizeQuads;

    // 물리 머티리얼
    TArray<UPhysicalMaterial*> PhysicalMaterials;

    // 간단한 콜리전 사용
    bool bSimpleCollision;
};
```

### 콜리전 LOD

```
┌─────────────────────────────────────────────────────────────────┐
│                  Landscape 콜리전 LOD                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Render Resolution (높음)                                       │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ ▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪ │   │
│  │ 255 × 255 쿼드                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│                              ▼                                  │
│  Collision Resolution (낮음)                                    │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ ▪   ▪   ▪   ▪   ▪   ▪   ▪   ▪   ▪   ▪   ▪   ▪   ▪   ▪ │   │
│  │ 127 × 127 (또는 63 × 63)                                │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  • 콜리전은 렌더링보다 낮은 해상도 사용                          │
│  • 메모리 및 물리 연산 절약                                     │
│  • Collision MipLevel로 조정                                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 최적화 팁

### 권장 설정

| 항목 | 권장값 | 이유 |
|------|--------|------|
| **Section Size** | 127 또는 255 | 밸런스 좋음 |
| **Components** | 8×8 km 이하 | 스트리밍 효율 |
| **LOD 0 Distance** | 1000-2000 | 품질/성능 밸런스 |
| **Collision MipLevel** | 1-2 | 메모리 절약 |

### 성능 체크리스트

```
┌─────────────────────────────────────────────────────────────────┐
│                  Landscape 최적화 체크리스트                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  □ 적절한 컴포넌트 크기 선택                                     │
│    └── 너무 작으면: Draw Call 증가                              │
│    └── 너무 크면: 컬링 비효율                                   │
│                                                                 │
│  □ LOD 거리 튜닝                                                │
│    └── Stat Unit으로 확인                                       │
│    └── 프로파일링으로 최적값 찾기                               │
│                                                                 │
│  □ 레이어 수 최소화                                             │
│    └── 3-4개 레이어 권장                                        │
│    └── 더 많으면 샘플러 부족 가능                               │
│                                                                 │
│  □ Virtual Texture 사용                                         │
│    └── 대규모 지형에서 메모리 절약                              │
│    └── 스트리밍으로 VRAM 효율화                                 │
│                                                                 │
│  □ Nanite 검토 (UE5.3+)                                        │
│    └── 고디테일 지형에 효과적                                   │
│    └── 제한사항 확인 필수                                       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 다음 단계

- [폴리지 렌더링](02-foliage-rendering.md)에서 대규모 식생 렌더링을 학습합니다.
