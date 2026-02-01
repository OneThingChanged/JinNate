# RDG (Render Dependency Graph) 활용

UE5의 Render Dependency Graph 시스템을 활용한 효율적인 렌더 패스 구현을 다룹니다.

---

## 개요

RDG는 렌더링 패스 간의 의존성을 자동으로 관리하고 리소스를 최적화하는 프레임워크입니다.

```
┌─────────────────────────────────────────────────────────────────┐
│                      RDG 아키텍처                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                    그래프 빌드 단계                       │    │
│  │                                                         │    │
│  │  Pass A ──┐                                             │    │
│  │           │                                             │    │
│  │  Pass B ──┼──▶ [RDG Builder] ──▶ Dependency Graph      │    │
│  │           │                                             │    │
│  │  Pass C ──┘                                             │    │
│  │                                                         │    │
│  └─────────────────────────────────────────────────────────┘    │
│                           │                                     │
│                           ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                    컴파일 단계                            │    │
│  │                                                         │    │
│  │  • 패스 순서 결정                                        │    │
│  │  • 리소스 수명 분석                                      │    │
│  │  • 메모리 앨리어싱                                       │    │
│  │  • 배리어 삽입                                          │    │
│  │                                                         │    │
│  └─────────────────────────────────────────────────────────┘    │
│                           │                                     │
│                           ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                    실행 단계                              │    │
│  │                                                         │    │
│  │  Pass A ──▶ Pass B ──▶ Pass C  (최적화된 순서)         │    │
│  │                                                         │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## RDG 리소스

### 텍스처 생성

```cpp
// 텍스처 생성
FRDGTextureDesc Desc = FRDGTextureDesc::Create2D(
    FIntPoint(1920, 1080),           // 크기
    PF_FloatRGBA,                    // 포맷
    FClearValueBinding::Black,       // 클리어 값
    TexCreate_RenderTargetable |     // 플래그
    TexCreate_ShaderResource |
    TexCreate_UAV
);

FRDGTextureRef MyTexture = GraphBuilder.CreateTexture(Desc, TEXT("MyTexture"));

// 외부 텍스처 등록
FRDGTextureRef ExternalTexture = GraphBuilder.RegisterExternalTexture(
    ExternalPooledRT,
    TEXT("ExternalTexture")
);
```

### 버퍼 생성

```cpp
// 구조화 버퍼
FRDGBufferDesc BufferDesc = FRDGBufferDesc::CreateStructuredDesc(
    sizeof(FMyStruct),  // 요소 크기
    1024               // 요소 수
);

FRDGBufferRef MyBuffer = GraphBuilder.CreateBuffer(BufferDesc, TEXT("MyBuffer"));

// 버텍스/인덱스 버퍼
FRDGBufferDesc VertexDesc = FRDGBufferDesc::CreateBufferDesc(
    sizeof(FVector4f),   // 스트라이드
    VertexCount          // 요소 수
);
VertexDesc.Usage = BUF_VertexBuffer;
```

### 뷰 생성

```cpp
// SRV (Shader Resource View)
FRDGTextureSRVRef SRV = GraphBuilder.CreateSRV(
    FRDGTextureSRVDesc::Create(MyTexture)
);

// UAV (Unordered Access View)
FRDGTextureUAVRef UAV = GraphBuilder.CreateUAV(
    FRDGTextureUAVDesc(MyTexture)
);

// 버퍼 SRV/UAV
FRDGBufferSRVRef BufferSRV = GraphBuilder.CreateSRV(
    FRDGBufferSRVDesc(MyBuffer, PF_R32_FLOAT)
);

FRDGBufferUAVRef BufferUAV = GraphBuilder.CreateUAV(
    FRDGBufferUAVDesc(MyBuffer)
);
```

---

## 패스 추가

### Raster 패스

```cpp
BEGIN_SHADER_PARAMETER_STRUCT(FMyRasterPassParameters, )
    SHADER_PARAMETER_RDG_TEXTURE_SRV(Texture2D, InputTexture)
    SHADER_PARAMETER_SAMPLER(SamplerState, InputSampler)
    SHADER_PARAMETER(FVector4f, MyParams)
    RENDER_TARGET_BINDING_SLOTS()
END_SHADER_PARAMETER_STRUCT()

void AddMyRasterPass(
    FRDGBuilder& GraphBuilder,
    FRDGTextureRef InputTexture,
    FRDGTextureRef OutputTexture)
{
    FMyRasterPassParameters* Parameters =
        GraphBuilder.AllocParameters<FMyRasterPassParameters>();

    Parameters->InputTexture = GraphBuilder.CreateSRV(
        FRDGTextureSRVDesc::Create(InputTexture));
    Parameters->InputSampler = TStaticSamplerState<SF_Bilinear>::GetRHI();
    Parameters->MyParams = FVector4f(1.0f, 0.0f, 0.0f, 1.0f);
    Parameters->RenderTargets[0] = FRenderTargetBinding(
        OutputTexture,
        ERenderTargetLoadAction::EClear
    );

    GraphBuilder.AddPass(
        RDG_EVENT_NAME("MyRasterPass"),
        Parameters,
        ERDGPassFlags::Raster,
        [Parameters](FRHICommandList& RHICmdList)
        {
            // 래스터화 로직
            // PSO 설정, 드로우 콜 등
        });
}
```

### Compute 패스

```cpp
BEGIN_SHADER_PARAMETER_STRUCT(FMyComputePassParameters, )
    SHADER_PARAMETER_RDG_TEXTURE_SRV(Texture2D, InputTexture)
    SHADER_PARAMETER_RDG_TEXTURE_UAV(RWTexture2D<float4>, OutputTexture)
    SHADER_PARAMETER(FIntPoint, TextureSize)
