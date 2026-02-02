# 02. RHI 리소스

RHI 리소스의 종류, 생성 방법, 메모리 관리를 분석합니다.

![FRenderResource 클래스 계층](../images/ch09/1617944-20210818142223492-1790478146.jpg)

*FRenderResource 클래스 계층 - 텍스처, 버텍스 버퍼, 인덱스 버퍼 등 리소스 타입*

---

## 리소스 개요

### 리소스 클래스 계층

```
┌─────────────────────────────────────────────────────────────────┐
│                    RHI 리소스 계층 구조                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│                    ┌─────────────┐                              │
│                    │ FRHIResource│ ← 모든 리소스의 기본 클래스   │
│                    └──────┬──────┘                              │
│                           │                                     │
│       ┌───────────────────┼───────────────────┐                 │
│       │                   │                   │                 │
│       ▼                   ▼                   ▼                 │
│  ┌──────────┐       ┌──────────┐       ┌──────────┐            │
│  │FRHITexture│       │FRHIBuffer │       │FRHIShader │            │
│  └────┬─────┘       └────┬─────┘       └────┬─────┘            │
│       │                  │                   │                  │
│   ┌───┴───┐              │           ┌──────┼──────┐            │
│   │       │              │           │      │      │            │
│   ▼       ▼              ▼           ▼      ▼      ▼            │
│ Tex2D  Tex3D        VertexBuf     VS     PS     CS             │
│ TexCube TexArray    IndexBuf                                    │
│                     UniformBuf                                  │
│                     StructuredBuf                               │
│                                                                 │
│  기타 리소스:                                                    │
│  - FRHISamplerState    : 텍스처 샘플러                          │
│  - FRHIRenderQuery     : 오클루전/타이밍 쿼리                    │
│  - FRHIGPUFence        : GPU 동기화                             │
│  - FRHIViewport        : 윈도우 뷰포트                          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 텍스처 리소스

![FRHITexture 클래스 계층](../images/ch09/1617944-20210818142234988-1224805374.jpg)

*FRHITexture 클래스 계층 - 플랫폼별 텍스처 구현 (D3D12, Metal, Vulkan, OpenGL, D3D11)*

### 텍스처 타입

```cpp
// 2D 텍스처
class FRHITexture2D : public FRHITexture
{
    uint32 SizeX;
    uint32 SizeY;
    uint32 NumMips;
    uint32 NumSamples;  // MSAA
    EPixelFormat Format;
};

// 3D 텍스처 (볼륨)
class FRHITexture3D : public FRHITexture
{
    uint32 SizeX;
    uint32 SizeY;
    uint32 SizeZ;
    uint32 NumMips;
    EPixelFormat Format;
};

// 큐브맵
class FRHITextureCube : public FRHITexture
{
    uint32 Size;  // 각 면의 크기
    uint32 NumMips;
    EPixelFormat Format;
};

// 텍스처 배열
class FRHITexture2DArray : public FRHITexture
{
    uint32 SizeX;
    uint32 SizeY;
    uint32 ArraySize;  // 배열 크기
    uint32 NumMips;
    EPixelFormat Format;
};
```

### 텍스처 생성

```cpp
// 텍스처 생성 플래그
enum class ETextureCreateFlags : uint32
{
    None                = 0,
    RenderTargetable    = 1 << 0,   // 렌더 타겟으로 사용
    ResolveTargetable   = 1 << 1,   // MSAA 리졸브 타겟
    DepthStencilTargetable = 1 << 2, // 깊이/스텐실
    ShaderResource      = 1 << 3,   // 셰이더에서 읽기
    SRGB                = 1 << 4,   // sRGB 색공간
    CPUWritable         = 1 << 5,   // CPU 쓰기 가능
    NoTiling            = 1 << 6,   // 선형 레이아웃
    UAV                 = 1 << 10,  // Unordered Access
    Presentable         = 1 << 11,  // 스왑체인 표시
    Shared              = 1 << 14,  // 프로세스간 공유
};

