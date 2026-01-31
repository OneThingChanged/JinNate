# Chapter 03: 렌더링 메커니즘

> 원문: https://www.cnblogs.com/timlly/p/14588598.html
> 시리즈: 剖析虚幻渲染体系 (Unreal 렌더링 시스템 분석)

---

## 목차

1. [핵심 클래스](#1-핵심-클래스)
2. [메시 드로잉 파이프라인 진화](#2-메시-드로잉-파이프라인-진화)
3. [씬 가시성 및 수집](#3-씬-가시성-및-수집)
4. [FMeshBatch 구조](#4-fmeshbatch-구조)
5. [FMeshPassProcessor 아키텍처](#5-fmeshpassprocessor-아키텍처)
6. [명령 생성 및 정렬](#6-명령-생성-및-정렬)
7. [FMeshDrawCommand 구조](#7-fmeshdrawcommand-구조)
8. [프레임 렌더링 흐름](#8-프레임-렌더링-흐름)
9. [성능 최적화](#9-성능-최적화)

---

## 1. 핵심 클래스

![UE4 렌더링 개요](./images/ch03/1617944-20210319203832841-1939790306.jpg)
*UE4 렌더링 시스템 개요*

### 주요 클래스 관계

| 클래스 | 역할 |
|--------|------|
| **UPrimitiveComponent** | CPU 측 렌더링 가능 객체 기본 클래스 |
| **FPrimitiveSceneProxy** | UPrimitiveComponent의 렌더링 스레드 미러 |
| **FScene** | 렌더러 모듈에서의 월드 표현 |
| **FSceneView** | FScene 내의 단일 뷰포트 |
| **FSceneRenderer** | 프레임별 렌더러 (임시 데이터 캡슐화) |
| **FMeshBatch** | 머티리얼과 버텍스 팩토리를 공유하는 메시 요소 컬렉션 |
| **FMeshDrawCommand** | 단일 패스 드로우 콜 상태의 완전한 설명 |

```
UWorld
    │
    └─→ FScene (렌더러 표현)
            │
            ├─→ FSceneView[] (뷰포트들)
            │
            └─→ FPrimitiveSceneProxy[] (프리미티브들)
                    │
                    └─→ FMeshBatch[] → FMeshDrawCommand[]
```

---

## 2. 메시 드로잉 파이프라인 진화

### 2.1 UE4.22 이전 아키텍처

![이전 파이프라인](./images/ch03/1617944-20210319203846059-346871767.jpg)
*UE4.22 이전 메시 드로잉 파이프라인*

```
FMeshBatch ──→ DrawingPolicy ──→ RHI Commands
```

**문제점:**
- 캐싱 기회 부족
- 재정렬 최적화 불가

### 2.2 UE4.22+ 아키텍처

![새 파이프라인](./images/ch03/1617944-20210319203908808-1155568886.jpg)
*UE4.22+ 메시 드로잉 파이프라인 - FMeshDrawCommand 도입*

> "재구조화된 파이프라인은 FMeshBatch와 RHI 명령 사이에 FMeshDrawCommand를 중간 표현으로 도입하여, 우수한 명령 캐싱과 정렬 유연성을 가능하게 했습니다."

```
FMeshBatch ──→ FMeshDrawCommand ──→ RHI Commands
                     │
                     └─→ 캐싱 가능!
```

**주요 개선사항:**

| 기능 | 설명 |
|------|------|
| **RTX 레이트레이싱** | 하드웨어 가속 |
| **GPU-driven 렌더링** | GPU 주도 파이프라인 |
| **정적 메시 캐싱** | 씬 로드 시 사전 캐싱 |

---

## 3. 씬 가시성 및 수집

### 3.1 GatherDynamicMeshElements

![가시성 수집](./images/ch03/1617944-20210319203940982-1545653618.png)
*동적 메시 요소 수집 과정*

```cpp
void FSceneRenderer::GatherDynamicMeshElements(
    TArray<FViewInfo>& InViews,
    const FScene* InScene,
    FMeshElementCollector& Collector)
{
    for (int32 PrimitiveIndex = 0; PrimitiveIndex < NumPrimitives; ++PrimitiveIndex)
    {
        if (ViewMask != 0)  // 가려지지 않은 객체만
        {
            FPrimitiveSceneInfo* PrimitiveSceneInfo =
                InScene->Primitives[PrimitiveIndex];

            // 핵심 수집 호출
            PrimitiveSceneInfo->Proxy->GetDynamicMeshElements(
                InViewFamily.Views,
                InViewFamily,
                ViewMaskFinal,
                Collector);
        }
    }
}
```

### 3.2 Relevance 계산

![Relevance 계산](./images/ch03/1617944-20210319204017205-991200520.png)
*메시 배치 Relevance 계산*

> "이 함수는 각 보이는 배치에 대해 어떤 MeshPass 참조가 발생하는지 계산합니다."

---

## 4. FMeshBatch 구조

![FMeshBatch 구조](./images/ch03/1617944-20210319204038916-909213164.jpg)
*FMeshBatch 내부 구조*

```cpp
struct FMeshBatch
{
    // 메시 요소 배열
    TArray<FMeshBatchElement> Elements;

    // 공유 리소스
    const FVertexFactory* VertexFactory;
    const FMaterialRenderProxy* MaterialRenderProxy;

    // 패스별 플래그
    uint32 CastShadow : 1;
    uint32 bUseForMaterial : 1;
    uint32 bUseForDepthPass : 1;
    uint32 bUseAsOccluder : 1;
};
```

---

## 5. FMeshPassProcessor 아키텍처

### 5.1 SetupMeshPass

![MeshPassProcessor](./images/ch03/1617944-20210319204048965-266989101.jpg)
*FMeshPassProcessor 처리 과정*

```cpp
void FSceneRenderer::SetupMeshPass(FViewInfo& View, FViewCommands& ViewCommands)
{
    for (int32 PassIndex = 0; PassIndex < EMeshPass::Num; PassIndex++)
    {
        FMeshPassProcessor* MeshPassProcessor =
            CreateFunction(Scene, &View, nullptr);

        Pass.DispatchPassSetup(...);
    }
}
```

### 5.2 패스 타입 (EMeshPass)

| 카테고리 | 패스들 |
|----------|--------|
| **기본** | DepthPass, BasePass, SkyPass |
| **그림자** | CSMShadowDepth |
| **반투명** | Translucency (Standard, AfterDOF, All) |
| **특수** | CustomDepth, Velocity, Distortion |

### 5.3 FMeshPassProcessor 책임

| 책임 | 설명 |
|------|------|
| **패스 필터링** | 관련 없는 배치 제외 |
| **셰이더 선택** | 적절한 셰이더 설정 |
| **렌더 상태 구성** | 블렌드, 뎁스 등 |
| **드로우 파라미터** | 드로우 콜 매개변수 |

---

## 6. 명령 생성 및 정렬

### 6.1 FMeshDrawCommandSortKey

![정렬 키](./images/ch03/1617944-20210319204117391-930676450.png)
*FMeshDrawCommandSortKey 구조*

```cpp
class FMeshDrawCommandSortKey
{
    union {
        uint64 PackedData;

        // BasePass 정렬
        struct {
            uint64 VertexShaderHash : 16;
            uint64 PixelShaderHash : 32;
            uint64 Masked : 16;
        } BasePass;

        // 반투명 정렬
        struct {
            uint64 MeshIdInPrimitive : 16;
            uint64 Distance : 32;
            uint64 Priority : 16;
        } Translucent;
    };
};
```

### 6.2 정렬 우선순위

| 패스 | 정렬 순서 |
|------|-----------|
| **BasePass** | Masked > Pixel Shader > Vertex Shader |
| **Translucent** | Priority > Distance > Mesh ID |

### 6.3 명령 생성 태스크

![명령 생성](./images/ch03/1617944-20210319204128286-1978093245.png)
*드로우 명령 생성 태스크 흐름*

```cpp
void GenerateDynamicMeshDrawCommands(...)
{
    for (int32 MeshIndex = 0; MeshIndex < NumDynamicMeshBatches; ++MeshIndex)
    {
        PassMeshProcessor->AddMeshBatch(...);
    }

    // 정렬
    VisibleCommands.Sort(FCompareFMeshDrawCommands());

    if (bUseGPUScene)
    {
        BuildMeshDrawCommandPrimitiveIdBuffer(...);
    }
}
```

---

## 7. FMeshDrawCommand 구조

![FMeshDrawCommand](./images/ch03/1617944-20210319204138477-1053404240.png)
*FMeshDrawCommand 구조*

```cpp
class FMeshDrawCommand
{
    FMeshDrawShaderBindings ShaderBindings;
    FVertexInputStreamArray VertexStreams;
    FRHIIndexBuffer* IndexBuffer;

    FGraphicsMinimalPipelineStateId CachedPipelineId;

    uint32 FirstIndex;
    uint32 NumPrimitives;
    uint32 NumInstances;

    // 동적 인스턴싱 매칭
    bool MatchesForDynamicInstancing(const FMeshDrawCommand& Rhs) const;
};
```

| 구성요소 | 설명 |
|----------|------|
| **ShaderBindings** | 셰이더 파라미터 바인딩 |
| **VertexStreams** | 버텍스 입력 스트림 |
| **CachedPipelineId** | PSO 캐시 ID |
| **NumPrimitives** | 그릴 프리미티브 수 |

---

## 8. 프레임 렌더링 흐름

### 전체 파이프라인

![렌더링 흐름](./images/ch03/1617944-20210319204156161-1637874484.png)
*프레임 렌더링 전체 흐름*

```
┌──────────────────────────────────────────────────────────────┐
│                    Frame Rendering Flow                       │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  1. InitViews                                                │
│     └─→ 가시성 컬링, 동적 요소 수집                           │
│                     │                                        │
│                     ▼                                        │
│  2. SetupMeshPass                                            │
│     └─→ 각 활성 패스에 대해 프로세서 생성                      │
│                     │                                        │
│                     ▼                                        │
│  3. Parallel Task Execution                                  │
│     └─→ 드로우 명령 생성, 정렬, 캐싱                          │
│                     │                                        │
│                     ▼                                        │
│  4. State Bucket Organization                                │
│     └─→ 동일한 PSO/바인딩을 가진 명령 병합                     │
│                     │                                        │
│                     ▼                                        │
│  5. Submission                                               │
│     └─→ GPU 실행을 위한 RHI 명령 큐잉                         │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

### 단계별 상세

| 단계 | 함수 | 설명 |
|------|------|------|
| 1 | `InitViews()` | 프러스텀 컬링, 오클루전 컬링 |
| 2 | `SetupMeshPass()` | EMeshPass별 프로세서 생성 |
| 3 | `DispatchPassSetup()` | 병렬 명령 생성 |
| 4 | State Bucket | 해시 기반 명령 병합 |
| 5 | `SubmitMeshDrawCommands()` | RHI 제출 |

---

## 9. 성능 최적화

### 9.1 캐싱 전략

![최적화](./images/ch03/1617944-20210319204219614-13890387.png)
*드로우 콜 최적화 결과*

> "Fortnite 씬 테스트에서 새 파이프라인이 DepthPass와 BasePass 드로우 콜을 여러 배 감소시켰습니다."

### 9.2 핵심 최적화 기법

| 기법 | 설명 |
|------|------|
| **정적 메시 사전 베이킹** | 로드 시 명령 캐싱 |
| **PSO 캐싱** | `FGraphicsMinimalPipelineStateId` |
| **동적 인스턴싱** | 상태 버킷 해싱 |
| **Primitive ID 버퍼** | GPU Scene 호환 |

### 9.3 State Bucket 해싱

```
┌─────────────────────────────────────────────┐
│           State Bucket Hashing              │
├─────────────────────────────────────────────┤
│                                             │
│  Command A ─┐                               │
│             ├─→ Same PSO/Bindings ─→ Merge  │
│  Command B ─┘                               │
│                                             │
│  Command C ─────→ Different ─→ Separate     │
│                                             │
└─────────────────────────────────────────────┘
```

### 9.4 디버그 콘솔 변수

| CVar | 용도 |
|------|------|
| `r.MeshDrawCommandsParallelPassSetup` | 병렬 패스 설정 |
| `r.DoLazyStaticMeshUpdate` | 지연 정적 메시 업데이트 |

---

## 요약 다이어그램

```
┌────────────────────────────────────────────────────────────────────┐
│                    UE4 Mesh Drawing Pipeline                        │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│  UPrimitiveComponent                                               │
│        │                                                           │
│        ▼                                                           │
│  FPrimitiveSceneProxy                                              │
│        │                                                           │
│        │ GetDynamicMeshElements()                                  │
│        ▼                                                           │
│  ┌─────────────┐                                                   │
│  │  FMeshBatch │ ← 머티리얼, 버텍스 팩토리, LOD 정보               │
│  └─────────────┘                                                   │
│        │                                                           │
│        │ FMeshPassProcessor::AddMeshBatch()                        │
│        ▼                                                           │
│  ┌──────────────────┐                                              │
│  │ FMeshDrawCommand │ ← 셰이더 바인딩, PSO, 드로우 파라미터        │
│  └──────────────────┘                                              │
│        │                                                           │
│        │ 정렬 (FMeshDrawCommandSortKey)                            │
│        │ 병합 (State Bucket)                                       │
│        ▼                                                           │
│  ┌──────────────────┐                                              │
│  │   RHI Commands   │ ← 최종 GPU 명령                              │
│  └──────────────────┘                                              │
│        │                                                           │
│        ▼                                                           │
│      GPU 실행                                                       │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

---

## 참고 자료

- 원문: https://www.cnblogs.com/timlly/p/14588598.html
- UE4 Source: Engine/Source/Runtime/Renderer/
- Epic Games 기술 블로그
