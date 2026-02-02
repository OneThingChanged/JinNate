# RDG 개발 가이드

> 원문: [剖析虚幻渲染体系（11）- RDG](https://www.cnblogs.com/timlly/p/15217090.html)

RDG를 사용한 실제 개발 방법과 코드 예제를 설명합니다.

---

## 11.4.1 기본 사용 패턴

### FRDGBuilder 생명주기

RDG 사용의 기본 패턴은 `FRDGBuilder`를 로컬 객체로 생성하고, Pass를 추가한 후 `Execute()`를 호출하는 것입니다.

```cpp
void RenderMyFeature(FRHICommandListImmediate& RHICmdList, FSceneView& View)
{
    // 1. RDG Builder 생성
    FRDGBuilder GraphBuilder(RHICmdList, RDG_EVENT_NAME("MyFeature"));

    // 2. 리소스 생성
    FRDGTextureRef OutputTexture = CreateOutputTexture(GraphBuilder);

    // 3. Pass 추가
    AddMyRenderPass(GraphBuilder, OutputTexture, View);

    // 4. 결과 추출 (필요시)
    TRefCountPtr<IPooledRenderTarget> ExtractedRT;
    GraphBuilder.QueueTextureExtraction(OutputTexture, &ExtractedRT);

    // 5. 실행 (컴파일 + 실행 + 정리)
    GraphBuilder.Execute();

    // 6. Execute() 이후 ExtractedRT 사용 가능
}
```

```
┌─────────────────────────────────────────────────────────────────┐
│                    기본 사용 흐름                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  FRDGBuilder GraphBuilder(RHICmdList, Name)              │  │
│  │  • 로컬 객체로 생성                                      │  │
│  │  • RHI 커맨드 리스트 연결                                │  │
│  └──────────────────────────────────────────────────────────┘  │
│                           │                                     │
│                           ▼                                     │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  리소스 생성                                              │  │
│  │  • CreateTexture(Desc, Name)                             │  │
│  │  • CreateBuffer(Desc, Name)                              │  │
│  │  • RegisterExternalTexture(PooledRT)                     │  │
│  └──────────────────────────────────────────────────────────┘  │
│                           │                                     │
│                           ▼                                     │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Pass 추가                                                │  │
│  │  • AllocParameters<T>()                                  │  │
│  │  • AddPass(Name, Params, Flags, Lambda)                  │  │
│  └──────────────────────────────────────────────────────────┘  │
│                           │                                     │
│                           ▼                                     │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  추출 큐 등록 (선택)                                      │  │
│  │  • QueueTextureExtraction(Tex, &OutPtr)                  │  │
│  └──────────────────────────────────────────────────────────┘  │
│                           │                                     │
│                           ▼                                     │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  GraphBuilder.Execute()                                  │  │
│  │  • Compile → Execute → Cleanup                           │  │
│  │  • 모든 RDG 메모리 자동 해제                             │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 11.4.2 리소스 생성

### 2D 렌더 타겟 텍스처

```cpp
// 기본 2D 렌더 타겟
FRDGTextureDesc RTDesc = FRDGTextureDesc::Create2D(
    View.ViewRect.Size(),                     // 크기
    PF_FloatRGBA,                              // 포맷
    FClearValueBinding::Black,                 // 클리어 값 (Fast Clear)
    TexCreate_RenderTargetable |               // 렌더 타겟으로 사용
    TexCreate_ShaderResource                   // SRV로도 사용
);

FRDGTextureRef MyRT = GraphBuilder.CreateTexture(RTDesc, TEXT("MyRenderTarget"));
```

### 컴퓨트 출력 텍스처 (UAV)

```cpp
// UAV로 쓰기 가능한 텍스처
FRDGTextureDesc UAVDesc = FRDGTextureDesc::Create2D(
    FIntPoint(512, 512),
    PF_R32_FLOAT,
    FClearValueBinding::None,
    TexCreate_UAV |                            // UAV로 사용
    TexCreate_ShaderResource                   // SRV로도 사용
);

FRDGTextureRef ComputeOutput = GraphBuilder.CreateTexture(UAVDesc, TEXT("ComputeOutput"));
```

### 3D 볼륨 텍스처

```cpp
FRDGTextureDesc VolumeDesc = FRDGTextureDesc::Create3D(
    FIntVector(128, 128, 128),                // 3D 크기
    PF_R16F,                                   // 포맷
    TexCreate_UAV | TexCreate_ShaderResource
);

FRDGTextureRef VolumeTex = GraphBuilder.CreateTexture(VolumeDesc, TEXT("VolumeTexture"));
```

### Structured Buffer

```cpp
// 구조체 정의
struct FMyParticleData
{
    FVector4f Position;
    FVector4f Velocity;
    float Lifetime;
    float Padding[3];  // 16바이트 정렬
};

// Structured Buffer 생성
FRDGBufferDesc ParticleDesc = FRDGBufferDesc::CreateStructuredDesc(
    sizeof(FMyParticleData),                  // 구조체 크기
    10000                                      // 요소 개수
);

FRDGBufferRef ParticleBuffer = GraphBuilder.CreateBuffer(ParticleDesc, TEXT("ParticleBuffer"));
```

### 뷰 생성 (SRV/UAV)

```cpp
// 텍스처 SRV
FRDGTextureSRVRef InputSRV = GraphBuilder.CreateSRV(
    FRDGTextureSRVDesc::Create(InputTexture)
);

// 특정 포맷으로 SRV
FRDGTextureSRVRef FormattedSRV = GraphBuilder.CreateSRV(
    FRDGTextureSRVDesc::CreateWithPixelFormat(InputTexture, PF_R32_FLOAT)
);

// 특정 밉 레벨 SRV
FRDGTextureSRVRef MipSRV = GraphBuilder.CreateSRV(
    FRDGTextureSRVDesc::CreateForMipLevel(InputTexture, /* MipLevel */ 2)
);

// 텍스처 UAV
FRDGTextureUAVRef OutputUAV = GraphBuilder.CreateUAV(
    FRDGTextureUAVDesc(OutputTexture, /* MipLevel */ 0)
);

// 버퍼 SRV/UAV
FRDGBufferSRVRef BufferSRV = GraphBuilder.CreateSRV(DataBuffer);
FRDGBufferUAVRef BufferUAV = GraphBuilder.CreateUAV(DataBuffer);
```

---

## 11.4.3 외부 리소스 등록

RDG 외부에서 생성된 리소스를 RDG 그래프에 등록하여 사용할 수 있습니다.

```cpp
// Scene Color 등록
FRDGTextureRef SceneColor = GraphBuilder.RegisterExternalTexture(
    SceneContext.GetSceneColor(),
    TEXT("SceneColor")
);

// GBuffer 텍스처 등록
FRDGTextureRef GBufferA = GraphBuilder.RegisterExternalTexture(
    SceneContext.GBufferA,
    TEXT("GBufferA")
);

// 외부 버퍼 등록
TRefCountPtr<FRDGPooledBuffer> ExternalBuffer = GetMyBuffer();
FRDGBufferRef Buffer = GraphBuilder.RegisterExternalBuffer(
    ExternalBuffer,
    TEXT("ExternalBuffer")
);
```

```
┌─────────────────────────────────────────────────────────────────┐
│                    외부 리소스 등록 흐름                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  외부 리소스                    RDG 시스템                      │
│                                                                 │
│  ┌──────────────────┐          ┌──────────────────┐            │
│  │ IPooledRenderTarget│─────────▶│ FRDGTexture     │            │
│  │ (기존 RT)          │  Register │ (RDG 핸들)      │            │
│  └──────────────────┘          └──────────────────┘            │
│                                                                 │
│  특징:                                                          │
│  • 외부 리소스의 생명주기는 RDG가 관리하지 않음                │
│  • RDG 사용 중 리소스가 유효한지 개발자가 보장                 │
│  • 동일 리소스 중복 등록 시 기존 핸들 반환 (캐싱)              │
│  • GetRHI()로 양방향 변환 가능                                 │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 11.4.4 셰이더 파라미터 구조체 정의

RDG Pass는 `BEGIN_SHADER_PARAMETER_STRUCT` 매크로로 정의된 파라미터 구조체를 사용합니다.

### 컴퓨트 Pass 파라미터

```cpp
BEGIN_SHADER_PARAMETER_STRUCT(FMyComputePassParameters, )
    // 입력 텍스처 (SRV)
    SHADER_PARAMETER_RDG_TEXTURE_SRV(Texture2D<float4>, InputTexture)

    // 출력 텍스처 (UAV)
    SHADER_PARAMETER_RDG_TEXTURE_UAV(RWTexture2D<float4>, OutputTexture)

    // 입력 버퍼 (SRV)
    SHADER_PARAMETER_RDG_BUFFER_SRV(StructuredBuffer<FMyData>, InputBuffer)

    // 출력 버퍼 (UAV)
    SHADER_PARAMETER_RDG_BUFFER_UAV(RWStructuredBuffer<FMyData>, OutputBuffer)

    // 상수 파라미터
    SHADER_PARAMETER(FVector4f, MyConstant)
    SHADER_PARAMETER(float, Intensity)
    SHADER_PARAMETER(uint32, ElementCount)

    // 샘플러
    SHADER_PARAMETER_SAMPLER(SamplerState, LinearSampler)
END_SHADER_PARAMETER_STRUCT()
```

### 래스터 Pass 파라미터

```cpp
BEGIN_SHADER_PARAMETER_STRUCT(FMyRasterPassParameters, )
    // 입력 텍스처
    SHADER_PARAMETER_RDG_TEXTURE_SRV(Texture2D, SceneColorTexture)
    SHADER_PARAMETER_RDG_TEXTURE_SRV(Texture2D, DepthTexture)

    // 상수
    SHADER_PARAMETER(FMatrix44f, ViewProjectionMatrix)
    SHADER_PARAMETER(FVector3f, CameraPosition)

    // 샘플러
    SHADER_PARAMETER_SAMPLER(SamplerState, PointClampSampler)

    // 렌더 타겟 바인딩 (래스터 Pass 필수)
    RENDER_TARGET_BINDING_SLOTS()
END_SHADER_PARAMETER_STRUCT()
```

```
┌─────────────────────────────────────────────────────────────────┐
│                    파라미터 매크로 종류                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  RDG 리소스:                                                    │
│  ├── SHADER_PARAMETER_RDG_TEXTURE(Type, Name)     // 텍스처    │
│  ├── SHADER_PARAMETER_RDG_TEXTURE_SRV(Type, Name) // 텍스처SRV │
│  ├── SHADER_PARAMETER_RDG_TEXTURE_UAV(Type, Name) // 텍스처UAV │
│  ├── SHADER_PARAMETER_RDG_BUFFER(Type, Name)      // 버퍼      │
│  ├── SHADER_PARAMETER_RDG_BUFFER_SRV(Type, Name)  // 버퍼SRV   │
│  └── SHADER_PARAMETER_RDG_BUFFER_UAV(Type, Name)  // 버퍼UAV   │
│                                                                 │
│  일반 파라미터:                                                 │
│  ├── SHADER_PARAMETER(Type, Name)                 // 스칼라    │
│  ├── SHADER_PARAMETER_ARRAY(Type, Name, [N])      // 배열      │
│  ├── SHADER_PARAMETER_SAMPLER(Type, Name)         // 샘플러    │
│  └── SHADER_PARAMETER_STRUCT(Type, Name)          // 구조체    │
│                                                                 │
│  렌더 타겟 (래스터 Pass):                                       │
│  └── RENDER_TARGET_BINDING_SLOTS()                // RT 바인딩 │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 11.4.5 Pass 추가

### 컴퓨트 Pass 추가

```cpp
void AddMyComputePass(
    FRDGBuilder& GraphBuilder,
    FRDGTextureRef InputTexture,
    FRDGTextureRef OutputTexture,
    const FViewInfo& View)
{
    // 1. 파라미터 할당
    FMyComputePassParameters* PassParameters =
        GraphBuilder.AllocParameters<FMyComputePassParameters>();

    // 2. 파라미터 설정
    PassParameters->InputTexture = GraphBuilder.CreateSRV(InputTexture);
    PassParameters->OutputTexture = GraphBuilder.CreateUAV(OutputTexture);
    PassParameters->Intensity = 1.5f;

    // 3. 셰이더 가져오기
    TShaderMapRef<FMyComputeShader> ComputeShader(View.ShaderMap);

    // 4. 그룹 수 계산
    FIntPoint OutputSize = OutputTexture->Desc.Extent;
    FIntVector GroupCount = FComputeShaderUtils::GetGroupCount(
        FIntVector(OutputSize.X, OutputSize.Y, 1),
        FIntVector(8, 8, 1)  // 스레드 그룹 크기
    );

    // 5. Pass 추가
    FComputeShaderUtils::AddPass(
        GraphBuilder,
        RDG_EVENT_NAME("MyComputePass"),
        ComputeShader,
        PassParameters,
        GroupCount
    );
}
```

### 래스터 Pass 추가

```cpp
void AddMyRasterPass(
    FRDGBuilder& GraphBuilder,
    FRDGTextureRef InputTexture,
    FRDGTextureRef OutputTexture,
    const FViewInfo& View)
{
    // 1. 파라미터 할당
    FMyRasterPassParameters* PassParameters =
        GraphBuilder.AllocParameters<FMyRasterPassParameters>();

    // 2. 파라미터 설정
    PassParameters->SceneColorTexture = GraphBuilder.CreateSRV(InputTexture);
    PassParameters->ViewProjectionMatrix = View.ViewProjectionMatrix;

    // 3. 렌더 타겟 바인딩
    PassParameters->RenderTargets[0] = FRenderTargetBinding(
        OutputTexture,
        ERenderTargetLoadAction::EClear   // Clear, Load, NoAction
    );

    // 4. 셰이더 가져오기
    TShaderMapRef<FMyVertexShader> VertexShader(View.ShaderMap);
    TShaderMapRef<FMyPixelShader> PixelShader(View.ShaderMap);

    // 5. Pass 추가
    GraphBuilder.AddPass(
        RDG_EVENT_NAME("MyRasterPass"),
        PassParameters,
        ERDGPassFlags::Raster,
        [VertexShader, PixelShader, PassParameters, &View]
        (FRHICommandList& RHICmdList)
        {
            // 그래픽 파이프라인 상태 설정
            FGraphicsPipelineStateInitializer PSOInit;
            FPixelShaderUtils::InitFullscreenPipelineState(
                RHICmdList, View.ShaderMap, PixelShader, PSOInit);

            SetGraphicsPipelineState(RHICmdList, PSOInit, 0);

            // 셰이더 파라미터 바인딩
            SetShaderParameters(RHICmdList, PixelShader,
                PixelShader.GetPixelShader(), *PassParameters);

            // 풀스크린 쿼드 드로우
            FPixelShaderUtils::DrawFullscreenTriangle(RHICmdList);
        }
    );
}
```

### FPixelShaderUtils 활용

풀스크린 패스의 경우 `FPixelShaderUtils`를 사용하면 간결하게 작성할 수 있습니다.

```cpp
// 풀스크린 래스터 Pass 간편 추가
FPixelShaderUtils::AddFullscreenPass(
    GraphBuilder,
    View.ShaderMap,
    RDG_EVENT_NAME("FullscreenEffect"),
    PixelShader,
    PassParameters,
    View.ViewRect
);
```

---

## 11.4.6 리소스 추출

RDG 지연 실행 특성으로 인해, 렌더링 결과를 후속 사용하려면 추출을 큐에 등록해야 합니다.

```cpp
// 텍스처 추출
TRefCountPtr<IPooledRenderTarget> ExtractedRT;
GraphBuilder.QueueTextureExtraction(OutputTexture, &ExtractedRT);

// 버퍼 추출
TRefCountPtr<FRDGPooledBuffer> ExtractedBuffer;
GraphBuilder.QueueBufferExtraction(OutputBuffer, &ExtractedBuffer);

// Execute() 호출
GraphBuilder.Execute();

// 이제 추출된 리소스 사용 가능
UseExtractedResult(ExtractedRT);
```

```
┌─────────────────────────────────────────────────────────────────┐
│                    리소스 추출 타이밍                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  시간 →                                                         │
│                                                                 │
│  ┌────────────────────────────────────────────────────────────┐│
│  │ QueueTextureExtraction()  │   Execute()   │  결과 사용     ││
│  │         ↓                 │      ↓        │      ↓         ││
│  │   추출 예약만 됨          │  실제 렌더링  │  유효한 데이터 ││
│  │   (포인터 저장)           │  + 추출 수행  │  (사용 가능)   ││
│  └────────────────────────────────────────────────────────────┘│
│                                                                 │
│  주의사항:                                                      │
│  • Execute() 전에는 추출된 리소스 접근 불가                    │
│  • 추출된 리소스는 다음 프레임에서 주로 사용                   │
│  • 추출하면 해당 리소스는 컬링되지 않음                        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 11.4.7 전체 예제: 가우시안 블러

```cpp
void RenderGaussianBlur(
    FRDGBuilder& GraphBuilder,
    FRDGTextureRef InputTexture,
    FRDGTextureRef OutputTexture,
    const FViewInfo& View,
    float BlurRadius)
{
    FIntPoint TextureSize = InputTexture->Desc.Extent;

    // ==================== 1. 중간 텍스처 생성 ====================
    // (수평 블러 결과를 저장할 임시 텍스처)
    FRDGTextureDesc TempDesc = FRDGTextureDesc::Create2D(
        TextureSize,
        InputTexture->Desc.Format,
        FClearValueBinding::None,
        TexCreate_RenderTargetable | TexCreate_ShaderResource
    );
    FRDGTextureRef TempTexture = GraphBuilder.CreateTexture(TempDesc, TEXT("BlurTemp"));

    // ==================== 2. 수평 블러 Pass ====================
    {
        FGaussianBlurPS::FParameters* Parameters =
            GraphBuilder.AllocParameters<FGaussianBlurPS::FParameters>();

        Parameters->InputTexture = GraphBuilder.CreateSRV(InputTexture);
        Parameters->InputSampler = TStaticSamplerState<SF_Bilinear, AM_Clamp>::GetRHI();
        Parameters->BlurDirection = FVector2f(1.0f / TextureSize.X, 0.0f);
        Parameters->BlurRadius = BlurRadius;

        Parameters->RenderTargets[0] = FRenderTargetBinding(
            TempTexture,
            ERenderTargetLoadAction::ENoAction
        );

        TShaderMapRef<FGaussianBlurPS> PixelShader(View.ShaderMap);

        FPixelShaderUtils::AddFullscreenPass(
            GraphBuilder,
            View.ShaderMap,
            RDG_EVENT_NAME("GaussianBlur_Horizontal"),
            PixelShader,
            Parameters,
            FIntRect(0, 0, TextureSize.X, TextureSize.Y)
        );
    }

    // ==================== 3. 수직 블러 Pass ====================
    {
        FGaussianBlurPS::FParameters* Parameters =
            GraphBuilder.AllocParameters<FGaussianBlurPS::FParameters>();

        // 수평 블러 결과를 입력으로
        Parameters->InputTexture = GraphBuilder.CreateSRV(TempTexture);
        Parameters->InputSampler = TStaticSamplerState<SF_Bilinear, AM_Clamp>::GetRHI();
        Parameters->BlurDirection = FVector2f(0.0f, 1.0f / TextureSize.Y);
        Parameters->BlurRadius = BlurRadius;

        Parameters->RenderTargets[0] = FRenderTargetBinding(
            OutputTexture,
            ERenderTargetLoadAction::ENoAction
        );

        TShaderMapRef<FGaussianBlurPS> PixelShader(View.ShaderMap);

        FPixelShaderUtils::AddFullscreenPass(
            GraphBuilder,
            View.ShaderMap,
            RDG_EVENT_NAME("GaussianBlur_Vertical"),
            PixelShader,
            Parameters,
            FIntRect(0, 0, TextureSize.X, TextureSize.Y)
        );
    }

    // TempTexture는 수직 블러 Pass 이후 자동으로 풀에 반환됨
    // (LastPass = 수직 블러 Pass)
}
```

```
┌─────────────────────────────────────────────────────────────────┐
│                    가우시안 블러 RDG 그래프                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  InputTexture (외부)                                            │
│       │                                                         │
│       ▼                                                         │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Pass 1: GaussianBlur_Horizontal                        │   │
│  │  • Input: InputTexture (SRV)                            │   │
│  │  • Output: TempTexture (RT)                             │   │
│  │  • Direction: (1/Width, 0)                              │   │
│  └─────────────────────────────────────────────────────────┘   │
│       │                                                         │
│       ▼ TempTexture 의존성                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Pass 2: GaussianBlur_Vertical                          │   │
│  │  • Input: TempTexture (SRV)                             │   │
│  │  • Output: OutputTexture (RT)                           │   │
│  │  • Direction: (0, 1/Height)                             │   │
│  └─────────────────────────────────────────────────────────┘   │
│       │                                                         │
│       ▼                                                         │
│  OutputTexture (결과)                                           │
│                                                                 │
│  RDG 최적화:                                                    │
│  • TempTexture: Pass 2 이후 즉시 풀 반환                       │
│  • 배리어: InputTexture→SRV, TempTexture RT→SRV 자동 처리     │
│  • Pass 병합: 다른 RT이므로 병합 불가 (별도 RenderPass)        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 11.4.8 모범 사례

### DO (권장)

```
┌─────────────────────────────────────────────────────────────────┐
│                    권장 사항                                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ✓ 임시 리소스는 CreateTexture/CreateBuffer 사용               │
│    • RDG가 생명주기 자동 관리, 앨리어싱 최적화                 │
│                                                                 │
│  ✓ 외부 리소스는 RegisterExternal* 사용                        │
│    • 기존 리소스를 RDG 그래프에 통합                           │
│                                                                 │
│  ✓ 프레임 간 유지 리소스에 MultiFrame 플래그                   │
│    • RDG가 해제하지 않도록 명시                                │
│                                                                 │
│  ✓ 의미 있는 이름으로 리소스/Pass 명명                         │
│    • 디버깅, 프로파일링 시 식별 용이                           │
│    • "Feature_Stage_Purpose" 형식 권장                         │
│                                                                 │
│  ✓ Pass Lambda 내에서만 RHI 명령 실행                          │
│    • Lambda 외부에서 RHI 호출 금지                             │
│                                                                 │
│  ✓ FComputeShaderUtils, FPixelShaderUtils 활용                 │
│    • 반복적인 보일러플레이트 코드 감소                         │
│                                                                 │
│  ✓ 실제 사용하는 리소스만 파라미터에 포함                      │
│    • 불필요한 의존성 방지                                      │
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
│    • GetRHI()는 Pass Lambda 내에서만 호출                      │
│                                                                 │
│  ✗ Lambda 캡처로 로컬 변수 참조                                │
│    • 지연 실행으로 인해 생명주기 문제 발생                     │
│    • 파라미터 구조체나 멤버 변수 사용                          │
│                                                                 │
│  ✗ Pass 외부에서 상태 변경                                     │
│    • 모든 렌더링 작업은 Pass Lambda 내에서                     │
│                                                                 │
│  ✗ 불필요하게 큰 리소스 생성                                   │
│    • 메모리 풀 효율 저하                                       │
│                                                                 │
│  ✗ 수동으로 배리어 삽입 시도                                   │
│    • RDG가 자동으로 최적의 배리어 배치                         │
│                                                                 │
│  ✗ 여러 작업을 하나의 Pass에 결합                              │
│    • Pass 단위 의존성 분석 방해                                │
│    • 컬링/병합 최적화 기회 상실                                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 다음 단계

[RDG 디버깅](05-rdg-debugging.md)에서 디버깅 방법과 즉시 실행 모드를 알아봅니다.