// 2D 텍스처 생성
FTexture2DRHIRef CreateTexture()
{
    FRHIResourceCreateInfo CreateInfo(TEXT("MyTexture"));
    CreateInfo.BulkData = nullptr;  // 초기 데이터 없음

    FTexture2DRHIRef Texture = RHICreateTexture2D(
        1024,                           // Width
        1024,                           // Height
        PF_R8G8B8A8,                   // Format
        1,                              // NumMips
        1,                              // NumSamples
        TexCreate_ShaderResource |      // Flags
        TexCreate_RenderTargetable,
        CreateInfo
    );

    return Texture;
}

// 렌더 타겟 생성
FTexture2DRHIRef CreateRenderTarget(uint32 Width, uint32 Height)
{
    FRHIResourceCreateInfo CreateInfo(TEXT("RenderTarget"));

    return RHICreateTexture2D(
        Width, Height,
        PF_FloatRGBA,                  // HDR 포맷
        1, 1,
        TexCreate_RenderTargetable | TexCreate_ShaderResource,
        CreateInfo
    );
}

// 초기 데이터와 함께 생성
FTexture2DRHIRef CreateTextureWithData(const void* Data, uint32 Width, uint32 Height)
{
    FRHIResourceCreateInfo CreateInfo(TEXT("TextureWithData"));

    // 벌크 데이터 설정
    FResourceArrayInterface* BulkData = new TResourceArray<uint8>();
    BulkData->SetNum(Width * Height * 4);  // RGBA
    FMemory::Memcpy(BulkData->GetData(), Data, Width * Height * 4);

    CreateInfo.BulkData = BulkData;

    return RHICreateTexture2D(
        Width, Height,
        PF_R8G8B8A8,
        1, 1,
        TexCreate_ShaderResource,
        CreateInfo
    );
}
```

### 픽셀 포맷

```
┌────────────────────────────────────────────────────────────────┐
│                    주요 픽셀 포맷                               │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│  포맷            크기      용도                                │
│  ─────────────  ────────  ──────────────────────────────────  │
│  PF_R8G8B8A8     4 bytes   일반 컬러 텍스처                     │
│  PF_B8G8R8A8     4 bytes   스왑체인 (Windows)                  │
│  PF_FloatRGBA   16 bytes   HDR 렌더 타겟                       │
│  PF_R16F         2 bytes   단일 채널 float16                   │
│  PF_R32_FLOAT    4 bytes   단일 채널 float32                   │
│  PF_G16R16F      4 bytes   2채널 float16 (노멀맵 등)           │
│  PF_A2B10G10R10  4 bytes   10비트 컬러 (HDR)                   │
│  PF_R11G11B10F   4 bytes   HDR (알파 없음)                     │
│                                                                │
│  깊이/스텐실:                                                  │
│  PF_DepthStencil  4 bytes  D24S8                               │
│  PF_ShadowDepth   2 bytes  D16                                 │
│  PF_D24           3 bytes  D24                                 │
│                                                                │
│  압축 포맷:                                                    │
│  PF_DXT1          0.5 byte/px  BC1 (RGB)                       │
│  PF_DXT5          1 byte/px    BC3 (RGBA)                      │
│  PF_BC5           1 byte/px    2채널 (노멀)                    │
│  PF_BC6H          1 byte/px    HDR (Unsigned)                  │
│  PF_BC7           1 byte/px    고품질 RGBA                     │
│  PF_ASTC_4x4      1 byte/px    모바일 HDR                      │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

---

## 버퍼 리소스

### 버퍼 타입