END_SHADER_PARAMETER_STRUCT()

void AddMyComputePass(
    FRDGBuilder& GraphBuilder,
    FRDGTextureRef InputTexture,
    FRDGTextureRef OutputTexture,
    FIntPoint Size)
{
    FMyComputePassParameters* Parameters =
        GraphBuilder.AllocParameters<FMyComputePassParameters>();

    Parameters->InputTexture = GraphBuilder.CreateSRV(
        FRDGTextureSRVDesc::Create(InputTexture));
    Parameters->OutputTexture = GraphBuilder.CreateUAV(
        FRDGTextureUAVDesc(OutputTexture));
    Parameters->TextureSize = Size;

    FMyComputeShader::FPermutationDomain PermutationVector;
    TShaderMapRef<FMyComputeShader> ComputeShader(GetGlobalShaderMap(GMaxRHIFeatureLevel));

    FIntVector GroupCount = FIntVector(
        FMath::DivideAndRoundUp(Size.X, 8),
        FMath::DivideAndRoundUp(Size.Y, 8),
        1
    );

    GraphBuilder.AddPass(
        RDG_EVENT_NAME("MyComputePass"),
        Parameters,
        ERDGPassFlags::Compute,
        [Parameters, ComputeShader, GroupCount](FRHIComputeCommandList& RHICmdList)
        {
            FComputeShaderUtils::Dispatch(
                RHICmdList,
                ComputeShader,
                *Parameters,
                GroupCount
            );
        });
}
```

### AsyncCompute 패스

```cpp
// 비동기 컴퓨트 (그래픽스와 병렬 실행)
GraphBuilder.AddPass(
    RDG_EVENT_NAME("MyAsyncComputePass"),
    Parameters,
    ERDGPassFlags::AsyncCompute,  // Async 플래그
    [Parameters, ComputeShader](FRHIComputeCommandList& RHICmdList)
    {
        // 비동기로 실행됨
        // 그래픽스 큐와 병렬 가능
    });
```

---

## 리소스 의존성

### 암시적 의존성

```cpp
// RDG가 자동으로 의존성 추론
void BuildPasses(FRDGBuilder& GraphBuilder)
{
    FRDGTextureRef TextureA = GraphBuilder.CreateTexture(...);
    FRDGTextureRef TextureB = GraphBuilder.CreateTexture(...);

    // Pass 1: TextureA에 쓰기
    {
        FPass1Parameters* Params = ...;
        Params->Output = GraphBuilder.CreateUAV(TextureA);
        GraphBuilder.AddPass(...);  // TextureA 생산
    }

    // Pass 2: TextureA 읽기, TextureB 쓰기
    {
        FPass2Parameters* Params = ...;
        Params->Input = GraphBuilder.CreateSRV(TextureA);  // 자동 의존성!
        Params->Output = GraphBuilder.CreateUAV(TextureB);
        GraphBuilder.AddPass(...);
    }
}
```

```
┌─────────────────────────────────────────────────────────────────┐
│                    의존성 그래프 예시                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────┐         ┌─────────┐         ┌─────────┐           │
│  │ Pass A  │────────▶│ Pass B  │────────▶│ Pass C  │           │
│  │(Write T1)│        │(Read T1)│         │(Read T2)│           │
│  └─────────┘         │(Write T2)│         └─────────┘           │
│                      └─────────┘                                │
│                                                                 │
│  RDG가 자동으로:                                                │
│  - Pass A → Pass B 순서 보장 (T1 의존성)                       │
│  - Pass B → Pass C 순서 보장 (T2 의존성)                       │
│  - 필요한 배리어 삽입                                          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 명시적 의존성

```cpp
// 리소스 없이 순서만 강제
GraphBuilder.AddPass(
    RDG_EVENT_NAME("PassB"),
    Parameters,
    ERDGPassFlags::Compute | ERDGPassFlags::NeverCull,
    [](FRHIComputeCommandList&) { ... }
);

// 특정 패스 후 실행 강제
// (보통 암시적 의존성으로 충분)
```

---

## 리소스 수명 관리

### Transient 리소스

