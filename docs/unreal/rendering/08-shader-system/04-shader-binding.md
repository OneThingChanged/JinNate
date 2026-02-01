# 파라미터 바인딩

셰이더 파라미터 시스템과 데이터 바인딩 메커니즘을 분석합니다.

---

## 파라미터 타입

### GPU 리소스 타입

```
┌─────────────────────────────────────────────────────────────────┐
│                    셰이더 리소스 타입                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Constant Buffer (cbuffer)                                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  - 작은 크기의 상수 데이터 (16KB 제한)                    │   │
│  │  - 모든 스레드가 동일한 값 접근                          │   │
│  │  - 예: 변환 행렬, 라이트 파라미터                        │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Shader Resource View (SRV)                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  - 읽기 전용 리소스                                      │   │
│  │  - 텍스처, 버퍼                                         │   │
│  │  - 예: 디퓨즈 맵, 본 행렬 버퍼                           │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Unordered Access View (UAV)                                    │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  - 읽기/쓰기 가능                                        │   │
│  │  - 컴퓨트 셰이더 출력                                    │   │
│  │  - 예: RWTexture2D, RWBuffer                            │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Sampler                                                        │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  - 텍스처 샘플링 방법 정의                               │   │
│  │  - 필터링, 래핑 모드                                     │   │
│  │  - 예: LinearSampler, PointSampler                      │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## UE 파라미터 매크로

### SHADER_PARAMETER 매크로

```cpp
// 기본 타입
SHADER_PARAMETER(float, MyFloat)
SHADER_PARAMETER(int32, MyInt)
SHADER_PARAMETER(FVector2f, MyVector2)
SHADER_PARAMETER(FVector3f, MyVector3)
SHADER_PARAMETER(FVector4f, MyVector4)
SHADER_PARAMETER(FMatrix44f, MyMatrix)

// 배열
SHADER_PARAMETER_ARRAY(float, MyFloatArray, [16])
SHADER_PARAMETER_ARRAY(FVector4f, MyVectorArray, [8])

// 텍스처 (SRV)
SHADER_PARAMETER_TEXTURE(Texture2D, MyTexture)
SHADER_PARAMETER_TEXTURE(TextureCube, MyCubemap)
SHADER_PARAMETER_TEXTURE(Texture2DArray, MyTextureArray)
SHADER_PARAMETER_TEXTURE(Texture3D, MyVolumeTexture)

// 샘플러
SHADER_PARAMETER_SAMPLER(SamplerState, MySampler)

// 조합
SHADER_PARAMETER_TEXTURE(Texture2D, BaseColorMap)
SHADER_PARAMETER_SAMPLER(SamplerState, BaseColorSampler)

// UAV
SHADER_PARAMETER_UAV(RWTexture2D<float4>, OutputTexture)
SHADER_PARAMETER_UAV(RWBuffer<uint>, OutputBuffer)

// 구조체 버퍼
SHADER_PARAMETER_SRV(StructuredBuffer<FMyStruct>, MyStructBuffer)
SHADER_PARAMETER_UAV(RWStructuredBuffer<FMyStruct>, MyRWStructBuffer)
```

### RDG 리소스

```cpp
// RDG 텍스처 (자동 생명주기 관리)
SHADER_PARAMETER_RDG_TEXTURE(Texture2D, SceneColor)
SHADER_PARAMETER_RDG_TEXTURE_UAV(RWTexture2D<float4>, OutputTexture)
SHADER_PARAMETER_RDG_TEXTURE_SRV(Texture2D, InputTexture)

// RDG 버퍼
SHADER_PARAMETER_RDG_BUFFER(Buffer<float4>, InputBuffer)
SHADER_PARAMETER_RDG_BUFFER_UAV(RWBuffer<float4>, OutputBuffer)
SHADER_PARAMETER_RDG_BUFFER_SRV(StructuredBuffer<FData>, DataBuffer)
```

---

## 파라미터 구조체

### 정의

```cpp
// 셰이더 파라미터 구조체 정의
BEGIN_SHADER_PARAMETER_STRUCT(FMyShaderParameters, )
    // 상수
    SHADER_PARAMETER(FVector4f, Color)
    SHADER_PARAMETER(float, Intensity)
    SHADER_PARAMETER(int32, Mode)

    // 텍스처
    SHADER_PARAMETER_RDG_TEXTURE(Texture2D, InputTexture)
    SHADER_PARAMETER_SAMPLER(SamplerState, InputSampler)

    // UAV 출력
    SHADER_PARAMETER_RDG_TEXTURE_UAV(RWTexture2D<float4>, OutputTexture)

    // 렌더 타겟
    RENDER_TARGET_BINDING_SLOTS()
