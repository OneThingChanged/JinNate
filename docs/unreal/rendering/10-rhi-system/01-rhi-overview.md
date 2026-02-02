# 01. RHI 개요

RHI의 아키텍처, 초기화 과정, 핵심 인터페이스를 분석합니다.

![Render Hardware Interface](../images/ch09/1617944-20210818142133976-1341431184.jpg)

*RHI 개념 - D3D11 API 기반 설계, 리소스 관리와 커맨드 인터페이스 제공*

---

## RHI 아키텍처

### 모듈 구조

```
┌─────────────────────────────────────────────────────────────────┐
│                    RHI 모듈 구조                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Engine/Source/Runtime/                                        │
│  │                                                              │
│  ├── RHI/                      ← RHI 인터페이스 정의            │
│  │   ├── Public/                                               │
│  │   │   ├── RHI.h                 메인 헤더                   │
│  │   │   ├── RHIResources.h        리소스 클래스               │
│  │   │   ├── RHICommandList.h      커맨드 리스트               │
│  │   │   └── RHIDefinitions.h      열거형, 상수                │
│  │   └── Private/                                              │
│  │       └── RHI.cpp               공통 구현                   │
│  │                                                              │
│  ├── RHICore/                  ← RHI 공통 유틸리티              │
│  │                                                              │
│  ├── D3D12RHI/                 ← DirectX 12 구현               │
│  ├── VulkanRHI/                ← Vulkan 구현                   │
│  ├── MetalRHI/                 ← Metal 구현                    │
│  ├── OpenGLDrv/                ← OpenGL 구현                   │
│  └── NullDrv/                  ← Null RHI (헤드리스)           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 핵심 인터페이스

```cpp
// 동적 RHI 인터페이스
class FDynamicRHI
{
public:
    virtual ~FDynamicRHI() {}

    // 초기화
    virtual void Init() = 0;
    virtual void Shutdown() = 0;

    // 리소스 생성
    virtual FTexture2DRHIRef RHICreateTexture2D(
        uint32 SizeX, uint32 SizeY,
        uint8 Format, uint32 NumMips,
        uint32 NumSamples, ETextureCreateFlags Flags,
        const FRHIResourceCreateInfo& CreateInfo) = 0;

    virtual FBufferRHIRef RHICreateBuffer(
        uint32 Size, EBufferUsageFlags Usage,
        uint32 Stride, ERHIAccess Access,
        const FRHIResourceCreateInfo& CreateInfo) = 0;

    // 셰이더 생성
    virtual FVertexShaderRHIRef RHICreateVertexShader(
        TArrayView<const uint8> Code,
        const FSHAHash& Hash) = 0;

    virtual FPixelShaderRHIRef RHICreatePixelShader(
        TArrayView<const uint8> Code,
        const FSHAHash& Hash) = 0;

    // PSO 생성
    virtual FGraphicsPipelineStateRHIRef RHICreateGraphicsPipelineState(
        const FGraphicsPipelineStateInitializer& Initializer) = 0;

    // 커맨드 리스트
    virtual FRHICommandList* RHIGetCommandList() = 0;
};

// 전역 RHI 인스턴스
extern RHI_API FDynamicRHI* GDynamicRHI;
```

![FDynamicRHI 클래스 계층](../images/ch09/1617944-20210818142245463-248526293.jpg)

*FDynamicRHI 클래스 계층 - D3D11, Metal, OpenGL, D3D12, Vulkan 등 플랫폼별 구현*

---

## RHI 초기화

### 초기화 흐름

```
┌─────────────────────────────────────────────────────────────────┐
│                    RHI 초기화 순서                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. 플랫폼 감지                                                  │
│     │                                                           │
│     ▼                                                           │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  FPlatformMisc::GetGPUInfo()                            │   │
│  │  - GPU 벤더, 모델, 드라이버 버전                         │   │
│  │  - 지원 기능 확인 (Ray Tracing, Mesh Shader 등)          │   │
│  └────────────────────────┬────────────────────────────────┘   │
│                           │                                     │
│  2. RHI 모듈 로드          ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  FModuleManager::LoadModule(RHIModuleName)              │   │
│  │  - "D3D12RHI", "VulkanRHI", "MetalRHI" 등              │   │
│  └────────────────────────┬────────────────────────────────┘   │
│                           │                                     │
│  3. RHI 생성              ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  PlatformCreateDynamicRHI()                             │   │
│  │  - 각 플랫폼 모듈에서 구현                               │   │
│  │  - GDynamicRHI에 할당                                    │   │
│  └────────────────────────┬────────────────────────────────┘   │
│                           │                                     │
│  4. 디바이스 초기화        ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  GDynamicRHI->Init()                                    │   │
│  │  - GPU 디바이스 생성                                     │   │
│  │  - 커맨드 큐 생성                                        │   │
│  │  - 힙/메모리 풀 초기화                                   │   │
│  └────────────────────────┬────────────────────────────────┘   │
│                           │                                     │
│  5. 렌더링 준비 완료       ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  GIsRHIInitialized = true                               │   │
│  │  → 렌더링 시스템 사용 가능                               │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 초기화 코드

