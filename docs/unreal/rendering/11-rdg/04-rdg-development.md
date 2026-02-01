# RDG 개발 가이드

RDG를 사용한 실제 개발 방법과 코드 예제를 설명합니다.

---

## 기본 사용 패턴

### FRDGBuilder 생성 및 실행

```cpp
void RenderMyFeature(FRHICommandListImmediate& RHICmdList, FSceneView& View)
{
    // 1. RDG Builder 생성
    FRDGBuilder GraphBuilder(RHICmdList, RDG_EVENT_NAME("MyFeature"));

    // 2. 리소스 생성 및 Pass 추가
    // ... (아래 예제 참조)

    // 3. 실행 (컴파일 + 실행 + 정리)
    GraphBuilder.Execute();
}
```

```
┌─────────────────────────────────────────────────────────────────┐
│                    기본 사용 흐름                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  FRDGBuilder GraphBuilder(RHICmdList, Name)              │  │
│  └──────────────────────────────────────────────────────────┘  │
│                           │                                     │
│                           ▼                                     │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  CreateTexture() / CreateBuffer()                        │  │
│  │  CreateSRV() / CreateUAV()                               │  │
│  │  RegisterExternalTexture() / RegisterExternalBuffer()    │  │
│  └──────────────────────────────────────────────────────────┘  │
│                           │                                     │
│                           ▼                                     │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  AddPass(Name, Parameters, Flags, Lambda)                │  │
│  │  AddPass(...)                                            │  │
│  │  AddPass(...)                                            │  │
│  └──────────────────────────────────────────────────────────┘  │
│                           │                                     │
│                           ▼                                     │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  QueueTextureExtraction() / QueueBufferExtraction()      │  │
│  └──────────────────────────────────────────────────────────┘  │
│                           │                                     │
│                           ▼                                     │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  GraphBuilder.Execute()                                  │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 텍스처 리소스 생성

### 2D 렌더 타겟

```cpp
// 2D 렌더 타겟 텍스처 생성
FRDGTextureDesc RTDesc = FRDGTextureDesc::Create2D(
    View.ViewRect.Size(),                // 크기
    PF_FloatRGBA,                         // 포맷
    FClearValueBinding::Black,            // 클리어 값
    TexCreate_RenderTargetable |          // 렌더 타겟
    TexCreate_ShaderResource              // 셰이더 리소스로도 사용
);

FRDGTextureRef MyRT = GraphBuilder.CreateTexture(RTDesc, TEXT("MyRenderTarget"));
```

### 컴퓨트 출력 텍스처

```cpp
// UAV로 쓰기 가능한 텍스처
FRDGTextureDesc UAVDesc = FRDGTextureDesc::Create2D(
    FIntPoint(512, 512),
    PF_R32_FLOAT,
    FClearValueBinding::None,
    TexCreate_UAV |
    TexCreate_ShaderResource
);

FRDGTextureRef OutputTex = GraphBuilder.CreateTexture(UAVDesc, TEXT("ComputeOutput"));
```

### 3D 볼륨 텍스처

```cpp
FRDGTextureDesc VolumeDesc = FRDGTextureDesc::Create3D(
    FIntVector(128, 128, 128),  // 3D 크기
    PF_R16F,
    TexCreate_UAV |
    TexCreate_ShaderResource
);

FRDGTextureRef VolumeTex = GraphBuilder.CreateTexture(VolumeDesc, TEXT("VolumeTexture"));
```

---

## 버퍼 리소스 생성

### Structured Buffer

```cpp
// 구조체 정의
struct FMyData
{
    FVector4f Position;
    FVector4f Color;
};

// Structured Buffer 생성
FRDGBufferDesc BufferDesc = FRDGBufferDesc::CreateStructuredDesc(
    sizeof(FMyData),   // 구조체 크기
    1024               // 요소 개수
);

FRDGBufferRef DataBuffer = GraphBuilder.CreateBuffer(BufferDesc, TEXT("MyDataBuffer"));
```

### Byte Address Buffer

```cpp
FRDGBufferDesc RawDesc = FRDGBufferDesc::CreateBufferDesc(
    sizeof(uint32),
    4096
);
RawDesc.Usage |= BUF_ByteAddressBuffer;

FRDGBufferRef RawBuffer = GraphBuilder.CreateBuffer(RawDesc, TEXT("RawBuffer"));
```

---

## 뷰 생성

### SRV 생성

```cpp
// 텍스처 SRV
FRDGTextureSRVRef TextureSRV = GraphBuilder.CreateSRV(
    FRDGTextureSRVDesc::Create(InputTexture)
);