END_SHADER_PARAMETER_STRUCT()

// 셰이더 클래스에서 사용
class FMyPixelShader : public FGlobalShader
{
    DECLARE_GLOBAL_SHADER(FMyPixelShader);
    SHADER_USE_PARAMETER_STRUCT(FMyPixelShader, FGlobalShader);

    using FParameters = FMyShaderParameters;
};
```

### 중첩 구조체

```cpp
// 공통 파라미터 구조체
BEGIN_SHADER_PARAMETER_STRUCT(FViewShaderParameters, )
    SHADER_PARAMETER(FMatrix44f, ViewMatrix)
    SHADER_PARAMETER(FMatrix44f, ProjectionMatrix)
    SHADER_PARAMETER(FMatrix44f, ViewProjectionMatrix)
    SHADER_PARAMETER(FVector3f, CameraPosition)
    SHADER_PARAMETER(float, NearPlane)
    SHADER_PARAMETER(float, FarPlane)
END_SHADER_PARAMETER_STRUCT()

BEGIN_SHADER_PARAMETER_STRUCT(FLightShaderParameters, )
    SHADER_PARAMETER(FVector3f, LightDirection)
    SHADER_PARAMETER(FVector3f, LightColor)
    SHADER_PARAMETER(float, LightIntensity)
END_SHADER_PARAMETER_STRUCT()

// 최종 파라미터 구조체
BEGIN_SHADER_PARAMETER_STRUCT(FMainPassParameters, )
    // 다른 구조체 포함
    SHADER_PARAMETER_STRUCT_INCLUDE(FViewShaderParameters, View)
    SHADER_PARAMETER_STRUCT_INCLUDE(FLightShaderParameters, Light)

    // 추가 파라미터
    SHADER_PARAMETER_RDG_TEXTURE(Texture2D, SceneColor)
    RENDER_TARGET_BINDING_SLOTS()
END_SHADER_PARAMETER_STRUCT()
```

---

## Uniform Buffer

### 정의

```cpp
// Uniform Buffer 레이아웃 정의
BEGIN_GLOBAL_SHADER_PARAMETER_STRUCT(FMyUniformBuffer, )
    SHADER_PARAMETER(FMatrix44f, Transform)
    SHADER_PARAMETER(FVector4f, Color)
    SHADER_PARAMETER(float, Time)
    SHADER_PARAMETER(int32, Flags)
END_GLOBAL_SHADER_PARAMETER_STRUCT()

// 구현 매크로
IMPLEMENT_GLOBAL_SHADER_PARAMETER_STRUCT(FMyUniformBuffer, "MyUniforms");

// 참조
SHADER_PARAMETER_STRUCT_REF(FMyUniformBuffer, MyUniforms)
```

### HLSL에서 접근

```hlsl
// Common.ush에서 자동 생성됨
cbuffer MyUniforms : register(b0)
{
    float4x4 MyUniforms_Transform;
    float4 MyUniforms_Color;
    float MyUniforms_Time;
    int MyUniforms_Flags;
};

// 사용
float4 MainPS() : SV_Target
{
    float3 TransformedPos = mul(float4(Position, 1), MyUniforms_Transform).xyz;
    return MyUniforms_Color * MyUniforms_Time;
}
```

### 업데이트

```cpp
// Uniform Buffer 생성 및 업데이트
void SetupUniformBuffer()
{
    // 데이터 설정
    FMyUniformBuffer Data;
    Data.Transform = LocalToWorld;
    Data.Color = FVector4f(1, 0, 0, 1);
    Data.Time = CurrentTime;
    Data.Flags = 0;

    // Uniform Buffer 생성
    TUniformBufferRef<FMyUniformBuffer> UniformBuffer =
        TUniformBufferRef<FMyUniformBuffer>::CreateUniformBufferImmediate(
            Data, UniformBuffer_SingleFrame);

    // 바인딩
    SetUniformBufferParameter(RHICmdList, ShaderRHI,
        GetUniformBufferParameter<FMyUniformBuffer>(), UniformBuffer);
}
```

---

## 텍스처 바인딩

### 기본 바인딩

```cpp
// 텍스처와 샘플러 설정
void BindTextures(FRHICommandList& RHICmdList, FRHIPixelShader* ShaderRHI)
{
    // 텍스처 SRV
    FRHIShaderResourceView* TextureSRV = TextureRHI->GetShaderResourceView();
    SetTextureParameter(RHICmdList, ShaderRHI,
        TextureParameter, SamplerParameter,
        TextureSRV, SamplerRHI);
}

