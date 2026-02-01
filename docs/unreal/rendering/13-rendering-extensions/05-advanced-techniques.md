# 고급 렌더링 기법

Compute Shader 활용, 비동기 처리, 멀티패스 렌더링 등 고급 기법을 다룹니다.

---

## 개요

고급 렌더링 기법은 GPU의 병렬 처리 능력을 최대한 활용하여 복잡한 효과를 구현합니다.

```
┌─────────────────────────────────────────────────────────────────┐
│                   고급 렌더링 기법 분류                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                  GPU Compute                            │    │
│  │  ┌───────────┐  ┌───────────┐  ┌───────────┐          │    │
│  │  │ 시뮬레이션│  │  컬링     │  │ 후처리    │          │    │
│  │  │ (물리,파티클)│ │ (GPU Driven)│ │ (필터링)  │          │    │
│  │  └───────────┘  └───────────┘  └───────────┘          │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                  멀티패스 렌더링                         │    │
│  │  ┌───────────┐  ┌───────────┐  ┌───────────┐          │    │
│  │  │ 캐스케이드│  │  MRT      │  │ 피드백    │          │    │
│  │  │ 처리      │  │           │  │ 루프      │          │    │
│  │  └───────────┘  └───────────┘  └───────────┘          │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                  비동기 처리                             │    │
│  │  ┌───────────┐  ┌───────────┐  ┌───────────┐          │    │
│  │  │ Async     │  │ Timeline  │  │ 멀티 큐   │          │    │
│  │  │ Compute   │  │ Semaphore │  │           │          │    │
│  │  └───────────┘  └───────────┘  └───────────┘          │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## GPU Compute 패턴

### Parallel Reduction

대량의 데이터를 병렬로 집계하는 패턴입니다.

```hlsl
// ParallelReduction.usf

groupshared float SharedData[THREADGROUP_SIZE];

[numthreads(THREADGROUP_SIZE, 1, 1)]
void ReductionCS(
    uint GroupIndex : SV_GroupIndex,
    uint3 GroupId : SV_GroupID,
    uint3 DispatchThreadId : SV_DispatchThreadID)
{
    // 초기 데이터 로드
    SharedData[GroupIndex] = InputBuffer[DispatchThreadId.x];
    GroupMemoryBarrierWithGroupSync();

    // 리덕션
    for (uint Stride = THREADGROUP_SIZE / 2; Stride > 0; Stride >>= 1)
    {
        if (GroupIndex < Stride)
        {
            SharedData[GroupIndex] += SharedData[GroupIndex + Stride];
        }
        GroupMemoryBarrierWithGroupSync();
    }

    // 결과 출력
    if (GroupIndex == 0)
    {
        OutputBuffer[GroupId.x] = SharedData[0];
    }
}
```

```
┌─────────────────────────────────────────────────────────────────┐
│                   Parallel Reduction 시각화                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Step 0: [1] [2] [3] [4] [5] [6] [7] [8]                       │
│             ╲ /     ╲ /     ╲ /     ╲ /                         │
│  Step 1:   [3]     [7]    [11]    [15]                         │
│               ╲   /           ╲   /                             │
│  Step 2:      [10]            [26]                              │
│                  ╲          /                                   │
│  Step 3:           [36]   ◀── 최종 합계                        │
│                                                                 │
│  복잡도: O(log N)                                               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Prefix Sum (Scan)