```cpp
// RHI 선택 및 초기화
void RHIInit(bool bHasEditorToken)
{
    // 1. 사용할 RHI 결정
    FString RHIName = GetSelectedRHIModuleName();

    // 커맨드라인 오버라이드 확인
    if (FParse::Value(FCommandLine::Get(), TEXT("-rhi="), RHIName))
    {
        // 명시적 RHI 지정
    }

    // 2. RHI 모듈 로드
    IDynamicRHIModule* DynamicRHIModule =
        FModuleManager::LoadModulePtr<IDynamicRHIModule>(*RHIName);

    // 3. 지원 여부 확인
    if (!DynamicRHIModule->IsSupported())
    {
        // 폴백 RHI 시도
        RHIName = GetFallbackRHIModuleName();
        DynamicRHIModule = FModuleManager::LoadModulePtr<IDynamicRHIModule>(*RHIName);
    }

    // 4. RHI 생성
    GDynamicRHI = DynamicRHIModule->CreateRHI();

    // 5. 초기화
    GDynamicRHI->Init();

    // 6. 전역 플래그 설정
    GIsRHIInitialized = true;
    GMaxRHIFeatureLevel = GDynamicRHI->GetMaxFeatureLevel();
    GMaxRHIShaderPlatform = GDynamicRHI->GetShaderPlatform();
}

// RHI 종료
void RHIExit()
{
    if (GDynamicRHI)
    {
        GDynamicRHI->Shutdown();
        delete GDynamicRHI;
        GDynamicRHI = nullptr;
    }
    GIsRHIInitialized = false;
}
```

---

## RHI 함수 인터페이스

### 글로벌 RHI 함수

```cpp
// 리소스 생성 함수 (글로벌 래퍼)
inline FTexture2DRHIRef RHICreateTexture2D(
    uint32 SizeX, uint32 SizeY,
    EPixelFormat Format, uint32 NumMips,
    uint32 NumSamples, ETextureCreateFlags Flags,
    const FRHIResourceCreateInfo& CreateInfo)
{
    return GDynamicRHI->RHICreateTexture2D(
        SizeX, SizeY, Format, NumMips, NumSamples, Flags, CreateInfo);
}

inline FBufferRHIRef RHICreateBuffer(
    uint32 Size, EBufferUsageFlags Usage,
    uint32 Stride, ERHIAccess Access,
    const FRHIResourceCreateInfo& CreateInfo)
{
    return GDynamicRHI->RHICreateBuffer(Size, Usage, Stride, Access, CreateInfo);
}

// 셰이더 생성
inline FVertexShaderRHIRef RHICreateVertexShader(
    TArrayView<const uint8> Code, const FSHAHash& Hash)
{
    return GDynamicRHI->RHICreateVertexShader(Code, Hash);
}

// 뷰포트 생성
inline FViewportRHIRef RHICreateViewport(
    void* WindowHandle, uint32 SizeX, uint32 SizeY, bool bIsFullscreen)
{
    return GDynamicRHI->RHICreateViewport(WindowHandle, SizeX, SizeY, bIsFullscreen);
}
```

### 커맨드 리스트 명령

