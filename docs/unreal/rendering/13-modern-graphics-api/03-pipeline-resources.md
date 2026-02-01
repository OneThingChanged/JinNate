# Pipeline 리소스

Command 모델, Render Pass, 리소스 관리를 설명합니다.

---

## Command 모델

### Command 계층 구조

```
┌─────────────────────────────────────────────────────────────────┐
│                    Command 계층 구조                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Command Queue                                                  │
│  ├── GPU 작업 실행 스케줄링                                    │
│  ├── 제출된 Command Buffer 순서대로 실행                       │
│  └── 여러 Queue 간 병렬 실행 가능                              │
│                                                                 │
│  Command Allocator (D3D12) / Command Pool (Vulkan)             │
│  ├── Command Buffer 메모리 관리                                │
│  ├── 스레드당 별도 Allocator 필요                              │
│  └── 프레임 완료 후 리셋 가능                                  │
│                                                                 │
│  Command Buffer / Command List                                  │
│  ├── GPU 명령 기록                                             │
│  ├── 재사용 가능 (리셋 후)                                     │
│  └── Primary / Secondary 레벨                                  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### API별 Command 매핑

| 개념 | DirectX 12 | Vulkan | Metal |
|------|-----------|--------|-------|
| Queue | ID3D12CommandQueue | VkQueue | MTLCommandQueue |
| Allocator | ID3D12CommandAllocator | VkCommandPool | 자동 관리 |
| Buffer | ID3D12GraphicsCommandList | VkCommandBuffer | MTLCommandBuffer |

### Command 사용 패턴

```
┌─────────────────────────────────────────────────────────────────┐
│                    Command 사용 흐름                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  프레임 N:                                                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  1. Command Buffer 획득 (Allocator에서)                 │   │
│  │     cmdBuffer = allocator.Allocate()                    │   │
│  │                                                         │   │
│  │  2. 기록 시작                                           │   │
│  │     cmdBuffer.Begin()                                   │   │
│  │                                                         │   │
│  │  3. 명령 기록                                           │   │
│  │     cmdBuffer.SetPipeline(...)                          │   │
│  │     cmdBuffer.SetDescriptorSets(...)                    │   │
│  │     cmdBuffer.Draw(...)                                 │   │
│  │                                                         │   │
│  │  4. 기록 종료                                           │   │
│  │     cmdBuffer.End()                                     │   │
│  │                                                         │   │
│  │  5. Queue에 제출                                        │   │
│  │     queue.Submit(cmdBuffer, fence)                      │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  프레임 N+2 (2프레임 후):                                       │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  • Fence 대기 (GPU 완료 확인)                           │   │
│  │  • Allocator 리셋 (메모리 재사용)                       │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Command Allocator 할당 전략

```
┌─────────────────────────────────────────────────────────────────┐
│              권장 Command Allocator 수                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  수식:                                                          │
│  Allocators = (Recording Threads × Buffered Frames) + Bundles  │
│                                                                 │
│  예시 (4 스레드, 3 프레임 버퍼링):                              │
│  • 메인 Allocators: 4 × 3 = 12개                               │
│  • Bundle Pool: 3개                                            │
│  • 총: 15개                                                    │
│                                                                 │
│  프레임당 Command Buffer:                                       │
│  • 일반적으로 15~30개                                          │
│  • 복잡한 장면에서 더 많을 수 있음                             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Render Pass

### 개념

Render Pass는 렌더링 작업의 입출력 리소스와 의존성을 정의합니다.

```
┌─────────────────────────────────────────────────────────────────┐
│                    Render Pass 구조                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Render Pass                                                    │
│  ├── Attachments (입출력 정의)                                 │
│  │   ├── Color Attachment 0 (G-Buffer A)                       │
│  │   ├── Color Attachment 1 (G-Buffer B)                       │
│  │   └── Depth Attachment                                      │
│  │                                                             │
│  ├── Subpass 0                                                 │
│  │   ├── Input: None                                           │
│  │   ├── Output: Color 0, Color 1, Depth                       │
│  │   └── 작업: Geometry 렌더링                                 │
│  │                                                             │
│  └── Subpass 1                                                 │
│      ├── Input: Color 0, Color 1, Depth (InputAttachment)      │
│      ├── Output: Swapchain Image                               │
│      └── 작업: Lighting 계산                                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Subpass의 장점

```
┌─────────────────────────────────────────────────────────────────┐
│                    Subpass 장점                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  TBDR GPU (모바일)에서:                                         │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Subpass 없이:                                          │   │
│  │  G-Buffer → System Memory → G-Buffer 읽기              │   │
│  │                  ↑                                      │   │
│  │            대역폭 낭비                                  │   │
│  │                                                         │   │
│  │  Subpass 사용:                                          │   │
│  │  G-Buffer → Tile Memory (유지) → Lighting              │   │
│  │                  ↑                                      │   │
│  │            대역폭 절약 (36~62%)                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  "작은 Render Pass라도 여러 Subpass로 구성하면 이점이 있다"     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Render Pass 코드 예시

```cpp
// Vulkan Render Pass 생성
VkAttachmentDescription attachments[3] = {};

// Color Attachment 0
attachments[0].format = VK_FORMAT_R8G8B8A8_SRGB;
attachments[0].loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR;
attachments[0].storeOp = VK_ATTACHMENT_STORE_OP_STORE;
attachments[0].initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
attachments[0].finalLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;

// Subpass 정의
VkSubpassDescription subpasses[2] = {};

