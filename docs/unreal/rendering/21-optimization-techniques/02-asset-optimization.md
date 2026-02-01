# 에셋 최적화

LOD, 텍스처, 메시, 머티리얼 등 에셋 최적화 기법을 분석합니다.

---

## LOD 시스템

```
┌─────────────────────────────────────────────────────────────────┐
│                      LOD System                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  LOD (Level of Detail) = 거리에 따른 디테일 단계 전환            │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  Camera ────────────────────────────────────────────►    │   │
│  │                                                          │   │
│  │  ┌─────┐    ┌─────┐    ┌─────┐    ┌─────┐              │   │
│  │  │LOD 0│    │LOD 1│    │LOD 2│    │LOD 3│              │   │
│  │  │100% │    │ 50% │    │ 25% │    │ 10% │              │   │
│  │  │ Tri │    │ Tri │    │ Tri │    │ Tri │              │   │
│  │  └─────┘    └─────┘    └─────┘    └─────┘              │   │
│  │   Near       Mid       Far        Very Far              │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  자동 LOD 생성:                                                 │
│  Static Mesh Editor → LOD Settings → Auto Generate LODs         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### LOD 설정

```cpp
// 자동 LOD 생성 설정
UPROPERTY(EditAnywhere, Category = "LOD")
FMeshReductionSettings LODReductionSettings;

void SetupAutoLOD(UStaticMesh* Mesh)
{
    // LOD 그룹 설정
    Mesh->LODGroup = TEXT("LargeProp");

    // 개별 LOD 설정
    FStaticMeshSourceModel& LOD1 = Mesh->GetSourceModel(1);
    LOD1.ReductionSettings.PercentTriangles = 0.5f;
    LOD1.ReductionSettings.PercentVertices = 0.5f;
    LOD1.ScreenSize = 0.5f;

    FStaticMeshSourceModel& LOD2 = Mesh->GetSourceModel(2);
    LOD2.ReductionSettings.PercentTriangles = 0.25f;
    LOD2.ScreenSize = 0.25f;

    // 빌드
    Mesh->Build();
}

// 런타임 LOD 강제
void ForceLOD(UStaticMeshComponent* Component, int32 LODIndex)
{
    Component->SetForcedLodModel(LODIndex + 1); // 0 = Auto
}

// 스크린 사이즈 기반 전환
// Project Settings → Engine → Rendering
// LOD Distance Scale: 1.0 (기본)
```

### HLOD (Hierarchical LOD)

```cpp
// HLOD = 원거리에서 여러 메시를 하나로 병합
// World Settings → Hierarchical LODSetup

// HLOD 레벨 설정
struct FHierarchicalLODSetup
{
    // 클러스터 생성 기준
    float MinClustersSize = 5000.0f;

    // LOD 레벨별 설정
    TArray<FHierarchicalSimplification> Levels;
    // Level 0: 개별 메시
    // Level 1: 근처 메시 클러스터
    // Level 2: 더 큰 클러스터
};

// HLOD 빌드
// Build → Build HLODs for Current Level

// 프록시 메시 생성 설정
FMeshProxySettings ProxySettings;
ProxySettings.ScreenSize = 300;
ProxySettings.MaterialSettings.TextureSize = 1024;
ProxySettings.bCreateCollision = false;
```

---

## 텍스처 최적화

```
┌─────────────────────────────────────────────────────────────────┐
│                   Texture Optimization                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  메모리 소비 계산:                                              │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  기본 공식: Width × Height × BytesPerPixel × MipCount    │   │
│  │                                                          │   │
│  │  예시 (4K RGBA):                                         │   │
│  │  4096 × 4096 × 4 bytes × 1.33 (mips) ≈ 85 MB            │   │
│  │                                                          │   │
│  │  압축 후 (BC7):                                          │   │
│  │  4096 × 4096 × 1 byte × 1.33 ≈ 21 MB                    │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  압축 포맷:                                                     │
│  ┌──────────────┬────────────┬─────────────────────────┐       │
│  │ 포맷         │ BPP       │ 용도                     │       │
│  ├──────────────┼────────────┼─────────────────────────┤       │
│  │ BC1 (DXT1)   │ 4 bit     │ RGB (노 알파)           │       │
│  │ BC3 (DXT5)   │ 8 bit     │ RGBA                    │       │
│  │ BC5          │ 8 bit     │ 노멀맵 (RG)             │       │
│  │ BC7          │ 8 bit     │ 고품질 RGBA             │       │
│  │ ASTC         │ 가변      │ 모바일                  │       │
│  └──────────────┴────────────┴─────────────────────────┘       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 텍스처 설정