// 특정 포맷으로 SRV 생성
FRDGTextureSRVRef FormattedSRV = GraphBuilder.CreateSRV(
    FRDGTextureSRVDesc::CreateWithPixelFormat(InputTexture, PF_R32_FLOAT)
);

// 버퍼 SRV
FRDGBufferSRVRef BufferSRV = GraphBuilder.CreateSRV(DataBuffer);
```

### UAV 생성

```cpp
// 텍스처 UAV (Mip 0)
FRDGTextureUAVRef TextureUAV = GraphBuilder.CreateUAV(OutputTexture);

// 특정 Mip Level UAV
FRDGTextureUAVRef MipUAV = GraphBuilder.CreateUAV(
    FRDGTextureUAVDesc(OutputTexture, /* MipLevel */ 1)
);

// 버퍼 UAV
FRDGBufferUAVRef BufferUAV = GraphBuilder.CreateUAV(DataBuffer, PF_R32_UINT);
```

---

## 외부 리소스 등록

### 외부 텍스처 등록

```cpp
// 기존 Pooled Render Target 등록
TRefCountPtr<IPooledRenderTarget> ExternalRT = GetExternalRenderTarget();
FRDGTextureRef ExternalTexture = GraphBuilder.RegisterExternalTexture(ExternalRT);

// Scene Color 등록 예시
FRDGTextureRef SceneColor = GraphBuilder.RegisterExternalTexture(
    SceneContext.GetSceneColor()
);
```

### 외부 버퍼 등록

```cpp
TRefCountPtr<FRDGPooledBuffer> ExternalBuffer = GetExternalBuffer();
FRDGBufferRef Buffer = GraphBuilder.RegisterExternalBuffer(ExternalBuffer);
```

---

## Pass 추가

### 셰이더 파라미터 정의

```cpp
// 셰이더 파라미터 구조체
BEGIN_SHADER_PARAMETER_STRUCT(FMyPassParameters, )
    // 입력 텍스처
    SHADER_PARAMETER_RDG_TEXTURE_SRV(Texture2D, InputTexture)

    // 출력 UAV
    SHADER_PARAMETER_RDG_TEXTURE_UAV(RWTexture2D<float4>, OutputTexture)

    // 상수 버퍼
    SHADER_PARAMETER(FVector4f, MyConstant)
    SHADER_PARAMETER(float, Intensity)

    // 렌더 타겟 (래스터 Pass용)
    RENDER_TARGET_BINDING_SLOTS()
END_SHADER_PARAMETER_STRUCT()
```

### 컴퓨트 Pass 추가

```cpp
// 파라미터 할당 및 설정
FMyComputePass::FParameters* PassParameters =
    GraphBuilder.AllocParameters<FMyComputePass::FParameters>();

PassParameters->InputTexture = GraphBuilder.CreateSRV(InputTex);
PassParameters->OutputTexture = GraphBuilder.CreateUAV(OutputTex);
PassParameters->MyConstant = FVector4f(1.0f, 0.5f, 0.0f, 1.0f);

// 셰이더 가져오기
TShaderMapRef<FMyComputeShader> ComputeShader(View.ShaderMap);

// Pass 추가
FComputeShaderUtils::AddPass(
    GraphBuilder,
    RDG_EVENT_NAME("MyComputePass"),
    ComputeShader,
    PassParameters,
    FIntVector(
        FMath::DivideAndRoundUp(OutputSize.X, 8),
        FMath::DivideAndRoundUp(OutputSize.Y, 8),
        1
    )
);
```

### 래스터 Pass 추가

```cpp
FMyRasterPass::FParameters* PassParameters =
    GraphBuilder.AllocParameters<FMyRasterPass::FParameters>();

PassParameters->InputTexture = GraphBuilder.CreateSRV(InputTex);
PassParameters->RenderTargets[0] = FRenderTargetBinding(
    OutputRT,
    ERenderTargetLoadAction::EClear
);

// 셰이더 가져오기
TShaderMapRef<FMyVertexShader> VertexShader(View.ShaderMap);
TShaderMapRef<FMyPixelShader> PixelShader(View.ShaderMap);

GraphBuilder.AddPass(
    RDG_EVENT_NAME("MyRasterPass"),
    PassParameters,
    ERDGPassFlags::Raster,
    [VertexShader, PixelShader, PassParameters](FRHICommandList& RHICmdList)
    {
        // 그래픽 파이프라인 상태 설정
        FGraphicsPipelineStateInitializer PSOInit;
        PSOInit.BoundShaderState.VertexShaderRHI = VertexShader.GetVertexShader();
        PSOInit.BoundShaderState.PixelShaderRHI = PixelShader.GetPixelShader();
        // ... 추가 PSO 설정

        SetGraphicsPipelineState(RHICmdList, PSOInit);
        SetShaderParameters(RHICmdList, PixelShader, PixelShader.GetPixelShader(), *PassParameters);

        // 드로우 콜
        RHICmdList.DrawPrimitive(0, 1, 1);
    }
);
```

---

## 리소스 추출

### 텍스처 추출

```cpp
// 추출 대상 포인터
TRefCountPtr<IPooledRenderTarget> ExtractedRT;

