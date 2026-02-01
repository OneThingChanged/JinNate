# 셰이더 개발

UE에서 커스텀 셰이더를 작성하고 통합하는 방법을 다룹니다.

---

## 개요

UE 셰이더 시스템은 HLSL 기반의 USF(Unreal Shader File) 형식을 사용하며, C++ 바인딩을 통해 엔진과 통합됩니다.

```
┌─────────────────────────────────────────────────────────────────┐
│                    셰이더 개발 워크플로우                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────┐      ┌─────────────┐      ┌─────────────┐     │
│  │   USF/USH   │─────▶│  Shader     │─────▶│  SPIRV/     │     │
│  │   (HLSL)    │      │  Compiler   │      │  DXIL/Metal │     │
│  └─────────────┘      └─────────────┘      └──────┬──────┘     │
│                                                    │            │
│  ┌─────────────┐      ┌─────────────┐             │            │
│  │   C++       │─────▶│  Shader     │◀────────────┘            │
│  │   Binding   │      │  Permutation│                          │
│  └─────────────┘      └─────────────┘                          │
│                              │                                  │
│                              ▼                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                   Shader Library                         │   │
│  │  (DDC 캐시 → 런타임 로드)                               │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## USF 파일 구조

### 파일 확장자

```
.usf  - Unreal Shader File (컴파일 대상)
.ush  - Unreal Shader Header (include용)
```

### 기본 템플릿

```hlsl
// MyShader.usf

// 엔진 공통 헤더
#include "/Engine/Private/Common.ush"

// 로컬 헤더 (선택)
#include "MyCommon.ush"

// 파라미터 선언 (C++ BEGIN_SHADER_PARAMETER_STRUCT와 매칭)
Texture2D InputTexture;
SamplerState InputSampler;
RWTexture2D<float4> OutputTexture;
float4 CustomParams;
int2 TextureSize;

// 메인 함수
#if COMPUTESHADER

[numthreads(8, 8, 1)]
void MainCS(uint3 DispatchThreadId : SV_DispatchThreadID)
{
    // Compute Shader 로직
}

#elif PIXELSHADER

void MainPS(
    float4 SvPosition : SV_POSITION,
    float2 UV : TEXCOORD0,
    out float4 OutColor : SV_Target0)
{
    // Pixel Shader 로직
}

#endif
```

---

## 셰이더 타입

### Compute Shader

```hlsl
// ComputeShader.usf

#include "/Engine/Private/Common.ush"

Texture2D<float4> InputTexture;
RWTexture2D<float4> OutputTexture;
float4 Params;
uint2 TextureSize;

[numthreads(THREADGROUP_SIZE_X, THREADGROUP_SIZE_Y, 1)]
void MainCS(
    uint3 GroupId : SV_GroupID,
    uint3 GroupThreadId : SV_GroupThreadID,
    uint3 DispatchThreadId : SV_DispatchThreadID)
{
    // 범위 체크
    if (any(DispatchThreadId.xy >= TextureSize))
        return;

    // 입력 읽기
    float4 InputColor = InputTexture[DispatchThreadId.xy];

    // 처리
    float4 OutputColor = InputColor * Params;

    // 출력 쓰기
    OutputTexture[DispatchThreadId.xy] = OutputColor;
}
```

### Vertex + Pixel Shader

```hlsl
// FullscreenShader.usf

#include "/Engine/Private/Common.ush"
#include "/Engine/Private/ScreenPass.ush"

Texture2D SceneColorTexture;
SamplerState SceneSampler;
float EffectStrength;

// 버텍스 셰이더 (풀스크린)
void MainVS(
    in float4 InPosition : ATTRIBUTE0,
    in float2 InTexCoord : ATTRIBUTE1,
    out float4 OutPosition : SV_POSITION,
    out float2 OutUV : TEXCOORD0)
{
    DrawRectangle(InPosition, InTexCoord, OutPosition, OutUV);
}