```cpp
// 텍스처 임포트 설정
void OptimizeTexture(UTexture2D* Texture)
{
    // 압축 설정
    Texture->CompressionSettings = TC_Default; // 또는 TC_BC7, TC_Normalmap

    // LOD 그룹
    Texture->LODGroup = TEXTUREGROUP_World;

    // 밉맵 설정
    Texture->MipGenSettings = TMGS_FromTextureGroup;

    // 최대 해상도 제한
    Texture->MaxTextureSize = 2048;

    // sRGB 설정
    Texture->SRGB = true; // 컬러 텍스처
    // Texture->SRGB = false; // 데이터 텍스처 (노멀, 마스크)

    // 스트리밍 설정
    Texture->NeverStream = false;
}

// 가상 텍스처링 (Virtual Texturing)
// 대형 텍스처를 타일 단위로 스트리밍
Texture->VirtualTextureStreaming = true;
```

### 텍스처 아틀라스

```cpp
// 텍스처 아틀라스 = 여러 텍스처를 하나로 병합
// 장점: 드로우콜 감소, 배칭 가능

// Paper2D 스프라이트 아틀라스
UPaperSpriteAtlas* Atlas = NewObject<UPaperSpriteAtlas>();
Atlas->MaxWidth = 2048;
Atlas->MaxHeight = 2048;
Atlas->AddSprite(Sprite1);
Atlas->AddSprite(Sprite2);
Atlas->RebuildAtlas();

// 머티리얼에서 아틀라스 사용
// UV 좌표 조정 필요
float2 AtlasUV = UV * TileSize + TileOffset;
float4 Color = Texture2DSample(AtlasTexture, AtlasUV);
```

---

## 메시 최적화

```
┌─────────────────────────────────────────────────────────────────┐
│                     Mesh Optimization                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  최적화 체크리스트:                                             │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  □ 불필요한 폴리곤 제거                                  │   │
│  │  □ 적절한 LOD 생성                                       │   │
│  │  □ 노멀 하드 엣지 최소화 (버텍스 분리 감소)             │   │
│  │  □ UV 심 최소화                                          │   │
│  │  □ 머티리얼 슬롯 수 최소화                               │   │
│  │  □ 콜리전 단순화                                         │   │
│  │  □ 라이트맵 UV 최적화                                    │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  버텍스 vs 트라이앵글:                                          │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  실제 비용 = 고유 버텍스 수 (인덱스된)                   │   │
│  │                                                          │   │
│  │  같은 위치라도 다음이 다르면 분리:                       │   │
│  │  • 노멀 (하드 엣지)                                      │   │
│  │  • UV 좌표 (UV 심)                                       │   │
│  │  • 버텍스 컬러                                           │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 메시 분석

```cpp
// 메시 통계 확인
void AnalyzeMesh(UStaticMesh* Mesh)
{
    const FStaticMeshLODResources& LOD0 = Mesh->GetLODForExport(0);

    int32 NumVertices = LOD0.VertexBuffers.StaticMeshVertexBuffer.GetNumVertices();
    int32 NumTriangles = 0;

    for (const FStaticMeshSection& Section : LOD0.Sections)
    {
        NumTriangles += Section.NumTriangles;
    }

    UE_LOG(LogTemp, Log, TEXT("Mesh: %s"), *Mesh->GetName());
    UE_LOG(LogTemp, Log, TEXT("Vertices: %d"), NumVertices);
    UE_LOG(LogTemp, Log, TEXT("Triangles: %d"), NumTriangles);
    UE_LOG(LogTemp, Log, TEXT("Materials: %d"), Mesh->GetStaticMaterials().Num());

    // 권장 기준
    // 배경 프롭: 500-5000 tri
    // 캐릭터: 15000-50000 tri
    // 주요 에셋: 5000-20000 tri
}
```

### 콜리전 최적화

```cpp
// 단순 콜리전 사용
// Static Mesh Editor → Collision → Add Box/Sphere/Capsule Simplified Collision

// 복잡 콜리전 vs 단순 콜리전
UPROPERTY(EditAnywhere, Category = "Collision")
ECollisionTraceFlag CollisionTraceFlag;
// CTF_UseDefault: 기본 (단순 또는 복잡)
// CTF_UseSimpleAndComplex: 둘 다
// CTF_UseSimpleAsComplex: 단순만
// CTF_UseComplexAsSimple: 복잡만 (성능 저하 주의)

// 컨벡스 분해 (Convex Decomposition)
// 복잡한 메시를 여러 컨벡스로 분해
UBodySetup* BodySetup = Mesh->GetBodySetup();
BodySetup->AggGeom.ConvexElems.Num(); // 컨벡스 수 확인
```

---

## 머티리얼 인스턴싱

```
┌─────────────────────────────────────────────────────────────────┐
│                  Material Instancing                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Material Instance = 부모 머티리얼의 파라미터 변형              │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │         Master Material                                  │   │
│  │              │                                           │   │
│  │    ┌─────────┼─────────┐                                │   │
│  │    │         │         │                                │   │
│  │    ▼         ▼         ▼                                │   │
│  │  MI_Red   MI_Blue   MI_Green                            │   │
│  │  (Color)  (Color)   (Color)                             │   │
│  │                                                          │   │
│  │  장점:                                                   │   │
│  │  • 셰이더 컴파일 공유                                    │   │
│  │  • 메모리 절약                                           │   │
│  │  • 배칭 가능 (동일 부모)                                 │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 인스턴스 생성