// Subpass 0: G-Buffer 생성
subpasses[0].colorAttachmentCount = 2;
subpasses[0].pColorAttachments = colorRefs;
subpasses[0].pDepthStencilAttachment = &depthRef;

// Subpass 1: Lighting
subpasses[1].inputAttachmentCount = 3;
subpasses[1].pInputAttachments = inputRefs;  // Subpass 0 출력을 입력으로
subpasses[1].colorAttachmentCount = 1;
subpasses[1].pColorAttachments = &swapchainRef;
```

---

## 리소스 타입

### 텍스처와 버퍼

```
┌─────────────────────────────────────────────────────────────────┐
│                    리소스 타입                                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Texture                                                        │
│  ├── 1D, 2D, 3D, Cube, Array                                   │
│  ├── 밉맵 레벨                                                 │
│  └── 용도: 이미지 데이터, 렌더 타겟, 깊이 버퍼                 │
│                                                                 │
│  Buffer                                                         │
│  ├── Vertex Buffer: 정점 데이터                                │
│  ├── Index Buffer: 인덱스 데이터                               │
│  ├── Constant/Uniform Buffer: 셰이더 상수                      │
│  ├── Structured Buffer: 구조체 배열                            │
│  └── UAV/Storage Buffer: 읽기/쓰기 가능                        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### View (리소스 접근 방식)

```
┌─────────────────────────────────────────────────────────────────┐
│                    View 타입                                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  SRV (Shader Resource View)                                     │
│  ├── 셰이더에서 읽기 전용 접근                                 │
│  └── Texture2D<float4>, Buffer<T>                              │
│                                                                 │
│  UAV (Unordered Access View)                                    │
│  ├── 셰이더에서 읽기/쓰기 접근                                 │
│  └── RWTexture2D<float4>, RWBuffer<T>                          │
│                                                                 │
│  RTV (Render Target View)                                       │
│  ├── 렌더 타겟으로 쓰기                                        │
│  └── 픽셀 셰이더 출력 대상                                     │
│                                                                 │
│  DSV (Depth Stencil View)                                       │
│  ├── 깊이/스텐실 버퍼 접근                                     │
│  └── 깊이 테스트, 스텐실 연산                                  │
│                                                                 │
│  CBV (Constant Buffer View)                                     │
│  ├── 상수 버퍼 바인딩                                          │
│  └── 셰이더 uniform 데이터                                     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 셰이더와 파이프라인

### 셰이더 스테이지

```
┌─────────────────────────────────────────────────────────────────┐
│                    셰이더 스테이지                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Graphics Pipeline:                                             │
│  ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐     │
│  │   VS    │ →  │   HS    │ →  │   DS    │ →  │   GS    │     │
│  │ Vertex  │    │  Hull   │    │ Domain  │    │Geometry │     │
│  └─────────┘    └─────────┘    └─────────┘    └─────────┘     │
│                                      │                          │
│                                      ▼                          │
│                               ┌─────────────┐                  │
│                               │ Rasterizer  │                  │
│                               └──────┬──────┘                  │
│                                      │                          │
│                                      ▼                          │
│                               ┌─────────────┐                  │
│                               │     PS      │                  │
│                               │   Pixel     │                  │
│                               └─────────────┘                  │
│                                                                 │
│  Compute Pipeline:                                              │
│  ┌─────────────┐                                               │
│  │     CS      │                                               │
│  │  Compute    │                                               │
│  └─────────────┘                                               │
│                                                                 │
│  Mesh Shading Pipeline (D3D12/Vulkan):                          │
│  ┌─────────┐    ┌─────────┐                                    │
│  │   AS    │ →  │   MS    │ → Rasterizer → PS                  │
│  │Amplific.│    │  Mesh   │                                    │
│  └─────────┘    └─────────┘                                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 셰이더 언어

| API | 셰이더 언어 | 중간 표현 |
|-----|-----------|----------|
| DirectX 12 | HLSL | DXIL |
| Vulkan | GLSL/HLSL | SPIR-V |
| Metal | MSL | Metal IR |

---

## Descriptor와 바인딩

### Descriptor 구조

```
┌─────────────────────────────────────────────────────────────────┐
│                    Descriptor 시스템                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Descriptor:                                                    │
│  └── 리소스를 셰이더에 바인딩하기 위한 메타데이터               │
│                                                                 │
│  Descriptor Set (Vulkan) / Descriptor Table (D3D12):            │
│  ├── 여러 Descriptor를 그룹화                                  │
│  └── 한 번에 바인딩 가능                                       │
│                                                                 │
│  예시:                                                          │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Set 0 (Per-Frame)                                      │   │
│  │  ├── Binding 0: Camera UBO                              │   │
│  │  └── Binding 1: Light UBO                               │   │
│  │                                                         │   │
│  │  Set 1 (Per-Material)                                   │   │
│  │  ├── Binding 0: Albedo Texture                          │   │
│  │  ├── Binding 1: Normal Texture                          │   │
│  │  └── Binding 2: Roughness Texture                       │   │
│  │                                                         │   │
│  │  Set 2 (Per-Object)                                     │   │
│  │  └── Binding 0: Transform UBO                           │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Bindless (D3D12 SM6.6 / Vulkan 확장):                         │
│  └── 모든 리소스를 전역 배열로 접근                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 다음 단계

[Pipeline 메커니즘](04-pipeline-mechanisms.md)에서 PSO, 동기화, 메모리 관리를 알아봅니다.