// RDG에서 바인딩
void SetupRDGParameters(FRDGBuilder& GraphBuilder, FParameters* Parameters)
{
    // 텍스처
    Parameters->InputTexture = SceneColorTexture;
    Parameters->InputSampler = TStaticSamplerState<SF_Bilinear>::GetRHI();

    // UAV
    Parameters->OutputTexture = GraphBuilder.CreateUAV(OutputTextureDesc);
}
```

### 텍스처 배열

```cpp
// 텍스처 배열 파라미터
BEGIN_SHADER_PARAMETER_STRUCT(FParameters, )
    SHADER_PARAMETER_RDG_TEXTURE_ARRAY(Texture2D, InputTextures, [8])
    SHADER_PARAMETER_SAMPLER(SamplerState, CommonSampler)
END_SHADER_PARAMETER_STRUCT()

// 바인딩
for (int i = 0; i < 8; i++)
{
    Parameters->InputTextures[i] = TextureArray[i];
}
Parameters->CommonSampler = TStaticSamplerState<SF_Bilinear>::GetRHI();
```

---

## 버퍼 바인딩

### Structured Buffer

```cpp
// 구조체 정의
struct FMyData
{
    FVector3f Position;
    FVector3f Normal;
    FVector2f UV;
};

// 파라미터
BEGIN_SHADER_PARAMETER_STRUCT(FParameters, )
    SHADER_PARAMETER_RDG_BUFFER_SRV(StructuredBuffer<FMyData>, DataBuffer)
    SHADER_PARAMETER(uint32, DataCount)
END_SHADER_PARAMETER_STRUCT()

// 버퍼 생성 및 바인딩
void SetupBuffer(FRDGBuilder& GraphBuilder)
{
    // 버퍼 설명
    FRDGBufferDesc BufferDesc = FRDGBufferDesc::CreateStructuredDesc(
        sizeof(FMyData), DataCount);

    // 버퍼 생성
    FRDGBufferRef Buffer = GraphBuilder.CreateBuffer(BufferDesc, TEXT("DataBuffer"));

    // 데이터 업로드
    GraphBuilder.QueueBufferUpload(Buffer, DataArray.GetData(),
        DataArray.Num() * sizeof(FMyData));

    // SRV 생성 및 바인딩
    Parameters->DataBuffer = GraphBuilder.CreateSRV(Buffer);
    Parameters->DataCount = DataCount;
}
```

### ByteAddress Buffer

```cpp
// Raw 버퍼 (바이트 주소 버퍼)
BEGIN_SHADER_PARAMETER_STRUCT(FParameters, )
    SHADER_PARAMETER_RDG_BUFFER_SRV(ByteAddressBuffer, RawBuffer)
    SHADER_PARAMETER_RDG_BUFFER_UAV(RWByteAddressBuffer, RWRawBuffer)
END_SHADER_PARAMETER_STRUCT()

// HLSL에서 사용
ByteAddressBuffer RawBuffer;
RWByteAddressBuffer RWRawBuffer;

void MainCS(uint ThreadId : SV_DispatchThreadID)
{
    // 읽기 (4바이트 단위)
    uint Value = RawBuffer.Load(ThreadId * 4);

    // 쓰기
    RWRawBuffer.Store(ThreadId * 4, Value * 2);

    // 원자적 연산
    uint Original;
    RWRawBuffer.InterlockedAdd(0, 1, Original);
}
```

---

## Indirect Arguments

### Indirect Draw/Dispatch

```cpp
// Indirect Arguments 버퍼
BEGIN_SHADER_PARAMETER_STRUCT(FParameters, )
    RDG_BUFFER_ACCESS(IndirectArgsBuffer, ERHIAccess::IndirectArgs)