// 픽셀 셰이더
void MainPS(
    float4 SvPosition : SV_POSITION,
    float2 UV : TEXCOORD0,
    out float4 OutColor : SV_Target0)
{
    float4 SceneColor = Texture2DSample(SceneColorTexture, SceneSampler, UV);

    // 효과 적용 (예: Sepia 톤)
    float Luminance = dot(SceneColor.rgb, float3(0.299, 0.587, 0.114));
    float3 Sepia = float3(
        Luminance * 1.2,
        Luminance * 1.0,
        Luminance * 0.8
    );

    OutColor.rgb = lerp(SceneColor.rgb, Sepia, EffectStrength);
    OutColor.a = SceneColor.a;
}
```

### Geometry Shader

```hlsl
// GeometryShader.usf

struct FVertexOutput
{
    float4 Position : SV_POSITION;
    float2 UV : TEXCOORD0;
};

// GS 입력당 최대 출력 버텍스 수
[maxvertexcount(3)]
void MainGS(
    triangle FVertexOutput Input[3],
    inout TriangleStream<FVertexOutput> OutputStream)
{
    // 삼각형 복제 또는 수정
    for (int i = 0; i < 3; ++i)
    {
        FVertexOutput Output = Input[i];
        // 필요한 변환
        OutputStream.Append(Output);
    }
}
```

---

## C++ 바인딩

### Global Shader

```cpp
// MyGlobalShader.h
#pragma once

#include "GlobalShader.h"
#include "ShaderParameterStruct.h"
#include "RenderGraphUtils.h"

class FMyGlobalShaderCS : public FGlobalShader
{
public:
    DECLARE_GLOBAL_SHADER(FMyGlobalShaderCS);
    SHADER_USE_PARAMETER_STRUCT(FMyGlobalShaderCS, FGlobalShader);

    // 셰이더 파라미터 구조체 (USF와 매칭 필수)
    BEGIN_SHADER_PARAMETER_STRUCT(FParameters, )
        SHADER_PARAMETER_RDG_TEXTURE_SRV(Texture2D, InputTexture)
        SHADER_PARAMETER_RDG_TEXTURE_UAV(RWTexture2D<float4>, OutputTexture)
        SHADER_PARAMETER_SAMPLER(SamplerState, InputSampler)
        SHADER_PARAMETER(FVector4f, Params)
        SHADER_PARAMETER(FUintVector2, TextureSize)
    END_SHADER_PARAMETER_STRUCT()

    // 컴파일 조건
    static bool ShouldCompilePermutation(
        const FGlobalShaderPermutationParameters& Parameters)
    {
        return IsFeatureLevelSupported(Parameters.Platform, ERHIFeatureLevel::SM5);
    }

    // 컴파일러 환경 수정
    static void ModifyCompilationEnvironment(
        const FGlobalShaderPermutationParameters& Parameters,
        FShaderCompilerEnvironment& OutEnvironment)
    {
        FGlobalShader::ModifyCompilationEnvironment(Parameters, OutEnvironment);
        OutEnvironment.SetDefine(TEXT("THREADGROUP_SIZE_X"), 8);
        OutEnvironment.SetDefine(TEXT("THREADGROUP_SIZE_Y"), 8);
    }
};

// 구현 등록
IMPLEMENT_GLOBAL_SHADER(FMyGlobalShaderCS,
    "/Plugin/MyPlugin/Private/MyComputeShader.usf",
    "MainCS",
    SF_Compute);
```

### 파라미터 타입

```cpp
// 스칼라
SHADER_PARAMETER(float, MyFloat)
SHADER_PARAMETER(int32, MyInt)
SHADER_PARAMETER(uint32, MyUint)
SHADER_PARAMETER(FVector2f, MyVector2)
SHADER_PARAMETER(FVector3f, MyVector3)
SHADER_PARAMETER(FVector4f, MyVector4)
SHADER_PARAMETER(FMatrix44f, MyMatrix)

// 텍스처 (RDG)
SHADER_PARAMETER_RDG_TEXTURE(Texture2D, MyTexture)
SHADER_PARAMETER_RDG_TEXTURE_SRV(Texture2D, MyTextureSRV)
SHADER_PARAMETER_RDG_TEXTURE_UAV(RWTexture2D<float4>, MyTextureUAV)

