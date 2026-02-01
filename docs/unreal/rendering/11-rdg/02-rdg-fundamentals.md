# RDG 기초 타입

RDG의 기본 플래그, 리소스 타입, 메모리 할당자를 설명합니다.

---

## Pass 플래그 (ERDGPassFlags)

Pass의 타입과 동작을 정의하는 플래그입니다.

```cpp
enum class ERDGPassFlags : uint8
{
    None = 0,
    Raster = 1 << 0,          // 래스터화 Pass (픽셀 셰이더)
    Compute = 1 << 1,         // 컴퓨트 Pass (컴퓨트 셰이더)
    AsyncCompute = 1 << 2,    // 비동기 컴퓨트 Pass
    Copy = 1 << 3,            // 복사 Pass
    NeverCull = 1 << 4,       // 컬링 대상에서 제외
    SkipRenderPass = 1 << 5   // Begin/EndRenderPass 생략
};
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
│  └──────────────┘  └──────────────┘  └──────────────┘          │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │     Copy     │  │  NeverCull   │  │SkipRenderPass│          │
│  ├──────────────┤  ├──────────────┤  ├──────────────┤          │
│  │ 리소스 복사  │  │ 항상 실행    │  │ RenderPass  │          │
│  │ CopyTexture  │  │ 컬링 제외    │  │ 설정 생략    │          │
│  │ CopyBuffer   │  │ 디버그용     │  │ 수동 제어    │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 리소스 플래그

### ERDGTextureFlags

```cpp
enum class ERDGTextureFlags : uint8
{
    None = 0,
    MultiFrame = 1 << 0,           // 여러 프레임에 걸쳐 유지
    MaintainCompression = 1 << 1   // 압축 상태 유지
};
```

### ERDGBufferFlags

```cpp
enum class ERDGBufferFlags : uint8
{
    None = 0,
    MultiFrame = 1 << 0   // 여러 프레임에 걸쳐 유지
};
```

### ERDGUnorderedAccessViewFlags

```cpp
enum class ERDGUnorderedAccessViewFlags : uint8
{
    None = 0,
    SkipBarrier = 1 << 0   // 배리어 생략 (직접 관리 시)
};
```

---

## 리소스 기본 클래스

### FRDGResource

모든 RDG 리소스의 기본 클래스입니다.

```
┌─────────────────────────────────────────────────────────────────┐
│                    FRDGResource 구조                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  FRDGResource                                                   │
│  ├── Name: const TCHAR*           // 디버그용 이름              │
│  ├── ReferenceCount: uint16       // 참조 카운트                │
│  ├── bExternal: bool              // 외부 리소스 여부           │
│  ├── bExtracted: bool             // 추출 예정 여부             │
│  ├── bCulled: bool                // 컬링 여부                  │
│  └── DebugData                    // 디버그 정보                │
│                                                                 │
│  기능:                                                          │
│  • RHI 리소스 캡슐화                                            │
│  • 생명주기 추적                                                │
│  • 디버그 정보 제공                                             │
│  • 사용 플래그 관리                                             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 텍스처 리소스 (FRDGTexture)

### FRDGTextureDesc

텍스처 생성에 필요한 속성을 정의합니다.

```cpp
struct FRDGTextureDesc
{
    ETextureDimension Dimension;    // 1D, 2D, 3D, Cube
    ETextureCreateFlags Flags;      // 생성 플래그
    EPixelFormat Format;            // 픽셀 포맷
    FClearValueBinding ClearValue;  // 클리어 값
    FIntPoint Extent;               // 크기 (Width, Height)
    uint16 Depth;                   // 깊이 (3D 텍스처)
    uint16 ArraySize;               // 배열 크기
    uint8 NumMips;                  // 밉맵 개수
    uint8 NumSamples;               // MSAA 샘플 수

    // 편의 생성 함수
    static FRDGTextureDesc Create2D(...);
    static FRDGTextureDesc Create3D(...);
    static FRDGTextureDesc CreateCube(...);
};
```

### 텍스처 생성 예시

```cpp
// 2D 렌더 타겟 텍스처 생성
FRDGTextureDesc TextureDesc = FRDGTextureDesc::Create2D(
    FIntPoint(1920, 1080),              // 크기
    PF_FloatRGBA,                        // 포맷
    FClearValueBinding::Black,           // 클리어 값
    TexCreate_RenderTargetable |         // 플래그
    TexCreate_ShaderResource
);

FRDGTextureRef MyTexture = GraphBuilder.CreateTexture(
    TextureDesc,
    TEXT("MyRenderTarget")
);
```

### FRDGPooledTexture

풀에서 관리되는 실제 텍스처 리소스입니다.

```
┌─────────────────────────────────────────────────────────────────┐
│                    텍스처 리소스 계층                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  FRDGTexture (논리적 핸들)                                      │
│       │                                                         │
│       ▼                                                         │
│  FRDGPooledTexture (풀 관리)                                    │
│       │                                                         │
│       ▼                                                         │
│  FRHITexture (RHI 리소스)                                       │
│       │                                                         │
│       ▼                                                         │
│  GPU Memory (실제 메모리)                                       │
│                                                                 │
│  • FRDGTexture: RDG 시스템 내 핸들                              │
│  • FRDGPooledTexture: 재사용 가능한 풀링된 리소스               │
│  • FRHITexture: 플랫폼별 RHI 구현                               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 버퍼 리소스 (FRDGBuffer)

### FRDGBufferDesc

버퍼 생성에 필요한 속성을 정의합니다.

```cpp
struct FRDGBufferDesc
{
    uint32 BytesPerElement;    // 요소당 바이트 수
    uint32 NumElements;        // 요소 개수
    EBufferUsageFlags Usage;   // 사용 용도

