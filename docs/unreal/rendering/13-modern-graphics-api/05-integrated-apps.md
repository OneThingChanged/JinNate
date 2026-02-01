# 통합 응용

RHI 추상화, 멀티스레드 렌더링, GPU-Driven 렌더링을 설명합니다.

---

## RHI (Render Hardware Interface)

### UE의 RHI 구조

```
┌─────────────────────────────────────────────────────────────────┐
│                    UE RHI 아키텍처                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    Game/Renderer                         │   │
│  │              (플랫폼 독립적 코드)                        │   │
│  └───────────────────────┬─────────────────────────────────┘   │
│                          │                                      │
│                          ▼                                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                     FDynamicRHI                          │   │
│  │                   (추상 인터페이스)                       │   │
│  └───────────────────────┬─────────────────────────────────┘   │
│                          │                                      │
│        ┌─────────────────┼─────────────────┐                   │
│        ▼                 ▼                 ▼                   │
│  ┌───────────┐    ┌───────────┐    ┌───────────┐              │
│  │FD3D12Dyna │    │FVulkanDyn │    │FMetalDyna │              │
│  │  micRHI   │    │  amicRHI  │    │  micRHI   │              │
│  └─────┬─────┘    └─────┬─────┘    └─────┬─────┘              │
│        │                │                │                      │
│        ▼                ▼                ▼                      │
│  ┌───────────┐    ┌───────────┐    ┌───────────┐              │
│  │DirectX 12 │    │  Vulkan   │    │   Metal   │              │
│  └───────────┘    └───────────┘    └───────────┘              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### RHI 주요 인터페이스

```cpp
// RHI 리소스 생성
class FDynamicRHI
{
    // 텍스처 생성
    virtual FTextureRHIRef RHICreateTexture(...) = 0;

    // 버퍼 생성
    virtual FBufferRHIRef RHICreateBuffer(...) = 0;

    // 셰이더 생성
    virtual FVertexShaderRHIRef RHICreateVertexShader(...) = 0;
    virtual FPixelShaderRHIRef RHICreatePixelShader(...) = 0;

    // 파이프라인 상태 생성
    virtual FGraphicsPipelineStateRHIRef RHICreateGraphicsPipelineState(...) = 0;

    // 커맨드 실행
    virtual void RHISubmitCommandLists(...) = 0;
};
```

### RHI Command List

```cpp
// RHI 커맨드 기록
void RenderScene(FRHICommandList& RHICmdList)
{
    // PSO 설정
    RHICmdList.SetGraphicsPipelineState(PSO);

    // 리소스 바인딩
    RHICmdList.SetShaderResourceViewParameter(ShaderRHI, SRV);
    RHICmdList.SetUniformBufferParameter(ShaderRHI, UBO);

    // 드로우
    RHICmdList.DrawIndexedPrimitive(IndexBuffer, 0, 0, NumVertices, 0, NumTriangles, 1);
}
```

---

## 멀티스레드 렌더링

### 병렬 커맨드 빌드

```
┌─────────────────────────────────────────────────────────────────┐
│                    멀티스레드 커맨드 빌드                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  싱글스레드 (레거시):                                           │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Thread 0: [Build All Commands] → Submit                │   │
│  │                                                         │   │
│  │  시간 ──────────────────────────────────▶              │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  멀티스레드 (현대):                                             │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Thread 0: [Build Shadows ]                             │   │
│  │  Thread 1: [Build GBuffer ]  → Merge → Submit          │   │
│  │  Thread 2: [Build Lighting]                             │   │
│  │  Thread 3: [Build PostFX  ]                             │   │
│  │                                                         │   │
│  │  시간 ─────────────▶                                   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  효과: D3D12에서 ~31% 프레임 타임 감소                          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### UE의 Parallel Command List

```cpp
// 병렬 커맨드 빌드
void RenderBasePass(FRHICommandListImmediate& RHICmdList)
{
    // 병렬 태스크 시작
    FParallelCommandListSet ParallelCommandLists(...);

    ParallelFor(NumMeshBatches, [&](int32 Index) {
        // 각 스레드에서 독립적으로 커맨드 빌드
        FRHICommandList* CmdList = ParallelCommandLists.NewParallelCommandList();

        DrawMeshBatch(*CmdList, MeshBatches[Index]);
    });

    // 병합 및 제출
    ParallelCommandLists.Commit();
}
```

---

## Async Compute

### 병렬 큐 활용

```
┌─────────────────────────────────────────────────────────────────┐
│                    Async Compute 활용                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Graphics Queue                                                 │
│  ├──── Shadow Pass ────├──── GBuffer ────├──── Lighting ────│  │
│                                                                 │
│  Compute Queue (병렬)                                           │
│       └──── SSAO ────┘   └──── Blur ────┘                      │
│                                                                 │
│  동기화 포인트:                                                 │
│  • SSAO는 Depth 완료 후 시작                                   │
│  • Lighting은 SSAO 완료 후 사용                                │
│                                                                 │
│  이점:                                                          │
│  • GPU 활용률 증가                                             │
│  • 총 프레임 시간 단축                                         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## GPU-Driven 렌더링

### 개념

GPU-Driven 렌더링은 컬링과 드로우 콜 생성을 GPU에서 수행합니다.

```
┌─────────────────────────────────────────────────────────────────┐
│                    GPU-Driven 파이프라인                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  기존 방식 (CPU-Driven):                                        │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  CPU: Frustum Cull → Occlusion Cull → Draw Calls       │   │
│  │         ↓                                               │   │
│  │  GPU: Execute Draw Calls                                │   │
│  │                                                         │   │
│  │  문제: Draw Call 수에 비례한 CPU 비용                   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  GPU-Driven:                                                    │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  CPU: 전체 씬 데이터 업로드 (한 번)                     │   │
│  │         ↓                                               │   │
│  │  GPU (Compute):                                         │   │
│  │  ├── Frustum Culling                                    │   │
│  │  ├── Cluster Culling                                    │   │
│  │  ├── Triangle Culling                                   │   │
│  │  ├── Occlusion Culling (HiZ)                           │   │
│  │  └── Indirect Draw Arguments 생성                       │   │
│  │         ↓                                               │   │
│  │  GPU (Graphics):                                        │   │
│  │  └── ExecuteIndirect (단일 호출로 전체 씬)             │   │
│  │                                                         │   │
│  │  이점: Draw Call 수와 무관한 CPU 비용                   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 컬링 기법

