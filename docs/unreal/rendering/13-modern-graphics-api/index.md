# Ch.13 Modern Graphics API

DirectX 12, Vulkan, Metal 등 현대 그래픽 API의 구조와 핵심 개념을 분석합니다.

---

## 개요

현대 그래픽 API는 드라이버 오버헤드를 최소화하고 애플리케이션에 더 많은 제어권을 부여합니다. 이를 통해 멀티스레드 렌더링과 명시적 리소스 관리가 가능해집니다.

```
┌─────────────────────────────────────────────────────────────────┐
│                    현대 그래픽 API 계층                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    Application                           │   │
│  └───────────────────────┬─────────────────────────────────┘   │
│                          │                                      │
│  ┌───────────────────────┼─────────────────────────────────┐   │
│  │                 RHI Abstraction                          │   │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐       │   │
│  │  │  D3D12  │ │ Vulkan  │ │  Metal  │ │ OpenGL  │       │   │
│  │  └────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘       │   │
│  └───────┼───────────┼───────────┼───────────┼─────────────┘   │
│          │           │           │           │                  │
│  ┌───────┴───────────┴───────────┴───────────┴─────────────┐   │
│  │                      GPU Driver                          │   │
│  └───────────────────────┬─────────────────────────────────┘   │
│                          │                                      │
│  ┌───────────────────────┴─────────────────────────────────┐   │
│  │                     GPU Hardware                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## API 비교

| 특성 | DirectX 12 | Vulkan | Metal |
|------|-----------|--------|-------|
| **플랫폼** | Windows, Xbox | Cross-platform | Apple 전용 |
| **진입점** | IDXGIFactory4 | vk::Instance | CAMetalLayer |
| **장치** | ID3D12Device | vk::Device | MTLDevice |
| **커맨드** | Command List | Command Buffer | Command Buffer |
| **동기화** | Fence, Barrier | Semaphore, Fence, Barrier | MTLFence, Event |

---

## 핵심 개념

```
┌─────────────────────────────────────────────────────────────────┐
│                    현대 API 핵심 개념                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Device/Context                                                 │
│  ├── 물리 장치 (GPU 하드웨어)                                  │
│  └── 논리 장치 (API 인터페이스)                                │
│                                                                 │
│  Command Model                                                  │
│  ├── Command Queue (GPU 작업 스케줄링)                         │
│  ├── Command Allocator (메모리 관리)                           │
│  ├── Command Buffer (GPU 명령 기록)                            │
│  └── Command List (제출 단위)                                  │
│                                                                 │
│  Pipeline State                                                 │
│  ├── Shader Stages                                             │
│  ├── Render State                                              │
│  └── Resource Binding                                          │
│                                                                 │
│  Synchronization                                                │
│  ├── Barrier (리소스 상태 전환)                                │
│  ├── Fence (CPU-GPU 동기화)                                    │
│  └── Semaphore (큐 간 동기화)                                  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 레거시 vs 현대 API

```
┌─────────────────────────────────────────────────────────────────┐
│                 레거시 API vs 현대 API                           │
├────────────────────────────┬────────────────────────────────────┤
│     레거시 (D3D11, GL)     │        현대 (D3D12, Vulkan)        │
├────────────────────────────┼────────────────────────────────────┤
│ 드라이버가 리소스 관리     │ 애플리케이션이 리소스 관리         │
│ 암시적 동기화              │ 명시적 동기화                      │
│ 전역 상태 머신             │ PSO (Pipeline State Object)        │
│ 싱글스레드 커맨드 빌드     │ 멀티스레드 커맨드 빌드             │
│ 런타임 셰이더 컴파일       │ 사전 컴파일된 셰이더               │
│ 드라이버 오버헤드 높음     │ 드라이버 오버헤드 최소             │
│ 예측 불가능한 성능         │ 예측 가능한 성능                   │
└────────────────────────────┴────────────────────────────────────┘
```

---

## 문서 구성

| 문서 | 내용 |
|------|------|
| [API 개요](01-api-overview.md) | 현대 API 소개, 설계 철학 |
| [Device와 Context](02-device-context.md) | Device, Swapchain 구조 |
| [Pipeline 리소스](03-pipeline-resources.md) | Command, Render Pass, 리소스 |
| [Pipeline 메커니즘](04-pipeline-mechanisms.md) | PSO, 동기화, 메모리 관리 |
| [통합 응용](05-integrated-apps.md) | RHI, GPU-Driven 렌더링 |

---

## 참고 자료

- [원본 문서 (timlly)](https://www.cnblogs.com/timlly/p/15680064.html)
- [DirectX 12 Programming Guide](https://docs.microsoft.com/en-us/windows/win32/direct3d12/)
- [Vulkan Specification](https://www.khronos.org/registry/vulkan/specs/)
- [Metal Programming Guide](https://developer.apple.com/documentation/metal/)