```hlsl
// PrefixSum.usf

groupshared float SharedData[THREADGROUP_SIZE * 2];

[numthreads(THREADGROUP_SIZE, 1, 1)]
void PrefixSumCS(uint GroupIndex : SV_GroupIndex)
{
    uint Offset = 1;

    // 데이터 로드
    SharedData[2 * GroupIndex] = InputBuffer[2 * GroupIndex];
    SharedData[2 * GroupIndex + 1] = InputBuffer[2 * GroupIndex + 1];

    // Up-sweep (Reduction)
    for (uint d = THREADGROUP_SIZE; d > 0; d >>= 1)
    {
        GroupMemoryBarrierWithGroupSync();

        if (GroupIndex < d)
        {
            uint ai = Offset * (2 * GroupIndex + 1) - 1;
            uint bi = Offset * (2 * GroupIndex + 2) - 1;
            SharedData[bi] += SharedData[ai];
        }
        Offset *= 2;
    }

    // 루트에 0 설정
    if (GroupIndex == 0)
        SharedData[THREADGROUP_SIZE * 2 - 1] = 0;

    // Down-sweep
    for (uint d = 1; d < THREADGROUP_SIZE * 2; d *= 2)
    {
        Offset >>= 1;
        GroupMemoryBarrierWithGroupSync();

        if (GroupIndex < d)
        {
            uint ai = Offset * (2 * GroupIndex + 1) - 1;
            uint bi = Offset * (2 * GroupIndex + 2) - 1;
            float t = SharedData[ai];
            SharedData[ai] = SharedData[bi];
            SharedData[bi] += t;
        }
    }

    GroupMemoryBarrierWithGroupSync();

    // 결과 출력
    OutputBuffer[2 * GroupIndex] = SharedData[2 * GroupIndex];
    OutputBuffer[2 * GroupIndex + 1] = SharedData[2 * GroupIndex + 1];
}
```

### GPU 정렬 (Bitonic Sort)

```hlsl
// BitonicSort.usf

groupshared uint SharedKeys[THREADGROUP_SIZE];

void CompareAndSwap(uint i, uint j, uint Dir)
{
    if ((SharedKeys[i] > SharedKeys[j]) == (Dir != 0))
    {
        uint Temp = SharedKeys[i];
        SharedKeys[i] = SharedKeys[j];
        SharedKeys[j] = Temp;
    }
}

[numthreads(THREADGROUP_SIZE, 1, 1)]
void BitonicSortCS(uint GroupIndex : SV_GroupIndex, uint3 GroupId : SV_GroupID)
{
    uint Offset = GroupId.x * THREADGROUP_SIZE;
    SharedKeys[GroupIndex] = InputBuffer[Offset + GroupIndex];
    GroupMemoryBarrierWithGroupSync();

    // Bitonic Sort
    for (uint k = 2; k <= THREADGROUP_SIZE; k <<= 1)
    {
        for (uint j = k >> 1; j > 0; j >>= 1)
        {
            uint ixj = GroupIndex ^ j;
            if (ixj > GroupIndex)
            {
                uint Dir = ((GroupIndex & k) != 0) ? 1 : 0;
                CompareAndSwap(GroupIndex, ixj, Dir);
            }
            GroupMemoryBarrierWithGroupSync();
        }
    }

    OutputBuffer[Offset + GroupIndex] = SharedKeys[GroupIndex];
}
```

---

## GPU Driven Rendering

### 인스턴스 컬링

```cpp
// C++ 설정
BEGIN_SHADER_PARAMETER_STRUCT(FGPUCullingParameters, )
    SHADER_PARAMETER_RDG_BUFFER_SRV(StructuredBuffer<FInstanceData>, InstanceBuffer)
    SHADER_PARAMETER_RDG_BUFFER_UAV(RWStructuredBuffer<FInstanceData>, VisibleInstances)
    SHADER_PARAMETER_RDG_BUFFER_UAV(RWBuffer<uint>, DrawIndirectArgs)
    SHADER_PARAMETER(FMatrix44f, ViewProjectionMatrix)
    SHADER_PARAMETER(FVector4f, FrustumPlanes, [6])
    SHADER_PARAMETER(uint32, InstanceCount)
END_SHADER_PARAMETER_STRUCT()
```

