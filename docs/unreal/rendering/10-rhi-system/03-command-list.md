# 03. 커맨드 리스트

RHI 커맨드 리스트의 구조, 인코딩, 제출 메커니즘을 분석합니다.

![FRHICommand 클래스 계층](../images/ch09/1617944-20210818142301582-67317422.jpg)

*FRHIResource, FRHICommand, IRHICommandContext 클래스 계층과 플랫폼별 컨텍스트*

---

## 커맨드 리스트 개요

### 개념

```
┌─────────────────────────────────────────────────────────────────┐
│                    커맨드 리스트 개념                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  커맨드 리스트란?                                               │
│  - GPU에게 보낼 명령어들의 목록                                 │
│  - CPU에서 기록, GPU에서 실행                                   │
│  - 병렬 기록 가능 (Modern API)                                  │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  CPU (Render Thread)                                    │   │
│  │                                                         │   │
│  │  FRHICommandList cmdList;                               │   │
│  │  cmdList.SetPipelineState(PSO);                         │   │
│  │  cmdList.SetTexture(0, Texture);                        │   │
│  │  cmdList.DrawPrimitive(0, 100, 1);                      │   │
│  │  cmdList.SetTexture(0, Texture2);                       │   │
│  │  cmdList.DrawPrimitive(0, 50, 1);                       │   │
│  │                                                         │   │
│  └────────────────────────┬────────────────────────────────┘   │
│                           │ Submit                              │
│                           ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  GPU (Command Queue)                                    │   │
│  │                                                         │   │
│  │  ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐         │   │
│  │  │SetPSO│→│SetTex│→│ Draw │→│SetTex│→│ Draw │         │   │
│  │  └──────┘ └──────┘ └──────┘ └──────┘ └──────┘         │   │
│  │                                                         │   │
│  │  순차 실행                                               │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 커맨드 리스트 계층

```cpp
// 커맨드 리스트 기본 클래스
class FRHICommandListBase
{
protected:
    // 커맨드 버퍼
    FMemStackBase CommandBuffer;

    // 현재 상태 추적
    FGraphicsPipelineStateRHIRef CachedGraphicsPSO;
    FComputePipelineStateRHIRef CachedComputePSO;

public:
    // 플러시
    void Flush();
};

// Immediate 커맨드 리스트
class FRHICommandList : public FRHICommandListBase
{
public:
    // 즉시 모드: 기록과 동시에 제출 가능
    // 단일 스레드에서 사용

    void BeginRenderPass(const FRHIRenderPassInfo& Info);
    void EndRenderPass();

    void SetGraphicsPipelineState(FRHIGraphicsPipelineState* PSO);
    void SetShaderTexture(FRHIShader* Shader, uint32 Index, FRHITexture* Texture);
    void DrawPrimitive(uint32 BaseVertexIndex, uint32 NumPrimitives, uint32 NumInstances);
};

// Compute 전용 커맨드 리스트
class FRHIComputeCommandList : public FRHICommandListBase
{
public:
    void SetComputePipelineState(FRHIComputePipelineState* PSO);
    void SetShaderUAV(uint32 Index, FRHIUnorderedAccessView* UAV);
    void DispatchComputeShader(uint32 X, uint32 Y, uint32 Z);
};

// 병렬 커맨드 리스트
class FRHIParallelCommandList
{
    // 여러 스레드에서 병렬로 커맨드 기록
    TArray<FRHICommandList*> ParallelCommandLists;

public:
    FRHICommandList* AcquireCommandList();
    void ReleaseCommandList(FRHICommandList* CmdList);
    void SubmitAll();
};
```

---

## 렌더 패스

![서브패스와 메모리](../images/ch09/1617944-20210818142400565-369905116.jpg)

*Unextended OpenGL의 서브패스 - 각 패스가 메모리를 통해 데이터 교환*

![멀티 서브패스 최적화](../images/ch09/1617944-20210818142406863-486058547.jpg)

*멀티 서브패스 - 온칩 대역폭 유지로 단일 렌더 패스 내 처리*

### 렌더 패스 구조

```cpp
// 렌더 패스 정보
struct FRHIRenderPassInfo
{
    // 색상 렌더 타겟 (최대 8개)
    FRHIRenderTargetView ColorRenderTargets[MaxSimultaneousRenderTargets];
    int32 NumColorRenderTargets;

