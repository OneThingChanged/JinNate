# UE5 렌더링 개요

UE5의 렌더링 아키텍처 변화와 새로운 시스템들을 개괄합니다.

---

## UE5의 비전

### 차세대 그래픽스 목표

Epic Games가 UE5에서 설정한 목표:

1. **영화 품질의 에셋을 직접 사용** - 폴리곤 수 제한 없는 렌더링
2. **실시간 글로벌 일루미네이션** - 베이크 없는 동적 조명
3. **대규모 오픈 월드** - 스트리밍과 LOD의 자동화
4. **크로스 플랫폼 확장성** - PC부터 모바일까지

```cpp
// UE5의 렌더링 철학
// "아티스트가 기술적 제약 없이 창작에 집중할 수 있도록"

// UE4에서의 일반적인 워크플로우
class UE4_Workflow
{
    // 1. 고폴리 모델 제작
    // 2. 리토폴로지 (수동)
    // 3. LOD 생성 (수동 또는 자동)
    // 4. 노멀맵 베이킹
    // 5. 라이트맵 베이킹
    // 6. 최적화 반복
};

// UE5에서의 새로운 워크플로우
class UE5_Workflow
{
    // 1. 고폴리 모델 제작
    // 2. Nanite 활성화 (끝)
    // LOD, 라이트맵 베이킹 불필요
};
```

---

## 렌더링 아키텍처 진화

### RDG (Render Dependency Graph) 강화

```cpp
// UE5에서 강화된 RDG 시스템
class FRDGBuilder
{
public:
    // 리소스 생성 - 실제 할당은 지연됨
    FRDGTextureRef CreateTexture(const FRDGTextureDesc& Desc);
    FRDGBufferRef CreateBuffer(const FRDGBufferDesc& Desc);

    // 패스 추가 - 의존성 자동 추적
    template<typename ParameterStructType>
    void AddPass(
        FRDGEventName&& Name,
        const ParameterStructType* ParameterStruct,
        ERDGPassFlags Flags,
        TFunction<void(FRHICommandList&)> Lambda);

    // 그래프 실행 - 최적화된 순서로 실행
    void Execute();

private:
    // UE5 추가 기능
    void OptimizeResourceLifetimes();    // 메모리 앨리어싱
    void ParallelizePassExecution();     // 병렬 패스 실행
    void AsyncComputeOverlap();          // 비동기 컴퓨트 오버랩
};
```

### 새로운 렌더링 경로

```
┌─────────────────────────────────────────────────────────────────┐
│                    UE5 렌더링 경로                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    Scene Setup                           │   │
│  │  - View 초기화                                           │   │
│  │  - Visibility 계산                                       │   │
│  │  - Nanite 컬링                                           │   │
│  └────────────────────────┬────────────────────────────────┘   │
│                           │                                     │
│           ┌───────────────┼───────────────┐                     │
│           ▼               ▼               ▼                     │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐            │
│  │   Nanite     │ │  Traditional │ │   Async      │            │
│  │   Path       │ │  Mesh Path   │ │   Compute    │            │
│  │              │ │              │ │              │            │
│  │ - Cluster    │ │ - LOD 선택   │ │ - Lumen      │            │
│  │   Culling    │ │ - Draw Call  │ │   Tracing    │            │
│  │ - Software   │ │   생성       │ │ - VSM        │            │
│  │   Raster     │ │              │ │   업데이트    │            │
│  └──────┬───────┘ └──────┬───────┘ └──────┬───────┘            │
│         │                │                │                     │
│         └────────────────┼────────────────┘                     │
│                          ▼                                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    G-Buffer                              │   │
│  │  - BaseColor, Normal, Roughness, Metallic               │   │
│  │  - Nanite Visibility Buffer → Material ID               │   │
│  └────────────────────────┬────────────────────────────────┘   │
│                           │                                     │
│                           ▼                                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    Lighting                              │   │
│  │  - Lumen GI Injection                                    │   │
│  │  - Virtual Shadow Maps                                   │   │
│  │  - Direct/Indirect Lighting                              │   │
│  └────────────────────────┬────────────────────────────────┘   │
│                           │                                     │
│                           ▼                                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    Post Processing                       │   │
│  │  - TSR (Temporal Super Resolution)                       │   │
│  │  - Bloom, Tone Mapping                                   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## GPU-Driven 렌더링

### 패러다임 전환

```cpp
// UE4: CPU-Driven 렌더링
class FCPUDrivenRenderer
{
    void Render()
    {
        // CPU에서 모든 결정
        for (FPrimitiveSceneProxy* Proxy : VisiblePrimitives)
        {
            // CPU: LOD 계산
            int32 LOD = ComputeLOD(Proxy, ViewOrigin);

            // CPU: 컬링
            if (!FrustumCull(Proxy, ViewFrustum))
                continue;

            // CPU: Draw Call 생성
            FMeshBatch MeshBatch;
            Proxy->GetDynamicMeshElements(LOD, MeshBatch);

            // GPU: 단순 실행
            RHICmdList.DrawIndexedPrimitive(MeshBatch);
        }
        // 병목: CPU-GPU 통신, Draw Call 오버헤드
    }
};

