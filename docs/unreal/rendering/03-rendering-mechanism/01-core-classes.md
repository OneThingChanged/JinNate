# 01. 핵심 클래스

> UE 렌더링 시스템의 핵심 클래스와 관계

---

## 목차

1. [클래스 개요](#1-클래스-개요)
2. [UPrimitiveComponent](#2-uprimitivecomponent)
3. [FPrimitiveSceneProxy](#3-fprimitivesceneproxy)
4. [FScene](#4-fscene)
5. [FSceneView와 FSceneRenderer](#5-fsceneview와-fscenerenderer)
6. [데이터 흐름](#6-데이터-흐름)

---

## 1. 클래스 개요 {#1-클래스-개요}

### 1.1 계층 구조

![UE4 렌더링 개요](../images/ch03/1617944-20210319203832841-1939790306.jpg)
*UE4 렌더링 시스템 개요*

```
┌─────────────────────────────────────────────────────────────────┐
│                    렌더링 클래스 계층                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Game Thread                                                    │
│  ┌────────────────────────────────────────────────────────┐    │
│  │  UWorld                                                 │    │
│  │    └─ AActor[]                                          │    │
│  │         └─ UPrimitiveComponent[]                        │    │
│  └────────────────────────────────────────────────────────┘    │
│                          │                                      │
│                          │ CreateSceneProxy()                   │
│                          ▼                                      │
│  Render Thread                                                  │
│  ┌────────────────────────────────────────────────────────┐    │
│  │  FScene                                                 │    │
│  │    ├─ FPrimitiveSceneInfo[] ─ FPrimitiveSceneProxy[]    │    │
│  │    ├─ FLightSceneInfo[] ─ FLightSceneProxy[]            │    │
│  │    └─ FSceneView[]                                      │    │
│  └────────────────────────────────────────────────────────┘    │
│                          │                                      │
│                          │ Render()                             │
│                          ▼                                      │
│  ┌────────────────────────────────────────────────────────┐    │
│  │  FSceneRenderer (FDeferredShadingSceneRenderer)         │    │
│  │    └─ FMeshDrawCommand[]                                │    │
│  └────────────────────────────────────────────────────────┘    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 1.2 주요 클래스 요약

| 클래스 | 역할 | 생명주기 |
|--------|------|----------|
| **UPrimitiveComponent** | 게임 오브젝트의 렌더링 가능 컴포넌트 | 게임 스레드 |
| **FPrimitiveSceneProxy** | UPrimitiveComponent의 렌더링 스레드 미러 | 렌더링 스레드 |
| **FPrimitiveSceneInfo** | Scene 내 프리미티브 정보 | FScene 소유 |
| **FScene** | 렌더러 모듈에서의 월드 표현 | UWorld당 하나 |
| **FSceneView** | FScene 내의 단일 뷰포트 | 프레임당 생성 |
| **FSceneRenderer** | 프레임별 렌더러 (임시 데이터 캡슐화) | 프레임당 생성 |

---

## 2. UPrimitiveComponent {#2-uprimitivecomponent}

### 2.1 개요

UPrimitiveComponent는 렌더링 가능한 모든 게임 오브젝트의 기본 클래스입니다.

```cpp
class UPrimitiveComponent : public USceneComponent
{
    GENERATED_BODY()

public:
    // 렌더링 프록시 생성
    virtual FPrimitiveSceneProxy* CreateSceneProxy();

    // 바운드 계산
    virtual FBoxSphereBounds CalcBounds(const FTransform& LocalToWorld) const;

    // 머티리얼
    virtual int32 GetNumMaterials() const;
    virtual UMaterialInterface* GetMaterial(int32 ElementIndex) const;

    // 가시성
    UPROPERTY(EditAnywhere, BlueprintReadOnly)
    uint8 bVisible : 1;

    UPROPERTY(EditAnywhere, BlueprintReadOnly)
    uint8 bCastShadow : 1;

    // 컬링
    UPROPERTY(EditAnywhere, BlueprintReadOnly)
    float BoundsScale;

protected:
    // Scene Proxy (렌더링 스레드 소유)
    FPrimitiveSceneProxy* SceneProxy;
};
```

### 2.2 파생 클래스

```
UPrimitiveComponent
├─ UMeshComponent
│   ├─ UStaticMeshComponent
│   │   └─ UInstancedStaticMeshComponent
│   └─ USkeletalMeshComponent
├─ UShapeComponent
│   ├─ UBoxComponent
│   ├─ USphereComponent
│   └─ UCapsuleComponent
├─ UBrushComponent
├─ ULandscapeComponent
└─ UTextRenderComponent
```

### 2.3 렌더링 상태 관리

```cpp
// 렌더링 상태 등록
void UPrimitiveComponent::CreateRenderState_Concurrent()
{
    Super::CreateRenderState_Concurrent();

    if (ShouldCreateRenderState())
    {
        // Scene Proxy 생성
        SceneProxy = CreateSceneProxy();

        if (SceneProxy)
        {
            // Scene에 추가
            GetWorld()->Scene->AddPrimitive(this);
        }
    }
}

// 렌더링 상태 제거
void UPrimitiveComponent::DestroyRenderState_Concurrent()
{
    if (SceneProxy)
    {
        GetWorld()->Scene->RemovePrimitive(this);

        // 렌더 스레드에서 삭제
        FPrimitiveSceneProxy* ProxyToDelete = SceneProxy;
        SceneProxy = nullptr;

        ENQUEUE_RENDER_COMMAND(DeleteProxy)(
            [ProxyToDelete](FRHICommandListImmediate&)
            {
                delete ProxyToDelete;
            });
    }

    Super::DestroyRenderState_Concurrent();
}
```

---

## 3. FPrimitiveSceneProxy {#3-fprimitivesceneproxy}

### 3.1 개요

FPrimitiveSceneProxy는 UPrimitiveComponent의 렌더링 스레드 측 표현입니다.

```cpp
class FPrimitiveSceneProxy
{
public:
    FPrimitiveSceneProxy(const UPrimitiveComponent* InComponent);
    virtual ~FPrimitiveSceneProxy();

    // 동적 메시 요소 수집 (매 프레임)
    virtual void GetDynamicMeshElements(
        const TArray<const FSceneView*>& Views,
        const FSceneViewFamily& ViewFamily,
        uint32 VisibilityMap,
        class FMeshElementCollector& Collector) const;

    // 정적 메시 요소 (캐싱 가능)
    virtual void DrawStaticElements(FStaticPrimitiveDrawInterface* PDI);

    // 바운드
    const FBoxSphereBounds& GetBounds() const { return Bounds; }
    const FMatrix& GetLocalToWorld() const { return LocalToWorld; }

    // 속성
    bool IsVisible() const { return bVisible; }
    bool CastsShadow() const { return bCastShadow; }
    bool IsMovable() const { return Mobility == EComponentMobility::Movable; }

protected:
    // 변환
    FMatrix LocalToWorld;
    FBoxSphereBounds Bounds;

    // 플래그
    uint32 bVisible : 1;
    uint32 bCastShadow : 1;
    uint32 bReceivesDecals : 1;

    // 이동성
    EComponentMobility::Type Mobility;

    // 소유 Scene Info
    FPrimitiveSceneInfo* PrimitiveSceneInfo;
};
```

### 3.2 GetDynamicMeshElements 구현

```cpp
void FStaticMeshSceneProxy::GetDynamicMeshElements(
    const TArray<const FSceneView*>& Views,
    const FSceneViewFamily& ViewFamily,
    uint32 VisibilityMap,
    FMeshElementCollector& Collector) const
{
    // 각 뷰에 대해
    for (int32 ViewIndex = 0; ViewIndex < Views.Num(); ViewIndex++)
    {
        if (VisibilityMap & (1 << ViewIndex))
        {
            const FSceneView* View = Views[ViewIndex];

            // LOD 선택
            int32 LODIndex = GetLOD(View);

            // 각 섹션(머티리얼)에 대해
            for (int32 SectionIndex = 0; SectionIndex < RenderData->LODResources[LODIndex].Sections.Num(); SectionIndex++)
            {
                const FStaticMeshSection& Section = RenderData->LODResources[LODIndex].Sections[SectionIndex];

                // FMeshBatch 생성
                FMeshBatch& MeshBatch = Collector.AllocateMesh();
                MeshBatch.VertexFactory = &RenderData->LODResources[LODIndex].VertexFactory;
                MeshBatch.MaterialRenderProxy = GetMaterialProxy(SectionIndex);
                MeshBatch.Type = PT_TriangleList;
                MeshBatch.bUseForMaterial = true;

                // FMeshBatchElement 설정
                FMeshBatchElement& BatchElement = MeshBatch.Elements[0];
                BatchElement.IndexBuffer = &Section.IndexBuffer;
                BatchElement.FirstIndex = Section.FirstIndex;
                BatchElement.NumPrimitives = Section.NumTriangles;
                BatchElement.MinVertexIndex = Section.MinVertexIndex;
                BatchElement.MaxVertexIndex = Section.MaxVertexIndex;

                // 수집기에 추가
                Collector.AddMesh(ViewIndex, MeshBatch);
            }
        }
    }
}
```

---

## 4. FScene {#4-fscene}

### 4.1 개요

FScene은 렌더링 모듈에서 UWorld를 표현합니다.

```cpp
class FScene : public FSceneInterface
{
public:
    // 프리미티브 관리
    virtual void AddPrimitive(UPrimitiveComponent* Primitive) override;
    virtual void RemovePrimitive(UPrimitiveComponent* Primitive) override;
    virtual void UpdatePrimitiveTransform(UPrimitiveComponent* Primitive) override;

    // 라이트 관리
    virtual void AddLight(ULightComponent* Light) override;
    virtual void RemoveLight(ULightComponent* Light) override;

    // 데이터 접근
    TArray<FPrimitiveSceneInfo*> Primitives;
    TArray<FLightSceneInfo*> Lights;

    // GPU Scene (4.22+)
    FGPUScene GPUScene;

    // 오클루전
    TUniquePtr<FOcclusionQueryPool> OcclusionQueryPool;

private:
    // 소유 월드
    UWorld* World;
};
```

### 4.2 프리미티브 추가

```cpp
void FScene::AddPrimitive(UPrimitiveComponent* Primitive)
{
    // Scene Info 생성
    FPrimitiveSceneInfo* SceneInfo = new FPrimitiveSceneInfo(Primitive, this);

    // 렌더 스레드에서 추가
    ENQUEUE_RENDER_COMMAND(AddPrimitive)(
        [this, SceneInfo](FRHICommandListImmediate& RHICmdList)
        {
            AddPrimitiveSceneInfo_RenderThread(SceneInfo);
        });
}

void FScene::AddPrimitiveSceneInfo_RenderThread(FPrimitiveSceneInfo* SceneInfo)
{
    // 배열에 추가
    Primitives.Add(SceneInfo);

    // 프리미티브 ID 할당
    SceneInfo->PackedIndex = Primitives.Num() - 1;

    // GPU Scene 업데이트
    if (GPUScene.IsEnabled())
    {
        GPUScene.AddPrimitive(SceneInfo);
    }

    // 정적 메시면 캐싱
    if (SceneInfo->Proxy->IsStatic())
    {
        CacheMeshDrawCommands(SceneInfo);
    }
}
```

---

## 5. FSceneView와 FSceneRenderer {#5-fsceneview와-fscenerenderer}

### 5.1 FSceneView

```cpp
class FSceneView
{
public:
    // 뷰 정보
    FSceneViewFamily* Family;
    FViewInfo* ViewInfo;

    // 행렬
    FMatrix ViewMatrix;
    FMatrix ProjectionMatrix;
    FMatrix ViewProjectionMatrix;
    FMatrix InvViewProjectionMatrix;

    // 프러스텀
    FConvexVolume ViewFrustum;

    // 뷰 사각형
    FIntRect ViewRect;

    // 카메라 정보
    FVector ViewOrigin;
    FRotator ViewRotation;
    float FOV;

    // 가시 프리미티브
    TArray<FPrimitiveSceneInfo*> VisiblePrimitives;
};

// FViewInfo는 FSceneView 확장
class FViewInfo : public FSceneView
{
public:
    // 가시성 비트맵
    FSceneBitArray PrimitiveVisibilityMap;
    FSceneBitArray StaticMeshVisibilityMap;

    // 드로우 명령
    TArray<FMeshDrawCommand> DynamicMeshCommands;
    TArray<FMeshDrawCommand> StaticMeshCommands;
};
```

### 5.2 FSceneRenderer

```cpp
class FSceneRenderer
{
public:
    FSceneRenderer(const FSceneViewFamily* InViewFamily, FHitProxyConsumer* InHitProxyConsumer);
    virtual ~FSceneRenderer();

    // 렌더링 진입점
    virtual void Render(FRHICommandListImmediate& RHICmdList) = 0;

protected:
    // 뷰 초기화
    void InitViews(FRHICommandListImmediate& RHICmdList);

    // 가시성 계산
    void ComputeViewVisibility(FRHICommandListImmediate& RHICmdList);

    // 메시 패스 설정
    void SetupMeshPass(FViewInfo& View);

protected:
    // Scene 참조
    FScene* Scene;

    // 뷰들
    TArray<FViewInfo> Views;

    // 뷰 패밀리
    const FSceneViewFamily* ViewFamily;
};

// 디퍼드 렌더러
class FDeferredShadingSceneRenderer : public FSceneRenderer
{
public:
    virtual void Render(FRHICommandListImmediate& RHICmdList) override;

private:
    void RenderPrePass(FRHICommandListImmediate& RHICmdList);
    void RenderBasePass(FRHICommandListImmediate& RHICmdList);
    void RenderLights(FRHICommandListImmediate& RHICmdList);
    void RenderTranslucency(FRHICommandListImmediate& RHICmdList);
};
```

---

## 6. 데이터 흐름 {#6-데이터-흐름}

### 6.1 프레임 렌더링 흐름

```
┌─────────────────────────────────────────────────────────────────┐
│                    프레임 데이터 흐름                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. UWorld::Tick() (Game Thread)                                │
│     └─ 액터/컴포넌트 업데이트                                     │
│                                                                 │
│  2. UPrimitiveComponent::SendRenderTransform() (Game Thread)    │
│     └─ ENQUEUE_RENDER_COMMAND()                                 │
│                                                                 │
│  3. FScene::UpdatePrimitiveTransform_RenderThread()             │
│     └─ FPrimitiveSceneProxy 업데이트                             │
│                                                                 │
│  4. FSceneRenderer::Render() (Render Thread)                    │
│     ├─ InitViews()                                              │
│     │   └─ 가시성 계산, 프러스텀 컬링                            │
│     │                                                           │
│     ├─ GatherDynamicMeshElements()                              │
│     │   └─ FPrimitiveSceneProxy::GetDynamicMeshElements()       │
│     │                                                           │
│     ├─ SetupMeshPass()                                          │
│     │   └─ FMeshPassProcessor::AddMeshBatch()                   │
│     │                                                           │
│     └─ RenderPass()                                             │
│         └─ SubmitMeshDrawCommands()                             │
│                                                                 │
│  5. FRHICommandList::Execute() (RHI Thread)                     │
│     └─ 실제 GPU 명령 제출                                        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 6.2 데이터 소유권

| 데이터 | 소유자 | 접근 |
|--------|--------|------|
| Actor Transform | UPrimitiveComponent (Game) | Game Thread |
| Proxy Transform | FPrimitiveSceneProxy (Render) | Render Thread |
| FMeshBatch | FMeshElementCollector | Render Thread (프레임 범위) |
| FMeshDrawCommand | FViewCommands | Render Thread (프레임 범위) |

---

## 요약

| 클래스 | 역할 | 핵심 메서드 |
|--------|------|------------|
| **UPrimitiveComponent** | 게임 렌더링 컴포넌트 | CreateSceneProxy() |
| **FPrimitiveSceneProxy** | 렌더링 스레드 표현 | GetDynamicMeshElements() |
| **FScene** | 월드의 렌더링 표현 | AddPrimitive(), RemovePrimitive() |
| **FSceneRenderer** | 프레임 렌더링 조정 | Render() |

---

## 다음 문서

[02. 파이프라인 진화](02-pipeline-evolution.md)에서 메시 드로잉 파이프라인의 변화를 살펴봅니다.