    // 깊이/스텐실 타겟
    FRHIDepthRenderTargetView DepthStencilTarget;

    // UAV (Pixel Shader에서 사용)
    FRHIUnorderedAccessView* UAVs[MaxSimultaneousUAVs];

    // 서브패스 정보 (Vulkan 타일 기반 렌더링용)
    FRHISubpassInfo SubpassInfo;

    // 렌더 영역
    FIntRect RenderArea;
};

// 렌더 패스 사용 예시
void ExecuteRenderPass(FRHICommandList& RHICmdList)
{
    // 렌더 패스 시작
    FRHIRenderPassInfo PassInfo;

    // 색상 타겟 설정
    PassInfo.ColorRenderTargets[0].RenderTarget = SceneColorRT;
    PassInfo.ColorRenderTargets[0].LoadAction = ERenderTargetLoadAction::Clear;
    PassInfo.ColorRenderTargets[0].StoreAction = ERenderTargetStoreAction::Store;
    PassInfo.ColorRenderTargets[0].ClearColor = FLinearColor::Black;

    // 깊이 타겟 설정
    PassInfo.DepthStencilTarget.DepthStencilTarget = SceneDepthRT;
    PassInfo.DepthStencilTarget.DepthLoadAction = ERenderTargetLoadAction::Clear;
    PassInfo.DepthStencilTarget.DepthStoreAction = ERenderTargetStoreAction::Store;
    PassInfo.DepthStencilTarget.StencilLoadAction = ERenderTargetLoadAction::Clear;
    PassInfo.DepthStencilTarget.StencilStoreAction = ERenderTargetStoreAction::DontCare;

    PassInfo.NumColorRenderTargets = 1;

    // 렌더 패스 시작
    RHICmdList.BeginRenderPass(PassInfo, TEXT("MainPass"));

    // 드로우 콜들
    DrawObjects(RHICmdList);

    // 렌더 패스 종료
    RHICmdList.EndRenderPass();
}
```

### 로드/저장 액션 최적화

```
┌─────────────────────────────────────────────────────────────────┐
│                    로드/저장 액션 최적화                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  로드 액션 (렌더 패스 시작 시):                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Load     : 기존 내용 보존 (메모리에서 읽기)             │   │
│  │  Clear    : 지정 색상으로 클리어 (빠름)                  │   │
│  │  DontCare : 이전 내용 무시 (가장 빠름)                   │   │
│  │            → 전체를 덮어쓸 때 사용                       │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  저장 액션 (렌더 패스 종료 시):                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Store    : 결과를 메모리에 저장                         │   │
│  │  DontCare : 저장 안함 (타일 메모리만 사용)               │   │
│  │            → 중간 결과만 필요할 때                       │   │
│  │  Resolve  : MSAA 리졸브                                  │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  모바일 최적화 (TBDR):                                          │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  DontCare + DontCare = 타일 메모리만 사용                │   │
│  │  → 메인 메모리 대역폭 절약                               │   │
│  │  → 전력 소모 감소                                        │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 리소스 배리어

### 배리어 개념

```
┌─────────────────────────────────────────────────────────────────┐
│                    리소스 배리어                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Modern GPU는 병렬/비순차 실행                                   │
│  → 리소스 접근 순서를 명시적으로 지정해야 함                    │
│                                                                 │
│  예시: 렌더 타겟을 셰이더 리소스로 사용                         │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Pass 1: Scene에 그리기 (RenderTarget으로 사용)          │   │
│  │                                                         │   │
│  │          ────────── Barrier ──────────                  │   │
│  │                                                         │   │
│  │  Pass 2: 셰이더에서 읽기 (ShaderResource로 사용)         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  배리어 없이는:                                                  │
│  - Pass 2가 Pass 1보다 먼저 실행될 수 있음                      │
│  - 잘못된 데이터 읽기                                           │
│  - 렌더링 결함, 크래시                                          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### RHI 전환 API

```cpp
// 리소스 접근 상태
enum class ERHIAccess : uint32
{
    Unknown            = 0,
    CPURead            = 1 << 0,
    Present            = 1 << 1,

