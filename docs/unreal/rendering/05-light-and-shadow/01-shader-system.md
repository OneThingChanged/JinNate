# 셰이더 시스템 아키텍처

> Chapter 05-1: UE 셰이더 파일 구조와 모듈 계층

---

## 목차

1. [셰이더 파일 개요](#1-셰이더-파일-개요)
2. [3-Tier 모듈 구조](#2-3-tier-모듈-구조)
3. [Tier 1: 기초 모듈](#3-tier-1-기초-모듈)
4. [Tier 2: 중간 모듈](#4-tier-2-중간-모듈)
5. [Tier 3: 구현 모듈](#5-tier-3-구현-모듈)
6. [모듈 의존성 다이어그램](#6-모듈-의존성-다이어그램)

---

## 1. 셰이더 파일 개요 {#1-셰이더-파일-개요}

### 파일 위치 및 수량

UE의 셰이더 파일은 `Engine/Shaders/` 디렉토리에 위치하며, **600개 이상**의 파일로 구성됩니다.

```
Engine/Shaders/
├── Private/           # 내부 구현 셰이더
│   ├── BasePassPixelShader.usf
│   ├── DeferredLightPixelShaders.usf
│   ├── ShadowProjectionPixelShader.usf
│   └── ...
├── Public/            # 공개 헤더
│   └── Platform.ush
└── Shared/            # 공유 유틸리티
```

### 파일 확장자 규칙

| 확장자 | 용도 | Include 가능 |
|--------|------|--------------|
| `.ush` | 헤더 파일 (선언, 유틸리티) | O |
| `.usf` | 구현 파일 (최종 셰이더) | X |

> **중요**: `.usf` 파일은 다른 파일에서 include할 수 없으며, 최종 컴파일 단위로만 사용됩니다.

---

## 2. 3-Tier 모듈 구조 {#2-3-tier-모듈-구조}

UE 셰이더는 3단계 계층 구조로 조직화되어 있습니다:

```
┌─────────────────────────────────────────────────────────────────┐
│                        Tier 3: 구현 모듈                         │
│  BasePassVertexShader.usf, DeferredLightPixelShaders.usf, ...  │
├─────────────────────────────────────────────────────────────────┤
│                        Tier 2: 중간 모듈                         │
│  ShadingModels.ush, DeferredLightingCommon.ush, ...            │
├─────────────────────────────────────────────────────────────────┤
│                        Tier 1: 기초 모듈                         │
│  Platform.ush, Common.ush, BRDF.ush, Definitions.ush, ...      │
└─────────────────────────────────────────────────────────────────┘
```

| Tier | 역할 | 특징 |
|------|------|------|
| **Tier 1** | 기초 함수, 타입, 매크로 | 다른 모듈에 의존하지 않음 |
| **Tier 2** | 라이팅/셰이딩 로직 | Tier 1 참조, Tier 3의 기반 |
| **Tier 3** | 최종 셰이더 구현 | `.usf` 파일, 컴파일 대상 |

---

## 3. Tier 1: 기초 모듈 {#3-tier-1-기초-모듈}

### 3.1 Platform.ush

그래픽 API와 Feature Level 관련 매크로를 정의합니다.

```hlsl
// Platform.ush - API 및 Feature Level 매크로

// Feature Level 정의
#define FEATURE_LEVEL_ES2_REMOVED  1
#define FEATURE_LEVEL_ES3_1        2
#define FEATURE_LEVEL_SM4_REMOVED  3
#define FEATURE_LEVEL_SM5          4
#define FEATURE_LEVEL_SM6          5

// 컴파일러 식별
#if defined(__INTELLISENSE__)
    #define INTELLISENSE_SHADER 1
#endif

// 플랫폼별 정밀도
#if COMPILER_GLSL_ES3_1
    #define half    mediump float
    #define half2   mediump float2
    #define half3   mediump float3
    #define half4   mediump float4
#else
    #define half    float
    #define half2   float2
    #define half3   float3
    #define half4   float4
#endif
```

### 3.2 Common.ush

수백 개의 유틸리티 함수를 제공하는 핵심 모듈입니다.

```hlsl
// Common.ush - 핵심 유틸리티 함수

// 수학 함수
float Square(float x) { return x * x; }
float Pow2(float x) { return x * x; }
float Pow4(float x) { float x2 = x * x; return x2 * x2; }
float Pow5(float x) { float x2 = x * x; return x2 * x2 * x; }

// 색 공간 변환
float3 LinearToSrgb(float3 lin)
{
    return select(lin < 0.00313067, lin * 12.92,
                  pow(lin, 1.0/2.4) * 1.055 - 0.055);
}

float3 SrgbToLinear(float3 srgb)
{
    return select(srgb < 0.04045, srgb / 12.92,
                  pow((srgb + 0.055) / 1.055, 2.4));
}

// 텍스처 샘플링 유틸리티
float4 Texture2DSample(Texture2D Tex, SamplerState Sampler, float2 UV)
{
    return Tex.Sample(Sampler, UV);
}

// 좌표 변환
float3 TransformWorldToView(float3 WorldPos)
{
    return mul(float4(WorldPos, 1), View.WorldToView).xyz;
}

float4 TransformWorldToClip(float3 WorldPos)
{
    return mul(float4(WorldPos, 1), View.WorldToClip);
}

// 뎁스 변환
float ConvertFromDeviceZ(float DeviceZ)
{
    return DeviceZ * View.InvDeviceZToWorldZTransform[0]
         + View.InvDeviceZToWorldZTransform[1]
         + 1.0f / (DeviceZ * View.InvDeviceZToWorldZTransform[2]
         - View.InvDeviceZToWorldZTransform[3]);
}
```

### 3.3 Definitions.ush

재정의를 방지하는 사전 정의 매크로를 제공합니다.

```hlsl
// Definitions.ush - 기본 매크로 정의

#ifndef MATERIALBLENDING_SOLID
    #define MATERIALBLENDING_SOLID 0
#endif

#ifndef MATERIALBLENDING_MASKED
    #define MATERIALBLENDING_MASKED 0
#endif

#ifndef MATERIALBLENDING_TRANSLUCENT
    #define MATERIALBLENDING_TRANSLUCENT 0
#endif

#ifndef MATERIAL_SHADINGMODEL_DEFAULT_LIT
    #define MATERIAL_SHADINGMODEL_DEFAULT_LIT 0
#endif

#ifndef MATERIAL_SHADINGMODEL_SUBSURFACE
    #define MATERIAL_SHADINGMODEL_SUBSURFACE 0
#endif

// 머티리얼 속성 기본값
#ifndef NUM_MATERIAL_TEXCOORDS
    #define NUM_MATERIAL_TEXCOORDS 1
#endif

#ifndef NUM_CUSTOMIZED_UVS
    #define NUM_CUSTOMIZED_UVS 0
#endif
```

### 3.4 ShadingCommon.ush

셰이딩 모델 정의와 반사율 계산 함수를 제공합니다.

```hlsl
// ShadingCommon.ush - 셰이딩 모델 정의

// 12가지 셰이딩 모델 ID
#define SHADINGMODELID_UNLIT                0
#define SHADINGMODELID_DEFAULT_LIT          1
#define SHADINGMODELID_SUBSURFACE           2
#define SHADINGMODELID_PREINTEGRATED_SKIN   3
#define SHADINGMODELID_CLEAR_COAT           4
#define SHADINGMODELID_SUBSURFACE_PROFILE   5
#define SHADINGMODELID_TWOSIDED_FOLIAGE     6
#define SHADINGMODELID_HAIR                 7
#define SHADINGMODELID_CLOTH                8
#define SHADINGMODELID_EYE                  9
#define SHADINGMODELID_SINGLELAYERWATER     10
#define SHADINGMODELID_THIN_TRANSLUCENT     11
#define SHADINGMODELID_NUM                  12

// F0 계산 (비금속 기준 반사율)
float3 ComputeF0(float Specular, float3 BaseColor, float Metallic)
{
    // 비금속: 0.08 * Specular (기본 0.04)
    // 금속: BaseColor
    return lerp(0.08 * Specular.xxx, BaseColor, Metallic);
}

// IOR에서 F0 계산
float F0FromIOR(float IOR)
{
    float F0Sqrt = (IOR - 1) / (IOR + 1);
    return F0Sqrt * F0Sqrt;
}

// F0에서 IOR 역산
float IORFromF0(float F0)
{
    float F0Sqrt = sqrt(F0);
    return (1 + F0Sqrt) / (1 - F0Sqrt);
}
```

### 3.5 BRDF.ush

Cook-Torrance BRDF의 모든 구성 요소를 구현합니다.

```hlsl
// BRDF.ush - Physically Based BRDF 함수

// BxDF 컨텍스트 구조체
struct BxDFContext
{
    float NoV;      // Normal · View
    float NoL;      // Normal · Light
    float VoL;      // View · Light
    float NoH;      // Normal · Half
    float VoH;      // View · Half
};

void Init(inout BxDFContext Context, half3 N, half3 V, half3 L)
{
    Context.NoL = dot(N, L);
    Context.NoV = dot(N, V);
    Context.VoL = dot(V, L);
    float InvLenH = rsqrt(2 + 2 * Context.VoL);
    Context.NoH = saturate((Context.NoL + Context.NoV) * InvLenH);
    Context.VoH = saturate(InvLenH + InvLenH * Context.VoL);
}

//=============================================================================
// Distribution Functions (D)
//=============================================================================

// GGX / Trowbridge-Reitz
float D_GGX(float a2, float NoH)
{
    float d = (NoH * a2 - NoH) * NoH + 1;
    return a2 / (PI * d * d);
}

// Beckmann
float D_Beckmann(float a2, float NoH)
{
    float NoH2 = NoH * NoH;
    return exp((NoH2 - 1) / (a2 * NoH2)) / (PI * a2 * NoH2 * NoH2);
}

// Anisotropic GGX
float D_GGXaniso(float ax, float ay, float NoH, float3 H, float3 X, float3 Y)
{
    float XoH = dot(X, H);
    float YoH = dot(Y, H);
    float d = XoH*XoH / (ax*ax) + YoH*YoH / (ay*ay) + NoH*NoH;
    return 1 / (PI * ax * ay * d * d);
}

//=============================================================================
// Visibility Functions (V)
//=============================================================================

// Smith Joint
float Vis_SmithJoint(float a2, float NoV, float NoL)
{
    float Vis_SmithV = NoL * sqrt(NoV * (NoV - NoV * a2) + a2);
    float Vis_SmithL = NoV * sqrt(NoL * (NoL - NoL * a2) + a2);
    return 0.5 * rcp(Vis_SmithV + Vis_SmithL);
}

// Smith Joint Approximation (더 빠름)
float Vis_SmithJointApprox(float a2, float NoV, float NoL)
{
    float a = sqrt(a2);
    float Vis_SmithV = NoL * (NoV * (1 - a) + a);
    float Vis_SmithL = NoV * (NoL * (1 - a) + a);
    return 0.5 * rcp(Vis_SmithV + Vis_SmithL);
}

//=============================================================================
// Fresnel Functions (F)
//=============================================================================

// Schlick 근사
float3 F_Schlick(float3 F0, float VoH)
{
    float Fc = Pow5(1 - VoH);
    return F0 + (1 - F0) * Fc;
}

// Roughness를 고려한 Schlick
float3 F_SchlickRoughness(float3 F0, float VoH, float Roughness)
{
    float Fc = Pow5(1 - VoH);
    return F0 + (max(1 - Roughness, F0) - F0) * Fc;
}

//=============================================================================
// Diffuse Models
//=============================================================================

// Lambert
float3 Diffuse_Lambert(float3 DiffuseColor)
{
    return DiffuseColor / PI;
}

// Burley (Disney)
float3 Diffuse_Burley(float3 DiffuseColor, float Roughness, float NoV, float NoL, float VoH)
{
    float FD90 = 0.5 + 2 * VoH * VoH * Roughness;
    float FdV = 1 + (FD90 - 1) * Pow5(1 - NoV);
    float FdL = 1 + (FD90 - 1) * Pow5(1 - NoL);
    return DiffuseColor * ((1 / PI) * FdV * FdL);
}

// Oren-Nayar (거친 표면)
float3 Diffuse_OrenNayar(float3 DiffuseColor, float Roughness, float NoV, float NoL, float VoH)
{
    float a = Roughness * Roughness;
    float s = a;
    float s2 = s * s;
    float VoL = 2 * VoH * VoH - 1;
    float Cosri = VoL - NoV * NoL;
    float C1 = 1 - 0.5 * s2 / (s2 + 0.33);
    float C2 = 0.45 * s2 / (s2 + 0.09) * Cosri * (Cosri >= 0 ? rcp(max(NoL, NoV)) : 1);
    return DiffuseColor / PI * (C1 + C2) * (1 + Roughness * 0.5);
}

//=============================================================================
// Specular BRDF 결합
//=============================================================================

float3 SpecularGGX(float Roughness, float3 F0, BxDFContext Context)
{
    float a2 = Pow4(Roughness);
    float D = D_GGX(a2, Context.NoH);
    float Vis = Vis_SmithJointApprox(a2, Context.NoV, Context.NoL);
    float3 F = F_Schlick(F0, Context.VoH);
    return D * Vis * F;
}
```

### 3.6 DeferredShadingCommon.ush

G-Buffer 인코딩/디코딩 함수를 제공합니다.

```hlsl
// DeferredShadingCommon.ush - G-Buffer 처리

struct FGBufferData
{
    float3 WorldNormal;
    float3 WorldTangent;
    float3 BaseColor;
    float  Metallic;
    float  Specular;
    float  Roughness;
    float  Anisotropy;
    uint   ShadingModelID;
    uint   SelectiveOutputMask;
    float  PerObjectGBufferData;
    float  CustomData;
    float  IndirectIrradiance;
    float4 PrecomputedShadowFactors;
    float3 DiffuseColor;
    float3 SpecularColor;
    float  Depth;
    float4 Velocity;
    float3 StoredBaseColor;
    float  StoredSpecular;
    float  StoredMetallic;
};

// 벡터 압축 (Octahedron Encoding)
float2 UnitVectorToOctahedron(float3 N)
{
    N.xy /= dot(1, abs(N));
    if (N.z <= 0)
    {
        N.xy = (1 - abs(N.yx)) * select(N.xy >= 0, float2(1,1), float2(-1,-1));
    }
    return N.xy;
}

float3 OctahedronToUnitVector(float2 Oct)
{
    float3 N = float3(Oct, 1 - dot(1, abs(Oct)));
    if (N.z < 0)
    {
        N.xy = (1 - abs(N.yx)) * select(N.xy >= 0, float2(1,1), float2(-1,-1));
    }
    return normalize(N);
}

// G-Buffer 인코딩
void EncodeGBuffer(
    FGBufferData GBuffer,
    out float4 OutGBufferA,
    out float4 OutGBufferB,
    out float4 OutGBufferC,
    out float4 OutGBufferD)
{
    OutGBufferA.xy = UnitVectorToOctahedron(GBuffer.WorldNormal) * 0.5 + 0.5;
    OutGBufferA.z = GBuffer.PerObjectGBufferData;
    OutGBufferA.w = GBuffer.ShadingModelID / 255.0;

    OutGBufferB.rgb = GBuffer.BaseColor;
    OutGBufferB.a = GBuffer.Metallic;

    OutGBufferC.r = GBuffer.Specular;
    OutGBufferC.g = GBuffer.Roughness;
    OutGBufferC.b = 0; // Reserved
    OutGBufferC.a = GBuffer.SelectiveOutputMask / 255.0;

    OutGBufferD = float4(GBuffer.CustomData, 0, 0, 0);
}

// G-Buffer 디코딩
FGBufferData DecodeGBuffer(
    float4 InGBufferA,
    float4 InGBufferB,
    float4 InGBufferC,
    float4 InGBufferD)
{
    FGBufferData GBuffer;

    GBuffer.WorldNormal = OctahedronToUnitVector(InGBufferA.xy * 2 - 1);
    GBuffer.PerObjectGBufferData = InGBufferA.z;
    GBuffer.ShadingModelID = uint(InGBufferA.w * 255.0 + 0.5);

    GBuffer.BaseColor = InGBufferB.rgb;
    GBuffer.Metallic = InGBufferB.a;

    GBuffer.Specular = InGBufferC.r;
    GBuffer.Roughness = InGBufferC.g;
    GBuffer.SelectiveOutputMask = uint(InGBufferC.a * 255.0 + 0.5);

    GBuffer.CustomData = InGBufferD.r;

    // 파생 값 계산
    GBuffer.DiffuseColor = GBuffer.BaseColor * (1 - GBuffer.Metallic);
    GBuffer.SpecularColor = ComputeF0(GBuffer.Specular, GBuffer.BaseColor, GBuffer.Metallic);

    return GBuffer;
}
```

---

## 4. Tier 2: 중간 모듈 {#4-tier-2-중간-모듈}

### 4.1 ShadingModels.ush

12가지 셰이딩 모델의 라이팅 계산을 구현합니다.

```hlsl
// ShadingModels.ush - 셰이딩 모델별 라이팅

FDirectLighting DefaultLitBxDF(
    FGBufferData GBuffer,
    half3 N, half3 V, half3 L,
    float Falloff, float NoL, FAreaLight AreaLight)
{
    BxDFContext Context;
    Init(Context, N, V, L);

    FDirectLighting Lighting;
    Lighting.Diffuse = AreaLight.FalloffColor * Falloff *
                       Diffuse_Lambert(GBuffer.DiffuseColor);
    Lighting.Specular = AreaLight.FalloffColor * Falloff *
                        SpecularGGX(GBuffer.Roughness, GBuffer.SpecularColor, Context);
    Lighting.Transmission = 0;

    return Lighting;
}

FDirectLighting SubsurfaceBxDF(
    FGBufferData GBuffer,
    half3 N, half3 V, half3 L,
    float Falloff, float NoL, FAreaLight AreaLight)
{
    FDirectLighting Lighting = DefaultLitBxDF(GBuffer, N, V, L, Falloff, NoL, AreaLight);

    // Subsurface Scattering
    float3 SubsurfaceColor = ExtractSubsurfaceColor(GBuffer);
    float Wrap = 0.5;
    float WrapNoL = saturate((NoL + Wrap) / (1 + Wrap));
    Lighting.Transmission = AreaLight.FalloffColor * Falloff *
                           SubsurfaceColor * WrapNoL;

    return Lighting;
}

// 셰이딩 모델 디스패치
FDirectLighting IntegrateBxDF(
    FGBufferData GBuffer,
    half3 N, half3 V, half3 L,
    float Falloff, float NoL, FAreaLight AreaLight)
{
    switch (GBuffer.ShadingModelID)
    {
        case SHADINGMODELID_DEFAULT_LIT:
            return DefaultLitBxDF(GBuffer, N, V, L, Falloff, NoL, AreaLight);
        case SHADINGMODELID_SUBSURFACE:
            return SubsurfaceBxDF(GBuffer, N, V, L, Falloff, NoL, AreaLight);
        case SHADINGMODELID_CLEAR_COAT:
            return ClearCoatBxDF(GBuffer, N, V, L, Falloff, NoL, AreaLight);
        // ... 다른 셰이딩 모델들
        default:
            return DefaultLitBxDF(GBuffer, N, V, L, Falloff, NoL, AreaLight);
    }
}
```

### 4.2 DeferredLightingCommon.ush

디퍼드 라이팅의 공통 로직을 제공합니다.

```hlsl
// DeferredLightingCommon.ush

struct FDeferredLightData
{
    float3 Position;
    float  InvRadius;
    float3 Color;
    float  FalloffExponent;
    float3 Direction;
    float3 Tangent;
    float  SourceRadius;
    float  SourceLength;
    float  SoftSourceRadius;
    float  SpecularScale;
    float  ContactShadowLength;
    float2 SpotAngles;
    float  RectLightBarnCosAngle;
    float  RectLightBarnLength;
    bool   bRadialLight;
    bool   bSpotLight;
    bool   bRectLight;
    uint   ShadowMapChannelMask;
    bool   bShadowed;
};

// 라이트 감쇠 계산
float GetLocalLightAttenuation(
    float3 WorldPosition,
    FDeferredLightData LightData,
    out float3 ToLight,
    out float3 L)
{
    ToLight = LightData.Position - WorldPosition;
    float DistanceSqr = dot(ToLight, ToLight);
    L = ToLight * rsqrt(DistanceSqr);

    // Inverse Square Falloff with Radius
    float Attenuation = 1 / (DistanceSqr + 1);
    float LightRadiusMask = Square(saturate(1 - Square(DistanceSqr * Square(LightData.InvRadius))));
    Attenuation *= LightRadiusMask;

    // Spot Light Cone
    if (LightData.bSpotLight)
    {
        float CosAngle = dot(-L, LightData.Direction);
        float SpotMask = saturate((CosAngle - LightData.SpotAngles.x) * LightData.SpotAngles.y);
        Attenuation *= Square(SpotMask);
    }

    return Attenuation;
}
```

---

## 5. Tier 3: 구현 모듈 {#5-tier-3-구현-모듈}

### 5.1 BasePassPixelShader.usf

BasePass 픽셀 셰이더의 최종 구현입니다.

```hlsl
// BasePassPixelShader.usf
#include "Common.ush"
#include "BRDF.ush"
#include "ShadingModels.ush"
#include "DeferredShadingCommon.ush"
#include "BasePassCommon.ush"

void Main(
    FVertexFactoryInterpolantsVSToPS Interpolants,
    FBasePassInterpolantsVSToPS BasePassInterpolants,
    out float4 OutGBufferA : SV_Target0,
    out float4 OutGBufferB : SV_Target1,
    out float4 OutGBufferC : SV_Target2,
    out float4 OutGBufferD : SV_Target3,
    out float4 OutGBufferE : SV_Target4)
{
    // 머티리얼 평가
    FMaterialPixelParameters MaterialParameters = GetMaterialPixelParameters(...);
    FPixelMaterialInputs PixelMaterialInputs;
    CalcMaterialParameters(MaterialParameters, PixelMaterialInputs);

    // G-Buffer 데이터 구성
    FGBufferData GBuffer;
    GBuffer.WorldNormal = MaterialParameters.WorldNormal;
    GBuffer.BaseColor = GetMaterialBaseColor(PixelMaterialInputs);
    GBuffer.Metallic = GetMaterialMetallic(PixelMaterialInputs);
    GBuffer.Specular = GetMaterialSpecular(PixelMaterialInputs);
    GBuffer.Roughness = GetMaterialRoughness(PixelMaterialInputs);
    GBuffer.ShadingModelID = GetMaterialShadingModel();

    // G-Buffer 인코딩 및 출력
    EncodeGBuffer(GBuffer, OutGBufferA, OutGBufferB, OutGBufferC, OutGBufferD);
}
```

### 5.2 DeferredLightPixelShaders.usf

디퍼드 라이트 픽셀 셰이더입니다.

```hlsl
// DeferredLightPixelShaders.usf
#include "Common.ush"
#include "BRDF.ush"
#include "ShadingModels.ush"
#include "DeferredLightingCommon.ush"

float4 DeferredLightPixelMain(
    float4 SVPos : SV_POSITION,
    float4 ScreenUV : TEXCOORD0) : SV_Target0
{
    // G-Buffer 샘플링
    FGBufferData GBuffer = GetGBufferData(ScreenUV.xy);

    // 월드 위치 재구성
    float Depth = GetGBufferDepth(ScreenUV.xy);
    float3 WorldPosition = ReconstructWorldPosition(ScreenUV.xy, Depth);

    // 라이트 계산
    float3 ToLight;
    float3 L;
    float Attenuation = GetLocalLightAttenuation(WorldPosition, LightData, ToLight, L);

    // BRDF 평가
    float3 V = normalize(View.WorldCameraOrigin - WorldPosition);
    float3 N = GBuffer.WorldNormal;
    float NoL = saturate(dot(N, L));

    FAreaLight AreaLight;
    AreaLight.FalloffColor = LightData.Color * Attenuation;

    FDirectLighting Lighting = IntegrateBxDF(GBuffer, N, V, L, Attenuation, NoL, AreaLight);

    // 그림자 적용
    float Shadow = GetShadow(WorldPosition, LightData);

    return float4((Lighting.Diffuse + Lighting.Specular) * Shadow, 0);
}
```

---

## 6. 모듈 의존성 다이어그램 {#6-모듈-의존성-다이어그램}

```
┌─────────────────────────────────────────────────────────────────────┐
│                      셰이더 모듈 의존성 그래프                        │
└─────────────────────────────────────────────────────────────────────┘

                    ┌─────────────────────────────┐
                    │   BasePassPixelShader.usf   │  (Tier 3)
                    │   DeferredLightPixelShaders │
                    │   ShadowProjectionPS.usf    │
                    └──────────────┬──────────────┘
                                   │
                    ┌──────────────▼──────────────┐
                    │      ShadingModels.ush      │  (Tier 2)
                    │   DeferredLightingCommon    │
                    │   ShadowProjectionCommon    │
                    │      BasePassCommon         │
                    └──────────────┬──────────────┘
                                   │
        ┌──────────────────────────┼──────────────────────────┐
        │                          │                          │
        ▼                          ▼                          ▼
┌───────────────┐      ┌───────────────────┐      ┌───────────────┐
│   BRDF.ush    │      │ DeferredShading   │      │ ShadingCommon │  (Tier 1)
│               │      │   Common.ush      │      │    .ush       │
└───────┬───────┘      └─────────┬─────────┘      └───────┬───────┘
        │                        │                        │
        └────────────────────────┼────────────────────────┘
                                 │
                    ┌────────────▼────────────┐
                    │       Common.ush        │  (Tier 1)
                    │     Definitions.ush     │
                    └────────────┬────────────┘
                                 │
                    ┌────────────▼────────────┐
                    │      Platform.ush       │  (Tier 1)
                    └─────────────────────────┘
```

---

## 요약

| 모듈 | Tier | 주요 기능 |
|------|------|-----------|
| Platform.ush | 1 | API 매크로, Feature Level |
| Common.ush | 1 | 유틸리티 함수 (수백 개) |
| Definitions.ush | 1 | 사전 정의 매크로 |
| ShadingCommon.ush | 1 | 12가지 셰이딩 모델 ID |
| BRDF.ush | 1 | D, V, F 함수, Diffuse 모델 |
| DeferredShadingCommon.ush | 1 | G-Buffer 인코딩/디코딩 |
| ShadingModels.ush | 2 | 셰이딩 모델별 BxDF |
| DeferredLightingCommon.ush | 2 | 라이트 감쇠, 공통 구조체 |
| BasePassPixelShader.usf | 3 | G-Buffer 생성 |
| DeferredLightPixelShaders.usf | 3 | 디퍼드 라이팅 |

---

## 참고 자료

- 원문: https://www.cnblogs.com/timlly/p/14817455.html
- UE Source: `Engine/Shaders/Private/`
- "Physically Based Rendering" - Pharr et al.