```hlsl
// GPUCulling.usf

StructuredBuffer<FInstanceData> InstanceBuffer;
RWStructuredBuffer<FInstanceData> VisibleInstances;
RWBuffer<uint> DrawIndirectArgs;
float4x4 ViewProjectionMatrix;
float4 FrustumPlanes[6];
uint InstanceCount;

bool IsSphereInFrustum(float3 Center, float Radius)
{
    for (int i = 0; i < 6; ++i)
    {
        float Distance = dot(FrustumPlanes[i].xyz, Center) + FrustumPlanes[i].w;
        if (Distance < -Radius)
            return false;
    }
    return true;
}

[numthreads(64, 1, 1)]
void CullingCS(uint3 DispatchThreadId : SV_DispatchThreadID)
{
    if (DispatchThreadId.x >= InstanceCount)
        return;

    FInstanceData Instance = InstanceBuffer[DispatchThreadId.x];

    // 프러스텀 컬링
    if (IsSphereInFrustum(Instance.BoundingCenter, Instance.BoundingRadius))
    {
        // 오클루전 컬링 (HZB)
        // ...

        // 가시 인스턴스 추가
        uint Index;
        InterlockedAdd(DrawIndirectArgs[1], 1, Index);  // InstanceCount++
        VisibleInstances[Index] = Instance;
    }
}
```

### Indirect Draw

```cpp
// C++에서 Indirect Draw 실행
void ExecuteIndirectDraw(FRHICommandList& RHICmdList)
{
    // DrawIndirectArgs 버퍼 구조:
    // [0] = IndexCountPerInstance
    // [1] = InstanceCount (GPU에서 설정)
    // [2] = StartIndexLocation
    // [3] = BaseVertexLocation
    // [4] = StartInstanceLocation

    RHICmdList.DrawIndexedIndirect(
        IndexBuffer,
        DrawIndirectArgsBuffer,
        0  // Offset
    );
}
```

---

## 멀티패스 렌더링

### 캐스케이드 블러

```cpp
// C++ 설정
void AddCascadeBlurPasses(
    FRDGBuilder& GraphBuilder,
    FRDGTextureRef InputTexture,
    FRDGTextureRef OutputTexture,
    int32 Iterations)
{
    FRDGTextureRef CurrentInput = InputTexture;

    for (int32 i = 0; i < Iterations; ++i)
    {
        // 다운샘플
        FRDGTextureDesc DownDesc = CurrentInput->Desc;
        DownDesc.Extent /= 2;
        FRDGTextureRef Downsampled = GraphBuilder.CreateTexture(
            DownDesc, TEXT("BlurDownsample"));

        AddDownsamplePass(GraphBuilder, CurrentInput, Downsampled);

        // 블러
        FRDGTextureRef Blurred = GraphBuilder.CreateTexture(
            DownDesc, TEXT("BlurResult"));

        AddGaussianBlurPass(GraphBuilder, Downsampled, Blurred);

        CurrentInput = Blurred;
    }

    // 업샘플 체인
    for (int32 i = Iterations - 1; i >= 0; --i)
    {
        FRDGTextureDesc UpDesc = CurrentInput->Desc;
        UpDesc.Extent *= 2;
        FRDGTextureRef Upsampled = (i == 0) ? OutputTexture :
            GraphBuilder.CreateTexture(UpDesc, TEXT("BlurUpsample"));

        AddUpsampleAndCombinePass(GraphBuilder, CurrentInput, Upsampled);

        CurrentInput = Upsampled;
    }
}
```

```
┌─────────────────────────────────────────────────────────────────┐
│                    캐스케이드 블러 구조                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Downsample Chain:                                              │
│  ┌────────┐   ┌────────┐   ┌────────┐   ┌────────┐            │
│  │ 1920×  │──▶│ 960×   │──▶│ 480×   │──▶│ 240×   │            │
│  │ 1080   │   │ 540    │   │ 270    │   │ 135    │            │
│  └────────┘   └────────┘   └────────┘   └────────┘            │
│       │            │            │            │                  │
│       │            │            │            │                  │
│       │            │            │            ▼                  │
│       │            │            │       ┌────────┐              │
│       │            │            │       │ Blur   │              │
│       │            │            │       └────┬───┘              │
│       │            │            │            │                  │
│  Upsample Chain:   │            │            │                  │
│       │            │            │            ▼                  │
│       │            │            │       ┌────────┐              │
│       │            │            └──────▶│ + Add  │              │
│       │            │                    └────┬───┘              │
│       │            │                         │                  │
│       │            │                         ▼                  │
│       │            │                    ┌────────┐              │
│       │            └───────────────────▶│ + Add  │              │
│       │                                 └────┬───┘              │
│       │                                      │                  │
│       │                                      ▼                  │
│       │                                 ┌────────┐              │
│       └────────────────────────────────▶│ Output │              │
│                                         └────────┘              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### MRT (Multiple Render Targets)

```hlsl
// MRT 출력
struct FMRTOutput
{
    float4 Target0 : SV_Target0;  // Albedo
    float4 Target1 : SV_Target1;  // Normal
    float4 Target2 : SV_Target2;  // Metallic/Roughness
    float4 Target3 : SV_Target3;  // Emissive
};

