# 05. 플랫폼별 RHI

DirectX 12, Vulkan, Metal 등 각 플랫폼 RHI 구현의 특성을 분석합니다.

---

## 플랫폼 개요

### 지원 플랫폼

```
┌─────────────────────────────────────────────────────────────────┐
│                    UE 지원 RHI 플랫폼                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Desktop:                                                       │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Windows    : D3D12 (기본), D3D11, Vulkan, OpenGL       │   │
│  │  Linux      : Vulkan (기본), OpenGL                     │   │
│  │  macOS      : Metal (전용)                              │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Mobile:                                                        │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  iOS        : Metal (전용)                              │   │
│  │  Android    : Vulkan (기본), OpenGL ES                  │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Console:                                                       │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  PlayStation 5 : AGC (Sony 전용 API)                    │   │
│  │  Xbox Series   : D3D12 (GDK)                            │   │
│  │  Nintendo Switch: NVN / Vulkan                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## DirectX 12 RHI

### D3D12 아키텍처

```
┌─────────────────────────────────────────────────────────────────┐
│                    D3D12RHI 구조                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  FD3D12DynamicRHI                                               │
│  ├── ID3D12Device (GPU 디바이스)                               │
│  │                                                              │
│  ├── Command Queues                                            │
│  │   ├── Graphics Queue (3D 렌더링)                            │
│  │   ├── Compute Queue (비동기 컴퓨트)                         │
│  │   └── Copy Queue (리소스 전송)                              │
│  │                                                              │
│  ├── Descriptor Heaps                                          │
│  │   ├── CBV/SRV/UAV Heap                                      │
│  │   ├── Sampler Heap                                          │
│  │   ├── RTV Heap                                              │
│  │   └── DSV Heap                                              │
│  │                                                              │
│  ├── Memory Heaps                                              │
│  │   ├── Default Heap (GPU 전용)                               │
│  │   ├── Upload Heap (CPU → GPU)                               │
│  │   └── Readback Heap (GPU → CPU)                             │
│  │                                                              │
│  └── FD3D12CommandContext (커맨드 리스트 관리)                  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### D3D12 초기화

```cpp
// D3D12 디바이스 생성
class FD3D12DynamicRHI : public FDynamicRHI
{
    ID3D12Device* Device;
    IDXGIAdapter* Adapter;
    ID3D12CommandQueue* GraphicsQueue;

public:
    virtual void Init() override
    {
        // 어댑터 열거
        IDXGIFactory4* Factory;
        CreateDXGIFactory1(IID_PPV_ARGS(&Factory));

        // 적합한 GPU 선택
        IDXGIAdapter1* SelectedAdapter = nullptr;
        for (UINT i = 0; Factory->EnumAdapters1(i, &SelectedAdapter) != DXGI_ERROR_NOT_FOUND; ++i)
        {
            DXGI_ADAPTER_DESC1 Desc;
            SelectedAdapter->GetDesc1(&Desc);
            // GPU 선택 로직...
        }

        // 디바이스 생성
        D3D12CreateDevice(
            SelectedAdapter,
            D3D_FEATURE_LEVEL_12_0,
            IID_PPV_ARGS(&Device)
        );

        // 커맨드 큐 생성
        D3D12_COMMAND_QUEUE_DESC QueueDesc = {};
        QueueDesc.Type = D3D12_COMMAND_LIST_TYPE_DIRECT;
        QueueDesc.Flags = D3D12_COMMAND_QUEUE_FLAG_NONE;
        Device->CreateCommandQueue(&QueueDesc, IID_PPV_ARGS(&GraphicsQueue));

        // 디스크립터 힙 초기화
        InitDescriptorHeaps();

        // 메모리 힙 초기화
        InitMemoryHeaps();
    }
};
```

### D3D12 리소스 바인딩