    // 읽기 상태들
    VertexOrIndexBuffer = 1 << 2,
    SRVCompute          = 1 << 3,
    SRVGraphics         = 1 << 4,
    CopySrc             = 1 << 5,
    IndirectArgs        = 1 << 6,
    ResolveSrc          = 1 << 7,
    DSVRead             = 1 << 8,

    // 쓰기 상태들
    UAVCompute          = 1 << 9,
    UAVGraphics         = 1 << 10,
    RTV                 = 1 << 11,
    CopyDest            = 1 << 12,
    ResolveDst          = 1 << 13,
    DSVWrite            = 1 << 14,

    // 조합
    SRVMask = SRVCompute | SRVGraphics,
    UAVMask = UAVCompute | UAVGraphics,
};

// 전환 정보
struct FRHITransitionInfo
{
    FRHIResource* Resource;
    ERHIAccess AccessBefore;
    ERHIAccess AccessAfter;
};

// 전환 실행
void TransitionResources(FRHICommandList& RHICmdList)
{
    // 단일 리소스 전환
    RHICmdList.Transition(FRHITransitionInfo(
        SceneColorTexture,
        ERHIAccess::RTV,
        ERHIAccess::SRVGraphics
    ));

    // 다중 리소스 전환 (배치)
    TArray<FRHITransitionInfo> Transitions;
    Transitions.Add(FRHITransitionInfo(Texture1, ERHIAccess::RTV, ERHIAccess::SRVGraphics));
    Transitions.Add(FRHITransitionInfo(Texture2, ERHIAccess::RTV, ERHIAccess::SRVGraphics));
    Transitions.Add(FRHITransitionInfo(Buffer1, ERHIAccess::UAVCompute, ERHIAccess::SRVGraphics));

    RHICmdList.Transition(MakeArrayView(Transitions));
}
```

### RDG 자동 배리어

```cpp
// Render Dependency Graph (RDG)
// → 배리어를 자동으로 관리

void RenderWithRDG(FRDGBuilder& GraphBuilder)
{
    // 리소스 선언
    FRDGTextureRef SceneColor = GraphBuilder.CreateTexture(
        FRDGTextureDesc::Create2D(Extent, PF_FloatRGBA, FClearValueBinding::Black),
        TEXT("SceneColor")
    );

    // Pass 1: 렌더 타겟으로 사용
    AddClearRenderTargetPass(GraphBuilder, SceneColor, FLinearColor::Black);

    // Pass 2: 셰이더 리소스로 사용 (배리어 자동 삽입)
    FMyShaderParameters* Parameters = GraphBuilder.AllocParameters<FMyShaderParameters>();
    Parameters->InputTexture = SceneColor;

    GraphBuilder.AddPass(
        RDG_EVENT_NAME("ReadSceneColor"),
        Parameters,
        ERDGPassFlags::Raster,
        [Parameters](FRHICommandList& RHICmdList)
        {
            // SceneColor는 자동으로 SRV 상태로 전환됨
            DrawQuad(RHICmdList, Parameters);
        });
}
```

---

## 동기화

### 펜스

```cpp
// GPU 펜스 - CPU/GPU 동기화
class FRHIGPUFence : public FRHIResource
{
public:
    // 펜스 상태 쿼리
    virtual bool Poll() const = 0;
    // CPU 대기
    virtual void Wait() const = 0;
};

// 펜스 사용 예시
void UseFence(FRHICommandList& RHICmdList)
{
    // 펜스 생성
    FGPUFenceRHIRef Fence = RHICreateGPUFence(TEXT("MyFence"));

    // GPU 작업
    RHICmdList.DrawPrimitive(0, 100, 1);

    // 펜스 시그널
    RHICmdList.WriteGPUFence(Fence);

    // CPU에서 대기 (필요한 경우)
    if (!Fence->Poll())
    {
        Fence->Wait();
    }

    // 이제 GPU 작업 완료 확인됨
    ProcessResults();
}
```

### 세마포어

```
┌─────────────────────────────────────────────────────────────────┐
│                    큐 간 동기화                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Graphics Queue                   Compute Queue                 │
│       │                                │                        │
│       │  렌더링                         │                        │
│       ▼                                │                        │
│  [Draw Scene]                          │                        │
│       │                                │                        │
│       │──── Signal Semaphore ────>     │                        │
│       │                                │                        │
│       │                    Wait ◄──────┤                        │
│       │                                │                        │
│       │                          [Compute Pass]                 │
│       │                                │                        │
│       │                    ──── Signal ─┤                       │
│       │                                │                        │
│       │    ◄──── Wait ─────────────────┤                        │
│       │                                │                        │
│  [Post Process]                        │                        │
│       │                                                         │
│       ▼                                                         │
│                                                                 │
│  UE에서는 FRHISyncPoint로 추상화                                 │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### GPU 타임라인