// 추출 큐에 등록
GraphBuilder.QueueTextureExtraction(OutputTexture, &ExtractedRT);

// Execute() 이후 ExtractedRT 사용 가능
GraphBuilder.Execute();

// 이제 ExtractedRT에 결과가 있음
```

### 버퍼 추출

```cpp
TRefCountPtr<FRDGPooledBuffer> ExtractedBuffer;
GraphBuilder.QueueBufferExtraction(OutputBuffer, &ExtractedBuffer);

GraphBuilder.Execute();
// ExtractedBuffer 사용 가능
```

---

## 전체 예제: 블러 효과

```cpp
void RenderGaussianBlur(
    FRDGBuilder& GraphBuilder,
    FRDGTextureRef InputTexture,
    FRDGTextureRef OutputTexture,
    const FViewInfo& View)
{
    // 중간 텍스처 생성 (수평 블러 결과)
    FRDGTextureDesc TempDesc = FRDGTextureDesc::Create2D(
        InputTexture->Desc.Extent,
        InputTexture->Desc.Format,
        FClearValueBinding::None,
        TexCreate_RenderTargetable | TexCreate_ShaderResource
    );
    FRDGTextureRef TempTexture = GraphBuilder.CreateTexture(TempDesc, TEXT("BlurTemp"));

    // Pass 1: 수평 블러
    {
        FBlurPass::FParameters* Parameters =
            GraphBuilder.AllocParameters<FBlurPass::FParameters>();
        Parameters->InputTexture = GraphBuilder.CreateSRV(InputTexture);
        Parameters->BlurDirection = FVector2f(1.0f, 0.0f);
        Parameters->RenderTargets[0] = FRenderTargetBinding(
            TempTexture,
            ERenderTargetLoadAction::ENoAction
        );

        TShaderMapRef<FBlurPS> PixelShader(View.ShaderMap);

        FPixelShaderUtils::AddFullscreenPass(
            GraphBuilder,
            View.ShaderMap,
            RDG_EVENT_NAME("HorizontalBlur"),
            PixelShader,
            Parameters,
            View.ViewRect
        );
    }

    // Pass 2: 수직 블러
    {
        FBlurPass::FParameters* Parameters =
            GraphBuilder.AllocParameters<FBlurPass::FParameters>();
        Parameters->InputTexture = GraphBuilder.CreateSRV(TempTexture);
        Parameters->BlurDirection = FVector2f(0.0f, 1.0f);
        Parameters->RenderTargets[0] = FRenderTargetBinding(
            OutputTexture,
            ERenderTargetLoadAction::ENoAction
        );

        TShaderMapRef<FBlurPS> PixelShader(View.ShaderMap);

        FPixelShaderUtils::AddFullscreenPass(
            GraphBuilder,
            View.ShaderMap,
            RDG_EVENT_NAME("VerticalBlur"),
            PixelShader,
            Parameters,
            View.ViewRect
        );
    }

    // TempTexture는 Pass 2 이후 자동으로 풀에 반환됨
}
```

---

## 모범 사례

### DO (권장)

```
┌─────────────────────────────────────────────────────────────────┐
│                    권장 사항                                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ✓ 임시 리소스는 CreateTexture/CreateBuffer 사용               │
│  ✓ 외부 리소스는 RegisterExternal* 사용                        │
│  ✓ 프레임 간 유지 리소스에 MultiFrame 플래그 사용              │
│  ✓ 의미 있는 이름으로 리소스/Pass 명명                         │
│  ✓ 필요한 최소 크기/포맷 사용                                  │
│  ✓ Pass Lambda 내에서만 RHI 명령 실행                          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### DON'T (비권장)

```
┌─────────────────────────────────────────────────────────────────┐
│                    비권장 사항                                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ✗ Execute() 전에 RDG 리소스에서 RHI 리소스 직접 접근          │
│  ✗ Lambda 캡처로 로컬 변수 참조 (생명주기 문제)                │
│  ✗ Pass 외부에서 상태 변경                                     │
│  ✗ 불필요하게 큰 리소스 생성                                   │
│  ✗ 수동으로 배리어 삽입 시도                                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 다음 단계

[RDG 디버깅](05-rdg-debugging.md)에서 디버깅 방법과 즉시 실행 모드를 알아봅니다.