```cpp
// 통합 버퍼 클래스 (UE5)
class FRHIBuffer : public FRHIResource
{
    uint32 Size;           // 총 크기 (바이트)
    uint32 Stride;         // 요소당 크기
    EBufferUsageFlags Usage;
};

// 버퍼 용도 플래그
enum class EBufferUsageFlags : uint32
{
    None           = 0,
    VertexBuffer   = 1 << 0,   // 버텍스 버퍼
    IndexBuffer    = 1 << 1,   // 인덱스 버퍼
    StructuredBuffer = 1 << 2, // 구조화 버퍼
    ByteAddress    = 1 << 3,   // Raw 버퍼
    UnorderedAccess = 1 << 4,  // UAV
    DrawIndirect   = 1 << 5,   // Indirect Draw 인자
    ShaderResource = 1 << 6,   // SRV
    KeepCPUAccessible = 1 << 7, // CPU 접근 유지
    Static         = 1 << 8,   // 정적 (변경 안됨)
    Dynamic        = 1 << 9,   // 동적 (자주 변경)
    Volatile       = 1 << 10,  // 매 프레임 변경
};
```

### 버퍼 생성

```cpp
// 버텍스 버퍼 생성
FBufferRHIRef CreateVertexBuffer(const TArray<FVertex>& Vertices)
{
    uint32 Size = Vertices.Num() * sizeof(FVertex);

    FRHIResourceCreateInfo CreateInfo(TEXT("VertexBuffer"));
    CreateInfo.ResourceArray = CreateFromArray(Vertices);

    return RHICreateBuffer(
        Size,
        BUF_VertexBuffer | BUF_Static,
        sizeof(FVertex),  // Stride
        ERHIAccess::VertexOrIndexBuffer,
        CreateInfo
    );
}

// 인덱스 버퍼 생성
FBufferRHIRef CreateIndexBuffer(const TArray<uint32>& Indices)
{
    uint32 Size = Indices.Num() * sizeof(uint32);

    FRHIResourceCreateInfo CreateInfo(TEXT("IndexBuffer"));
    CreateInfo.ResourceArray = CreateFromArray(Indices);

    return RHICreateBuffer(
        Size,
        BUF_IndexBuffer | BUF_Static,
        sizeof(uint32),
        ERHIAccess::VertexOrIndexBuffer,
        CreateInfo
    );
}

// 동적 버퍼 생성 (매 프레임 업데이트)
FBufferRHIRef CreateDynamicBuffer(uint32 Size)
{
    FRHIResourceCreateInfo CreateInfo(TEXT("DynamicBuffer"));

    return RHICreateBuffer(
        Size,
        BUF_VertexBuffer | BUF_Dynamic,
        0,
        ERHIAccess::VertexOrIndexBuffer,
        CreateInfo
    );
}

// 구조화 버퍼 (Compute Shader용)
FBufferRHIRef CreateStructuredBuffer(uint32 NumElements, uint32 ElementSize)
{
    FRHIResourceCreateInfo CreateInfo(TEXT("StructuredBuffer"));

    return RHICreateBuffer(
        NumElements * ElementSize,
        BUF_StructuredBuffer | BUF_ShaderResource | BUF_UnorderedAccess,
        ElementSize,
        ERHIAccess::UAVCompute,
        CreateInfo
    );
}
```

### 버퍼 업데이트

```cpp
// 버퍼 데이터 업데이트
void UpdateBufferData(FRHIBuffer* Buffer, const void* Data, uint32 Size)
{
    // 방법 1: Lock/Unlock (동적 버퍼용)
    void* MappedData = RHILockBuffer(Buffer, 0, Size, RLM_WriteOnly);
    FMemory::Memcpy(MappedData, Data, Size);
    RHIUnlockBuffer(Buffer);

    // 방법 2: UpdateBuffer (작은 업데이트용)
    RHIUpdateBuffer(Buffer, 0, Size, Data);
}

// 비동기 업데이트 (Staging Buffer 사용)
void UpdateBufferAsync(FRHICommandList& RHICmdList, FRHIBuffer* DestBuffer, const void* Data, uint32 Size)
{
    // 스테이징 버퍼 생성
    FBufferRHIRef StagingBuffer = RHICreateBuffer(
        Size,
        BUF_ShaderResource,
        0,
        ERHIAccess::CopySrc,
        FRHIResourceCreateInfo(TEXT("Staging"))
    );

    // 스테이징에 쓰기
    void* Mapped = RHILockBuffer(StagingBuffer, 0, Size, RLM_WriteOnly);
    FMemory::Memcpy(Mapped, Data, Size);
    RHIUnlockBuffer(StagingBuffer);

    // GPU 복사 명령
    RHICmdList.CopyBufferRegion(DestBuffer, 0, StagingBuffer, 0, Size);
}
```