```cpp
// 머티리얼 인스턴스 동적 생성
UMaterialInstanceDynamic* CreateDynamicMaterial(UMaterialInterface* Parent)
{
    UMaterialInstanceDynamic* MID = UMaterialInstanceDynamic::Create(Parent, this);

    // 파라미터 설정
    MID->SetScalarParameterValue(TEXT("Roughness"), 0.5f);
    MID->SetVectorParameterValue(TEXT("BaseColor"), FLinearColor::Red);
    MID->SetTextureParameterValue(TEXT("Diffuse"), MyTexture);

    return MID;
}

// 머티리얼 파라미터 컬렉션 (MPC)
// 여러 머티리얼에서 공유하는 글로벌 파라미터
UMaterialParameterCollection* MPC = LoadObject<UMaterialParameterCollection>(...);
UMaterialParameterCollectionInstance* MPCI =
    GetWorld()->GetParameterCollectionInstance(MPC);

MPCI->SetScalarParameterValue(TEXT("GlobalWetness"), 0.8f);
```

### 머티리얼 최적화 팁

```cpp
// 1. 불필요한 피처 비활성화
Material->bUsedWithSkeletalMesh = false; // 사용 안 하면 비활성화

// 2. 텍스처 샘플러 수 제한
// Shader Model 5: 최대 128개 (권장 16개 이하)

// 3. 머티리얼 도메인 적절히 설정
Material->MaterialDomain = MD_Surface;  // 대부분
Material->MaterialDomain = MD_DeferredDecal;  // 데칼
Material->MaterialDomain = MD_UI;  // UI

// 4. Blend Mode 최적화
// Opaque > Masked > Translucent (성능 순)

// 5. Two Sided 피하기 (폴리곤 2배)
Material->TwoSided = false;

// 6. 비용이 큰 노드 피하기
// - Noise 함수
// - 루프/반복
// - 과도한 레이어 블렌딩
```

---

## 에셋 오디팅

```
┌─────────────────────────────────────────────────────────────────┐
│                     Asset Auditing                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Size Map (에디터):                                             │
│  Window → Developer Tools → Asset Audit                         │
│                                                                 │
│  체크 항목:                                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  □ 사용되지 않는 에셋                                    │   │
│  │  □ 중복 에셋                                             │   │
│  │  □ 과도하게 큰 텍스처                                    │   │
│  │  □ 과도하게 복잡한 메시                                  │   │
│  │  □ 순환 참조                                             │   │
│  │  □ 미참조 에셋                                           │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Reference Viewer:                                              │
│  에셋 우클릭 → Reference Viewer                                 │
│  의존성 그래프 시각화                                           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 에셋 통계 수집

```cpp
// 에셋 레지스트리 활용
void AuditAssets()
{
    FAssetRegistryModule& AssetRegistry =
        FModuleManager::LoadModuleChecked<FAssetRegistryModule>("AssetRegistry");

    TArray<FAssetData> AllTextures;
    AssetRegistry.Get().GetAssetsByClass(UTexture2D::StaticClass()->GetFName(), AllTextures);

    int64 TotalTextureMemory = 0;
    for (const FAssetData& AssetData : AllTextures)
    {
        if (UTexture2D* Texture = Cast<UTexture2D>(AssetData.GetAsset()))
        {
            int64 Size = Texture->CalcTextureMemorySizeEnum(TMC_AllMips);
            TotalTextureMemory += Size;

            // 4K 이상 텍스처 경고
            if (Texture->GetSizeX() >= 4096 || Texture->GetSizeY() >= 4096)
            {
                UE_LOG(LogTemp, Warning, TEXT("Large texture: %s (%dx%d)"),
                    *Texture->GetName(),
                    Texture->GetSizeX(),
                    Texture->GetSizeY());
            }
        }
    }

    UE_LOG(LogTemp, Log, TEXT("Total Texture Memory: %.2f MB"),
        TotalTextureMemory / (1024.0 * 1024.0));
}
```

---

## 주요 클래스 요약

| 클래스/설정 | 역할 |
|-------------|------|
| `LODGroup` | LOD 전환 거리 그룹 |
| `FMeshReductionSettings` | 메시 단순화 설정 |
| `FHierarchicalLODSetup` | HLOD 설정 |
| `UMaterialInstanceDynamic` | 동적 머티리얼 인스턴스 |
| `UMaterialParameterCollection` | 글로벌 머티리얼 파라미터 |
| `FAssetRegistryModule` | 에셋 레지스트리 |

---

## 참고 자료

- [Static Mesh LOD](https://docs.unrealengine.com/static-mesh-lod/)
- [Texture Optimization](https://docs.unrealengine.com/texture-guidelines/)
- [Material Optimization](https://docs.unrealengine.com/material-optimization/)