// UE5: GPU-Driven 렌더링 (Nanite)
class FGPUDrivenRenderer
{
    void Render()
    {
        // CPU: 최소한의 준비만
        UploadInstanceData(AllInstances);

        // GPU: 모든 결정
        // Pass 1: Instance Culling (Compute Shader)
        DispatchCompute(InstanceCullingShader, NumInstances);

        // Pass 2: Cluster Culling (Compute Shader)
        DispatchCompute(ClusterCullingShader, NumClusters);

        // Pass 3: Rasterization (Compute Shader!)
        DispatchCompute(SoftwareRasterizer, VisibleClusters);

        // Pass 4: Material Evaluation
        DispatchCompute(MaterialShader, VisiblePixels);

        // 장점: 최소 CPU 오버헤드, 대규모 병렬 처리
    }
};
```

### Indirect Draw 활용

```cpp
// GPU-Driven을 위한 Indirect Draw
struct FDrawIndirectArgs
{
    uint32 VertexCountPerInstance;
    uint32 InstanceCount;      // GPU가 결정
    uint32 StartVertexLocation;
    uint32 StartInstanceLocation;
};

// GPU가 Indirect Args 버퍼를 채움
[numthreads(64, 1, 1)]
void CullingComputeShader(uint ThreadID : SV_DispatchThreadID)
{
    FInstance Instance = InstanceBuffer[ThreadID];

    // GPU에서 직접 가시성 테스트
    if (IsVisible(Instance, ViewFrustum, HZB))
    {
        // Atomic으로 Draw Args 업데이트
        uint Index;
        InterlockedAdd(DrawArgs.InstanceCount, 1, Index);
        VisibleInstances[Index] = Instance;
    }
}

// CPU는 Draw 명령만 발행 (GPU가 실제 수 결정)
RHICmdList.DrawIndexedIndirect(DrawArgsBuffer, 0);
```

---

## 새로운 렌더링 기능

### 1. Nanite (가상화 지오메트리)

```cpp
// Nanite의 핵심 데이터 구조
struct FNaniteCluster
{
    FVector Bounds;           // 클러스터 바운딩 볼륨
    float LODError;           // 화면 공간 오차
    uint32 TriangleOffset;    // 삼각형 데이터 오프셋
    uint32 TriangleCount;     // 삼각형 수 (최대 128)
    uint32 GroupIndex;        // 클러스터 그룹 (LOD 전환용)
};

// 클러스터 그룹 - DAG 구조
struct FNaniteClusterGroup
{
    TArray<uint32> ChildClusters;    // 더 상세한 자식들
    float MaxParentLODError;         // 부모로 전환 기준
    float MinChildLODError;          // 자식으로 전환 기준
};
```

### 2. Lumen (글로벌 일루미네이션)

```cpp
// Lumen의 씬 표현
class FLumenSceneData
{
    // 메시 카드 - 표면의 간략화된 표현
    TArray<FLumenMeshCards> MeshCards;

    // Surface Cache - 저해상도 라이팅 캐시
    FLumenSurfaceCache SurfaceCache;

    // Radiance Cache - 복셀 기반 간접광
    FLumenRadianceCache RadianceCache;

    // Screen Probes - 화면 공간 프로브
    FLumenScreenProbes ScreenProbes;
};

// Lumen 트레이싱 옵션
enum class ELumenTracingMethod
{
    SoftwareTracing,    // Surface Cache 기반
    HardwareTracing,    // RTX 레이트레이싱
    DetailTracing       // 근거리 고품질
};
```

### 3. Virtual Shadow Maps

```cpp
// 가상 섀도우 맵 구조
class FVirtualShadowMap
{
    // 물리적 타일 풀 (16K x 16K 가상 해상도)
    FRDGTexture* PhysicalTilePool;

    // 페이지 테이블 - 가상 → 물리 매핑
    FRDGBuffer* PageTable;

    // 클립맵 레벨 (Directional Light용)
    int32 NumClipmapLevels;

    // 캐싱 - 정적 지오메트리용
    FVSMCacheData CacheData;
};
```

### 4. TSR (Temporal Super Resolution)

```cpp
// TSR 파이프라인
class FTemporalSuperResolution
{
    void Execute(FRDGBuilder& GraphBuilder)
    {
        // 1. 히스토리 리프로젝션
        ReprojectHistory(GraphBuilder);

        // 2. 현재 프레임 분석
        AnalyzeCurrentFrame(GraphBuilder);

        // 3. 히스토리 거부/수용 판단
        RejectHistory(GraphBuilder);

        // 4. 업스케일 + 샤프닝
        Upscale(GraphBuilder);

        // 5. 히스토리 업데이트
        UpdateHistory(GraphBuilder);
    }