---

## 유니폼 버퍼

### 유니폼 버퍼 정의

```cpp
// 유니폼 버퍼 구조체 정의
BEGIN_GLOBAL_SHADER_PARAMETER_STRUCT(FViewUniformShaderParameters, )
    SHADER_PARAMETER(FMatrix44f, ViewToClip)
    SHADER_PARAMETER(FMatrix44f, WorldToView)
    SHADER_PARAMETER(FMatrix44f, WorldToClip)
    SHADER_PARAMETER(FVector4f, ViewSizeAndInvSize)
    SHADER_PARAMETER(FVector3f, WorldCameraOrigin)
    SHADER_PARAMETER(float, Padding)
END_GLOBAL_SHADER_PARAMETER_STRUCT()

// 유니폼 버퍼 생성
TUniformBufferRef<FViewUniformShaderParameters> CreateViewUniformBuffer(
    const FViewMatrices& ViewMatrices)
{
    FViewUniformShaderParameters Parameters;
    Parameters.ViewToClip = ViewMatrices.GetProjectionMatrix();
    Parameters.WorldToView = ViewMatrices.GetViewMatrix();
    Parameters.WorldToClip = ViewMatrices.GetViewProjectionMatrix();
    Parameters.WorldCameraOrigin = ViewMatrices.GetViewOrigin();

    return TUniformBufferRef<FViewUniformShaderParameters>::CreateUniformBufferImmediate(
        Parameters,
        UniformBuffer_SingleFrame
    );
}
```

### 유니폼 버퍼 수명

```
┌─────────────────────────────────────────────────────────────────┐
│                    유니폼 버퍼 수명 정책                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  수명 타입                설명                                  │
│  ─────────────────────   ────────────────────────────────────  │
│  UniformBuffer_SingleDraw   단일 드로우 콜용                    │
│                             → 드로우 후 즉시 재활용              │
│                                                                 │
│  UniformBuffer_SingleFrame  단일 프레임용                       │
│                             → 프레임 끝에 재활용                 │
│                                                                 │
│  UniformBuffer_MultiFrame   여러 프레임용                       │
│                             → 명시적 해제 필요                   │
│                                                                 │
│  성능 고려:                                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  - SingleDraw: 가장 빠름, 메모리 풀에서 할당             │   │
│  │  - SingleFrame: 프레임 끝 배치 해제                      │   │
│  │  - MultiFrame: 수동 관리, 오래 유지되는 데이터용         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 리소스 뷰

### Shader Resource View (SRV)

```cpp
// SRV - 셰이더에서 읽기용
class FRHIShaderResourceView : public FRHIResource
{
    // 텍스처 또는 버퍼의 읽기 전용 뷰
};

// 텍스처 SRV 생성
FShaderResourceViewRHIRef CreateTextureSRV(FRHITexture* Texture)
{
    FRHIShaderResourceViewCreateInfo CreateInfo;
    CreateInfo.Texture = Texture;
    CreateInfo.MipLevel = 0;
    CreateInfo.NumMips = Texture->GetNumMips();

    return RHICreateShaderResourceView(CreateInfo);
}

// 버퍼 SRV 생성
FShaderResourceViewRHIRef CreateBufferSRV(FRHIBuffer* Buffer, EPixelFormat Format)
{
    FRHIShaderResourceViewCreateInfo CreateInfo;
    CreateInfo.Buffer = Buffer;
    CreateInfo.Format = Format;

    return RHICreateShaderResourceView(CreateInfo);
}
```

### Unordered Access View (UAV)

```cpp
// UAV - 셰이더에서 읽기/쓰기용
class FRHIUnorderedAccessView : public FRHIResource
{
    // 텍스처 또는 버퍼의 읽기/쓰기 뷰
    // Compute Shader에서 주로 사용
};

