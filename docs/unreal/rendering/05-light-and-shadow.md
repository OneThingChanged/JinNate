# Chapter 05: 광원과 그림자

> 원문: https://www.cnblogs.com/timlly/p/14817455.html
> 시리즈: 剖析虚幻渲染体系 (Unreal 렌더링 시스템 분석)

---

## 목차

1. [광원 타입](#1-광원-타입)
2. [그림자 시스템 아키텍처](#2-그림자-시스템-아키텍처)
3. [Shadow Mapping 기법](#3-shadow-mapping-기법)
4. [라이트 컬링과 그리드 시스템](#4-라이트-컬링과-그리드-시스템)
5. [BRDF와 라이팅 계산](#5-brdf와-라이팅-계산)
6. [셰이더 모듈 계층](#6-셰이더-모듈-계층)
7. [핵심 데이터 구조](#7-핵심-데이터-구조)
8. [UE 라이팅 구현](#8-ue-라이팅-구현)

---

## 1. 광원 타입 {#1-광원-타입}

### 1.1 기본 광원 종류

![광원 타입](./images/ch05/1617944-20210527124933083-399182186.jpg)
*UE의 다양한 광원 타입*

UE의 디퍼드 렌더링 시스템에서 지원하는 광원 타입 (`FDeferredLightData` 구조체):

| 광원 타입 | 제어 플래그 | 특징 |
|-----------|-------------|------|
| **Directional Light** | `bRadialLight = false` | 무한 거리, 평행 광선 |
| **Point Light** | `bRadialLight = true` | 반경 기반 감쇠 |
| **Spot Light** | `bSpotLight` + `SpotAngles` | 원뿔형 광원 |
| **Rect Light** | `bRectLight` + Barn Door | 사각형 영역 광원 |

### 1.2 특수 광원

![Point Light](./images/ch05/1617944-20210527125020040-880689474.jpg)
*Point Light 예시*

![Spot Light](./images/ch05/1617944-20210527125053515-1208510005.jpg)
*Spot Light 예시*

추가 특수 광원:
- **Capsule Light** - 캡슐 형태
- **Area Light** - `FAreaLight` (구체 및 선 지오메트리 파라미터)
- **Sky Light** - 환경 조명

### 1.3 Light Function

![Light Function](./images/ch05/1617944-20210527125132427-988340219.jpg)
*Light Function 효과*

Light-specific 파라미터:
- `ContactShadowLength` - 컨택트 섀도우
- `DistanceFadeMAD` - 거리 페이드
- `SpecularScale` - 스페큘러 스케일
- `FHairTransmittanceData` - 헤어 투과 데이터

---

## 2. 그림자 시스템 아키텍처 {#2-그림자-시스템-아키텍처}

### 2.1 핵심 그림자 타입

![Shadow 개요](./images/ch05/1617944-20210527125147250-1932921585.jpg)
*그림자 시스템 개요*

| 타입 | 초기화 함수 | 설명 |
|------|-------------|------|
| **Whole-scene Shadows** | `CreateWholeSceneProjectedShadow` | 전체 씬 투영 그림자 |
| **Per-object Shadows** | `CreatePerObjectProjectedShadow` | 오브젝트별 투영 그림자 |
| **Preshadow Cache** | `UpdatePreshadowCache` | 프리섀도우 캐시 |

### 2.2 그림자 렌더링 파이프라인

![Shadow Pipeline](./images/ch05/1617944-20210527125201662-1245458023.jpg)
*그림자 렌더링 파이프라인*

```
InitDynamicShadows
    │
    ├─→ GatherShadowPrimitives      (그림자 캐스팅 지오메트리 수집)
    │
    ├─→ AllocateShadowDepthTargets  (텍스처 리소스 예약)
    │
    ├─→ RenderShadowDepthMaps       (뎁스 맵 생성)
    │
    └─→ RenderShadowProjections     (씬에 그림자 적용)
```

### 2.3 Cascaded Shadow Maps (CSM)

![CSM 개념](./images/ch05/1617944-20210527125219066-1431109239.jpg)
*Cascaded Shadow Maps 개념*

![CSM 분할](./images/ch05/1617944-20210527125241317-1921288899.jpg)
*CSM 캐스케이드 분할*

CSM은 카메라 프러스텀을 여러 캐스케이드로 분할하여, 가까운 영역에 더 높은 해상도의 그림자를 제공:

| 캐스케이드 | 거리 | 해상도 |
|------------|------|--------|
| Cascade 0 | 가까움 | 높음 |
| Cascade 1 | 중간 | 중간 |
| Cascade 2 | 멀리 | 낮음 |
| Cascade 3 | 매우 멀리 | 최저 |

---

## 3. Shadow Mapping 기법 {#3-shadow-mapping-기법}

### 3.1 기본 Shadow Mapping

![Shadow Map 원리](./images/ch05/1617944-20210527125258210-1377087590.jpg)
*Shadow Mapping 기본 원리*

1. 광원 시점에서 씬을 뎁스 버퍼로 렌더링
2. 카메라 시점에서 각 픽셀을 광원 공간으로 변환
3. 저장된 뎁스와 비교하여 그림자 결정

### 3.2 Shadow Filtering 기법

![PCF](./images/ch05/1617944-20210527125320468-1405692173.jpg)
*PCF (Percentage Closer Filtering)*

#### PCF (Percentage Closer Filtering)

주변 텍셀을 샘플링하여 소프트 섀도우 생성:

```hlsl
float shadow = 0;
for (int i = 0; i < numSamples; i++)
{
    float2 offset = PoissonDisk[i] * filterRadius;
    shadow += ShadowMap.SampleCmpLevelZero(sampler, uv + offset, depth);
}
shadow /= numSamples;
```

#### PCSS (Percentage Closer Soft Shadows)

![PCSS](./images/ch05/1617944-20210527125349440-1839933829.jpg)
*PCSS - 거리에 따른 소프트 섀도우*

블로커 검색을 통해 반음영 크기를 동적으로 계산:

1. **Blocker Search** - 평균 블로커 깊이 계산
2. **Penumbra Estimation** - 반음영 크기 추정
3. **PCF Filtering** - 가변 커널 크기로 필터링

#### VSM (Variance Shadow Maps)

![VSM](./images/ch05/1617944-20210527125433934-1857100229.jpg)
*VSM - 분산 섀도우 맵*

뎁스와 뎁스² 저장, 체비셰프 부등식으로 가시성 계산:

```hlsl
float variance = moments.y - moments.x * moments.x;
float d = depth - moments.x;
float p_max = variance / (variance + d * d);
```

**장점:** 하드웨어 필터링 사용 가능
**단점:** Light bleeding 아티팩트

#### ESM (Exponential Shadow Maps)

![ESM](./images/ch05/1617944-20210527125446315-516828752.jpg)
*ESM - 지수 섀도우 맵*

```hlsl
float shadow = saturate(exp(-c * (depth - occluder)));
```

### 3.3 Contact Shadows

![Contact Shadow](./images/ch05/1617944-20210527125504321-1034510017.jpg)
*Contact Shadows - 근접 그림자*

스크린 스페이스 레이 마칭으로 작은 디테일의 그림자 생성.

---

## 4. 라이트 컬링과 그리드 시스템 {#4-라이트-컬링과-그리드-시스템}

### 4.1 Spatial Light Grid

![Light Grid](./images/ch05/1617944-20210527125516707-1077778770.jpg)
*공간 라이트 그리드*

```cpp
GatherAndSortLights()  // 광원 수집 및 정렬
    │
    └─→ ComputeLightGrid()  // 공간 셀에 광원 분배
```

그리드 기반 컬링으로 픽셀당 라이트 평가 오버헤드 감소.

### 4.2 Tiled Light Culling

![Tiled Culling](./images/ch05/1617944-20210527125540123-1236750462.jpg)
*Tiled 기반 라이트 컬링*

스크린을 타일로 분할하고 각 타일에 영향을 미치는 라이트만 처리:

```
1. 타일별 Min/Max 뎁스 계산
2. 타일 프러스텀 생성
3. 라이트-타일 교차 테스트
4. 타일별 라이트 리스트 생성
```

### 4.3 Clustered Light Culling

![Clustered](./images/ch05/1617944-20210527125604394-1116075554.jpg)
*Clustered 라이트 컬링*

Tiled + 뎁스 슬라이싱으로 3D 클러스터 생성:

```
클러스터 = 타일(X, Y) × 뎁스 슬라이스(Z)
```

---

## 5. BRDF와 라이팅 계산 {#5-brdf와-라이팅-계산}

### 5.1 BRDF 모듈

![BRDF](./images/ch05/1617944-20210527125630692-2036345235.jpg)
*BRDF 컴포넌트*

#### Distribution Functions (D)

| 함수 | 설명 |
|------|------|
| `D_GGX` | GGX/Trowbridge-Reitz |
| `D_Beckmann` | Beckmann 분포 |
| `D_Blinn` | Blinn-Phong |

#### Visibility Functions (V)

| 함수 | 설명 |
|------|------|
| `Vis_Smith` | Smith |
| `Vis_SmithJoint` | Smith Joint |
| `Vis_SmithJointAniso` | 이방성 Smith Joint |

#### Fresnel Functions (F)

| 함수 | 설명 |
|------|------|
| `F_Schlick` | Schlick 근사 |
| `F_Fresnel` | 정확한 Fresnel |

### 5.2 Diffuse 모델

![Diffuse Models](./images/ch05/1617944-20210527125647846-1373192437.jpg)
*다양한 Diffuse 모델*

- **Lambert** - 기본 확산
- **Burley** - Disney Diffuse
- **OrenNayar** - 거친 표면

### 5.3 스페큘러 계산

![Specular](./images/ch05/1617944-20210527125700281-1732940334.jpg)
*스페큘러 하이라이트*

```hlsl
// Cook-Torrance Specular BRDF
float3 Specular = D * F * V / (4 * NoL * NoV);
```

---

## 6. 셰이더 모듈 계층 {#6-셰이더-모듈-계층}

### 3-Tier 구조

![Shader Hierarchy](./images/ch05/1617944-20210527125716483-612678730.jpg)
*셰이더 모듈 계층 구조*

| Tier | 모듈 | 역할 |
|------|------|------|
| **Tier 1 (기초)** | Common.ush, BRDF.ush, ShadingCommon.ush, ShadowDepthCommon.ush | 기본 함수 |
| **Tier 2 (중간)** | ShadingModels.ush, DeferredLightingCommon.ush, ShadowProjectionCommon.ush | 라이팅 로직 |
| **Tier 3 (구현)** | BasePassPixelShader.usf, DeferredLightPixelShaders.usf, ShadowProjectionPixelShader.usf | 최종 셰이더 |

---

## 7. 핵심 데이터 구조 {#7-핵심-데이터-구조}

### 7.1 FGBufferData

![GBuffer Data](./images/ch05/1617944-20210527125733360-1579820233.png)
*G-Buffer 데이터 구조*

```cpp
struct FGBufferData
{
    float3 WorldNormal;
    float3 WorldTangent;
    float3 BaseColor;
    float  Metallic;
    float  Specular;
    float  Roughness;
    uint   ShadingModelID;  // 4비트 (최대 16개 모델)
    // ...
};
```

> "UE는 Shading Model ID에 4비트를 할당하여, 커스텀 모델은 최대 3개로 제한됩니다."

### 7.2 FShadowTerms

```cpp
struct FShadowTerms
{
    float SurfaceShadow;      // 표면 그림자
    float TransmissionShadow; // 투과 그림자
    float Thickness;          // 두께
    FHairTransmittanceData HairTransmittance; // 헤어 투과
};
```

### 7.3 FDeferredLightData

![Light Data](./images/ch05/1617944-20210527125757261-177285983.jpg)
*디퍼드 라이트 데이터*

```cpp
struct FDeferredLightData
{
    float3 Position;
    float3 Direction;
    float3 Color;
    float  Radius;
    float2 SpotAngles;

    uint   ShadowMapChannelMask;
    uint   ShadowedBits;

    bool   bRadialLight;
    bool   bSpotLight;
    bool   bRectLight;
};
```

---

## 8. UE 라이팅 구현 {#8-ue-라이팅-구현}

### 8.1 라이팅 패스 흐름

![Lighting Pass](./images/ch05/1617944-20210527125816032-546720973.jpg)
*UE 라이팅 패스*

```
RenderLights()
    │
    ├─→ RenderDirectionalLight()
    │
    ├─→ RenderPointLight()
    │
    ├─→ RenderSpotLight()
    │
    └─→ RenderRectLight()
```

### 8.2 그림자 렌더링 흐름

![Shadow Rendering](./images/ch05/1617944-20210527125853255-868399953.jpg)
*그림자 렌더링 흐름*

![Shadow Depth](./images/ch05/1617944-20210527125905484-986749331.jpg)
*Shadow Depth Map 생성*

![Shadow Projection](./images/ch05/1617944-20210527125917125-541399809.jpg)
*Shadow Projection*

### 8.3 IES 프로파일

![IES Profile](./images/ch05/1617944-20210527125954790-2014059921.jpg)
*IES Light Profile*

IES (Illuminating Engineering Society) 프로파일로 실제 조명 기구의 배광 특성 재현.

### 8.4 Area Light

![Area Light](./images/ch05/1617944-20210527130006177-768044047.jpg)
*Area Light 렌더링*

영역 광원의 소프트 라이팅 효과.

### 8.5 프레임 분석

![Frame Analysis 1](./images/ch05/1617944-20210527130049178-1390887379.jpg)
*라이팅 프레임 분석 1*

![Frame Analysis 2](./images/ch05/1617944-20210527130104721-1388293420.jpg)
*라이팅 프레임 분석 2*

![Frame Analysis 3](./images/ch05/1617944-20210527130206062-1209308195.jpg)
*그림자 프레임 분석*

---

## 요약 다이어그램

```
┌────────────────────────────────────────────────────────────────────┐
│                 UE Light & Shadow System                           │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │                    Light Types                               │  │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐           │  │
│  │  │Direction│ │  Point  │ │  Spot   │ │  Rect   │           │  │
│  │  └─────────┘ └─────────┘ └─────────┘ └─────────┘           │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                              │                                     │
│                              ▼                                     │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │                 Light Culling                                │  │
│  │         Tiled / Clustered Light Assignment                   │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                              │                                     │
│          ┌───────────────────┼───────────────────┐                │
│          ▼                   ▼                   ▼                │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐        │
│  │ Shadow Maps  │    │    BRDF      │    │   G-Buffer   │        │
│  │  ├─ CSM      │    │  ├─ D_GGX    │    │   Sampling   │        │
│  │  ├─ PCF      │    │  ├─ F_Schlick│    │              │        │
│  │  ├─ PCSS     │    │  └─ Vis_Smith│    │              │        │
│  │  └─ VSM/ESM  │    │              │    │              │        │
│  └──────────────┘    └──────────────┘    └──────────────┘        │
│          │                   │                   │                │
│          └───────────────────┼───────────────────┘                │
│                              ▼                                     │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │                  Final Lighting                              │  │
│  │     Color = Diffuse * Shadow + Specular * Shadow            │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

---

## 참고 자료

- 원문: https://www.cnblogs.com/timlly/p/14817455.html
- "Real-Time Shadows" - Eisemann et al.
- "Physically Based Rendering" - Pharr, Jakob, Humphreys
- UE4 Source: Engine/Shaders/Private/DeferredLightingCommon.ush