void MainPS(
    FVertexOutput Input,
    out FMRTOutput Output)
{
    Output.Target0 = float4(Albedo, 1);
    Output.Target1 = float4(Normal * 0.5 + 0.5, 1);
    Output.Target2 = float4(Metallic, Roughness, AO, 1);
    Output.Target3 = float4(Emissive, 1);
}
```

```cpp
// C++ MRT 설정
FMyMRTParameters* Parameters = GraphBuilder.AllocParameters<FMyMRTParameters>();
Parameters->RenderTargets[0] = FRenderTargetBinding(AlbedoRT, ERenderTargetLoadAction::EClear);
Parameters->RenderTargets[1] = FRenderTargetBinding(NormalRT, ERenderTargetLoadAction::EClear);
Parameters->RenderTargets[2] = FRenderTargetBinding(MetallicRT, ERenderTargetLoadAction::EClear);
Parameters->RenderTargets[3] = FRenderTargetBinding(EmissiveRT, ERenderTargetLoadAction::EClear);
```

---

## 비동기 Compute

### Async Compute 패스

```cpp
// RDG에서 Async Compute 사용
GraphBuilder.AddPass(
    RDG_EVENT_NAME("AsyncComputePass"),
    Parameters,
    ERDGPassFlags::AsyncCompute,  // Async 플래그
    [Parameters, ComputeShader](FRHIComputeCommandList& RHICmdList)
    {
        // Graphics 큐와 병렬 실행
        FComputeShaderUtils::Dispatch(RHICmdList, ComputeShader, *Parameters, GroupCount);
    });
```

```
┌─────────────────────────────────────────────────────────────────┐
│                    Async Compute 타이밍                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Without Async:                                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │ Graphics │ Compute │ Graphics │ Compute │ Graphics    │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                 │
│  With Async:                                                    │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │ Graphics ─────────▶ Graphics ─────────▶ Graphics       │    │
│  ├─────────────────────────────────────────────────────────┤    │
│  │    Compute ──────────▶    Compute ──────────▶          │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                 │
│  → Compute가 Graphics와 병렬 실행되어 총 시간 단축             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 동기화 포인트

```cpp
// 명시적 동기화가 필요한 경우
// (RDG가 대부분 자동 처리)

// Graphics → Compute 의존성
// 텍스처를 먼저 Graphics에서 생성 후 Compute에서 읽기

// Compute → Graphics 의존성
// Compute 결과를 Graphics에서 렌더링
```

---

## 템포럴 처리

### History Buffer 관리

```cpp
// 프레임 간 히스토리 유지
class FTemporalHistory
{
public:
    TRefCountPtr<IPooledRenderTarget> CurrentFrame;
    TRefCountPtr<IPooledRenderTarget> PreviousFrame;

    void SwapBuffers()
    {
        Swap(CurrentFrame, PreviousFrame);
    }
};

// RDG에서 사용
void AddTemporalPass(
    FRDGBuilder& GraphBuilder,
    FTemporalHistory& History,
    FRDGTextureRef CurrentInput)
{
    FRDGTextureRef HistoryTexture = History.PreviousFrame.IsValid() ?
        GraphBuilder.RegisterExternalTexture(History.PreviousFrame) :
        GraphBuilder.CreateTexture(...);

    // 현재 + 이전 프레임 조합
    FMyTemporalParameters* Params = GraphBuilder.AllocParameters<...>();
    Params->CurrentFrame = CurrentInput;
    Params->PreviousFrame = HistoryTexture;

    // 결과 추출
    FRDGTextureRef OutputTexture = GraphBuilder.CreateTexture(...);

    GraphBuilder.AddPass(...);

    // 다음 프레임용 저장
    GraphBuilder.QueueTextureExtraction(OutputTexture, &History.CurrentFrame);
}
```