```cpp
// Root Signature - 셰이더 파라미터 레이아웃
class FD3D12RootSignature
{
    ID3D12RootSignature* RootSignature;

public:
    void Create(const FD3D12RootSignatureDesc& Desc)
    {
        // Root Parameter 정의
        CD3DX12_ROOT_PARAMETER1 Parameters[32];
        int32 ParamIndex = 0;

        // CBV (Constant Buffer View)
        for (int32 i = 0; i < Desc.NumCBVs; ++i)
        {
            Parameters[ParamIndex++].InitAsConstantBufferView(i);
        }

        // Descriptor Table (SRV, UAV)
        CD3DX12_DESCRIPTOR_RANGE1 Ranges[16];
        // ... 범위 설정

        // Root Signature 생성
        CD3DX12_VERSIONED_ROOT_SIGNATURE_DESC RootSigDesc;
        RootSigDesc.Init_1_1(ParamIndex, Parameters, Desc.NumSamplers, Samplers);

        ID3DBlob* Blob;
        D3DX12SerializeVersionedRootSignature(&RootSigDesc, &Blob);
        Device->CreateRootSignature(0, Blob->GetBufferPointer(),
            Blob->GetBufferSize(), IID_PPV_ARGS(&RootSignature));
    }
};

// Descriptor 바인딩
void FD3D12CommandContext::SetShaderResourceView(uint32 Index, FD3D12ShaderResourceView* SRV)
{
    // Descriptor Heap에서 할당
    D3D12_CPU_DESCRIPTOR_HANDLE Handle = AllocateDescriptor();

    // SRV 복사
    Device->CopyDescriptorsSimple(1, Handle, SRV->GetHandle(),
        D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV);

    // 커맨드 리스트에 바인딩
    CommandList->SetGraphicsRootDescriptorTable(Index, GetGPUHandle(Handle));
}
```

---

## Vulkan RHI

### Vulkan 아키텍처

```
┌─────────────────────────────────────────────────────────────────┐
│                    VulkanRHI 구조                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  FVulkanDynamicRHI                                              │
│  ├── VkInstance (Vulkan 인스턴스)                              │
│  │                                                              │
│  ├── FVulkanDevice                                             │
│  │   ├── VkDevice (논리 디바이스)                              │
│  │   ├── VkPhysicalDevice (물리 GPU)                           │
│  │   │                                                          │
│  │   ├── Queue Families                                        │
│  │   │   ├── Graphics Queue                                    │
│  │   │   ├── Compute Queue                                     │
│  │   │   └── Transfer Queue                                    │
│  │   │                                                          │
│  │   └── VkPhysicalDeviceMemoryProperties                      │
│  │                                                              │
│  ├── FVulkanCommandBufferManager                               │
│  │   └── Command Pools (스레드당 하나)                         │
│  │                                                              │
│  └── FVulkanDescriptorPoolManager                              │
│      └── Descriptor Pools                                      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Vulkan 파이프라인

```cpp
// Vulkan Graphics Pipeline 생성
VkPipeline FVulkanPipelineStateCache::CreateGraphicsPipeline(
    const FGraphicsPipelineStateInitializer& Initializer)
{
    VkGraphicsPipelineCreateInfo PipelineInfo = {};
    PipelineInfo.sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO;

    // 셰이더 스테이지
    VkPipelineShaderStageCreateInfo ShaderStages[5];
    int32 NumStages = 0;

    ShaderStages[NumStages++] = GetShaderStage(Initializer.VertexShader, VK_SHADER_STAGE_VERTEX_BIT);
    ShaderStages[NumStages++] = GetShaderStage(Initializer.PixelShader, VK_SHADER_STAGE_FRAGMENT_BIT);

    PipelineInfo.stageCount = NumStages;
    PipelineInfo.pStages = ShaderStages;

    // 버텍스 입력
    VkPipelineVertexInputStateCreateInfo VertexInputInfo = {};
    // ... 버텍스 바인딩, 어트리뷰트 설정

    // 래스터라이저
    VkPipelineRasterizationStateCreateInfo RasterInfo = {};
    RasterInfo.polygonMode = TranslateFillMode(Initializer.RasterizerState);
    RasterInfo.cullMode = TranslateCullMode(Initializer.RasterizerState);
    RasterInfo.frontFace = VK_FRONT_FACE_CLOCKWISE;

    // 블렌드
    VkPipelineColorBlendStateCreateInfo BlendInfo = {};
    // ... 블렌드 상태 설정

    // 깊이/스텐실
    VkPipelineDepthStencilStateCreateInfo DepthInfo = {};
    // ... 깊이 상태 설정

    // 렌더 패스
    PipelineInfo.renderPass = GetRenderPass(Initializer);
    PipelineInfo.layout = GetPipelineLayout(Initializer);

    // 파이프라인 생성
    VkPipeline Pipeline;
    vkCreateGraphicsPipelines(Device, PipelineCache, 1, &PipelineInfo, nullptr, &Pipeline);

    return Pipeline;
}
```

### Vulkan 동기화

```cpp
// Vulkan 세마포어/펜스
class FVulkanSemaphore
{
    VkSemaphore Semaphore;

public:
    void Create(VkDevice Device)
    {
        VkSemaphoreCreateInfo Info = {};
        Info.sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;
        vkCreateSemaphore(Device, &Info, nullptr, &Semaphore);
    }
};