```
┌─────────────────────────────────────────────────────────────────┐
│                    GPU 컬링 기법                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Frustum Culling                                             │
│     └── 뷰 프러스텀 외부 오브젝트 제거                         │
│                                                                 │
│  2. Cluster/Meshlet Culling                                     │
│     └── 메시를 작은 클러스터로 분할, 클러스터 단위 컬링        │
│                                                                 │
│  3. Triangle Culling                                            │
│     ├── Zero-Area: 면적 0인 삼각형 제거                        │
│     ├── Small-Area: 1픽셀 미만 삼각형 제거                     │
│     ├── Backface: 뒷면 삼각형 제거                             │
│     └── Degenerate: 퇴화 삼각형 제거                           │
│                                                                 │
│  4. Occlusion Culling (HiZ)                                     │
│     └── 이전 프레임 깊이로 가려진 오브젝트 제거               │
│                                                                 │
│  5. Contribution Culling                                        │
│     └── 화면에 기여가 미미한 오브젝트 제거                     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### ExecuteIndirect

```cpp
// GPU에서 생성된 인자로 간접 드로우
struct IndirectDrawArgs
{
    uint32 IndexCountPerInstance;
    uint32 InstanceCount;
    uint32 StartIndexLocation;
    int32 BaseVertexLocation;
    uint32 StartInstanceLocation;
};

// 컴퓨트 셰이더가 IndirectArgsBuffer를 채움
// ...

// 단일 호출로 전체 씬 렌더링
commandList->ExecuteIndirect(
    commandSignature,
    maxCommandCount,      // 최대 드로우 수
    indirectArgsBuffer,   // GPU가 생성한 인자
    0,
    countBuffer,          // 실제 드로우 수 (GPU 결정)
    0
);
```

### Nanite의 GPU-Driven

UE5의 Nanite는 GPU-Driven 렌더링의 극단적인 구현입니다.

```
┌─────────────────────────────────────────────────────────────────┐
│                    Nanite GPU-Driven                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. 메시를 Cluster (128 삼각형)로 분할                         │
│                                                                 │
│  2. GPU에서 Cluster 단위 LOD 선택                              │
│                                                                 │
│  3. GPU에서 Cluster 컬링                                        │
│     ├── Frustum                                                │
│     ├── Occlusion (Two-Pass HiZ)                               │
│     └── Backface                                               │
│                                                                 │
│  4. Software Rasterization (작은 삼각형)                        │
│     └── Compute 셰이더로 Visibility Buffer 생성               │
│                                                                 │
│  5. Hardware Rasterization (큰 삼각형)                          │
│     └── 기존 파이프라인 사용                                   │
│                                                                 │
│  결과: 수십억 개 삼각형을 실시간 렌더링                        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 프로파일링

### 성능 분석 도구

| 도구 | 벤더 | 주요 기능 |
|------|------|----------|
| **PIX** | Microsoft | D3D12 프레임 분석 |
| **RenderDoc** | 오픈소스 | 범용 프레임 캡처 |
| **Nsight** | NVIDIA | NVIDIA GPU 분석 |
| **RGP** | AMD | AMD GPU 분석 |

### 핵심 메트릭

```
┌─────────────────────────────────────────────────────────────────┐
│                    성능 분석 메트릭                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  GPU 시간 분석:                                                 │
│  • Pass별 시간 (Shadow, GBuffer, Lighting, PostFX)             │
│  • 셰이더 실행 시간                                            │
│  • 배리어/동기화 대기 시간                                     │
│                                                                 │
│  GPU 점유율:                                                    │
│  • Wave/Warp 실행 상태                                         │
│  • ALU vs Memory 바운드                                        │
│  • 레지스터 사용량                                             │
│                                                                 │
│  캐시 효율성:                                                   │
│  • L1/L2 캐시 히트율                                           │
│  • 텍스처 캐시 히트율                                          │
│                                                                 │
│  대역폭:                                                        │
│  • 메모리 읽기/쓰기 대역폭                                     │
│  • 텍스처 샘플링 대역폭                                        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 참고 자료

- [DirectX 12 Programming Guide](https://docs.microsoft.com/en-us/windows/win32/direct3d12/)
- [Vulkan Tutorial](https://vulkan-tutorial.com/)
- [Metal Best Practices Guide](https://developer.apple.com/documentation/metal/)
- [GPU-Driven Rendering (SIGGRAPH)](https://advances.realtimerendering.com/)
- [원본 문서 (timlly)](https://www.cnblogs.com/timlly/p/15680064.html)
