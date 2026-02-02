# Ch.08 셰이더 시스템

UE의 셰이더 아키텍처, 컴파일 시스템, 최적화 기법을 분석합니다.

---

## 개요

셰이더는 GPU에서 실행되는 프로그램으로, 렌더링의 핵심입니다. UE는 복잡한 셰이더 시스템을 통해 크로스 플랫폼 지원과 고성능을 달성합니다.

![UE 셰이더 컴파일 아키텍처](../images/ch08/1617944-20210802224354581-1202563787.jpg)

*UE 4.25 셰이더 컴파일 파이프라인 - HLSL에서 각 플랫폼별 셰이더 언어로 변환 (OpenGL, Metal, GNM, Vulkan, DX11/12)*

```
┌─────────────────────────────────────────────────────────────────┐
│                    UE 셰이더 시스템 개요                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    HLSL 소스 코드                        │   │
│  │  (.usf, .ush 파일)                                      │   │
│  └────────────────────────┬────────────────────────────────┘   │
│                           │                                     │
│                           ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    셰이더 컴파일러                        │   │
│  │  ┌───────────┐  ┌───────────┐  ┌───────────┐            │   │
│  │  │   HLSL    │  │   GLSL    │  │   Metal   │            │   │
│  │  │ Compiler  │  │  Cross    │  │ Compiler  │            │   │
│  │  │  (DXC)    │  │ Compiler  │  │           │            │   │
│  │  └───────────┘  └───────────┘  └───────────┘            │   │
│  └────────────────────────┬────────────────────────────────┘   │
│                           │                                     │
│           ┌───────────────┼───────────────┐                     │
│           ▼               ▼               ▼                     │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐            │
│  │  DXBC/DXIL   │ │   SPIRV     │ │   Metal IR   │            │
│  │  (DirectX)   │ │  (Vulkan)   │ │   (Apple)    │            │
│  └──────────────┘ └──────────────┘ └──────────────┘            │
│                           │                                     │
│                           ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    Shader Cache                          │   │
│  │  (.ushaderbytecode, DDC)                                 │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 목차

| 문서 | 주제 | 핵심 내용 |
|------|------|----------|
| [01](01-shader-architecture.md) | 셰이더 아키텍처 | FShader, FGlobalShader, FMaterialShader |
| [02](02-shader-compilation.md) | 셰이더 컴파일 | 순열, 크로스 컴파일, 캐싱 |
| [03](03-shader-types.md) | 셰이더 타입 | VS, PS, CS, GS, HS/DS |
| [04](04-shader-binding.md) | 파라미터 바인딩 | Uniform Buffer, SRV, UAV |
| [05](05-shader-optimization.md) | 셰이더 최적화 | 분기, 점유율, 디버깅 |

---

## 셰이더 계층 구조

### 클래스 다이어그램

```
┌─────────────────────────────────────────────────────────────────┐
│                    셰이더 클래스 계층                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│                    ┌─────────────┐                              │
│                    │   FShader   │  ← 모든 셰이더의 기본 클래스   │
│                    └──────┬──────┘                              │
│                           │                                     │
│           ┌───────────────┼───────────────┐                     │
│           │               │               │                     │
│           ▼               ▼               ▼                     │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐            │
│  │FGlobalShader │ │FMaterialShader│ │FMeshMaterial │            │
│  │              │ │              │ │   Shader     │            │
│  └──────┬───────┘ └──────┬───────┘ └──────┬───────┘            │
│         │                │                │                     │
│         ▼                ▼                ▼                     │
│  ┌────────────┐  ┌────────────┐  ┌────────────────┐            │
│  │ PostProcess│  │  Material  │  │ BasePassPixel  │            │
│  │    CS      │  │   VS/PS    │  │    Shader      │            │
│  └────────────┘  └────────────┘  └────────────────┘            │
│                                                                 │
│  FGlobalShader: 전역 셰이더 (포스트 프로세스, 컴퓨트 등)          │
│  FMaterialShader: 머티리얼 기반 셰이더                           │
│  FMeshMaterialShader: 메시 + 머티리얼 조합 셰이더                 │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 핵심 클래스

