# 03. 그래픽 API 멀티스레딩

> DX11/12, Vulkan, Metal의 멀티스레딩 모델

---

## 목차

1. [전통 그래픽 API의 한계](#1-전통-그래픽-api의-한계)
2. [DirectX 11 멀티스레딩](#2-directx-11-멀티스레딩)
3. [DirectX 12 멀티스레딩](#3-directx-12-멀티스레딩)
4. [Vulkan 멀티스레딩](#4-vulkan-멀티스레딩)
5. [Metal 멀티스레딩](#5-metal-멀티스레딩)
6. [API 비교](#6-api-비교)

---

## 1. 전통 그래픽 API의 한계 {#1-전통-그래픽-api의-한계}

### 1.1 단일 Context 모델

![전통 API](../images/ch02/1617944-20210125210143940-1531101013.png)
*전통 그래픽 API의 선형 드로우 명령 실행*

전통 그래픽 API (OpenGL, DX9)의 문제점:

| 문제 | 설명 |
|------|------|
| **단일 Context** | 모든 GPU 명령이 하나의 Context 통과 |
| **드라이버 오버헤드** | 상태 검증, 메모리 관리 등 |
| **CPU 병목** | GPU는 대기, CPU는 과부하 |

![CPU-GPU 블로킹](../images/ch02/1617944-20210125210152724-219846672.jpg)
*전통 API - 단일 스레드/Context에서 블로킹 드로우 콜*

### 1.2 드로우 콜 비용

```cpp
// 전통 API의 드로우 콜 (의사 코드)
void DrawMesh_LegacyAPI(FMesh* Mesh)
{
    // 1. 상태 검증 (드라이버)
    ValidateRenderState();          // ~10us

    // 2. 셰이더 바인딩 검증
    ValidateShaderBindings();       // ~5us

    // 3. 리소스 레지던시 확인
    EnsureResourcesResident();      // ~5us

    // 4. 실제 GPU 명령 생성
    GenerateGPUCommands(Mesh);      // ~2us

    // 총 ~22us per draw call
    // 60fps = ~16ms/frame
    // 최대 ~700 드로우 콜 (이론상)
}
```

---

## 2. DirectX 11 멀티스레딩 {#2-directx-11-멀티스레딩}

### 2.1 Deferred Context

DX11은 Deferred Context를 통한 제한적 멀티스레딩 지원:

![DX11 아키텍처](../images/ch02/1617944-20210125210204887-1574578553.png)
*DirectX 11 소프트웨어 레벨 멀티스레드 렌더링*

![DX11 모델](../images/ch02/1617944-20210125210224685-921400643.png)
*DirectX 11 멀티스레드 모델*

```cpp
// DX11 Deferred Context 사용
ID3D11Device* Device;
ID3D11DeviceContext* ImmediateContext;
ID3D11DeviceContext* DeferredContext;

// Deferred Context 생성
Device->CreateDeferredContext(0, &DeferredContext);

// 워커 스레드에서 명령 기록
void WorkerThread()
{
    // Deferred Context에 명령 기록
    DeferredContext->IASetVertexBuffers(...);
    DeferredContext->VSSetShader(...);
    DeferredContext->Draw(...);

    // Command List로 변환
    ID3D11CommandList* CommandList;
    DeferredContext->FinishCommandList(FALSE, &CommandList);

    // 메인 스레드로 전달
    EnqueueCommandList(CommandList);
}

// 메인 스레드에서 실행
void MainThread()
{
    ID3D11CommandList* CommandList = DequeueCommandList();

    // Immediate Context에서 실행
    ImmediateContext->ExecuteCommandList(CommandList, TRUE);
    CommandList->Release();
}
```

![DX11 상세](../images/ch02/1617944-20210125210250981-472165669.png)
*DirectX 11 멀티스레드 아키텍처 상세*

### 2.2 DX11의 한계

| 한계 | 설명 |
|------|------|
| **직렬 제출** | Immediate Context는 여전히 단일 스레드 |
| **드라이버 오버헤드** | 상태 검증이 여전히 존재 |
| **제한된 이점** | 명령 기록만 병렬화 |

---

## 3. DirectX 12 멀티스레딩 {#3-directx-12-멀티스레딩}

### 3.1 명령 큐 아키텍처

DX12는 완전한 저수준 멀티스레딩 지원:

![DX12 모델](../images/ch02/1617944-20210125210312585-1398642718.png)
*DirectX 12 멀티스레드 모델*

![DX12 메커니즘](../images/ch02/1617944-20210125210324897-639832403.png)
*DX12: CPU 스레드 → 명령 리스트 → 명령 큐 → GPU 엔진*

### 3.2 세 가지 큐 타입

```
┌─────────────────┐     ┌─────────────────┐
│   Copy Queue    │ ──→ │   Copy Engine   │
│   (복사 전용)    │     │   (DMA 전용)    │
└─────────────────┘     └─────────────────┘

┌─────────────────┐     ┌─────────────────┐
│  Compute Queue  │ ──→ │ Compute + Copy  │
│   (컴퓨트용)     │     │   (연산+복사)   │
└─────────────────┘     └─────────────────┘

┌─────────────────┐     ┌─────────────────┐
│    3D Queue     │ ──→ │   All Engines   │
│   (그래픽스용)   │     │   (모든 기능)   │
└─────────────────┘     └─────────────────┘
```

### 3.3 DX12 명령 기록

```cpp
// DX12 멀티스레드 명령 기록
class FD3D12CommandContext
{
    ID3D12GraphicsCommandList* CommandList;
    ID3D12CommandAllocator* CommandAllocator;

public:
    void BeginRecording()
    {
        CommandAllocator->Reset();
        CommandList->Reset(CommandAllocator, nullptr);
    }

    void RecordDraws(const TArray<FMeshBatch>& Batches)
    {
        for (const FMeshBatch& Batch : Batches)
        {
            CommandList->SetPipelineState(Batch.PSO);
            CommandList->SetGraphicsRootSignature(Batch.RootSig);
            CommandList->IASetVertexBuffers(0, 1, &Batch.VBView);
            CommandList->IASetIndexBuffer(&Batch.IBView);
            CommandList->DrawIndexedInstanced(
                Batch.NumIndices, Batch.NumInstances, 0, 0, 0);
        }
    }

    ID3D12CommandList* FinishRecording()
    {
        CommandList->Close();
        return CommandList;
    }
};

// 병렬 기록
void ParallelRecord()
{
    TArray<ID3D12CommandList*> CommandLists;

    ParallelFor(NumWorkers, [&](int32 WorkerIndex)
    {
        FD3D12CommandContext& Context = Contexts[WorkerIndex];
        Context.BeginRecording();
        Context.RecordDraws(BatchesForWorker[WorkerIndex]);
        CommandLists[WorkerIndex] = Context.FinishRecording();
    });

    // 모든 명령 리스트 한번에 제출
    CommandQueue->ExecuteCommandLists(
        CommandLists.Num(),
        CommandLists.GetData());
}
```

### 3.4 Async Compute

```cpp
// 비동기 컴퓨트 예시
void AsyncComputeExample()
{
    // 그래픽스 큐에서 G-Buffer 렌더링
    GraphicsQueue->ExecuteCommandLists(1, &GBufferCommands);

    // 컴퓨트 큐에서 SSAO 계산 (병렬)
    ComputeQueue->ExecuteCommandLists(1, &SSAOCommands);

    // 그래픽스 큐에서 라이팅 (SSAO 완료 대기)
    GraphicsQueue->Wait(ComputeFence, SSAOFenceValue);
    GraphicsQueue->ExecuteCommandLists(1, &LightingCommands);
}
```

---

## 4. Vulkan 멀티스레딩 {#4-vulkan-멀티스레딩}

### 4.1 명령 버퍼 병렬 처리

![Vulkan 병렬](../images/ch02/1617944-20210125210348224-1598024134.jpg)
*Vulkan 그래픽 API 병렬 처리*

```cpp
// Vulkan 멀티스레드 명령 기록
void VulkanParallelRecord()
{
    // 각 스레드에 Command Pool 할당 (필수!)
    // Command Pool은 스레드 로컬
    TArray<VkCommandPool> ThreadCommandPools;
    TArray<VkCommandBuffer> CommandBuffers;

    ParallelFor(NumThreads, [&](int32 ThreadIndex)
    {
        VkCommandPool Pool = ThreadCommandPools[ThreadIndex];
        VkCommandBuffer CmdBuf;

        VkCommandBufferAllocateInfo AllocInfo = {};
        AllocInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
        AllocInfo.commandPool = Pool;
        AllocInfo.level = VK_COMMAND_BUFFER_LEVEL_SECONDARY;
        AllocInfo.commandBufferCount = 1;

        vkAllocateCommandBuffers(Device, &AllocInfo, &CmdBuf);

        // 명령 기록
        VkCommandBufferBeginInfo BeginInfo = {};
        BeginInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
        BeginInfo.flags = VK_COMMAND_BUFFER_USAGE_RENDER_PASS_CONTINUE_BIT;

        vkBeginCommandBuffer(CmdBuf, &BeginInfo);
        RecordDrawCommands(CmdBuf, ThreadIndex);
        vkEndCommandBuffer(CmdBuf);

        CommandBuffers[ThreadIndex] = CmdBuf;
    });

    // Primary 버퍼에서 Secondary 실행
    vkCmdExecuteCommands(PrimaryBuffer,
        CommandBuffers.Num(),
        CommandBuffers.GetData());
}
```

![Vulkan CommandPool](../images/ch02/1617944-20210125210402618-829810560.jpg)
*Vulkan CommandPool의 프레임 간 병렬 처리*

### 4.2 Vulkan 동기화

![Vulkan 동기화](../images/ch02/1617944-20210125210419647-168271108.jpg)
*Vulkan 동기화 프리미티브*

| 프리미티브 | 용도 | 범위 |
|-----------|------|------|
| **Semaphore** | 큐 간 동기화 | GPU-GPU |
| **Fence** | CPU-GPU 동기화 | CPU-GPU |
| **Event** | 명령 버퍼 내 동기화 | 세밀한 제어 |
| **Barrier** | 파이프라인 동기화 | 리소스 전환 |

```cpp
// 큐 동기화 예시
void QueueSynchronization()
{
    // 세마포어로 큐 간 동기화
    VkSemaphore RenderComplete;
    VkSemaphore ComputeComplete;

    // 렌더 큐 제출
    VkSubmitInfo RenderSubmit = {};
    RenderSubmit.signalSemaphoreCount = 1;
    RenderSubmit.pSignalSemaphores = &RenderComplete;
    vkQueueSubmit(GraphicsQueue, 1, &RenderSubmit, VK_NULL_HANDLE);

    // 컴퓨트 큐는 렌더 완료 대기
    VkSubmitInfo ComputeSubmit = {};
    ComputeSubmit.waitSemaphoreCount = 1;
    ComputeSubmit.pWaitSemaphores = &RenderComplete;
    ComputeSubmit.signalSemaphoreCount = 1;
    ComputeSubmit.pSignalSemaphores = &ComputeComplete;
    vkQueueSubmit(ComputeQueue, 1, &ComputeSubmit, VK_NULL_HANDLE);
}
```

---

## 5. Metal 멀티스레딩 {#5-metal-멀티스레딩}

### 5.1 Metal 기본 개념

![Metal 개념](../images/ch02/1617944-20210125210454310-1431175121.png)
*Metal: CommandEncoder → CommandBuffer → CommandQueue*

```
┌─────────────────────────────────────────────────────────────────┐
│                    Metal 파이프라인                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────┐                                            │
│  │ Command Queue   │ ← 제출 순서 보장                            │
│  └────────┬────────┘                                            │
│           │                                                     │
│  ┌────────▼────────┐                                            │
│  │ Command Buffer  │ ← 재사용 불가, 한번 제출                     │
│  └────────┬────────┘                                            │
│           │                                                     │
│  ┌────────▼────────┬─────────────────┬─────────────────┐       │
│  │Render Encoder   │Compute Encoder  │ Blit Encoder    │       │
│  │(래스터라이제이션)│(GPGPU 연산)      │(메모리 복사)     │       │
│  └─────────────────┴─────────────────┴─────────────────┘       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 5.2 Metal 병렬 인코딩

![Metal 멀티스레드](../images/ch02/1617944-20210125210507226-1441423249.png)
*Metal 멀티스레드 모델 - 3개 CPU 스레드가 다른 타입의 Encoder 동시 녹화*

```objc
// Metal 병렬 커맨드 인코딩
- (void)parallelEncode
{
    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];

    // Parallel Render Command Encoder 생성
    id<MTLParallelRenderCommandEncoder> parallelEncoder =
        [commandBuffer parallelRenderCommandEncoderWithDescriptor:_renderPassDesc];

    // 각 스레드에서 서브 인코더 획득
    dispatch_apply(NumThreads, dispatch_get_global_queue(0, 0), ^(size_t threadIndex) {
        id<MTLRenderCommandEncoder> encoder = [parallelEncoder renderCommandEncoder];

        // 이 스레드의 드로우 명령 인코딩
        [self encodeDrawCallsForThread:threadIndex withEncoder:encoder];

        [encoder endEncoding];
    });

    [parallelEncoder endEncoding];
    [commandBuffer commit];
}
```

### 5.3 API 마이그레이션 고려

![API 마이그레이션](../images/ch02/1617944-20210125210433701-1895270677.png)
*OpenGL에서 신세대 API 마이그레이션 비용 vs 성능 이점*

---

## 6. API 비교 {#6-api-비교}

### 6.1 기능 비교

| 기능 | DX11 | DX12 | Vulkan | Metal |
|------|------|------|--------|-------|
| **멀티스레드 명령 기록** | 제한적 | 완전 | 완전 | 완전 |
| **다중 큐** | No | Yes (3종류) | Yes (다수) | Yes |
| **Async Compute** | No | Yes | Yes | Yes |
| **명시적 동기화** | 암시적 | 명시적 | 명시적 | 명시적 |
| **PSO 캐싱** | 드라이버 | 명시적 | 명시적 | 명시적 |
| **메모리 관리** | 드라이버 | 명시적 | 명시적 | 명시적 |

### 6.2 UE RHI 추상화

```cpp
// UE의 API 추상화
class FRHICommandList
{
public:
    // 플랫폼 독립적 인터페이스
    void SetGraphicsPipelineState(FGraphicsPipelineStateRHI* PSO);
    void SetVertexBuffer(uint32 StreamIndex, FVertexBufferRHIRef VB);
    void DrawIndexedPrimitive(FIndexBufferRHIRef IB, ...);

    // 내부적으로 플랫폼별 구현 호출
    // DX12: ID3D12GraphicsCommandList
    // Vulkan: VkCommandBuffer
    // Metal: MTLRenderCommandEncoder
};

// 병렬 명령 리스트 생성
TArray<FRHICommandList*> ParallelLists;
ParallelFor(NumWorkers, [&ParallelLists](int32 Index)
{
    FRHICommandList* CmdList = new FRHICommandList();
    RecordCommands(CmdList, Index);
    ParallelLists[Index] = CmdList;
});
```

### 6.3 성능 특성

```
┌─────────────────────────────────────────────────────────────────┐
│                    드로우 콜 오버헤드 비교                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  DX11:   ████████████████████████████████ ~20us/call            │
│                                                                 │
│  DX12:   ████                              ~2us/call            │
│                                                                 │
│  Vulkan: ████                              ~2us/call            │
│                                                                 │
│  Metal:  ████                              ~2us/call            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

최대 드로우 콜 (60fps, 16ms 예산):
- DX11:   ~800 calls
- DX12:   ~8000 calls (10x)
- Vulkan: ~8000 calls
- Metal:  ~8000 calls
```

---

## 요약

| API | 멀티스레딩 모델 | 핵심 특징 |
|-----|----------------|----------|
| **DX11** | Deferred Context | 제한적, 드라이버 오버헤드 |
| **DX12** | Command List + Queue | 완전 병렬, 명시적 제어 |
| **Vulkan** | Command Buffer + Pool | 크로스 플랫폼, 세밀한 동기화 |
| **Metal** | Parallel Encoder | Apple 최적화, 간결한 API |

---

## 다음 문서

[04. UE 렌더링 스레드](04-ue-rendering-threads.md)에서 UE의 실제 렌더링 스레드 구현을 살펴봅니다.
---

<div style="display: flex; justify-content: space-between; align-items: center; padding: 16px 0;">
  <a href="../02-threading-infrastructure/" style="text-decoration: none;">← 이전: 02. 스레딩 인프라</a>
  <a href="../04-ue-rendering-threads/" style="text-decoration: none;">다음: 04. UE 렌더링 스레드 아키텍처 →</a>
</div>
