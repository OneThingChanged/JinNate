# RDG 기초 타입

> 원문: [剖析虚幻渲染体系（11）- RDG](https://www.cnblogs.com/timlly/p/15217090.html)

RDG의 기본 열거형, 리소스 타입, Pass 구조체, FRDGBuilder 클래스를 상세히 설명합니다.

---

## 11.2.1 열거형 정의

### ERDGPassFlags (Pass 플래그)

Pass의 타입과 실행 속성을 정의하는 플래그입니다.

```cpp
// Engine/Source/Runtime/RenderCore/Public/RenderGraphDefinitions.h

enum class ERDGPassFlags : uint8
{
    // 기본 Pass 타입
    None = 0,

    // 래스터화 Pass - Vertex/Pixel Shader 사용
    Raster = 1 << 0,

    // 컴퓨트 Pass - Compute Shader 사용
    Compute = 1 << 1,

    // 비동기 컴퓨트 Pass - AsyncCompute 큐에서 실행
    AsyncCompute = 1 << 2,

    // 복사 Pass - CopyTexture/CopyBuffer
    Copy = 1 << 3,

    // 컬링에서 제외 - 항상 실행
    NeverCull = 1 << 4,

    // Begin/EndRenderPass 호출 생략 - 수동 제어
    SkipRenderPass = 1 << 5,

    // UAV 오버랩 허용 (동일 리소스 여러 UAV 바인딩)
    UntrackedAccess = 1 << 6,

    // 조합 플래그
    CommandListBegin = Copy | NeverCull,       // 커맨드 리스트 시작
    CommandListEnd = Copy | NeverCull,         // 커맨드 리스트 종료
};
ENUM_CLASS_FLAGS(ERDGPassFlags);
```

```
┌─────────────────────────────────────────────────────────────────┐
│                    Pass 타입별 특성                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │    Raster    │  │   Compute    │  │ AsyncCompute │          │
│  ├──────────────┤  ├──────────────┤  ├──────────────┤          │
│  │ VS/PS 실행   │  │ CS 실행      │  │ CS 비동기    │          │
│  │ RenderTarget │  │ UAV 출력     │  │ 병렬 실행    │          │
│  │ 동기 실행    │  │ 동기 실행    │  │ Fork/Join   │          │
│  │ BeginRP 호출 │  │ 배리어 처리  │  │ 교차큐 펜스  │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │     Copy     │  │  NeverCull   │  │SkipRenderPass│          │
│  ├──────────────┤  ├──────────────┤  ├──────────────┤          │
│  │ 리소스 복사  │  │ 항상 실행    │  │ RenderPass   │          │
│  │ CopyTexture  │  │ 컬링 제외    │  │ 설정 생략    │          │
│  │ CopyBuffer   │  │ 디버그/필수용│  │ 수동 제어    │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### ERDGTextureFlags (텍스처 플래그)

```cpp
enum class ERDGTextureFlags : uint8
{
    None = 0,

    // 여러 프레임에 걸쳐 유지되는 텍스처
    // RDG가 자동으로 해제하지 않음
    MultiFrame = 1 << 0,

    // 압축 상태 유지 (DCC, HTILE 등)
    // 레이아웃 전환 시 압축 메타데이터 보존
    MaintainCompression = 1 << 1,
};
ENUM_CLASS_FLAGS(ERDGTextureFlags);
```

### ERDGBufferFlags (버퍼 플래그)

```cpp
enum class ERDGBufferFlags : uint8
{
    None = 0,

    // 여러 프레임에 걸쳐 유지되는 버퍼
    MultiFrame = 1 << 0,
};
ENUM_CLASS_FLAGS(ERDGBufferFlags);
```

### ERDGUnorderedAccessViewFlags (UAV 플래그)

```cpp
enum class ERDGUnorderedAccessViewFlags : uint8
{
    None = 0,

    // 배리어 생략 (개발자가 직접 관리)
    // 고급 최적화나 특수 케이스용
    SkipBarrier = 1 << 0,
};
ENUM_CLASS_FLAGS(ERDGUnorderedAccessViewFlags);
```

### ERDGViewType (뷰 타입)

```cpp
enum class ERDGViewType : uint8
{
    TextureUAV,    // 텍스처 UAV
    TextureSRV,    // 텍스처 SRV
    BufferUAV,     // 버퍼 UAV
    BufferSRV,     // 버퍼 SRV
};
```

---

## 11.2.2 리소스 기본 클래스

### FRDGResource

모든 RDG 리소스의 추상 기본 클래스입니다. RHI 리소스 래핑, 생명주기 추적, 디버그 검증 기능을 제공합니다.

```cpp
// Engine/Source/Runtime/RenderCore/Public/RenderGraphResources.h

class RENDERCORE_API FRDGResource
{
public:
    // 디버그용 리소스 이름
    const TCHAR* Name = nullptr;

protected:
    // 참조 카운트 - Pass에서 참조될 때마다 증가
    uint16 ReferenceCount = 0;

    // 외부에서 등록된 리소스 (RegisterExternal*)
    uint8 bExternal : 1;

    // 추출 예정 (QueueExtraction 호출됨)
    uint8 bExtracted : 1;

    // 컬링됨 (사용되지 않음)
    uint8 bCulled : 1;

    // 전환이 필요한 상태
    uint8 bTransient : 1;

    // 첫 Pass (생명주기 시작)
    FRDGPassHandle FirstPass;

    // 마지막 Pass (생명주기 종료)
    FRDGPassHandle LastPass;

#if RDG_ENABLE_DEBUG
    // 디버그 데이터
    FRDGResourceDebugData DebugData;
#endif
};
```

```
┌─────────────────────────────────────────────────────────────────┐
│                    FRDGResource 구조                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  FRDGResource (추상 기본 클래스)                                │
│  │                                                              │
│  ├── Name: const TCHAR*         // 디버그용 이름                │
│  ├── ReferenceCount: uint16     // 참조 카운트                  │
│  │                                                              │
│  ├── Flags (비트 필드):                                         │
│  │   ├── bExternal              // 외부 리소스 여부             │
│  │   ├── bExtracted             // 추출 예정 여부               │
│  │   ├── bCulled                // 컬링 여부                    │
│  │   └── bTransient             // 임시 리소스 여부             │
│  │                                                              │
│  ├── FirstPass: FRDGPassHandle  // 생명주기 시작 Pass           │
│  ├── LastPass: FRDGPassHandle   // 생명주기 종료 Pass           │
│  │                                                              │
│  └── DebugData                  // 디버그 정보 (DEBUG 빌드)     │
│                                                                 │
│  핵심 기능:                                                     │
│  • RHI 리소스 캡슐화                                            │
│  • 생명주기 추적 (First/Last Pass)                              │
│  • 접근 권한 검증 (Pass 실행 시에만 허용)                       │
│  • 디버그 정보 제공                                             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 11.2.3 텍스처 리소스 (FRDGTexture)

### FRDGTextureDesc (텍스처 디스크립터)

텍스처 생성에 필요한 모든 속성을 정의합니다.

```cpp
struct RENDERCORE_API FRDGTextureDesc
{
    // 텍스처 차원 (1D, 2D, 3D, Cube, 2DArray, CubeArray)
    ETextureDimension Dimension = ETextureDimension::Texture2D;

    // 생성 플래그 (RenderTargetable, ShaderResource, UAV 등)
    ETextureCreateFlags Flags = TexCreate_None;

    // 픽셀 포맷
    EPixelFormat Format = PF_Unknown;

    // 클리어 값 (Fast Clear 최적화용)
    FClearValueBinding ClearValue;

    // 2D 크기 (Width, Height)
    FIntPoint Extent = FIntPoint(1, 1);

    // 3D 텍스처 깊이
    uint16 Depth = 1;

    // 배열 크기 (2DArray, CubeArray용)
    uint16 ArraySize = 1;

    // 밉맵 개수
    uint8 NumMips = 1;

    // MSAA 샘플 수
    uint8 NumSamples = 1;

    // 팩터리 메서드
    static FRDGTextureDesc Create2D(
        FIntPoint InExtent,
        EPixelFormat InFormat,
        FClearValueBinding InClearValue = FClearValueBinding::None,
        ETextureCreateFlags InFlags = TexCreate_None,
        uint8 InNumMips = 1,
        uint8 InNumSamples = 1
    );

    static FRDGTextureDesc Create3D(
        FIntVector InSize,
        EPixelFormat InFormat,
        ETextureCreateFlags InFlags = TexCreate_None
    );

    static FRDGTextureDesc CreateCube(
        int32 InExtent,
        EPixelFormat InFormat,
        ETextureCreateFlags InFlags = TexCreate_None,
        uint8 InNumMips = 1
    );

    static FRDGTextureDesc Create2DArray(
        FIntPoint InExtent,
        EPixelFormat InFormat,
        uint16 InArraySize,
        ETextureCreateFlags InFlags = TexCreate_None,
        uint8 InNumMips = 1
    );
};
```

### FRDGTexture 클래스

```cpp
class RENDERCORE_API FRDGTexture : public FRDGResource
{
public:
    // 텍스처 디스크립터
    const FRDGTextureDesc Desc;

    // 서브리소스 레이아웃 (밉맵, 배열 슬라이스별 상태)
    const FRDGTextureSubresourceLayout Layout;

    // 풀링된 렌더 타겟 (할당 후 설정)
    IPooledRenderTarget* PooledRenderTarget = nullptr;

    // RHI 텍스처 접근 (Execute 단계에서만 유효)
    FRHITexture* GetRHI() const;

    // 풀링된 RT 접근
    IPooledRenderTarget* GetPooledRenderTarget() const;

private:
    // 서브리소스별 상태 (밉맵, 배열 슬라이스)
    TArray<FRDGTextureSubresourceState> SubresourceState;
};
```

```
┌─────────────────────────────────────────────────────────────────┐
│                    텍스처 리소스 계층 구조                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  FRDGTexture (RDG 핸들)                                         │
│       │ • 논리적 리소스 핸들                                    │
│       │ • 디스크립터 보유                                       │
│       │ • 서브리소스 상태 추적                                  │
│       │                                                         │
│       ▼                                                         │
│  IPooledRenderTarget (풀 관리)                                  │
│       │ • 메모리 풀에서 할당/반환                               │
│       │ • 재사용 가능                                           │
│       │ • 앨리어싱 지원                                         │
│       │                                                         │
│       ▼                                                         │
│  FRHITexture (RHI 리소스)                                       │
│       │ • 플랫폼별 구현                                         │
│       │ • D3D12/Vulkan/Metal 리소스                             │
│       │                                                         │
│       ▼                                                         │
│  GPU Memory (실제 메모리)                                       │
│         • VRAM에 실제 할당                                      │
│                                                                 │
│  접근 규칙:                                                     │
│  • FRDGTexture: AddPass, CreateSRV/UAV 시 사용                 │
│  • GetRHI(): Pass Lambda 내에서만 호출 가능                    │
│  • Execute() 전에는 RHI 리소스 직접 접근 불가                  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 텍스처 생성 예시

```cpp
// 2D 렌더 타겟 텍스처
FRDGTextureDesc RTDesc = FRDGTextureDesc::Create2D(
    FIntPoint(1920, 1080),                    // 해상도
    PF_FloatRGBA,                              // 포맷
    FClearValueBinding::Black,                 // 클리어 값
    TexCreate_RenderTargetable |               // 렌더 타겟
    TexCreate_ShaderResource                   // SRV로도 사용
);

FRDGTextureRef MyRT = GraphBuilder.CreateTexture(RTDesc, TEXT("MyRenderTarget"));

// 3D 볼륨 텍스처
FRDGTextureDesc VolumeDesc = FRDGTextureDesc::Create3D(
    FIntVector(128, 128, 128),                // 3D 크기
    PF_R16F,                                   // 포맷
    TexCreate_UAV | TexCreate_ShaderResource  // UAV + SRV
);

FRDGTextureRef VolumeTex = GraphBuilder.CreateTexture(VolumeDesc, TEXT("VolumeData"));

// 큐브맵 텍스처
FRDGTextureDesc CubeDesc = FRDGTextureDesc::CreateCube(
    512,                                       // 각 면 크기
    PF_FloatRGBA,                              // 포맷
    TexCreate_RenderTargetable,                // 렌더 타겟
    /* NumMips */ 6                            // 밉맵 개수
);

FRDGTextureRef CubeTex = GraphBuilder.CreateTexture(CubeDesc, TEXT("EnvironmentCube"));
```

---

## 11.2.4 버퍼 리소스 (FRDGBuffer)

### FRDGBufferDesc (버퍼 디스크립터)

```cpp
struct RENDERCORE_API FRDGBufferDesc
{
    // 요소당 바이트 수
    uint32 BytesPerElement = 1;

    // 요소 개수
    uint32 NumElements = 0;

    // 사용 용도 플래그
    EBufferUsageFlags Usage = BUF_None;

    // Structured Buffer 생성
    static FRDGBufferDesc CreateStructuredDesc(
        uint32 BytesPerElement,
        uint32 NumElements
    )
    {
        FRDGBufferDesc Desc;
        Desc.BytesPerElement = BytesPerElement;
        Desc.NumElements = NumElements;
        Desc.Usage = BUF_StructuredBuffer | BUF_ShaderResource | BUF_UnorderedAccess;
        return Desc;
    }

    // 일반 버퍼 생성
    static FRDGBufferDesc CreateBufferDesc(
        uint32 BytesPerElement,
        uint32 NumElements
    )
    {
        FRDGBufferDesc Desc;
        Desc.BytesPerElement = BytesPerElement;
        Desc.NumElements = NumElements;
        Desc.Usage = BUF_ShaderResource | BUF_UnorderedAccess;
        return Desc;
    }

    // Byte Address Buffer 생성
    static FRDGBufferDesc CreateByteAddressDesc(uint32 NumBytes)
    {
        FRDGBufferDesc Desc;
        Desc.BytesPerElement = 4;
        Desc.NumElements = NumBytes / 4;
        Desc.Usage = BUF_ByteAddressBuffer | BUF_ShaderResource | BUF_UnorderedAccess;
        return Desc;
    }

    // 간접 드로우 버퍼
    static FRDGBufferDesc CreateIndirectDesc(uint32 NumElements)
    {
        FRDGBufferDesc Desc;
        Desc.BytesPerElement = sizeof(uint32);
        Desc.NumElements = NumElements;
        Desc.Usage = BUF_DrawIndirect | BUF_ShaderResource | BUF_UnorderedAccess;
        return Desc;
    }
};
```

### FRDGBuffer 클래스

```cpp
class RENDERCORE_API FRDGBuffer : public FRDGResource
{
public:
    // 버퍼 디스크립터
    const FRDGBufferDesc Desc;

    // 풀링된 버퍼
    FRDGPooledBuffer* PooledBuffer = nullptr;

    // RHI 버퍼 접근 (Execute 단계에서만)
    FRHIBuffer* GetRHI() const;

    // 총 바이트 크기
    uint32 GetSize() const { return Desc.BytesPerElement * Desc.NumElements; }
};
```

```
┌─────────────────────────────────────────────────────────────────┐
│                    버퍼 타입별 용도                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────────┐  ┌──────────────────┐                    │
│  │ Structured Buffer │  │ Byte Address Buffer│                  │
│  ├──────────────────┤  ├──────────────────┤                    │
│  │ 구조체 배열       │  │ Raw 바이트 접근   │                    │
│  │ StructuredBuffer<T>│ │ ByteAddressBuffer │                    │
│  │ 타입 안전         │  │ 유연한 오프셋     │                    │
│  │ 컴퓨트 입출력     │  │ 가변 데이터       │                    │
│  └──────────────────┘  └──────────────────┘                    │
│                                                                 │
│  ┌──────────────────┐  ┌──────────────────┐                    │
│  │   Indirect Args   │  │   Append/Consume  │                    │
│  ├──────────────────┤  ├──────────────────┤                    │
│  │ 간접 드로우 인자  │  │ 동적 카운터 버퍼  │                    │
│  │ DrawIndirect      │  │ AppendBuffer      │                    │
│  │ DispatchIndirect  │  │ ConsumeBuffer     │                    │
│  │ GPU 드리븐 렌더링 │  │ 스트림 출력       │                    │
│  └──────────────────┘  └──────────────────┘                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 버퍼 생성 예시

```cpp
// 구조체 정의
struct FMyParticle
{
    FVector4f Position;
    FVector4f Velocity;
    float Lifetime;
    float Size;
};

// Structured Buffer 생성
FRDGBufferDesc ParticleBufferDesc = FRDGBufferDesc::CreateStructuredDesc(
    sizeof(FMyParticle),    // 구조체 크기
    10000                   // 파티클 개수
);
FRDGBufferRef ParticleBuffer = GraphBuilder.CreateBuffer(
    ParticleBufferDesc,
    TEXT("ParticleBuffer")
);

// Byte Address Buffer 생성
FRDGBufferDesc RawBufferDesc = FRDGBufferDesc::CreateByteAddressDesc(
    1024 * 1024             // 1MB 버퍼
);
FRDGBufferRef RawBuffer = GraphBuilder.CreateBuffer(
    RawBufferDesc,
    TEXT("RawDataBuffer")
);

// Indirect Draw Buffer 생성
FRDGBufferDesc IndirectDesc = FRDGBufferDesc::CreateIndirectDesc(
    5                       // DrawIndexedIndirect 인자 5개
);
FRDGBufferRef IndirectArgs = GraphBuilder.CreateBuffer(
    IndirectDesc,
    TEXT("IndirectDrawArgs")
);
```

---

## 11.2.5 뷰 리소스 (SRV/UAV)

### FRDGTextureSRV / FRDGTextureSRVDesc

```cpp
struct FRDGTextureSRVDesc
{
    FRDGTextureRef Texture;          // 대상 텍스처
    uint8 MipLevel = 0;              // 시작 밉 레벨
    uint8 NumMipLevels = 0;          // 밉 레벨 수 (0 = 전체)
    EPixelFormat Format = PF_Unknown; // 포맷 재해석 (PF_Unknown = 원본)

    // 팩터리 메서드
    static FRDGTextureSRVDesc Create(FRDGTextureRef InTexture)
    {
        return FRDGTextureSRVDesc{ InTexture };
    }

    static FRDGTextureSRVDesc CreateWithPixelFormat(
        FRDGTextureRef InTexture,
        EPixelFormat InFormat
    )
    {
        FRDGTextureSRVDesc Desc;
        Desc.Texture = InTexture;
        Desc.Format = InFormat;
        return Desc;
    }

    static FRDGTextureSRVDesc CreateForMipLevel(
        FRDGTextureRef InTexture,
        uint8 InMipLevel
    )
    {
        FRDGTextureSRVDesc Desc;
        Desc.Texture = InTexture;
        Desc.MipLevel = InMipLevel;
        Desc.NumMipLevels = 1;
        return Desc;
    }
};
```

### FRDGTextureUAV / FRDGTextureUAVDesc

```cpp
struct FRDGTextureUAVDesc
{
    FRDGTextureRef Texture;          // 대상 텍스처
    uint8 MipLevel = 0;              // 밉 레벨 (UAV는 단일 밉만)
    EPixelFormat Format = PF_Unknown; // 포맷 재해석

    FRDGTextureUAVDesc() = default;

    FRDGTextureUAVDesc(FRDGTextureRef InTexture, uint8 InMipLevel = 0)
        : Texture(InTexture)
        , MipLevel(InMipLevel)
    {}
};
```

### FRDGBufferSRV / FRDGBufferUAV

```cpp
// 버퍼 SRV - CreateSRV(Buffer) 또는 CreateSRV(Buffer, Format)
FRDGBufferSRVRef BufferSRV = GraphBuilder.CreateSRV(
    DataBuffer,
    PF_R32_UINT  // 포맷 (Structured Buffer는 생략 가능)
);

// 버퍼 UAV - CreateUAV(Buffer) 또는 CreateUAV(Buffer, Format)
FRDGBufferUAVRef BufferUAV = GraphBuilder.CreateUAV(
    DataBuffer,
    PF_R32_UINT
);
```

```
┌─────────────────────────────────────────────────────────────────┐
│                    SRV vs UAV 비교                               │
├────────────────────────────┬────────────────────────────────────┤
│           SRV              │              UAV                    │
├────────────────────────────┼────────────────────────────────────┤
│ 읽기 전용                  │ 읽기/쓰기                          │
│ Texture2D<float4>          │ RWTexture2D<float4>                │
│ StructuredBuffer<T>        │ RWStructuredBuffer<T>              │
│ Buffer<T>                  │ RWBuffer<T>                        │
├────────────────────────────┼────────────────────────────────────┤
│ VS/PS/GS/HS/DS/CS 사용     │ PS(제한적)/CS 사용                 │
│ 샘플링 가능 (Sampler)      │ 직접 주소 지정만                   │
│ 전체 밉맵 체인 접근        │ 단일 밉 레벨만                     │
├────────────────────────────┼────────────────────────────────────┤
│ ERHIAccess::SRVCompute     │ ERHIAccess::UAVCompute             │
│ ERHIAccess::SRVGraphics    │ ERHIAccess::UAVGraphics            │
└────────────────────────────┴────────────────────────────────────┘
```

---

## 11.2.6 Pass 클래스

### FRDGPass (추상 기본 클래스)

모든 RDG Pass의 기본 클래스입니다.

```cpp
class RENDERCORE_API FRDGPass
{
public:
    // Pass 이름 (RDG_EVENT_NAME)
    const TCHAR* Name;

    // Pass 핸들 (인덱스)
    FRDGPassHandle Handle;

    // Pass 플래그 (Raster, Compute, AsyncCompute 등)
    ERDGPassFlags Flags;

    // 파이프라인 (Graphics 또는 AsyncCompute)
    ERHIPipeline Pipeline;

    // 파라미터 구조체 포인터
    const FShaderParametersMetadata* ParameterMetadata;

    // 이 Pass가 생산하는 리소스의 이전 생산자 목록
    TArray<FRDGPassHandle> Producers;

    // 텍스처 상태 맵
    TMap<FRDGTextureRef, FRDGTextureState> TextureStates;

    // 버퍼 상태 맵
    TMap<FRDGBufferRef, FRDGBufferState> BufferStates;

    // 전위 배리어 배치
    FRDGBarrierBatchBegin* PrologueBarriersToBegin = nullptr;
    FRDGBarrierBatchEnd* PrologueBarriersToEnd = nullptr;

    // 후위 배리어 배치
    FRDGBarrierBatchBegin* EpilogueBarriersToBegin = nullptr;
    FRDGBarrierBatchEnd* EpilogueBarriersToEnd = nullptr;

    // 컬링 여부
    bool bCulled = false;

    // 비동기 컴퓨트 분기점 여부
    bool bAsyncComputeBegin = false;
    bool bAsyncComputeEnd = false;

    // Pass 실행 (순수 가상)
    virtual void Execute(FRHICommandListImmediate& RHICmdList) = 0;
};
```

### TRDGLambdaPass (Lambda Pass)

사용자가 제공한 Lambda 함수를 실행하는 Pass 템플릿 클래스입니다.

```cpp
template<typename TParameterStruct, typename TLambda>
class TRDGLambdaPass : public FRDGPass
{
public:
    // 파라미터 구조체
    TParameterStruct* Parameters;

    // 실행 Lambda
    TLambda Lambda;

    TRDGLambdaPass(
        const TCHAR* InName,
        FRDGPassHandle InHandle,
        TParameterStruct* InParameters,
        ERDGPassFlags InFlags,
        TLambda&& InLambda
    )
        : FRDGPass(InName, InHandle, InFlags)
        , Parameters(InParameters)
        , Lambda(MoveTemp(InLambda))
    {}

    virtual void Execute(FRHICommandListImmediate& RHICmdList) override
    {
        // Lambda 실행
        Lambda(RHICmdList, Parameters);
    }
};
```

```
┌─────────────────────────────────────────────────────────────────┐
│                    FRDGPass 구조                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  FRDGPass                                                       │
│  ├── 기본 정보                                                  │
│  │   ├── Name: const TCHAR*         // 이름 (GPU 프로파일러)   │
│  │   ├── Handle: FRDGPassHandle     // 핸들 (인덱스)           │
│  │   ├── Flags: ERDGPassFlags       // 타입 플래그             │
│  │   └── Pipeline: ERHIPipeline     // 파이프라인              │
│  │                                                              │
│  ├── 의존성 정보                                                │
│  │   ├── Producers[]                // 생산자 Pass 목록        │
│  │   ├── TextureStates{}            // 텍스처 상태 맵          │
│  │   └── BufferStates{}             // 버퍼 상태 맵            │
│  │                                                              │
│  ├── 배리어 정보                                                │
│  │   ├── PrologueBarriersToBegin    // 전위 시작 배리어        │
│  │   ├── PrologueBarriersToEnd      // 전위 종료 배리어        │
│  │   ├── EpilogueBarriersToBegin    // 후위 시작 배리어        │
│  │   └── EpilogueBarriersToEnd      // 후위 종료 배리어        │
│  │                                                              │
│  └── 실행 상태                                                  │
│      ├── bCulled                    // 컬링 여부               │
│      ├── bAsyncComputeBegin         // 비동기 분기 시작        │
│      └── bAsyncComputeEnd           // 비동기 분기 종료        │
│                                                                 │
│  TRDGLambdaPass<TParameterStruct, TLambda> : FRDGPass           │
│  ├── Parameters: TParameterStruct*  // 파라미터 구조체         │
│  └── Lambda: TLambda                // 실행 함수               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 11.2.7 FRDGBuilder (그래프 빌더)

RDG 시스템의 중앙 관리자 클래스입니다. 리소스 생성, Pass 관리, 컴파일, 실행을 담당합니다.

```cpp
class RENDERCORE_API FRDGBuilder
{
public:
    // 생성자
    FRDGBuilder(
        FRHICommandListImmediate& InRHICmdList,
        FRDGEventName InName = {}
    );

    // ==================== 리소스 생성 ====================

    // 텍스처 생성
    FRDGTextureRef CreateTexture(
        const FRDGTextureDesc& Desc,
        const TCHAR* Name,
        ERDGTextureFlags Flags = ERDGTextureFlags::None
    );

    // 버퍼 생성
    FRDGBufferRef CreateBuffer(
        const FRDGBufferDesc& Desc,
        const TCHAR* Name,
        ERDGBufferFlags Flags = ERDGBufferFlags::None
    );

    // SRV 생성
    FRDGTextureSRVRef CreateSRV(const FRDGTextureSRVDesc& Desc);
    FRDGBufferSRVRef CreateSRV(FRDGBufferRef Buffer, EPixelFormat Format = PF_Unknown);

    // UAV 생성
    FRDGTextureUAVRef CreateUAV(const FRDGTextureUAVDesc& Desc);
    FRDGBufferUAVRef CreateUAV(FRDGBufferRef Buffer, EPixelFormat Format = PF_Unknown);

    // ==================== 외부 리소스 등록 ====================

    // 외부 텍스처 등록
    FRDGTextureRef RegisterExternalTexture(
        const TRefCountPtr<IPooledRenderTarget>& ExternalPooledTexture,
        const TCHAR* Name = TEXT("External")
    );

    // 외부 버퍼 등록
    FRDGBufferRef RegisterExternalBuffer(
        const TRefCountPtr<FRDGPooledBuffer>& ExternalPooledBuffer,
        const TCHAR* Name = TEXT("External")
    );

    // ==================== Pass 관리 ====================

    // Pass 추가 (템플릿)
    template<typename TParameterStruct, typename TLambda>
    void AddPass(
        FRDGEventName&& Name,
        TParameterStruct* ParameterStruct,
        ERDGPassFlags Flags,
        TLambda&& Lambda
    );

    // 파라미터 할당
    template<typename TParameterStruct>
    TParameterStruct* AllocParameters();

    // ==================== 리소스 추출 ====================

    // 텍스처 추출 큐
    void QueueTextureExtraction(
        FRDGTextureRef Texture,
        TRefCountPtr<IPooledRenderTarget>* OutPooledTexturePtr
    );

    // 버퍼 추출 큐
    void QueueBufferExtraction(
        FRDGBufferRef Buffer,
        TRefCountPtr<FRDGPooledBuffer>* OutPooledBufferPtr
    );

    // ==================== 실행 ====================

    // 그래프 실행 (컴파일 + 실행 + 정리)
    void Execute();

private:
    // ==================== 내부 데이터 ====================

    // RHI 커맨드 리스트
    FRHICommandListImmediate& RHICmdList;

    // 메모리 할당자
    FRDGAllocator Allocator;

    // 등록된 Pass 목록
    TArray<FRDGPass*> Passes;

    // 등록된 텍스처 목록
    TArray<FRDGTexture*> Textures;

    // 등록된 버퍼 목록
    TArray<FRDGBuffer*> Buffers;

    // 외부 텍스처 맵 (중복 등록 방지)
    TMap<FRHITexture*, FRDGTexture*> ExternalTextures;

    // 외부 버퍼 맵
    TMap<FRHIBuffer*, FRDGBuffer*> ExternalBuffers;

    // 추출 큐
    TArray<FRDGTextureExtraction> TextureExtractions;
    TArray<FRDGBufferExtraction> BufferExtractions;

    // Prologue/Epilogue Pass
    FRDGPass* ProloguePass = nullptr;
    FRDGPass* EpiloguePass = nullptr;

    // Pass 컬링 비트 배열
    TBitArray<> PassCullingBits;
};
```

```
┌─────────────────────────────────────────────────────────────────┐
│                    FRDGBuilder 구조                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  FRDGBuilder (중앙 관리자)                                      │
│  │                                                              │
│  ├── 리소스 생성                                                │
│  │   ├── CreateTexture(Desc, Name)     → FRDGTextureRef        │
│  │   ├── CreateBuffer(Desc, Name)      → FRDGBufferRef         │
│  │   ├── CreateSRV(Texture/Buffer)     → FRDGTextureSRVRef     │
│  │   └── CreateUAV(Texture/Buffer)     → FRDGTextureUAVRef     │
│  │                                                              │
│  ├── 외부 리소스 등록                                           │
│  │   ├── RegisterExternalTexture(PooledRT)                     │
│  │   └── RegisterExternalBuffer(PooledBuffer)                  │
│  │                                                              │
│  ├── Pass 관리                                                  │
│  │   ├── AddPass(Name, Params, Flags, Lambda)                  │
│  │   └── AllocParameters<T>()          → T*                    │
│  │                                                              │
│  ├── 리소스 추출                                                │
│  │   ├── QueueTextureExtraction(Tex, Out)                      │
│  │   └── QueueBufferExtraction(Buf, Out)                       │
│  │                                                              │
│  └── 실행                                                       │
│      └── Execute()                                              │
│          ├── Compile()                 // 의존성 분석, 최적화  │
│          ├── ExecutePasses()           // Pass 실행            │
│          └── Cleanup()                 // 메모리 해제          │
│                                                                 │
│  내부 데이터:                                                   │
│  ├── RHICmdList                        // RHI 커맨드 리스트    │
│  ├── Allocator                         // MemStack 할당자      │
│  ├── Passes[]                          // Pass 목록            │
│  ├── Textures[]                        // 텍스처 목록          │
│  ├── Buffers[]                         // 버퍼 목록            │
│  └── ExternalTextures/Buffers{}        // 외부 리소스 맵       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 11.2.8 메모리 할당자 (FRDGAllocator)

RDG 객체와 메모리의 생명주기를 관리하는 할당자입니다.

```cpp
class FRDGAllocator
{
public:
    // MemStack 기반 할당
    FMemStackBase MemStack;

    // 타입별 할당
    template<typename T, typename... TArgs>
    T* Alloc(TArgs&&... Args)
    {
        T* Object = new (MemStack) T(Forward<TArgs>(Args)...);
        return Object;
    }

    // 배열 할당
    template<typename T>
    T* AllocArray(uint32 Count)
    {
        return static_cast<T*>(MemStack.Alloc(sizeof(T) * Count, alignof(T)));
    }

    // 전체 리셋 (프레임 종료 시)
    void ReleaseAll()
    {
        MemStack.Flush();
    }
};
```

```
┌─────────────────────────────────────────────────────────────────┐
│                    FRDGAllocator 작동 방식                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    Memory Stack                          │   │
│  ├─────────────────────────────────────────────────────────┤   │
│  │                                                         │   │
│  │  ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐         │   │
│  │  │Pass 1│ │Pass 2│ │Tex 1 │ │Buf 1 │ │ ... │         │   │
│  │  └──────┘ └──────┘ └──────┘ └──────┘ └──────┘         │   │
│  │  ←─────────────── 순차 할당 ───────────────→          │   │
│  │                                                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  작동 원리:                                                     │
│  • 프레임 시작: 스택 포인터 초기화                              │
│  • 프레임 중: 순차적 할당 (포인터 증가만)                       │
│  • 프레임 끝: Flush()로 전체 리셋                               │
│                                                                 │
│  장점:                                                          │
│  • O(1) 할당 (포인터 증가만)                                   │
│  • 메모리 단편화 없음                                          │
│  • 일괄 해제로 효율적 (개별 delete 불필요)                     │
│  • 캐시 친화적 (연속 메모리)                                   │
│                                                                 │
│  사용 패턴:                                                     │
│  void RenderFrame()                                             │
│  {                                                              │
│      FRDGBuilder GraphBuilder(RHICmdList);                     │
│      // ... Pass 추가, 리소스 생성                             │
│      GraphBuilder.Execute();                                    │
│      // Execute() 완료 후 모든 RDG 메모리 자동 해제            │
│  }                                                              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 11.2.9 유틸리티 함수

### FComputeShaderUtils

컴퓨트 셰이더 관련 유틸리티 함수를 제공합니다.

```cpp
// Engine/Source/Runtime/RenderCore/Public/RenderGraphUtils.h

struct RENDERCORE_API FComputeShaderUtils
{
    // 컴퓨트 Pass 추가 (디스패치 포함)
    template<typename TShaderClass>
    static void AddPass(
        FRDGBuilder& GraphBuilder,
        FRDGEventName&& PassName,
        const TShaderRef<TShaderClass>& ComputeShader,
        typename TShaderClass::FParameters* PassParameters,
        FIntVector GroupCount
    );

    // UAV 클리어
    static void AddClearUAVPass(
        FRDGBuilder& GraphBuilder,
        FRDGBufferUAVRef BufferUAV,
        uint32 ClearValue
    );

    static void AddClearUAVPass(
        FRDGBuilder& GraphBuilder,
        FRDGTextureUAVRef TextureUAV,
        const FUintVector4& ClearValue
    );

    // 그룹 수 계산
    static FIntVector GetGroupCount(FIntVector ThreadCount, FIntVector GroupSize)
    {
        return FIntVector(
            FMath::DivideAndRoundUp(ThreadCount.X, GroupSize.X),
            FMath::DivideAndRoundUp(ThreadCount.Y, GroupSize.Y),
            FMath::DivideAndRoundUp(ThreadCount.Z, GroupSize.Z)
        );
    }
};
```

### 기타 유틸리티 함수

```cpp
// 텍스처 복사
void AddCopyTexturePass(
    FRDGBuilder& GraphBuilder,
    FRDGTextureRef SrcTexture,
    FRDGTextureRef DstTexture,
    const FRHICopyTextureInfo& CopyInfo = FRHICopyTextureInfo()
);

// 렌더 타겟 클리어
void AddClearRenderTargetPass(
    FRDGBuilder& GraphBuilder,
    FRDGTextureRef Texture,
    const FLinearColor& ClearColor = FLinearColor::Black
);

// 깊이 스텐실 클리어
void AddClearDepthStencilPass(
    FRDGBuilder& GraphBuilder,
    FRDGTextureRef Texture,
    bool bClearDepth = true,
    float Depth = 0.0f,
    bool bClearStencil = false,
    uint8 Stencil = 0
);
```

---

## 다음 단계

[RDG 메커니즘](03-rdg-mechanisms.md)에서 AddPass, Compile, Execute의 내부 동작을 상세히 알아봅니다.