```cpp
// 셰이더 기본 클래스
class FShader
{
public:
    // 셰이더 타입 정보
    FShaderType* GetType() const;

    // 컴파일된 바이너리
    FShaderResource* GetResource() const;

    // 파라미터 바인딩
    FShaderParameterBindings ParameterBindings;

    // 해시 (동일성 체크용)
    FSHAHash GetHash() const;
};

// 전역 셰이더
class FGlobalShader : public FShader
{
    // 머티리얼과 무관한 셰이더
    // 예: 블룸, SSAO, 컴퓨트 셰이더
};

// 머티리얼 셰이더
class FMaterialShader : public FShader
{
    // 특정 머티리얼 타입에 종속
    // 머티리얼 파라미터 접근 가능
};

// 메시 머티리얼 셰이더
class FMeshMaterialShader : public FMaterialShader
{
    // 버텍스 팩토리 + 머티리얼 조합
    // BasePass, Depth Pass 등
};
```

---

## 셰이더 파일 구조

### 파일 확장자

```
┌────────────────────────────────────────────────────────────────┐
│                    셰이더 파일 타입                             │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│  확장자      용도                    예시                      │
│  ─────────  ─────────────────────  ─────────────────────────  │
│  .usf       셰이더 소스             BasePassPixelShader.usf   │
│  .ush       셰이더 헤더 (include)   Common.ush                │
│  .h         C++ 파라미터 정의       ShaderParameters.h        │
│                                                                │
│  경로:                                                         │
│  - Engine/Shaders/Private/         엔진 프라이빗 셰이더        │
│  - Engine/Shaders/Public/          엔진 퍼블릭 헤더            │
│  - [Project]/Shaders/              프로젝트 커스텀 셰이더      │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

### 파일 예시

```hlsl
// Common.ush - 공통 헤더
#pragma once

// 상수
#define PI 3.14159265359
#define HALF_PI 1.5707963267

// 공통 함수
float Square(float X) { return X * X; }
float3 SafeNormalize(float3 V) { return V * rsqrt(max(dot(V, V), 0.0001)); }

// 좌표 변환
float3 TransformWorldToView(float3 WorldPos)
{
    return mul(float4(WorldPos, 1), View.WorldToView).xyz;
}
```

```hlsl
// BasePassPixelShader.usf
#include "Common.ush"
#include "MaterialTemplate.ush"
#include "DeferredShadingCommon.ush"

void Main(
    FVertexFactoryInterpolantsVSToPS Interpolants,
    FBasePassInterpolantsVSToPS BasePassInterpolants,
    in float4 SvPosition : SV_Position,
    out float4 OutGBufferA : SV_Target0,
    out float4 OutGBufferB : SV_Target1,
    out float4 OutGBufferC : SV_Target2,
    out float4 OutGBufferD : SV_Target3
)
{
    // 머티리얼 평가
    FMaterialPixelParameters MaterialParameters = GetMaterialPixelParameters(
        Interpolants, SvPosition);

    FPixelMaterialInputs PixelMaterialInputs;
    CalcMaterialParameters(MaterialParameters, PixelMaterialInputs);

    // G-Buffer 출력
    FGBufferData GBuffer = (FGBufferData)0;
    GBuffer.WorldNormal = MaterialParameters.WorldNormal;
    GBuffer.BaseColor = GetMaterialBaseColor(PixelMaterialInputs);
    GBuffer.Metallic = GetMaterialMetallic(PixelMaterialInputs);
    GBuffer.Roughness = GetMaterialRoughness(PixelMaterialInputs);

    EncodeGBuffer(GBuffer, OutGBufferA, OutGBufferB, OutGBufferC, OutGBufferD);
}
```

---

## 셰이더 순열 (Permutation)

### 개념

```
┌─────────────────────────────────────────────────────────────────┐
│                    셰이더 순열 시스템                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  하나의 셰이더 소스 → 다양한 변형 생성                           │
│                                                                 │
│  BasePassPS.usf                                                 │
│       │                                                         │
│       ├── #if USE_NORMAL_MAP                                    │
│       ├── #if USE_EMISSIVE                                      │
│       ├── #if MATERIALBLENDING_MASKED                           │
│       └── #if NUM_LIGHTS > 0                                    │
│                                                                 │
│  조합 예시 (2^4 = 16개 순열):                                    │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Permutation 0:  NormalMap=0, Emissive=0, Masked=0       │   │
│  │ Permutation 1:  NormalMap=1, Emissive=0, Masked=0       │   │
│  │ Permutation 2:  NormalMap=0, Emissive=1, Masked=0       │   │
│  │ Permutation 3:  NormalMap=1, Emissive=1, Masked=0       │   │
│  │ ...                                                     │   │
│  │ Permutation 15: NormalMap=1, Emissive=1, Masked=1       │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  문제: 순열 폭발 (조합이 기하급수적으로 증가)                     │
│  해결: 필요한 순열만 컴파일, PSO 캐싱                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 순열 정의