```cpp
// GPU 타이밍 쿼리
void MeasureGPUTime(FRHICommandList& RHICmdList)
{
    // 타임스탬프 쿼리 생성
    FRenderQueryRHIRef StartQuery = RHICreateRenderQuery(RQT_AbsoluteTime);
    FRenderQueryRHIRef EndQuery = RHICreateRenderQuery(RQT_AbsoluteTime);

    // 시작 타임스탬프
    RHICmdList.EndRenderQuery(StartQuery);

    // 측정할 작업
    DrawExpensivePass(RHICmdList);

    // 종료 타임스탬프
    RHICmdList.EndRenderQuery(EndQuery);

    // 결과 읽기 (다음 프레임에)
    uint64 StartTime, EndTime;
    if (RHIGetRenderQueryResult(StartQuery, StartTime, false) &&
        RHIGetRenderQueryResult(EndQuery, EndTime, false))
    {
        double ElapsedMS = (EndTime - StartTime) / 1000000.0;
        UE_LOG(LogRHI, Log, TEXT("GPU Time: %.3f ms"), ElapsedMS);
    }
}
```

---

## 병렬 커맨드 기록

### 병렬 컨텍스트

```
┌─────────────────────────────────────────────────────────────────┐
│                    병렬 커맨드 기록                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Legacy (D3D11):                                                │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Single Thread                                          │   │
│  │  ┌────────────────────────────────────────────────────┐ │   │
│  │  │ Draw 1 → Draw 2 → Draw 3 → Draw 4 → Draw 5 → ...  │ │   │
│  │  └────────────────────────────────────────────────────┘ │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Modern (D3D12/Vulkan):                                         │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Thread 1: ┌──────────────────┐                         │   │
│  │            │ Draw 1, Draw 2   │                         │   │
│  │            └────────┬─────────┘                         │   │
│  │                     │                                   │   │
│  │  Thread 2: ┌────────┴─────────┐                         │   │
│  │            │ Draw 3, Draw 4   │                         │   │
│  │            └────────┬─────────┘         Merge           │   │
│  │                     │              ──────────────>      │   │
│  │  Thread 3: ┌────────┴─────────┐     Submit to GPU       │   │
│  │            │ Draw 5, Draw 6   │                         │   │
│  │            └──────────────────┘                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### UE 병렬 기록

```cpp
// 병렬 렌더링 태스크
class FParallelMeshDrawTask
{
    FRHICommandList* RHICmdList;
    TArray<FMeshBatch> MeshBatches;
    int32 StartIndex;
    int32 EndIndex;

public:
    void DoTask()
    {
        for (int32 i = StartIndex; i < EndIndex; ++i)
        {
            DrawMesh(RHICmdList, MeshBatches[i]);
        }
    }
};