// 텍스처 UAV 생성
FUnorderedAccessViewRHIRef CreateTextureUAV(FRHITexture* Texture, uint32 MipLevel = 0)
{
    return RHICreateUnorderedAccessView(Texture, MipLevel);
}

// 버퍼 UAV 생성
FUnorderedAccessViewRHIRef CreateBufferUAV(FRHIBuffer* Buffer, EPixelFormat Format)
{
    return RHICreateUnorderedAccessView(Buffer, Format);
}
```

### Render Target View

```cpp
// 렌더 타겟 뷰 정보
struct FRHIRenderTargetView
{
    FRHITexture* Texture;        // 대상 텍스처
    uint32 MipIndex;             // 밉 레벨
    uint32 ArraySliceIndex;      // 배열 인덱스
    ERenderTargetLoadAction LoadAction;   // 로드 액션
    ERenderTargetStoreAction StoreAction; // 저장 액션
};

// 로드/저장 액션
enum class ERenderTargetLoadAction : uint8
{
    Load,    // 기존 내용 유지
    Clear,   // 클리어
    NoAction // 내용 무시 (가장 빠름)
};

enum class ERenderTargetStoreAction : uint8
{
    Store,         // 결과 저장
    DontCare,      // 저장 안함 (타일 메모리 최적화)
    Resolve,       // MSAA 리졸브
    StoreAndResolve
};
```

---

## 메모리 관리

### GPU 메모리 할당

```
┌─────────────────────────────────────────────────────────────────┐
│                    GPU 메모리 계층                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    VRAM (Dedicated)                      │   │
│  │  - 가장 빠름                                             │   │
│  │  - 용량 제한 (8-24GB)                                    │   │
│  │  - 렌더 타겟, 주요 텍스처                                │   │
│  └─────────────────────────────────────────────────────────┘   │
│                           │                                     │
│                           ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    Shared Memory                         │   │
│  │  - CPU/GPU 공유                                          │   │
│  │  - 업로드/리드백 버퍼                                    │   │
│  └─────────────────────────────────────────────────────────┘   │
│                           │                                     │
│                           ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    System Memory                         │   │
│  │  - 가장 느림                                             │   │
│  │  - 용량 큼                                               │   │
│  │  - 스테이징 데이터                                       │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 메모리 풀

```cpp
// 텍스처 스트리밍 풀
class FTextureStreamingPool
{
    // 텍스처 밉맵 스트리밍을 위한 메모리 풀
    // 우선순위 기반 로드/언로드

    int64 PoolSize;           // 풀 크기
    int64 UsedMemory;         // 사용 중인 메모리
    TArray<FStreamingTexture*> Textures;

    void UpdatePriorities();  // 우선순위 업데이트
    void StreamIn(FStreamingTexture* Texture);
    void StreamOut(FStreamingTexture* Texture);
};

// 버퍼 풀링
class FRHIBufferPool
{
    // 자주 생성/삭제되는 버퍼 재활용

    TMap<uint32, TArray<FBufferRHIRef>> FreePools;  // 크기별 풀

    FBufferRHIRef Allocate(uint32 Size, EBufferUsageFlags Usage)
    {
        // 풀에서 적합한 버퍼 검색
        if (FBufferRHIRef* Found = FindInPool(Size, Usage))
        {
            return *Found;
        }
        // 없으면 새로 생성
        return RHICreateBuffer(Size, Usage, 0, ERHIAccess::None, CreateInfo);
    }

    void Release(FBufferRHIRef Buffer)
    {
        // 풀에 반환
        FreePools.FindOrAdd(Buffer->GetSize()).Add(Buffer);
    }
};
```