```cpp
// 임시 리소스 (프레임 내에서만 유효)
FRDGTextureDesc TransientDesc = ...;
TransientDesc.Flags |= TexCreate_Transient;

FRDGTextureRef TransientTexture = GraphBuilder.CreateTexture(
    TransientDesc, TEXT("TransientRT"));

// RDG가 수명 분석 후 메모리 앨리어싱
// 다른 패스에서 같은 메모리 재사용 가능
```

### 외부 리소스 추출

```cpp
// 프레임 간 유지되는 리소스
FRDGTextureRef PersistentTexture = GraphBuilder.RegisterExternalTexture(
    PersistentPooledRT);

// 패스에서 사용 후 추출
GraphBuilder.QueueTextureExtraction(
    PersistentTexture,
    &PersistentPooledRT
);
```

### 메모리 앨리어싱

```
┌─────────────────────────────────────────────────────────────────┐
│                    RDG 메모리 앨리어싱                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Without Aliasing:                                              │
│  ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐                   │
│  │ Tex A  │ │ Tex B  │ │ Tex C  │ │ Tex D  │  = 4× 메모리     │
│  └────────┘ └────────┘ └────────┘ └────────┘                   │
│                                                                 │
│  With RDG Aliasing (수명 분석 후):                             │
│  ┌────────────────────────────────┐                            │
│  │ Pass1: A │ Pass2: B │ Pass3: C │  = 1× 메모리              │
│  └────────────────────────────────┘   (재사용)                 │
│                                                                 │
│  조건: 리소스 수명이 겹치지 않아야 함                          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 배리어 관리

### 자동 배리어

```cpp
// RDG가 자동으로 리소스 상태 전환 처리
// 개발자가 명시적 배리어 불필요

// Pass 1: UAV로 쓰기
Params1->OutputUAV = GraphBuilder.CreateUAV(Texture);

// Pass 2: SRV로 읽기 (자동 UAV→SRV 전환)
Params2->InputSRV = GraphBuilder.CreateSRV(Texture);
```

### 디버깅

```cpp
// RDG 디버그 출력
r.RDG.Debug 1              // 기본 디버그 정보
r.RDG.DumpGraph 1          // 그래프 덤프
r.RDG.OverlapUAVs 1        // UAV 오버랩 허용 (고급)

// 배리어 시각화
r.RDG.Debug.FlushGPU 1     // 각 패스 후 GPU 플러시 (디버그용)
```

---

## 유틸리티 함수

### 전체 화면 패스

```cpp
// 풀스크린 드로우 헬퍼
FPixelShaderUtils::AddFullscreenPass(
    GraphBuilder,
    View.ShaderMap,
    RDG_EVENT_NAME("FullscreenEffect"),
    PixelShader,
    Parameters,
    View.ViewRect
);
```

### 텍스처 복사

```cpp
// 텍스처 복사
AddCopyTexturePass(
    GraphBuilder,
    SourceTexture,
    DestTexture,
    FIntPoint::ZeroValue  // 오프셋
);

// 텍스처 클리어
AddClearRenderTargetPass(
    GraphBuilder,
    TargetTexture,
    FLinearColor::Black
);
```

### 리소스 읽기

```cpp
// GPU → CPU 복사 (디버그용)
AddEnqueueCopyPass(
    GraphBuilder,
    PooledBuffer,
    Offset,
    Size
);
```

---

## 성능 최적화

### 패스 병합

```cpp
// 연속된 작은 패스는 병합 고려
// BAD: 많은 작은 패스
for (int i = 0; i < 10; ++i)
{
    GraphBuilder.AddPass(...);  // 10개 패스
}

// GOOD: 하나의 패스에서 루프
GraphBuilder.AddPass(
    RDG_EVENT_NAME("CombinedPass"),
    ...,
    [](FRHICommandList& RHICmdList)
    {
        for (int i = 0; i < 10; ++i)
        {
            // 내부 루프
        }
    });
```

### 불필요한 클리어 방지

```cpp
// Load Action 최적화
Parameters->RenderTargets[0] = FRenderTargetBinding(
    OutputTexture,
    ERenderTargetLoadAction::ENoAction  // 전체 덮어쓰면 클리어 불필요
);
```

### 패스 컬링

```cpp
// 사용되지 않는 패스 자동 제거
// NeverCull 플래그로 방지 가능 (사이드 이펙트가 있는 패스)

GraphBuilder.AddPass(
    ...,
    ERDGPassFlags::Compute | ERDGPassFlags::NeverCull,
    ...
);
```

---

## 요약

| 기능 | 용도 | 장점 |
|------|------|------|
| 자동 의존성 | 패스 순서 관리 | 코드 단순화 |
| 메모리 앨리어싱 | 리소스 재사용 | 메모리 절약 |
| 자동 배리어 | 상태 전환 | 버그 방지 |
| 패스 컬링 | 불필요한 패스 제거 | 성능 향상 |

---

## 참고 자료

- [RDG Documentation](https://docs.unrealengine.com/render-dependency-graph/)
- [RDG Best Practices](https://docs.unrealengine.com/rdg-best-practices/)
- [Render Graph Programming](https://www.youtube.com/watch?v=rdg_programming)