// 버퍼 (RDG)
SHADER_PARAMETER_RDG_BUFFER_SRV(StructuredBuffer<FMyStruct>, MyBufferSRV)
SHADER_PARAMETER_RDG_BUFFER_UAV(RWStructuredBuffer<FMyStruct>, MyBufferUAV)

// 샘플러
SHADER_PARAMETER_SAMPLER(SamplerState, MySampler)

// 배열
SHADER_PARAMETER_ARRAY(FVector4f, MyArray, [16])

// Uniform Buffer
SHADER_PARAMETER_RDG_UNIFORM_BUFFER(FMyUniformBuffer, MyUB)

// 렌더 타겟
RENDER_TARGET_BINDING_SLOTS()
```

---

## Permutation (변형)

### Permutation 정의

```cpp
// 불리언 permutation
class FMyFeatureDim : SHADER_PERMUTATION_BOOL("MY_FEATURE_ENABLED");

// 정수 범위 permutation
class FQualityDim : SHADER_PERMUTATION_RANGE_INT("QUALITY_LEVEL", 0, 3);

// 스파스 정수 permutation
class FModeDim : SHADER_PERMUTATION_SPARSE_INT("MODE", 1, 2, 4, 8);

// 열거형 permutation
enum class EMyMode : uint8 { ModeA, ModeB, ModeC };
class FMyModeDim : SHADER_PERMUTATION_ENUM_CLASS("MY_MODE", EMyMode);
```

### Permutation 사용

```cpp
class FMyShaderCS : public FGlobalShader
{
public:
    // 여러 permutation 조합
    using FPermutationDomain = TShaderPermutationDomain<
        FMyFeatureDim,
        FQualityDim
    >;

    DECLARE_GLOBAL_SHADER(FMyShaderCS);
    SHADER_USE_PARAMETER_STRUCT(FMyShaderCS, FGlobalShader);

    // Permutation 조합 컴파일 여부
    static bool ShouldCompilePermutation(
        const FGlobalShaderPermutationParameters& Parameters)
    {
        FPermutationDomain PermutationVector(Parameters.PermutationId);

        // 특정 조합만 컴파일
        bool bFeatureEnabled = PermutationVector.Get<FMyFeatureDim>();
        int32 Quality = PermutationVector.Get<FQualityDim>();

        // 기능 비활성화 시 품질 0만 컴파일
        if (!bFeatureEnabled && Quality > 0)
            return false;

        return IsFeatureLevelSupported(Parameters.Platform, ERHIFeatureLevel::SM5);
    }
};

// 사용 시
void DispatchShader(...)
{
    FMyShaderCS::FPermutationDomain PermutationVector;
    PermutationVector.Set<FMyFeatureDim>(bFeatureEnabled);
    PermutationVector.Set<FQualityDim>(QualityLevel);

    TShaderMapRef<FMyShaderCS> ComputeShader(ShaderMap, PermutationVector);
    // ...
}
```

---

## 유틸리티 함수

### 엔진 제공 함수 (Common.ush)

```hlsl
// 좌표 변환
float4 WorldPosition = mul(float4(LocalPos, 1), LocalToWorld);
float4 ClipPosition = mul(WorldPosition, ViewProjection);
float3 ViewDirection = normalize(CameraPos - WorldPosition.xyz);

// 샘플링
float4 Color = Texture2DSample(Tex, Sampler, UV);
float4 ColorLevel = Texture2DSampleLevel(Tex, Sampler, UV, MipLevel);
float4 ColorBias = Texture2DSampleBias(Tex, Sampler, UV, Bias);
float4 ColorGrad = Texture2DSampleGrad(Tex, Sampler, UV, DDX, DDY);

// 깊이
float LinearDepth = ConvertFromDeviceZ(HardwareDepth);
float3 WorldPos = ReconstructWorldPositionFromDepth(UV, Depth);