### 메모리 통계

```cpp
// 콘솔 명령어
// stat rhi              - RHI 메모리 통계
// stat d3d12memory      - D3D12 상세 메모리
// r.RHI.PooledBufferBudget=256  // 버퍼 풀 크기 (MB)

// 프로그램적 확인
void LogMemoryStats()
{
    FTextureMemoryStats Stats;
    RHIGetTextureMemoryStats(Stats);

    UE_LOG(LogRHI, Log, TEXT("Textures: %d MB used of %d MB pool"),
        Stats.AllocatedMemorySize / 1024 / 1024,
        Stats.TexturePoolSize / 1024 / 1024);

    // 버퍼 메모리
    SIZE_T BufferMemory = 0;
    RHIGetBufferMemoryStats(BufferMemory);
    UE_LOG(LogRHI, Log, TEXT("Buffers: %d MB"), BufferMemory / 1024 / 1024);
}
```

---

## 리소스 업로드

### 비동기 업로드

```
┌─────────────────────────────────────────────────────────────────┐
│                    리소스 업로드 파이프라인                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. 스테이징 버퍼 할당                                          │
│     CPU 접근 가능한 메모리에 할당                               │
│                                                                 │
│  2. CPU에서 스테이징에 쓰기                                     │
│     memcpy로 데이터 복사                                        │
│                                                                 │
│  3. Copy 커맨드 기록                                            │
│     스테이징 → GPU 리소스 복사 명령                             │
│                                                                 │
│  4. GPU에서 복사 실행                                           │
│     Copy Queue 또는 Graphics Queue                              │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  [CPU] ───write──→ [Staging] ───copy──→ [GPU Resource]  │   │
│  │           │                      │                       │   │
│  │           │                      │                       │   │
│  │       CPU Memory            GPU Memory                   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 텍스처 업로드 예시

```cpp
void UploadTextureData(FRHITexture2D* Texture, const void* Data, uint32 Width, uint32 Height)
{
    // 업로드 힙에서 스테이징 할당
    uint32 RowPitch = Width * GPixelFormats[Texture->GetFormat()].BlockBytes;
    uint32 TotalSize = RowPitch * Height;

    // 락/언락 방식
    uint32 DestStride;
    void* LockedData = RHILockTexture2D(Texture, 0, RLM_WriteOnly, DestStride, false);

    // Row-by-row 복사 (패딩 처리)
    const uint8* SrcRow = (const uint8*)Data;
    uint8* DestRow = (uint8*)LockedData;
    for (uint32 Row = 0; Row < Height; ++Row)
    {
        FMemory::Memcpy(DestRow, SrcRow, RowPitch);
        SrcRow += RowPitch;
        DestRow += DestStride;
    }

    RHIUnlockTexture2D(Texture, 0, false);
}
```

---

## 요약

RHI 리소스 핵심:

1. **텍스처** - 2D, 3D, Cube, Array 지원, 다양한 포맷
2. **버퍼** - 버텍스, 인덱스, 유니폼, 구조화 버퍼
3. **뷰** - SRV, UAV, RTV로 리소스 접근 방식 정의
4. **참조 카운팅** - 자동 수명 관리, 지연 삭제
5. **메모리 관리** - 풀링, 스트리밍, 계층적 할당

리소스 생성은 RHI 레이어에서 플랫폼별 차이를 숨깁니다.

---

## 참고 자료

- [UE RHI Resources](https://github.com/EpicGames/UnrealEngine/tree/release/Engine/Source/Runtime/RHI/Public)
- [원문 시리즈 (중국어)](https://www.cnblogs.com/timlly/p/13512787.html)
---

<div style="display: flex; justify-content: space-between; align-items: center; padding: 16px 0;">
  <a href="../01-rhi-overview/" style="text-decoration: none;">← 이전: 01. RHI 개요</a>
  <a href="../03-command-list/" style="text-decoration: none;">다음: 03. 커맨드 리스트 →</a>
</div>
