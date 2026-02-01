# Device와 Context

현대 그래픽 API의 Device, Context, Swapchain 구조를 설명합니다.

---

## Device 계층 구조

### Entry Point → Physical Device → Logical Device

```
┌─────────────────────────────────────────────────────────────────┐
│                    Device 계층 구조                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Entry Point (진입점)                                        │
│     ┌─────────────────────────────────────────────────────┐    │
│     │ D3D12:  IDXGIFactory4                                │    │
│     │ Vulkan: vk::Instance                                 │    │
│     │ Metal:  CAMetalLayer (또는 직접 MTLDevice 획득)      │    │
│     └─────────────────────────────────────────────────────┘    │
│                          │                                      │
│                          ▼                                      │
│  2. Physical Device (물리 장치)                                 │
│     ┌─────────────────────────────────────────────────────┐    │
│     │ D3D12:  IDXGIAdapter1                                │    │
│     │ Vulkan: vk::PhysicalDevice                           │    │
│     │ Metal:  MTLDevice (물리/논리 통합)                   │    │
│     │                                                     │    │
│     │ 역할:                                                │    │
│     │ • GPU 하드웨어 정보 조회                             │    │
│     │ • 지원 기능 확인                                    │    │
│     │ • 메모리 속성 조회                                  │    │
│     └─────────────────────────────────────────────────────┘    │
│                          │                                      │
│                          ▼                                      │
│  3. Logical Device (논리 장치)                                  │
│     ┌─────────────────────────────────────────────────────┐    │
│     │ D3D12:  ID3D12Device                                 │    │
│     │ Vulkan: vk::Device                                   │    │
│     │ Metal:  MTLDevice                                    │    │
│     │                                                     │    │
│     │ 역할:                                                │    │
│     │ • 리소스 생성 (텍스처, 버퍼)                        │    │
│     │ • 파이프라인 생성                                   │    │
│     │ • 큐 생성                                           │    │
│     │ • 커맨드 할당                                       │    │
│     └─────────────────────────────────────────────────────┘    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Device 생성 코드

### DirectX 12

```cpp
// 1. Factory 생성
ComPtr<IDXGIFactory4> factory;
CreateDXGIFactory2(0, IID_PPV_ARGS(&factory));

// 2. Adapter 열거
ComPtr<IDXGIAdapter1> adapter;
for (UINT i = 0; factory->EnumAdapters1(i, &adapter) != DXGI_ERROR_NOT_FOUND; ++i)
{
    DXGI_ADAPTER_DESC1 desc;
    adapter->GetDesc1(&desc);
    // 적절한 GPU 선택
}

// 3. Device 생성
ComPtr<ID3D12Device> device;
D3D12CreateDevice(adapter.Get(), D3D_FEATURE_LEVEL_12_0, IID_PPV_ARGS(&device));
```

### Vulkan

```cpp
// 1. Instance 생성
VkInstanceCreateInfo instanceInfo = {};
vkCreateInstance(&instanceInfo, nullptr, &instance);

// 2. Physical Device 열거
uint32_t deviceCount = 0;
vkEnumeratePhysicalDevices(instance, &deviceCount, nullptr);
std::vector<VkPhysicalDevice> devices(deviceCount);
vkEnumeratePhysicalDevices(instance, &deviceCount, devices.data());

// 3. Logical Device 생성
VkDeviceCreateInfo deviceInfo = {};
// Queue 정보 설정...
vkCreateDevice(physicalDevice, &deviceInfo, nullptr, &device);
```

---

## Swapchain

### 개념

Swapchain은 화면에 표시될 이미지 버퍼들을 관리합니다.

```
┌─────────────────────────────────────────────────────────────────┐
│                    Swapchain 구조                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                     Swapchain                            │   │
│  │                                                         │   │
│  │   ┌─────────┐    ┌─────────┐    ┌─────────┐            │   │
│  │   │ Image 0 │    │ Image 1 │    │ Image 2 │            │   │
│  │   │ (Back)  │    │ (Back)  │    │ (Front) │            │   │
│  │   └────┬────┘    └────┬────┘    └────┬────┘            │   │
│  │        │              │              │                  │   │
│  │        └──────────────┼──────────────┘                  │   │
│  │                       │                                 │   │
│  │                       ▼                                 │   │
│  │              ┌─────────────────┐                        │   │
│  │              │     Display     │                        │   │
│  │              └─────────────────┘                        │   │
│  │                                                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Present Mode:                                                  │
│  • FIFO (VSync): 수직 동기화, 티어링 방지                      │
│  • Mailbox: 트리플 버퍼링, 낮은 지연                           │
│  • Immediate: VSync 없음, 티어링 가능                          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 버퍼링 전략