// 커맨드 제출 with 동기화
void FVulkanQueue::Submit(FVulkanCommandBuffer* CmdBuffer,
    FVulkanSemaphore* WaitSemaphore, FVulkanSemaphore* SignalSemaphore,
    FVulkanFence* Fence)
{
    VkSubmitInfo SubmitInfo = {};
    SubmitInfo.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;

    VkPipelineStageFlags WaitStage = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    SubmitInfo.waitSemaphoreCount = WaitSemaphore ? 1 : 0;
    SubmitInfo.pWaitSemaphores = WaitSemaphore ? &WaitSemaphore->Semaphore : nullptr;
    SubmitInfo.pWaitDstStageMask = &WaitStage;

    SubmitInfo.commandBufferCount = 1;
    SubmitInfo.pCommandBuffers = &CmdBuffer->Handle;

    SubmitInfo.signalSemaphoreCount = SignalSemaphore ? 1 : 0;
    SubmitInfo.pSignalSemaphores = SignalSemaphore ? &SignalSemaphore->Semaphore : nullptr;

    vkQueueSubmit(Queue, 1, &SubmitInfo, Fence ? Fence->Handle : VK_NULL_HANDLE);
}
```

---

## Metal RHI

### Metal 아키텍처

```
┌─────────────────────────────────────────────────────────────────┐
│                    MetalRHI 구조                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  FMetalDynamicRHI                                               │
│  ├── id<MTLDevice> (Metal 디바이스)                            │
│  │                                                              │
│  ├── id<MTLCommandQueue> (커맨드 큐)                           │
│  │                                                              │
│  ├── FMetalCommandEncoder                                      │
│  │   ├── Render Encoder                                        │
│  │   ├── Compute Encoder                                       │
│  │   └── Blit Encoder                                          │
│  │                                                              │
│  └── FMetalHeap (메모리 힙)                                    │
│      ├── Private (GPU 전용)                                    │
│      └── Shared (CPU/GPU 공유)                                 │
│                                                                 │
│  특징:                                                          │
│  - Objective-C++ 기반                                          │
│  - Automatic Reference Counting (ARC)                          │
│  - Argument Buffers (효율적 바인딩)                            │
│  - Tile-based Deferred Rendering 최적화                        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Metal 렌더 인코더