END_SHADER_PARAMETER_STRUCT()

// Indirect Draw 구조
struct FDrawIndexedIndirectArgs
{
    uint32 IndexCountPerInstance;
    uint32 InstanceCount;
    uint32 StartIndexLocation;
    int32 BaseVertexLocation;
    uint32 StartInstanceLocation;
};

// 컴퓨트 셰이더에서 Indirect Args 설정
[numthreads(1, 1, 1)]
void PrepareIndirectArgsCS(uint ThreadId : SV_DispatchThreadID)
{
    // 가시 오브젝트 수에 따라 동적으로 설정
    RWIndirectArgs.Store4(0, uint4(IndexCount, VisibleCount, 0, 0));
}

// Indirect Draw 실행
void ExecuteIndirectDraw(FRHICommandList& RHICmdList)
{
    RHICmdList.DrawIndexedPrimitiveIndirect(
        IndexBuffer,
        IndirectArgsBuffer,
        0);  // Args 오프셋
}
```

---

## Push Constants (Vulkan)

### 빠른 상수 업데이트

```cpp
// Push Constants - Uniform Buffer보다 빠름
// 작은 크기 (128바이트 권장)

// 파라미터 구조체
struct FPushConstants
{
    FMatrix44f Transform;
    FVector4f Color;
};  // 80바이트

// HLSL
[[vk::push_constant]]
ConstantBuffer<FPushConstants> PushConstants;

// C++에서 설정
void SetPushConstants(FRHICommandList& RHICmdList, const FPushConstants& Data)
{
    RHICmdList.SetShaderParameters(
        PixelShader,
        &Data,
        sizeof(Data),
        0);  // 오프셋
}
```

---

## 바인딩 최적화

### 루트 시그니처 최적화

```cpp
// 자주 변경되는 파라미터 → 루트 상수
// 가끔 변경되는 파라미터 → Uniform Buffer
// 거의 변경되지 않는 파라미터 → 글로벌 Uniform Buffer

// 바인딩 빈도별 분류
BEGIN_SHADER_PARAMETER_STRUCT(FPerFrameParameters, )
    SHADER_PARAMETER(float, Time)
    SHADER_PARAMETER(float, DeltaTime)
END_SHADER_PARAMETER_STRUCT()

BEGIN_SHADER_PARAMETER_STRUCT(FPerObjectParameters, )
    SHADER_PARAMETER(FMatrix44f, LocalToWorld)
    SHADER_PARAMETER(uint32, ObjectId)
END_SHADER_PARAMETER_STRUCT()

BEGIN_SHADER_PARAMETER_STRUCT(FPerMaterialParameters, )
    SHADER_PARAMETER_RDG_TEXTURE(Texture2D, DiffuseMap)
    SHADER_PARAMETER(FVector4f, BaseColor)
END_SHADER_PARAMETER_STRUCT()
```

### 바인딩 캐싱

```cpp
// 중복 바인딩 방지
class FShaderBindingCache
{
public:
    void SetTexture(int32 Slot, FRHITexture* Texture)
    {
        if (BoundTextures[Slot] != Texture)
        {
            BoundTextures[Slot] = Texture;
            RHICmdList.SetShaderTexture(ShaderRHI, Slot, Texture);
        }
    }

    void SetUniformBuffer(int32 Slot, FRHIUniformBuffer* Buffer)
    {
        if (BoundUniformBuffers[Slot] != Buffer)
        {
            BoundUniformBuffers[Slot] = Buffer;
            RHICmdList.SetShaderUniformBuffer(ShaderRHI, Slot, Buffer);
        }
    }

private:
    TArray<FRHITexture*> BoundTextures;
    TArray<FRHIUniformBuffer*> BoundUniformBuffers;
};
```

---

## 요약

| 타입 | 용도 | 크기 제한 | 업데이트 비용 |
|------|------|----------|--------------|
| Constant Buffer | 상수 데이터 | 16KB | 중간 |
| Push Constants | 빠른 상수 | 128B | 낮음 |
| SRV | 읽기 전용 리소스 | 없음 | 낮음 |
| UAV | 읽기/쓰기 리소스 | 없음 | 낮음 |
| Sampler | 샘플링 상태 | - | 매우 낮음 |

효율적인 파라미터 바인딩은 렌더링 성능의 핵심입니다.
