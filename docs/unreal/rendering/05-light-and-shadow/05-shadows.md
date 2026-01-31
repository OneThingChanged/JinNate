# 그림자 시스템

> Chapter 05-5: Shadow Mapping과 소프트 섀도우 기법

---

## 목차

1. [그림자 시스템 개요](#1-그림자-시스템-개요)
2. [Shadow Mapping 기초](#2-shadow-mapping-기초)
3. [Cascaded Shadow Maps (CSM)](#3-cascaded-shadow-maps-csm)
4. [Shadow Filtering](#4-shadow-filtering)
5. [Contact Shadows](#5-contact-shadows)
6. [그림자 최적화](#6-그림자-최적화)

---

## 1. 그림자 시스템 개요 {#1-그림자-시스템-개요}

![Shadow 개요](./images/1617944-20210527125147250-1932921585.jpg)
*그림자 시스템 개요*

### 그림자 렌더링 파이프라인

```
InitDynamicShadows()
│
├─→ GatherShadowPrimitives()        // 그림자 캐스터 수집
│
├─→ AllocateShadowDepthTargets()    // 섀도우 맵 할당
│
├─→ RenderShadowDepthMaps()         // 뎁스 맵 렌더링
│   ├─ Directional Light → CSM
│   ├─ Point Light → Cube Map
│   ├─ Spot Light → 2D Map
│   └─ Rect Light → 2D Map
│
└─→ RenderShadowProjections()       // 그림자 투영
```

### 핵심 그림자 타입

| 타입 | 함수 | 설명 |
|------|------|------|
| **Whole-scene** | `CreateWholeSceneProjectedShadow` | 전체 씬 투영 그림자 (CSM) |
| **Per-object** | `CreatePerObjectProjectedShadow` | 오브젝트별 그림자 |
| **Preshadow** | `UpdatePreshadowCache` | 프리섀도우 캐시 |
| **Ray Traced** | `RenderRayTracedShadows` | 레이트레이싱 그림자 |

---

## 2. Shadow Mapping 기초 {#2-shadow-mapping-기초}

![Shadow Map 원리](./images/1617944-20210527125258210-1377087590.jpg)
*Shadow Mapping 기본 원리*

### 2단계 알고리즘

**1단계: Shadow Map 생성**
```hlsl
// Shadow Depth Vertex Shader
float4 ShadowDepthVS(
    FVertexFactoryInput Input) : SV_POSITION
{
    float4 WorldPosition = VertexFactoryGetWorldPosition(Input);
    return mul(WorldPosition, LightViewProjection);
}

// Shadow Depth Pixel Shader (옵션)
void ShadowDepthPS(
    float4 Position : SV_POSITION,
    out float OutDepth : SV_Depth)
{
    OutDepth = Position.z;
}
```

**2단계: Shadow Sampling**
```hlsl
float GetShadow(float3 WorldPosition, FDeferredLightData LightData)
{
    // 월드 좌표 → 라이트 공간 변환
    float4 LightSpacePos = mul(float4(WorldPosition, 1), LightData.WorldToLight);
    float3 ShadowCoord = LightSpacePos.xyz / LightSpacePos.w;

    // NDC → UV 변환
    float2 ShadowUV = ShadowCoord.xy * 0.5 + 0.5;
    float ReceiverDepth = ShadowCoord.z;

    // Shadow Map 샘플링
    float OccluderDepth = ShadowDepthTexture.Sample(ShadowSampler, ShadowUV).r;

    // 뎁스 비교
    float Bias = 0.005;  // Shadow Acne 방지
    float Shadow = ReceiverDepth - Bias > OccluderDepth ? 0.0 : 1.0;

    return Shadow;
}
```

### Shadow Acne와 Peter Panning

```
Shadow Acne (자가 그림자):           Peter Panning (그림자 분리):
─────────────────────────           ─────────────────────────
  Shadow Map 해상도 한계로            Bias가 너무 커서
  표면이 자기 자신에 그림자            그림자가 표면에서 떨어짐

  해결: Depth Bias                    해결: 적절한 Bias 값
       Slope-scaled Bias                  Normal Offset
       Normal Offset

적절한 Bias:
  Bias = BaseBias + SlopeScale * tan(θ)
  여기서 θ = 표면과 광원 각도
```

---

## 3. Cascaded Shadow Maps (CSM) {#3-cascaded-shadow-maps-csm}

![CSM 개념](./images/1617944-20210527125219066-1431109239.jpg)
*Cascaded Shadow Maps 개념*

![CSM 분할](./images/1617944-20210527125241317-1921288899.jpg)
*CSM 캐스케이드 분할*

### CSM 개념

카메라 프러스텀을 여러 캐스케이드로 분할하여, 가까운 영역에 더 높은 해상도의 그림자를 제공합니다.

```
카메라                                          Far Plane
   │
   │   ┌─────────┬─────────────┬───────────────────┐
   ├───│ Cascade │  Cascade 1  │    Cascade 2      │
   │   │    0    │             │                   │
   │   │ (High)  │  (Medium)   │     (Low)         │
   │   └─────────┴─────────────┴───────────────────┘
   │
   └──→ Near                                     Far
        (고해상도)                               (저해상도)
```

### CSM 구현

```hlsl
// CSM 캐스케이드 선택
uint SelectCascade(float3 WorldPosition, float4 CascadeSplits)
{
    float ViewDepth = dot(WorldPosition - View.WorldCameraOrigin, View.ViewForward);

    uint Cascade = 0;
    if (ViewDepth > CascadeSplits.x) Cascade = 1;
    if (ViewDepth > CascadeSplits.y) Cascade = 2;
    if (ViewDepth > CascadeSplits.z) Cascade = 3;

    return Cascade;
}

// CSM 샘플링
float SampleCascadedShadowMap(
    float3 WorldPosition,
    float4x4 CascadeViewProj[4],
    Texture2DArray ShadowMapArray)
{
    uint Cascade = SelectCascade(WorldPosition, CascadeSplits);

    float4 LightSpacePos = mul(float4(WorldPosition, 1), CascadeViewProj[Cascade]);
    float3 ShadowCoord = LightSpacePos.xyz / LightSpacePos.w;
    float2 ShadowUV = ShadowCoord.xy * 0.5 + 0.5;

    float Shadow = ShadowMapArray.SampleCmpLevelZero(
        ShadowComparisonSampler,
        float3(ShadowUV, Cascade),
        ShadowCoord.z);

    return Shadow;
}
```

### CSM 파라미터

| 파라미터 | 설명 |
|----------|------|
| `DynamicShadowCascades` | 캐스케이드 수 (1-4) |
| `CascadeDistributionExponent` | 분할 비율 (1=균등, >1=가까운 곳 집중) |
| `CascadeTransitionFraction` | 캐스케이드 간 블렌딩 |
| `ShadowDistance` | 그림자 최대 거리 |

---

## 4. Shadow Filtering {#4-shadow-filtering}

### 4.1 PCF (Percentage Closer Filtering)

![PCF](./images/1617944-20210527125320468-1405692173.jpg)
*PCF (Percentage Closer Filtering)*

주변 텍셀을 샘플링하여 소프트 섀도우를 생성합니다.

```hlsl
float PCF_Shadow(float3 ShadowCoord, float2 ShadowMapSize, uint NumSamples)
{
    float2 TexelSize = 1.0 / ShadowMapSize;
    float Shadow = 0;

    // Poisson Disk 샘플링
    static const float2 PoissonDisk[16] = {
        float2(-0.94201624, -0.39906216),
        float2(0.94558609, -0.76890725),
        float2(-0.094184101, -0.92938870),
        float2(0.34495938, 0.29387760),
        // ... 더 많은 샘플
    };

    for (uint i = 0; i < NumSamples; i++)
    {
        float2 Offset = PoissonDisk[i] * TexelSize * FilterRadius;
        Shadow += ShadowMap.SampleCmpLevelZero(
            ShadowComparisonSampler,
            ShadowCoord.xy + Offset,
            ShadowCoord.z);
    }

    return Shadow / NumSamples;
}
```

### 4.2 PCSS (Percentage Closer Soft Shadows)

![PCSS](./images/1617944-20210527125349440-1839933829.jpg)
*PCSS - 거리에 따른 소프트 섀도우*

블로커 검색을 통해 반음영 크기를 동적으로 계산합니다.

```hlsl
float PCSS_Shadow(
    float3 ShadowCoord,
    float LightSize)
{
    // 1단계: Blocker Search
    float AvgBlockerDepth = 0;
    uint NumBlockers = 0;
    float SearchRadius = LightSize * ShadowCoord.z / LightZNear;

    for (uint i = 0; i < BLOCKER_SEARCH_SAMPLES; i++)
    {
        float2 Offset = PoissonDisk[i] * SearchRadius;
        float BlockerDepth = ShadowMap.SampleLevel(PointSampler, ShadowCoord.xy + Offset, 0).r;

        if (BlockerDepth < ShadowCoord.z)
        {
            AvgBlockerDepth += BlockerDepth;
            NumBlockers++;
        }
    }

    if (NumBlockers == 0)
        return 1.0;  // 완전히 밝음

    AvgBlockerDepth /= NumBlockers;

    // 2단계: Penumbra Estimation
    float PenumbraWidth = (ShadowCoord.z - AvgBlockerDepth) * LightSize / AvgBlockerDepth;

    // 3단계: PCF with Variable Kernel
    float Shadow = 0;
    for (uint j = 0; j < PCF_SAMPLES; j++)
    {
        float2 Offset = PoissonDisk[j] * PenumbraWidth;
        Shadow += ShadowMap.SampleCmpLevelZero(
            ShadowComparisonSampler,
            ShadowCoord.xy + Offset,
            ShadowCoord.z);
    }

    return Shadow / PCF_SAMPLES;
}
```

### 4.3 VSM (Variance Shadow Maps)

![VSM](./images/1617944-20210527125433934-1857100229.jpg)
*VSM - 분산 섀도우 맵*

뎁스와 뎁스²를 저장하고, 체비셰프 부등식으로 가시성을 계산합니다.

```hlsl
// VSM Shadow Map 생성
float2 VSM_StoreMoments(float Depth)
{
    return float2(Depth, Depth * Depth);
}

// VSM 샘플링
float VSM_Shadow(float2 Moments, float ReceiverDepth)
{
    float Mean = Moments.x;
    float MeanSqr = Moments.y;

    // 분산 계산
    float Variance = max(MeanSqr - Mean * Mean, 0.0001);

    // 체비셰프 부등식
    float d = ReceiverDepth - Mean;
    float p_max = Variance / (Variance + d * d);

    // Light Bleeding 감소
    float Bias = 0.3;
    p_max = saturate((p_max - Bias) / (1 - Bias));

    return (ReceiverDepth <= Mean) ? 1.0 : p_max;
}
```

**장점:** 하드웨어 필터링(밉맵, 바이리니어) 사용 가능
**단점:** Light Bleeding 아티팩트

### 4.4 ESM (Exponential Shadow Maps)

![ESM](./images/1617944-20210527125446315-516828752.jpg)
*ESM - 지수 섀도우 맵*

```hlsl
// ESM Shadow Map 생성
float ESM_StoreDepth(float Depth, float C)
{
    return exp(C * Depth);
}

// ESM 샘플링
float ESM_Shadow(float OccluderExp, float ReceiverDepth, float C)
{
    return saturate(exp(-C * ReceiverDepth) * OccluderExp);
}
```

### 필터링 기법 비교

| 기법 | 품질 | 성능 | 메모리 |
|------|------|------|--------|
| **Basic** | 하드 엣지 | 빠름 | 낮음 |
| **PCF** | 균일 소프트 | 중간 | 낮음 |
| **PCSS** | 물리적 소프트 | 느림 | 낮음 |
| **VSM** | 소프트 | 빠름 | 2x |
| **ESM** | 소프트 | 빠름 | 1x |

---

## 5. Contact Shadows {#5-contact-shadows}

![Contact Shadow](./images/1617944-20210527125504321-1034510017.jpg)
*Contact Shadows - 근접 그림자*

스크린 스페이스 레이 마칭으로 작은 디테일의 그림자를 생성합니다.

```hlsl
float ContactShadow(
    float3 WorldPosition,
    float3 LightDirection,
    float MaxDistance)
{
    // 월드 공간에서 스크린 공간으로
    float4 RayStart = mul(float4(WorldPosition, 1), View.WorldToClip);
    float4 RayEnd = mul(float4(WorldPosition + LightDirection * MaxDistance, 1), View.WorldToClip);

    float3 RayStartScreen = RayStart.xyz / RayStart.w;
    float3 RayEndScreen = RayEnd.xyz / RayEnd.w;

    float3 RayDir = RayEndScreen - RayStartScreen;

    // 스크린 스페이스 레이 마칭
    const int NumSteps = 16;
    float StepSize = 1.0 / NumSteps;

    for (int i = 1; i <= NumSteps; i++)
    {
        float t = i * StepSize;
        float3 SamplePos = RayStartScreen + RayDir * t;

        // UV 변환
        float2 SampleUV = SamplePos.xy * 0.5 + 0.5;
        SampleUV.y = 1 - SampleUV.y;

        // 뎁스 비교
        float SceneDepth = SceneDepthTexture.SampleLevel(PointSampler, SampleUV, 0).r;
        float RayDepth = SamplePos.z;

        if (RayDepth > SceneDepth + Bias)
        {
            return 0.0;  // 그림자
        }
    }

    return 1.0;  // 밝음
}
```

---

## 6. 그림자 최적화 {#6-그림자-최적화}

### 6.1 Shadow Map 아틀라스

```
┌─────────────────────────────────────────────────┐
│                Shadow Atlas                      │
├───────────────────┬───────────────────┬─────────┤
│                   │                   │         │
│    Directional    │    Spot Light 0   │ Point   │
│    (CSM 0-3)      │                   │   0     │
│                   │                   │         │
├───────────────────┼───────────────────┼─────────┤
│                   │                   │         │
│   Spot Light 1    │   Spot Light 2    │ Point   │
│                   │                   │   1     │
│                   │                   │         │
└───────────────────┴───────────────────┴─────────┘

장점: 텍스처 바인딩 감소, 배칭 가능
```

### 6.2 Shadow Caching

```cpp
struct FShadowCacheEntry
{
    FMatrix LightViewProj;          // 이전 프레임 매트릭스
    FRHITexture2D* CachedShadowMap; // 캐시된 섀도우 맵
    uint32 FrameNumber;             // 마지막 업데이트 프레임
    bool bValid;                    // 유효성
};

// 움직이지 않는 라이트의 그림자 재사용
bool CanUseCachedShadow(const FLightSceneInfo* Light)
{
    return !Light->bMovable &&
           !Light->bCastDynamicShadow &&
           CachedShadow.bValid;
}
```

### 6.3 그림자 컬링

```cpp
// 거리 기반 컬링
bool ShouldRenderShadow(const FLightSceneInfo* Light, const FViewInfo& View)
{
    float Distance = FVector::Dist(Light->Position, View.ViewOrigin);
    float MaxDistance = Light->GetMaxShadowDistance();

    return Distance < MaxDistance;
}

// 화면 크기 기반 컬링
bool ShouldRenderPerObjectShadow(const FPrimitiveSceneInfo* Primitive)
{
    float ScreenSize = ComputeScreenSize(Primitive->Bounds);
    return ScreenSize > MinScreenSizeForShadow;
}
```

### 6.4 성능 통계

| 기법 | GPU 비용 | 품질 |
|------|----------|------|
| **1024 Shadow Map** | 낮음 | 저품질 |
| **2048 Shadow Map** | 중간 | 중품질 |
| **4096 Shadow Map** | 높음 | 고품질 |
| **CSM 4 Cascades** | 4x Single | 거리별 적응 |
| **Ray Traced** | 매우 높음 | 최고 품질 |

---

## 요약

```
┌─────────────────────────────────────────────────────────────────┐
│                    Shadow System Summary                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   Shadow Map Generation:                                         │
│   ┌──────────────┐                                              │
│   │  Light View  │ → Render Depth → Store in Texture            │
│   └──────────────┘                                              │
│                                                                  │
│   Shadow Sampling:                                               │
│   ┌──────────────┐                                              │
│   │ World Pos    │ → Transform → Sample → Compare → Shadow      │
│   └──────────────┘                                              │
│                                                                  │
│   Filtering Techniques:                                          │
│   ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐              │
│   │   PCF   │ │  PCSS   │ │   VSM   │ │   ESM   │              │
│   │ Uniform │ │Variable │ │Variance │ │  Exp    │              │
│   │  Soft   │ │  Soft   │ │  Based  │ │  Based  │              │
│   └─────────┘ └─────────┘ └─────────┘ └─────────┘              │
│                                                                  │
│   CSM for Directional Lights:                                    │
│   Near ─────────────────────────────────────────→ Far           │
│   [Cascade0][  Cascade1  ][    Cascade2    ][  Cascade3  ]      │
│    High Res   Medium Res     Low Res          Lowest Res        │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 참고 자료

- 원문: https://www.cnblogs.com/timlly/p/14817455.html
- "Real-Time Shadows" - Eisemann, Schwarz, Assarsson, Wimmer
- "Cascaded Shadow Maps" - GPU Gems 3
- "PCSS" - Fernando, NVIDIA
- UE Source: `Engine/Shaders/Private/ShadowProjectionPixelShader.usf`