### 리프로젝션

```hlsl
// TemporalReprojection.usf

float4x4 PrevViewProjection;
float4x4 InvViewProjection;
Texture2D VelocityTexture;
Texture2D HistoryTexture;
Texture2D CurrentTexture;

float4 MainPS(float2 UV : TEXCOORD0) : SV_Target0
{
    // 현재 픽셀의 월드 위치 재구성
    float Depth = SceneDepthTexture.Sample(PointSampler, UV).r;
    float4 ClipPos = float4(UV * 2 - 1, Depth, 1);
    ClipPos.y = -ClipPos.y;
    float4 WorldPos = mul(ClipPos, InvViewProjection);
    WorldPos /= WorldPos.w;

    // 이전 프레임 UV 계산
    float4 PrevClipPos = mul(float4(WorldPos.xyz, 1), PrevViewProjection);
    float2 PrevUV = PrevClipPos.xy / PrevClipPos.w * 0.5 + 0.5;
    PrevUV.y = 1 - PrevUV.y;

    // 또는 Velocity Buffer 사용
    float2 Velocity = VelocityTexture.Sample(PointSampler, UV).xy;
    PrevUV = UV - Velocity;

    // 히스토리 샘플링 (범위 체크)
    if (all(PrevUV >= 0) && all(PrevUV <= 1))
    {
        float4 HistoryColor = HistoryTexture.Sample(LinearSampler, PrevUV);
        float4 CurrentColor = CurrentTexture.Sample(PointSampler, UV);

        // 블렌딩 (예: 90% 히스토리)
        return lerp(CurrentColor, HistoryColor, 0.9);
    }

    return CurrentTexture.Sample(PointSampler, UV);
}
```

---

## Indirect Dispatch

### 동적 작업 크기

```cpp
// 조건부 Dispatch (GPU에서 작업량 결정)
BEGIN_SHADER_PARAMETER_STRUCT(FIndirectDispatchParameters, )
    SHADER_PARAMETER_RDG_BUFFER_SRV(Buffer<uint>, IndirectArgs)
    // ... 다른 파라미터
END_SHADER_PARAMETER_STRUCT()

void AddIndirectDispatchPass(...)
{
    // IndirectArgs 버퍼: [GroupCountX, GroupCountY, GroupCountZ]
    // 이전 패스에서 GPU가 값을 설정

    GraphBuilder.AddPass(
        RDG_EVENT_NAME("IndirectDispatch"),
        Parameters,
        ERDGPassFlags::Compute,
        [Parameters, ComputeShader, IndirectArgsBuffer](FRHIComputeCommandList& RHICmdList)
        {
            SetComputePipelineState(RHICmdList, ComputeShader.GetComputeShader());
            SetShaderParameters(RHICmdList, ComputeShader, ComputeShader.GetComputeShader(), *Parameters);

            // Indirect Dispatch
            RHICmdList.DispatchIndirectComputeShader(IndirectArgsBuffer, 0);
        });
}
```

---

## 요약

| 기법 | 용도 | 성능 이점 |
|------|------|----------|
| Parallel Reduction | 데이터 집계 | O(log N) |
| GPU Culling | 가시성 판정 | CPU 오프로드 |
| Async Compute | 병렬 처리 | 파이프라인 활용 |
| Temporal | 프레임 누적 | 품질 향상 |
| Indirect | 동적 작업량 | GPU 자율성 |

---

## 참고 자료

- [GPU Gems 3 - Parallel Prefix Sum](https://developer.nvidia.com/gpugems/gpugems3/)
- [GPU-Based Rendering](https://advances.realtimerendering.com/)
- [Async Compute in UE](https://docs.unrealengine.com/async-compute/)