```cpp
// 순열 차원 정의
class FBasePassPS : public FMeshMaterialShader
{
    DECLARE_SHADER_TYPE(FBasePassPS, MeshMaterial);

    // 순열 차원 선언
    class FLightMapPolicyDim : SHADER_PERMUTATION_INT("LIGHTMAP_POLICY", 3);
    class FSkyLightDim : SHADER_PERMUTATION_BOOL("USE_SKY_LIGHT");
    class FAtmosphericFogDim : SHADER_PERMUTATION_BOOL("USE_ATMOSPHERIC_FOG");

    // 순열 도메인 정의
    using FPermutationDomain = TShaderPermutationDomain<
        FLightMapPolicyDim,
        FSkyLightDim,
        FAtmosphericFogDim
    >;

    // 순열 필터링 (불필요한 조합 제외)
    static bool ShouldCompilePermutation(const FMeshMaterialShaderPermutationParameters& Parameters)
    {
        // 모바일에서는 특정 조합만
        if (IsMobilePlatform(Parameters.Platform))
        {
            return Parameters.Get<FSkyLightDim>() == false;
        }
        return true;
    }
};
```

---

## 성능 특성

### 컴파일 시간 vs 런타임 성능

```
┌────────────────────────────────────────────────────────────────┐
│                    트레이드오프                                 │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│  많은 순열                    적은 순열                         │
│  ┌─────────────────┐         ┌─────────────────┐               │
│  │ 컴파일 시간: 길다 │         │ 컴파일 시간: 짧다 │               │
│  │ 셰이더 크기: 크다 │         │ 셰이더 크기: 작다 │               │
│  │ 런타임: 빠름     │         │ 런타임: 느림      │               │
│  │ (최적화된 코드)   │         │ (동적 분기)       │               │
│  └─────────────────┘         └─────────────────┘               │
│                                                                │
│  UE 전략:                                                      │
│  - 중요한 분기는 순열로                                        │
│  - 작은 분기는 동적으로                                        │
│  - PSO 캐싱으로 런타임 컴파일 최소화                            │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

---

## 학습 순서

1. **셰이더 아키텍처** - 클래스 계층과 생명주기
2. **셰이더 컴파일** - 순열, 크로스 컴파일, 캐싱
3. **셰이더 타입** - 각 셰이더 스테이지별 역할
4. **파라미터 바인딩** - 데이터 전달 방법
5. **셰이더 최적화** - 성능 향상 기법

---

## ShaderCompileWorker

![ShaderCompileWorker 설정](../images/ch08/1617944-20210802224631477-1524681730.jpg)

*Visual Studio Configuration Manager - ShaderCompileWorker 프로젝트의 다양한 플랫폼 빌드 구성*

---

## 참고 자료

- [UE 셰이더 개발 문서](https://docs.unrealengine.com/5.0/en-US/shader-development-in-unreal-engine/)
- [원문 시리즈 (중국어)](https://www.cnblogs.com/timlly/p/13512787.html)
---

<div style="display: flex; justify-content: space-between; align-items: center; padding: 16px 0;">
  <a href="../07-post-processing/05-screen-space-effects/" style="text-decoration: none;">← 이전: Ch.07 05. 포스트 프로세싱</a>
  <a href="01-shader-architecture/" style="text-decoration: none;">다음: 01. 셰이더 아키텍처 →</a>
</div>