```objc
// Metal 렌더 패스
- (void)executeRenderPass:(FMetalRenderPassInfo*)PassInfo
{
    MTLRenderPassDescriptor* Descriptor = [MTLRenderPassDescriptor new];

    // 색상 첨부
    Descriptor.colorAttachments[0].texture = PassInfo->ColorTarget;
    Descriptor.colorAttachments[0].loadAction = TranslateLoadAction(PassInfo->ColorLoadAction);
    Descriptor.colorAttachments[0].storeAction = TranslateStoreAction(PassInfo->ColorStoreAction);
    Descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);

    // 깊이 첨부
    Descriptor.depthAttachment.texture = PassInfo->DepthTarget;
    Descriptor.depthAttachment.loadAction = TranslateLoadAction(PassInfo->DepthLoadAction);
    Descriptor.depthAttachment.storeAction = TranslateStoreAction(PassInfo->DepthStoreAction);
    Descriptor.depthAttachment.clearDepth = 1.0;

    // 렌더 커맨드 인코더 생성
    id<MTLRenderCommandEncoder> Encoder = [CommandBuffer renderCommandEncoderWithDescriptor:Descriptor];

    // PSO 설정
    [Encoder setRenderPipelineState:PipelineState];
    [Encoder setDepthStencilState:DepthState];

    // 리소스 바인딩
    [Encoder setVertexBuffer:VertexBuffer offset:0 atIndex:0];
    [Encoder setFragmentTexture:Texture atIndex:0];

    // 드로우
    [Encoder drawPrimitives:MTLPrimitiveTypeTriangle
              vertexStart:0
              vertexCount:VertexCount];

    [Encoder endEncoding];
}
```

### Metal Tile Shading

```objc
// Metal Tile Shading (Apple Silicon 최적화)
// - Tile 메모리에서 직접 연산
// - 메인 메모리 대역폭 절약

MTLTileRenderPipelineDescriptor* TileDesc = [MTLTileRenderPipelineDescriptor new];
TileDesc.tileFunction = TileKernelFunction;
TileDesc.rasterSampleCount = 1;
TileDesc.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA8Unorm;

id<MTLRenderPipelineState> TilePipeline = [Device newRenderPipelineStateWithTileDescriptor:TileDesc
                                                                                   options:0
                                                                                reflection:nil
                                                                                     error:nil];

// 렌더 인코더에서 타일 셰이더 디스패치
[Encoder setTileTexture:TileTexture atIndex:0];
[Encoder dispatchThreadsPerTile:MTLSizeMake(16, 16, 1)];
```

---

## 플랫폼 비교

### 기능 비교

```
┌────────────────────────────────────────────────────────────────┐
│                    플랫폼 기능 비교                             │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│  기능              D3D12      Vulkan     Metal                 │
│  ───────────────  ─────────  ─────────  ─────────              │
│  Ray Tracing      DXR        VK_KHR_RT  Metal RT (M3+)        │
│  Mesh Shader      MS 1.0     Mesh Ext   Object/Mesh           │
│  Variable Rate    VRS 1.0    VRS Ext    Raster Rate           │
│  Bindless         SM 6.6     Descriptor Argument Buffer       │
│                              Indexing                          │
│  Async Compute    지원       지원       지원                   │
│  Multi-GPU        Explicit   VK_KHR_*   제한적                 │
│                                                                │
│  특화 기능:                                                    │
│  D3D12  : PIX 디버깅, Xbox 호환                                │
│  Vulkan : 크로스 플랫폼, 확장성                                │
│  Metal  : Apple 생태계, Tile Shading                          │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

### 성능 특성

```
┌────────────────────────────────────────────────────────────────┐
│                    플랫폼 성능 특성                             │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│  Draw Call 오버헤드:                                           │
│  ┌────────────────────────────────────────────────────────┐   │
│  │  D3D11     : ~10 μs/draw (드라이버 검증)               │   │
│  │  D3D12     : ~1-2 μs/draw                              │   │
│  │  Vulkan    : ~0.5-1 μs/draw                            │   │
│  │  Metal     : ~0.5-1 μs/draw                            │   │
│  └────────────────────────────────────────────────────────┘   │
│                                                                │
│  메모리 관리:                                                  │
│  ┌────────────────────────────────────────────────────────┐   │
│  │  D3D12/Vulkan : 명시적, 세밀한 제어                    │   │
│  │  Metal        : Heap 기반, 자동 퍼징                   │   │
│  └────────────────────────────────────────────────────────┘   │
│                                                                │
│  파이프라인 캐시:                                              │
│  ┌────────────────────────────────────────────────────────┐   │
│  │  D3D12  : PSO 직렬화, 디스크 캐시                      │   │
│  │  Vulkan : VkPipelineCache                              │   │
│  │  Metal  : 자동 캐싱 (OS 레벨)                          │   │
│  └────────────────────────────────────────────────────────┘   │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