```cpp
// FRHICommandList 주요 명령어
class FRHICommandList
{
public:
    // 상태 설정
    void SetGraphicsPipelineState(FRHIGraphicsPipelineState* PSO);
    void SetComputePipelineState(FRHIComputePipelineState* PSO);

    // 리소스 바인딩
    void SetShaderTexture(FRHIPixelShader* Shader, uint32 Index, FRHITexture* Texture);
    void SetShaderSampler(FRHIPixelShader* Shader, uint32 Index, FRHISamplerState* Sampler);
    void SetShaderUniformBuffer(FRHIVertexShader* Shader, uint32 Index, FRHIUniformBuffer* UB);

    // 렌더 타겟
    void SetRenderTargets(
        uint32 NumRTs, const FRHIRenderTargetView* RTs,
        FRHITexture* DepthStencil);

    // 드로우 콜
    void DrawPrimitive(uint32 BaseVertexIndex, uint32 NumPrimitives, uint32 NumInstances);
    void DrawIndexedPrimitive(
        FRHIBuffer* IndexBuffer,
        int32 BaseVertexIndex, uint32 FirstInstance,
        uint32 NumVertices, uint32 StartIndex,
        uint32 NumPrimitives, uint32 NumInstances);

    // 디스패치
    void DispatchComputeShader(uint32 ThreadGroupCountX, uint32 ThreadGroupCountY, uint32 ThreadGroupCountZ);

    // 리소스 전환
    void Transition(TArrayView<const FRHITransitionInfo> Transitions);

    // 동기화
    void BeginRenderPass(const FRHIRenderPassInfo& Info);
    void EndRenderPass();
};
```

---

## 리소스 참조 관리

### 스마트 포인터

```cpp
// TRefCountPtr 기반 리소스 참조
template<typename ReferencedType>
using TRHIRef = TRefCountPtr<ReferencedType>;

// 타입별 별칭
using FTexture2DRHIRef = TRHIRef<FRHITexture2D>;
using FBufferRHIRef = TRHIRef<FRHIBuffer>;
using FVertexShaderRHIRef = TRHIRef<FRHIVertexShader>;
using FPixelShaderRHIRef = TRHIRef<FRHIPixelShader>;
using FUniformBufferRHIRef = TRHIRef<FRHIUniformBuffer>;

// 사용 예시
void CreateResources()
{
    // 리소스 생성 (자동 참조 카운팅)
    FTexture2DRHIRef Texture = RHICreateTexture2D(
        1024, 1024, PF_R8G8B8A8,
        1, 1, TexCreate_RenderTargetable,
        CreateInfo);

    // 복사 시 참조 카운트 증가
    FTexture2DRHIRef TextureCopy = Texture;  // RefCount = 2

    // 스코프 벗어나면 자동 해제
}  // RefCount = 0, 리소스 파괴
```

### 지연 삭제

```
┌─────────────────────────────────────────────────────────────────┐
│                    RHI 리소스 수명 관리                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  문제: GPU가 아직 사용 중인 리소스를 삭제하면 안됨               │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Frame N                                                │   │
│  │    CPU: 리소스 참조 해제 (RefCount = 0)                 │   │
│  │    GPU: 아직 Frame N-2 처리 중 (리소스 사용 중!)        │   │
│  │    → 바로 삭제하면 크래시                               │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  해결: 지연 삭제 큐                                             │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  1. RefCount = 0 → DeferredDeletionQueue에 추가         │   │
│  │  2. 여러 프레임 대기 (보통 3프레임)                      │   │
│  │  3. GPU 펜스 확인 후 안전하게 삭제                       │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  코드:                                                          │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  void FRHIResource::Release()                           │   │
│  │  {                                                      │   │
│  │      if (--NumRefs == 0)                                │   │
│  │      {                                                  │   │
│  │          // 즉시 삭제 대신 큐에 추가                     │   │
│  │          DeferredDeletionQueue.Enqueue(this);           │   │
│  │      }                                                  │   │
│  │  }                                                      │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## RHI 기능 레벨

### Feature Level

```cpp
// 지원 기능 레벨
enum class ERHIFeatureLevel : uint8
{
    ES3_1,      // OpenGL ES 3.1 / 모바일
    SM5,        // Shader Model 5 / DX11 수준
    SM6,        // Shader Model 6 / DX12 수준
};