// 병렬 실행
void ParallelDraw(FRHICommandListImmediate& RHICmdListImmediate)
{
    const int32 NumTasks = FTaskGraphInterface::Get().GetNumWorkerThreads();
    const int32 BatchesPerTask = MeshBatches.Num() / NumTasks;

    // 병렬 커맨드 리스트 할당
    TArray<FRHICommandList*> ParallelCmdLists;
    for (int32 i = 0; i < NumTasks; ++i)
    {
        ParallelCmdLists.Add(new FRHICommandList(FRHIGPUMask::All()));
    }

    // 태스크 생성 및 실행
    ParallelFor(NumTasks, [&](int32 TaskIndex)
    {
        int32 Start = TaskIndex * BatchesPerTask;
        int32 End = (TaskIndex == NumTasks - 1) ? MeshBatches.Num() : Start + BatchesPerTask;

        FRHICommandList& CmdList = *ParallelCmdLists[TaskIndex];

        for (int32 i = Start; i < End; ++i)
        {
            DrawMesh(CmdList, MeshBatches[i]);
        }
    });

    // 메인 커맨드 리스트에 병합
    for (FRHICommandList* CmdList : ParallelCmdLists)
    {
        RHICmdListImmediate.QueueAsyncCommandListSubmit(CmdList);
    }
}
```

---

## 커맨드 버퍼링

### 버퍼링 전략

```
┌─────────────────────────────────────────────────────────────────┐
│                    커맨드 버퍼링                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Frame N-1          Frame N            Frame N+1               │
│  ┌─────────┐       ┌─────────┐        ┌─────────┐              │
│  │GPU 실행 │       │GPU 실행 │        │GPU 실행 │              │
│  └─────────┘       └─────────┘        └─────────┘              │
│       ↑                 ↑                  ↑                    │
│       │                 │                  │                    │
│  ┌─────────┐       ┌─────────┐        ┌─────────┐              │
│  │Cmd List │       │Cmd List │        │Cmd List │              │
│  │  N-1    │       │   N     │        │  N+1    │              │
│  └─────────┘       └─────────┘        └─────────┘              │
│       ↑                 ↑                  ↑                    │
│       │                 │                  │                    │
│  CPU 기록완료      CPU 기록중          CPU 대기                  │
│                                                                 │
│  트리플 버퍼링:                                                  │
│  - CPU는 항상 새 프레임 기록 가능                               │
│  - GPU는 이전 프레임 실행                                       │
│  - 파이프라인 효율 최대화                                       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 프레임 플리핑

```cpp
// 프레임 리소스 관리
class FFrameResources
{
    static const int32 NumBufferedFrames = 3;

    // 프레임별 리소스
    struct FFrameData
    {
        FGPUFenceRHIRef Fence;
        TArray<FBufferRHIRef> DynamicBuffers;
        TUniformBufferRef<FViewUniformShaderParameters> ViewUB;
    };

    FFrameData FrameData[NumBufferedFrames];
    int32 CurrentFrameIndex = 0;

public:
    void BeginFrame()
    {
        // 현재 프레임 리소스의 펜스 대기
        FFrameData& CurrentFrame = FrameData[CurrentFrameIndex];
        if (CurrentFrame.Fence && !CurrentFrame.Fence->Poll())
        {
            QUICK_SCOPE_CYCLE_COUNTER(STAT_WaitForGPU);
            CurrentFrame.Fence->Wait();
        }

        // 리소스 재활용 준비
        CurrentFrame.DynamicBuffers.Reset();
    }

    void EndFrame(FRHICommandList& RHICmdList)
    {
        // 펜스 시그널
        FFrameData& CurrentFrame = FrameData[CurrentFrameIndex];
        if (!CurrentFrame.Fence)
        {
            CurrentFrame.Fence = RHICreateGPUFence(TEXT("FrameFence"));
        }
        RHICmdList.WriteGPUFence(CurrentFrame.Fence);

        // 다음 프레임으로
        CurrentFrameIndex = (CurrentFrameIndex + 1) % NumBufferedFrames;
    }
};
```

---

## 요약

커맨드 리스트 핵심:

1. **렌더 패스** - 렌더 타겟 설정, 로드/저장 액션 최적화
2. **리소스 배리어** - 상태 전환 명시, RDG 자동 관리
3. **동기화** - 펜스, 세마포어로 CPU/GPU 동기화
4. **병렬 기록** - 멀티스레드 커맨드 생성, 병합 제출
5. **버퍼링** - 트리플 버퍼링으로 파이프라인 효율화

Modern API에서는 명시적 동기화가 필수이며, UE RHI가 이를 추상화합니다.

---

## 참고 자료

- [D3D12 Command Lists](https://docs.microsoft.com/en-us/windows/win32/direct3d12/command-lists-and-bundles)
- [Vulkan Command Buffers](https://www.khronos.org/registry/vulkan/specs/1.3/html/chap6.html)
- [원문 시리즈 (중국어)](https://www.cnblogs.com/timlly/p/13512787.html)
---

<div style="display: flex; justify-content: space-between; align-items: center; padding: 16px 0;">
  <a href="../02-rhi-resources/" style="text-decoration: none;">← 이전: 02. RHI 리소스</a>
  <a href="../04-pipeline-state/" style="text-decoration: none;">다음: 04. 파이프라인 스테이트 →</a>
</div>