```
┌─────────────────────────────────────────────────────────────────┐
│                    버퍼링 전략                                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Single Buffer:                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  [Buffer] ← 렌더링하면서 동시에 표시                    │   │
│  │  문제: 티어링, 깜빡임                                   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Double Buffer:                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  [Front] ← 표시 중                                      │   │
│  │  [Back]  ← 렌더링 중                                    │   │
│  │  VSync에서 교체                                         │   │
│  │  앱이 VSync보다 빠르면 대기                             │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Triple Buffer (권장):                                          │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  [Front]  ← 표시 중                                     │   │
│  │  [Back1]  ← 대기 중 (완료된 프레임)                     │   │
│  │  [Back2]  ← 렌더링 중                                   │   │
│  │  앱이 빨라도 계속 렌더링 가능                           │   │
│  │  가변 성능에서 부드러운 프레임                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Swapchain 생성

```cpp
// Vulkan Swapchain 생성 예시
VkSwapchainCreateInfoKHR createInfo = {};
createInfo.sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR;
createInfo.surface = surface;
createInfo.minImageCount = 3;  // Triple buffering
createInfo.imageFormat = VK_FORMAT_B8G8R8A8_SRGB;
createInfo.imageColorSpace = VK_COLOR_SPACE_SRGB_NONLINEAR_KHR;
createInfo.imageExtent = extent;
createInfo.imageArrayLayers = 1;
createInfo.imageUsage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
createInfo.presentMode = VK_PRESENT_MODE_MAILBOX_KHR;  // Low latency

vkCreateSwapchainKHR(device, &createInfo, nullptr, &swapchain);
```

---

## Queue

### Queue Family와 Queue

```
┌─────────────────────────────────────────────────────────────────┐
│                    Queue 구조                                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Device                                                         │
│  ├── Queue Family 0 (Graphics + Compute + Transfer)            │
│  │   ├── Queue 0                                               │
│  │   └── Queue 1                                               │
│  │                                                             │
│  ├── Queue Family 1 (Compute Only)                             │
│  │   └── Queue 0  ← Async Compute                             │
│  │                                                             │
│  └── Queue Family 2 (Transfer Only)                            │
│      └── Queue 0  ← DMA 전용                                  │
│                                                                 │
│  Queue 타입:                                                    │
│  • Graphics: 렌더링, 컴퓨트, 전송 모두 가능                    │
│  • Compute: 컴퓨트, 전송 가능                                  │
│  • Transfer: 전송만 가능 (DMA 전용)                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 큐 사용 전략

```cpp
// 병렬 큐 활용 예시
// Graphics Queue: 메인 렌더링
// Compute Queue: 비동기 컴퓨트 (SSAO, Blur 등)
// Transfer Queue: 텍스처 스트리밍

// Graphics Queue에 렌더링 제출
vkQueueSubmit(graphicsQueue, 1, &graphicsSubmitInfo, graphicsFence);

// Async Compute Queue에 병렬 작업 제출
vkQueueSubmit(computeQueue, 1, &computeSubmitInfo, computeFence);

// Transfer Queue에 리소스 업로드
vkQueueSubmit(transferQueue, 1, &transferSubmitInfo, transferFence);
```

---

## Surface와 Window 통합

```
┌─────────────────────────────────────────────────────────────────┐
│                    Surface 생성                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Window System Integration (WSI):                               │
│                                                                 │
│  ┌─────────────────┐                                           │
│  │   OS Window     │  ← HWND (Windows), NSWindow (macOS)       │
│  └────────┬────────┘                                           │
│           │                                                     │
│           ▼                                                     │
│  ┌─────────────────┐                                           │
│  │    Surface      │  ← API-specific surface                   │
│  └────────┬────────┘                                           │
│           │                                                     │
│           ▼                                                     │
│  ┌─────────────────┐                                           │
│  │   Swapchain     │  ← 렌더링 대상 이미지들                   │
│  └─────────────────┘                                           │
│                                                                 │
│  플랫폼별 Surface 생성:                                         │
│  • Windows: VK_KHR_win32_surface                               │
│  • Linux:   VK_KHR_xcb_surface 또는 VK_KHR_wayland_surface    │
│  • Android: VK_KHR_android_surface                             │
│  • macOS:   VK_MVK_macos_surface (MoltenVK)                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 다음 단계

[Pipeline 리소스](03-pipeline-resources.md)에서 Command와 Render Pass를 알아봅니다.