---

## 플랫폼별 최적화

### D3D12 최적화

```cpp
// D3D12 특화 최적화

// 1. ExecuteIndirect - GPU 구동 렌더링
void ExecuteIndirectDraws(ID3D12GraphicsCommandList* CmdList)
{
    // 인자 버퍼 (GPU에서 생성)
    CmdList->ExecuteIndirect(
        CommandSignature,
        MaxDrawCount,
        ArgumentBuffer,
        0,
        CountBuffer,  // 실제 드로우 수
        0
    );
}

// 2. 리소스 배리어 배칭
D3D12_RESOURCE_BARRIER Barriers[16];
int32 NumBarriers = 0;
// 배리어 수집...
CmdList->ResourceBarrier(NumBarriers, Barriers);

// 3. 번들 사용
CmdList->ExecuteBundle(PrerecordedBundle);
```

### Vulkan 최적화

```cpp
// Vulkan 특화 최적화

// 1. Secondary Command Buffer
VkCommandBuffer Secondary;
// 사전 기록된 커맨드 실행
vkCmdExecuteCommands(Primary, 1, &Secondary);

// 2. Push Constants (작은 데이터용)
vkCmdPushConstants(CmdBuffer, PipelineLayout,
    VK_SHADER_STAGE_VERTEX_BIT, 0, sizeof(Matrix), &MVP);

// 3. 동적 렌더링 (VK_KHR_dynamic_rendering)
VkRenderingInfo RenderInfo = {};
RenderInfo.renderArea = { {0, 0}, {Width, Height} };
RenderInfo.colorAttachmentCount = 1;
RenderInfo.pColorAttachments = &ColorAttachment;
vkCmdBeginRendering(CmdBuffer, &RenderInfo);
```

### Metal 최적화

```objc
// Metal 특화 최적화

// 1. Argument Buffer (Bindless)
id<MTLArgumentEncoder> Encoder = [Function newArgumentEncoderWithBufferIndex:0];
[Encoder setBuffer:Buffer offset:0 atIndex:0];
[Encoder setTexture:Texture atIndex:1];

// 2. Indirect Command Buffer
id<MTLIndirectCommandBuffer> ICB = [Device newIndirectCommandBufferWithDescriptor:Desc
                                                                  maxCommandCount:1000
                                                                          options:0];
// GPU에서 커맨드 생성
[ComputeEncoder setBuffer:ICB offset:0 atIndex:0];
[ComputeEncoder dispatchThreads:...];

// 렌더에서 실행
[RenderEncoder executeCommandsInBuffer:ICB withRange:NSMakeRange(0, Count)];

// 3. 메모리 힙 사용
MTLHeapDescriptor* HeapDesc = [MTLHeapDescriptor new];
HeapDesc.size = 256 * 1024 * 1024;  // 256 MB
HeapDesc.storageMode = MTLStorageModePrivate;
id<MTLHeap> Heap = [Device newHeapWithDescriptor:HeapDesc];

// 힙에서 리소스 할당
id<MTLTexture> Texture = [Heap newTextureWithDescriptor:TextureDesc];
```

---

## 요약

플랫폼별 RHI 핵심:

1. **D3D12** - Windows 기본, Root Signature, ExecuteIndirect
2. **Vulkan** - 크로스 플랫폼, 확장 기반, 최저 오버헤드
3. **Metal** - Apple 전용, Tile Shading, Argument Buffer

UE RHI는 이러한 차이점을 추상화하여 플랫폼 독립적 렌더링 코드를 가능하게 합니다.

---

## 참고 자료

- [D3D12 프로그래밍 가이드](https://docs.microsoft.com/en-us/windows/win32/direct3d12/)
- [Vulkan 스펙](https://www.khronos.org/registry/vulkan/)
- [Metal 프로그래밍 가이드](https://developer.apple.com/metal/)
- [원문 시리즈 (중국어)](https://www.cnblogs.com/timlly/p/13512787.html)