    // 편의 생성 함수
    static FRDGBufferDesc CreateStructuredDesc(uint32 BytesPerElement, uint32 NumElements);
    static FRDGBufferDesc CreateBufferDesc(uint32 BytesPerElement, uint32 NumElements);
};
```

### 버퍼 타입

```
┌─────────────────────────────────────────────────────────────────┐
│                    버퍼 타입별 용도                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐    │
│  │  Vertex Buffer │  │  Index Buffer  │  │Structured Buffer│   │
│  ├────────────────┤  ├────────────────┤  ├────────────────┤    │
│  │ 정점 데이터    │  │ 인덱스 데이터  │  │ 구조체 배열    │    │
│  │ Position, UV   │  │ Triangle List  │  │ 컴퓨트 입출력  │    │
│  └────────────────┘  └────────────────┘  └────────────────┘    │
│                                                                 │
│  ┌────────────────┐  ┌────────────────┐                        │
│  │  Byte Address  │  │  Indirect Args │                        │
│  ├────────────────┤  ├────────────────┤                        │
│  │ Raw 바이트     │  │ 간접 드로우    │                        │
│  │ 유연한 접근    │  │ DrawIndirect   │                        │
│  └────────────────┘  └────────────────┘                        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 버퍼 생성 예시

```cpp
// Structured Buffer 생성
FRDGBufferDesc BufferDesc = FRDGBufferDesc::CreateStructuredDesc(
    sizeof(FMyStruct),   // 구조체 크기
    1024                 // 요소 개수
);

FRDGBufferRef MyBuffer = GraphBuilder.CreateBuffer(
    BufferDesc,
    TEXT("MyStructuredBuffer")
);
```

---

## 뷰 리소스

### SRV (Shader Resource View)

셰이더에서 읽기 전용으로 접근하는 뷰입니다.

```cpp
// 텍스처 SRV 생성
FRDGTextureSRVRef TextureSRV = GraphBuilder.CreateSRV(
    FRDGTextureSRVDesc::CreateWithPixelFormat(
        Texture,
        PF_FloatRGBA
    )
);

// 버퍼 SRV 생성
FRDGBufferSRVRef BufferSRV = GraphBuilder.CreateSRV(
    Buffer,
    PF_R32_UINT
);
```

### UAV (Unordered Access View)

셰이더에서 읽기/쓰기로 접근하는 뷰입니다.

```cpp
// 텍스처 UAV 생성
FRDGTextureUAVRef TextureUAV = GraphBuilder.CreateUAV(
    FRDGTextureUAVDesc(Texture, 0)  // Mip Level 0
);

// 버퍼 UAV 생성
FRDGBufferUAVRef BufferUAV = GraphBuilder.CreateUAV(
    Buffer,
    PF_R32_UINT
);
```

```
┌─────────────────────────────────────────────────────────────────┐
│                    SRV vs UAV                                    │
├────────────────────────────┬────────────────────────────────────┤
│           SRV              │              UAV                    │
├────────────────────────────┼────────────────────────────────────┤
│ 읽기 전용                  │ 읽기/쓰기                          │
│ Texture2D<float4>          │ RWTexture2D<float4>                │
│ StructuredBuffer<T>        │ RWStructuredBuffer<T>              │
│ VS/PS/CS에서 사용          │ PS/CS에서 사용                     │
│ 샘플링 가능                │ 직접 주소 지정                     │
└────────────────────────────┴────────────────────────────────────┘
```

---

## 메모리 할당자 (FRDGAllocator)

RDG 객체와 메모리의 생명주기를 관리합니다.

```
┌─────────────────────────────────────────────────────────────────┐
│                    FRDGAllocator 구조                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  FRDGAllocator                                                  │
│  └── FMemStackBase (MemStack 할당자)                            │
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
│  │  • 프레임 시작: 스택 초기화                             │   │
│  │  • 프레임 중: 순차적 할당 (개별 해제 없음)              │   │
│  │  • 프레임 끝: 전체 리셋                                 │   │
│  │                                                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  장점:                                                          │
│  • 빠른 할당 (포인터 증가만)                                   │
│  • 메모리 단편화 없음                                          │
│  • 일괄 해제로 효율적                                          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 파라미터 할당

```cpp
// Pass 파라미터 할당
FMyPassParameters* Parameters = GraphBuilder.AllocParameters<FMyPassParameters>();

// 메모리는 FRDGBuilder::Execute() 완료 후 자동 해제됨
```

---

## 리소스 상태 관리

RDG는 리소스의 상태를 자동으로 추적하고 필요한 전환을 수행합니다.

### 상태 전환 예시

```
┌─────────────────────────────────────────────────────────────────┐
│                    리소스 상태 전환                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Pass A (렌더 타겟)        Pass B (셰이더 리소스)               │
│  ┌─────────────────┐       ┌─────────────────┐                 │
│  │ State: RT       │  →    │ State: SRV      │                 │
│  │ Write Access    │       │ Read Access     │                 │
│  └─────────────────┘       └─────────────────┘                 │
│                  │                                              │
│                  ▼                                              │
│         ┌───────────────┐                                      │
│         │   Barrier     │  ← RDG가 자동 삽입                   │
│         │ RT → SRV      │                                      │
│         └───────────────┘                                      │
│                                                                 │
│  불필요한 전환은 자동 제거:                                     │
│  • SRV → SRV (Read → Read) : 배리어 불필요                     │
│  • 동일 상태 유지 : 배리어 불필요                               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 다음 단계

[RDG 메커니즘](03-rdg-mechanisms.md)에서 의존성 관리와 컴파일/실행 과정을 자세히 알아봅니다.