// 노멀
float3 WorldNormal = TransformTangentToWorld(TangentNormal, TangentBasis);
float3 EncodedNormal = EncodeNormal(Normal);
float3 DecodedNormal = DecodeNormal(EncodedNormal);

// 색상
float Luminance = Luminance(Color.rgb);
float3 LinearColor = sRGBToLinear(sRGBColor);
float3 sRGBColor = LinearTosRGB(LinearColor);
```

### 수학 함수

```hlsl
// 보간
float Value = lerp(A, B, T);
float Value = smoothstep(Edge0, Edge1, X);

// 벡터
float Length = length(V);
float3 Normalized = normalize(V);
float Dot = dot(A, B);
float3 Cross = cross(A, B);
float3 Reflected = reflect(Incident, Normal);
float3 Refracted = refract(Incident, Normal, Eta);

// 행렬
float4x4 InverseMatrix = Inverse(Matrix);
float4x4 TransposedMatrix = transpose(Matrix);

// 클램프
float Clamped = clamp(Value, Min, Max);
float Saturated = saturate(Value);  // clamp(0, 1)
```

---

## 디버깅

### 컴파일 에러 확인

```cpp
// 에디터에서 Output Log 확인
// 셰이더 컴파일 오류 시 상세 정보 출력

// 셰이더 리컴파일
RecompileShaders changed
RecompileShaders all
RecompileShaders global
```

### 디버그 출력

```hlsl
// USF에서 디버그 출력 (개발용)
#if DEBUG_OUTPUT
    OutColor = float4(DebugValue, 0, 0, 1);
    return;
#endif

// 색상으로 값 시각화
OutColor.rgb = frac(SomeValue) * float3(1, 0.5, 0.25);
```

### RenderDoc 연동

```cpp
// 디버그 심볼 유지
r.Shaders.KeepDebugInfo 1
r.Shaders.Optimize 0  // 최적화 비활성화 (디버그용)

// RenderDoc에서 셰이더 스텝 실행 가능
```

### 셰이더 프린트

```cpp
// ShaderPrint 시스템 (UE5)
#include "/Engine/Private/ShaderPrint.ush"

void MainCS(...)
{
    // 화면에 값 출력
    FShaderPrintContext Context = InitShaderPrintContext(true, ...);
    Print(Context, TEXT("Value: "));
    Print(Context, MyValue);
}
```

---

## 성능 최적화

### ALU 최적화

```hlsl
// MAD 연산 활용
// BAD
float Result = A * B + C;

// GOOD (명시적 MAD)
float Result = mad(A, B, C);

// 역수 사용
// BAD
float Result = A / B;

// GOOD (나눗셈 비용이 높은 경우)
float InvB = rcp(B);
float Result = A * InvB;
```

### 분기 최적화

```hlsl
// 동적 분기 피하기
// BAD
if (Condition)
    Result = ExpensiveA();
else
    Result = ExpensiveB();

// GOOD (값이 작으면)
Result = lerp(ExpensiveB(), ExpensiveA(), Condition);

// GOOD (컴파일 타임 분기)
#if MY_FEATURE
    Result = FeatureA();
#else
    Result = FeatureB();
#endif
```

### 메모리 접근 최적화

```hlsl
// 코얼레싱 접근 패턴
// GOOD: 연속 스레드가 연속 메모리 접근
uint Index = GroupThreadId.x + GroupId.x * 64;

// BAD: 스트라이드 접근
uint Index = GroupThreadId.x * LargeStride;
```

---

## 요약

| 항목 | 설명 |
|------|------|
| USF/USH | HLSL 기반 셰이더 파일 |
| C++ 바인딩 | DECLARE/IMPLEMENT_GLOBAL_SHADER |
| 파라미터 | SHADER_PARAMETER_* 매크로 |
| Permutation | 컴파일 타임 변형 |
| 디버깅 | ShaderPrint, RenderDoc |

---

## 참고 자료

- [Shader Development](https://docs.unrealengine.com/shader-development/)
- [HLSL Reference](https://docs.microsoft.com/en-us/windows/win32/direct3dhlsl/)
- [Shader Permutations](https://docs.unrealengine.com/shader-permutations/)