// 기능 레벨별 지원 기능
┌────────────────────────────────────────────────────────────────┐
│                    기능 레벨 비교                               │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│  기능              ES3_1    SM5      SM6                       │
│  ───────────────  ───────  ───────  ───────                   │
│  Compute Shader    제한적   지원     지원                      │
│  Tessellation      미지원   지원     지원                      │
│  Geometry Shader   미지원   지원     지원                      │
│  Wave Intrinsics   미지원   미지원   지원                      │
│  Mesh Shader       미지원   미지원   지원                      │
│  Ray Tracing       미지원   미지원   지원 (HW 필요)            │
│  Variable Rate     미지원   미지원   지원                      │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

### 런타임 기능 확인

```cpp
// RHI 기능 확인
bool SupportsRayTracing()
{
    return GRHISupportsRayTracing && IsRHIDeviceNVIDIA(); // 예시
}

bool SupportsMeshShaders()
{
    return GRHISupportsMeshShaders;
}

bool SupportsVariableRateShading()
{
    return GRHISupportsVariableRateShading;
}

// Feature Level 확인
if (GMaxRHIFeatureLevel >= ERHIFeatureLevel::SM6)
{
    // SM6 기능 사용 가능
    UseMeshShaders();
}
else if (GMaxRHIFeatureLevel >= ERHIFeatureLevel::SM5)
{
    // SM5 폴백
    UseTraditionalPipeline();
}

// 플랫폼별 분기
switch (GMaxRHIShaderPlatform)
{
case SP_PCD3D_SM6:
    // Windows DX12
    break;
case SP_VULKAN_SM5:
    // Vulkan
    break;
case SP_METAL_SM5:
    // Metal
    break;
}
```

---

## RHI 디버깅

### 디버그 레이어

```cpp
// D3D12 디버그 레이어 활성화
#if UE_BUILD_DEBUG || UE_BUILD_DEVELOPMENT
void EnableDebugLayer()
{
    ID3D12Debug* DebugController;
    if (SUCCEEDED(D3D12GetDebugInterface(IID_PPV_ARGS(&DebugController))))
    {
        DebugController->EnableDebugLayer();

        // GPU 기반 검증 (느리지만 상세함)
        ID3D12Debug1* DebugController1;
        if (SUCCEEDED(DebugController->QueryInterface(IID_PPV_ARGS(&DebugController1))))
        {
            DebugController1->SetEnableGPUBasedValidation(true);
        }
    }
}
#endif

// Vulkan 검증 레이어
const char* ValidationLayers[] = {
    "VK_LAYER_KHRONOS_validation"
};
```

### RHI 통계

```cpp
// 콘솔 명령어
// stat rhi          - RHI 통계 표시
// stat d3d12rhi     - D3D12 상세 통계
// stat vulkanrhi    - Vulkan 상세 통계

// 주요 통계 항목
// - Draw calls
// - Primitives drawn
// - Textures created/destroyed
// - Buffers created/destroyed
// - Memory usage
// - Command list submissions
```

---

## 요약

RHI 핵심 개념:

1. **추상화 계층** - 플랫폼 독립적 그래픽스 인터페이스
2. **동적 로딩** - 런타임에 적절한 RHI 모듈 선택
3. **리소스 관리** - 참조 카운팅, 지연 삭제
4. **커맨드 인터페이스** - FRHICommandList로 GPU 명령 발행
5. **기능 레벨** - ES3.1/SM5/SM6 수준별 기능 분기

RHI는 UE 렌더링의 최하위 레이어로, 상위 렌더링 코드를 플랫폼 세부사항에서 격리합니다.

---

## 참고 자료

- [UE RHI 소스코드](https://github.com/EpicGames/UnrealEngine/tree/release/Engine/Source/Runtime/RHI)
- [원문 시리즈 (중국어)](https://www.cnblogs.com/timlly/p/13512787.html)
---

<div style="display: flex; justify-content: space-between; align-items: center; padding: 16px 0;">
  <a href="../" style="text-decoration: none;">← 이전: Ch.09 개요</a>
  <a href="../02-rhi-resources/" style="text-decoration: none;">다음: 02. RHI 리소스 →</a>
</div>