    // 해상도 스케일 (네이티브의 50-100%)
    float ScreenPercentage;

    // 품질 설정
    ETSRQuality Quality;
};
```

---

## 기존 시스템과의 통합

### 폴백 경로

```cpp
// Nanite 미지원 시 폴백
class FNaniteFallback
{
    static bool ShouldUseFallback(const FStaticMeshRenderData* RenderData)
    {
        // Nanite 미지원 조건
        if (!GNaniteSupported) return true;
        if (!RenderData->HasNaniteData()) return true;
        if (RenderData->bHasVertexColors) return true;  // 일부 기능 미지원
        if (Material->HasWorldPositionOffset()) return true;

        return false;
    }
};

// 렌더러에서의 분기
void FSceneRenderer::RenderOpaque()
{
    // Nanite 경로
    if (bUseNanite)
    {
        NaniteRenderer->Render(Scene, Views);
    }

    // 전통적 메시 경로 (Nanite 미지원 메시)
    MeshPassRenderer->RenderMeshPass(Scene, Views, EMeshPass::BasePass);

    // 두 경로의 결과가 동일한 G-Buffer에 기록됨
}
```

### 하이브리드 렌더링

```
┌─────────────────────────────────────────────────────────────────┐
│                    하이브리드 렌더링                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Scene Objects                                                  │
│       │                                                         │
│       ├─────────────────────────────────────────┐               │
│       │                                         │               │
│       ▼                                         ▼               │
│  ┌──────────────────┐               ┌──────────────────┐       │
│  │  Nanite Meshes   │               │ Traditional Mesh │       │
│  │                  │               │                  │       │
│  │ - Static Meshes  │               │ - Skeletal Mesh  │       │
│  │ - 고폴리 에셋    │               │ - WPO 사용 메시  │       │
│  │ - 대량 인스턴스  │               │ - 투명 메시      │       │
│  └────────┬─────────┘               └────────┬─────────┘       │
│           │                                  │                  │
│           ▼                                  ▼                  │
│  ┌──────────────────┐               ┌──────────────────┐       │
│  │ Visibility Buffer│               │    G-Buffer      │       │
│  │ + Depth          │               │    (BasePass)    │       │
│  └────────┬─────────┘               └────────┬─────────┘       │
│           │                                  │                  │
│           └─────────────┬────────────────────┘                  │
│                         ▼                                       │
│           ┌──────────────────────────┐                         │
│           │     Merged G-Buffer      │                         │
│           │ (통합된 지오메트리 정보)   │                         │
│           └──────────────────────────┘                         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 프로젝트 설정

### Nanite 활성화

```ini
; DefaultEngine.ini
[/Script/Engine.RendererSettings]
r.Nanite=1
r.Nanite.MaxPixelsPerEdge=1.0
```

### Lumen 설정

```ini
; DefaultEngine.ini
[/Script/Engine.RendererSettings]
r.Lumen.DiffuseIndirect.Allow=1
r.Lumen.Reflections.Allow=1
r.Lumen.HardwareRayTracing=1  ; RTX 사용 시
```

### Virtual Shadow Maps 설정

```ini
; DefaultEngine.ini
[/Script/Engine.RendererSettings]
r.Shadow.Virtual.Enable=1
r.Shadow.Virtual.ResolutionLodBiasDirectional=0
```

---

## 디버깅 및 프로파일링

### 시각화 명령어

```cpp
// Nanite 시각화
r.Nanite.Visualize.Overview        // 전체 개요
r.Nanite.Visualize.Triangles       // 삼각형 밀도
r.Nanite.Visualize.Clusters        // 클러스터 경계

// Lumen 시각화
r.Lumen.Visualize.Mode             // GI 시각화
r.Lumen.Visualize.CardPlacement    // 메시 카드 배치
r.Lumen.Visualize.SurfaceCache     // Surface Cache

// Virtual Shadow Maps 시각화
r.Shadow.Virtual.Visualize         // VSM 타일 시각화
```

### 통계

```cpp
// GPU Profiler 마커
stat Nanite          // Nanite 성능 통계
stat Lumen           // Lumen 성능 통계
stat ShadowRendering // 그림자 렌더링 통계
```

---

## 요약

| 기능 | 목적 | 핵심 기술 |
|------|------|----------|
| Nanite | 무제한 폴리곤 | 가상화 지오메트리, GPU 컬링 |
| Lumen | 동적 GI | 소프트웨어/하드웨어 RT, Surface Cache |
| VSM | 고품질 그림자 | 가상 텍스처, 클립맵 |
| TSR | 성능 확보 | 템포럴 업스케일링 |

다음 문서에서 각 시스템을 상세히 분석합니다.
