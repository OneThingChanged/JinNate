# 광원 (Light Sources)

> Chapter 05-3: UE 광원 타입과 속성

---

## 목차

1. [광원 타입 개요](#1-광원-타입-개요)
2. [Directional Light](#2-directional-light)
3. [Point Light](#3-point-light)
4. [Spot Light](#4-spot-light)
5. [Rect Light](#5-rect-light)
6. [Area Light](#6-area-light)
7. [Light Function](#7-light-function)
8. [IES 프로파일](#8-ies-프로파일)

---

## 1. 광원 타입 개요 {#1-광원-타입-개요}

![광원 타입](./images/1617944-20210527124933083-399182186.jpg)
*UE의 다양한 광원 타입*

### FDeferredLightData 구조체

모든 디퍼드 라이트 정보를 담는 핵심 구조체입니다.

```cpp
struct FDeferredLightData
{
    // 기본 속성
    float3 Position;           // 광원 위치
    float3 Direction;          // 광원 방향 (Directional, Spot)
    float3 Color;              // 광원 색상
    float  InvRadius;          // 1 / 반경 (감쇠 계산용)

    // 물리적 속성
    float3 Tangent;            // 탄젠트 (Rect Light용)
    float  SourceRadius;       // 소스 반경 (소프트 섀도우용)
    float  SourceLength;       // 소스 길이 (Capsule Light용)
    float  SoftSourceRadius;   // 소프트 소스 반경
    float  SpecularScale;      // 스페큘러 스케일

    // Spot Light 속성
    float2 SpotAngles;         // (CosOuter, InvCosRange)

    // Rect Light 속성
    float  RectLightBarnCosAngle;
    float  RectLightBarnLength;

    // 타입 플래그
    bool   bRadialLight;       // Point/Spot/Rect (true) vs Directional (false)
    bool   bSpotLight;         // Spot Light 여부
    bool   bRectLight;         // Rect Light 여부
    bool   bInverseSquared;    // 역제곱 감쇠

    // 그림자 속성
    bool   bShadowed;
    uint   ShadowMapChannelMask;
    uint   ShadowedBits;

    // 특수 기능
    float  ContactShadowLength;        // 컨택트 섀도우
    float2 DistanceFadeMAD;            // 거리 페이드
    FHairTransmittanceData HairTransmittance;  // 헤어 투과
};
```

### 광원 타입 분류

| 타입 | bRadialLight | bSpotLight | bRectLight | 특징 |
|------|--------------|------------|------------|------|
| **Directional** | false | false | false | 무한 거리, 평행 광선 |
| **Point** | true | false | false | 구형 감쇠 |
| **Spot** | true | true | false | 원뿔형 |
| **Rect** | true | false | true | 사각형 영역 |

---

## 2. Directional Light {#2-directional-light}

### 특징

- **무한 거리**: 감쇠 없음
- **평행 광선**: 모든 지점에서 동일한 방향
- **주요 용도**: 태양, 달

```hlsl
// Directional Light 계산
float3 GetDirectionalLightAttenuation(FDeferredLightData LightData, float3 WorldPosition)
{
    // Directional Light는 감쇠가 없음
    return LightData.Color;
}

float3 GetDirectionalLightDirection(FDeferredLightData LightData)
{
    // 모든 지점에서 동일한 방향
    return -LightData.Direction;
}
```

### 주요 파라미터

| 파라미터 | 설명 |
|----------|------|
| `Direction` | 광원 방향 벡터 |
| `Color` | 광원 색상 × 강도 |
| `bCastShadows` | CSM 그림자 캐스팅 |
| `DynamicShadowCascades` | CSM 캐스케이드 수 |

---

## 3. Point Light {#3-point-light}

![Point Light](./images/1617944-20210527125020040-880689474.jpg)
*Point Light 예시*

### 특징

- **구형 감쇠**: 거리에 따른 역제곱 감쇠
- **반경 제한**: Attenuation Radius로 영향 범위 제한
- **주요 용도**: 전구, 횃불, 캠프파이어

### 감쇠 계산

```hlsl
float GetPointLightAttenuation(FDeferredLightData LightData, float3 WorldPosition)
{
    float3 ToLight = LightData.Position - WorldPosition;
    float DistanceSqr = dot(ToLight, ToLight);

    // 역제곱 감쇠
    float Attenuation;
    if (LightData.bInverseSquared)
    {
        // 물리적으로 정확한 역제곱 감쇠
        Attenuation = 1.0 / (DistanceSqr + 1.0);
    }
    else
    {
        // Exponential Falloff (레거시)
        float Distance = sqrt(DistanceSqr);
        Attenuation = pow(saturate(1 - pow(Distance * LightData.InvRadius, 4)), 2);
    }

    // 반경 마스크 (부드러운 경계)
    float LightRadiusMask = Square(saturate(
        1 - Square(DistanceSqr * Square(LightData.InvRadius))));

    return Attenuation * LightRadiusMask;
}
```

### 감쇠 비교

```
거리 기반 감쇠 곡선:

강도
│
│ ████                    Inverse Square (물리적)
│ █████████
│ ██████████████
│ █████████████████████
│ ███████████████████████████████
└───────────────────────────────────→ 거리
      r=0.25   r=0.5    r=0.75   r=1.0

강도
│
│ ████████████████        Exponential (레거시)
│ █████████████████████
│ ████████████████████████
│ █████████████████████████████
│ ███████████████████████████████
└───────────────────────────────────→ 거리
      r=0.25   r=0.5    r=0.75   r=1.0
```

---

## 4. Spot Light {#4-spot-light}

![Spot Light](./images/1617944-20210527125053515-1208510005.jpg)
*Spot Light 예시*

### 특징

- **원뿔형 영역**: Inner/Outer Cone Angle
- **Point Light 기반**: 거리 감쇠 + 각도 감쇠
- **주요 용도**: 손전등, 무대 조명, 가로등

### 각도 감쇠 계산

```hlsl
float GetSpotLightAttenuation(FDeferredLightData LightData, float3 WorldPosition)
{
    float3 ToLight = LightData.Position - WorldPosition;
    float DistanceSqr = dot(ToLight, ToLight);
    float3 L = ToLight * rsqrt(DistanceSqr);

    // 거리 감쇠 (Point Light와 동일)
    float DistanceAttenuation = 1.0 / (DistanceSqr + 1.0);
    float LightRadiusMask = Square(saturate(
        1 - Square(DistanceSqr * Square(LightData.InvRadius))));

    // 각도 감쇠
    float CosAngle = dot(-L, LightData.Direction);

    // SpotAngles.x = CosOuterAngle
    // SpotAngles.y = 1 / (CosInnerAngle - CosOuterAngle)
    float SpotFalloff = saturate((CosAngle - LightData.SpotAngles.x) * LightData.SpotAngles.y);
    float SpotAttenuation = Square(SpotFalloff);  // 더 부드러운 경계

    return DistanceAttenuation * LightRadiusMask * SpotAttenuation;
}
```

### Spot Light 파라미터

```
                  광원 위치
                     │
                     │  Inner Cone (100% 강도)
                    /│\
                   / │ \
                  /  │  \    Outer Cone (감쇠 영역)
                 /   │   \
                /    │    \
               /     │     \
              /      │      \
             ────────┴────────  (0% 강도)

Inner Cone Angle: 완전 밝음
Outer Cone Angle: 감쇠 시작
Attenuation Radius: 최대 도달 거리
```

| 파라미터 | 설명 |
|----------|------|
| `InnerConeAngle` | 감쇠 없는 중심 각도 |
| `OuterConeAngle` | 총 조명 각도 |
| `AttenuationRadius` | 최대 반경 |
| `SourceRadius` | 소프트 섀도우용 소스 크기 |

---

## 5. Rect Light {#5-rect-light}

### 특징

- **사각형 영역 광원**: 물리적으로 정확한 면광원
- **소프트 섀도우**: 영역 크기에 따른 자연스러운 그림자
- **주요 용도**: 창문, TV 화면, 형광등

### 구조

```cpp
// Rect Light 추가 파라미터
struct FRectLightData
{
    float  SourceWidth;      // 사각형 너비
    float  SourceHeight;     // 사각형 높이
    float  BarnDoorAngle;    // 반 도어 각도
    float  BarnDoorLength;   // 반 도어 길이
    float3 Tangent;          // 탄젠트 벡터
    float3 Bitangent;        // 바이탄젠트 벡터
};
```

### Rect Light 계산

```hlsl
float3 GetRectLightIntegration(
    FDeferredLightData LightData,
    float3 WorldPosition,
    float3 WorldNormal,
    float3 V)
{
    // 사각형의 4개 꼭지점
    float3 LightCenter = LightData.Position;
    float3 LightX = LightData.Tangent * LightData.SourceRadius;
    float3 LightY = cross(LightData.Direction, LightData.Tangent) * LightData.SourceLength;

    float3 Corners[4];
    Corners[0] = LightCenter - LightX - LightY;
    Corners[1] = LightCenter + LightX - LightY;
    Corners[2] = LightCenter + LightX + LightY;
    Corners[3] = LightCenter - LightX + LightY;

    // Most Representative Point (MRP) 기법
    // 또는 LTC (Linearly Transformed Cosines) 기법
    float3 Irradiance = IntegrateRectAreaLight(
        WorldPosition,
        WorldNormal,
        V,
        Corners);

    return Irradiance * LightData.Color;
}
```

### Barn Door

```
        ┌─────────────┐
        │             │
        │  Rect Light │
        │             │
        └─────────────┘
         \           /
          \         /
           \       /    ← Barn Door
            \     /
             \   /
              \ /
               ▼
        광원 출력 영역
```

---

## 6. Area Light {#6-area-light}

### FAreaLight 구조체

```cpp
struct FAreaLight
{
    float3 FalloffColor;           // 감쇠 적용된 색상
    float3 SphereSinAlpha;         // 구체 광원 sin(alpha)
    float3 SphereSinAlphaSoft;     // 소프트 구체
    float  SphereSourceRadius;     // 구체 반경
    float  LineCosSubtended;       // 선 광원
    float  LineLength;             // 선 길이
    bool   bIsRect;                // Rect Light 여부
    FRect  Rect;                   // Rect 데이터
};
```

### 영역 광원 근사

```hlsl
// Sphere Light 근사
float3 SphereAreaLight(
    float3 N, float3 V, float3 L,
    float SphereRadius, float Distance)
{
    // Representative Point 계산
    float3 R = reflect(-V, N);
    float3 CenterToRay = dot(L, R) * R - L;
    float3 ClosestPoint = L + CenterToRay * saturate(
        SphereRadius / length(CenterToRay));

    // 수정된 방향으로 BRDF 계산
    float3 ModifiedL = normalize(ClosestPoint);
    return ModifiedL;
}

// Tube Light (선 광원) 근사
float3 TubeAreaLight(
    float3 N, float3 V, float3 L0, float3 L1)
{
    // 선분에서 가장 가까운 점 찾기
    float3 Ld = L1 - L0;
    float t = saturate(dot(-L0, Ld) / dot(Ld, Ld));
    float3 ClosestPoint = L0 + t * Ld;
    return normalize(ClosestPoint);
}
```

---

## 7. Light Function {#7-light-function}

![Light Function](./images/1617944-20210527125132427-988340219.jpg)
*Light Function 효과*

### 개념

Light Function은 머티리얼을 사용해 광원의 형태를 변형합니다.

```cpp
// Light Function 컴포넌트
class ULightFunctionMaterial
{
    UMaterialInterface* LightFunctionMaterial;  // 변형 머티리얼
    float Scale;                                 // 프로젝션 스케일
    float FadeDistance;                          // 페이드 거리
    float DisabledBrightness;                    // 비활성화 시 밝기
};
```

### 셰이더에서의 적용

```hlsl
float3 ApplyLightFunction(
    FDeferredLightData LightData,
    float3 WorldPosition,
    float3 LightColor)
{
    // Light Function 텍스처 좌표 계산
    float2 LightFunctionUV = ComputeLightFunctionUV(
        WorldPosition,
        LightData.Position,
        LightData.Direction);

    // Light Function 머티리얼 샘플링
    float3 LightFunctionValue = SampleLightFunction(LightFunctionUV);

    return LightColor * LightFunctionValue;
}
```

### 사용 예시

- **창문 그림자**: 창살 패턴 투영
- **나뭇잎 그림자**: 복잡한 그림자 패턴
- **고보 조명**: 무대 조명 효과
- **애니메이션 조명**: 시간에 따른 조명 변화

---

## 8. IES 프로파일 {#8-ies-프로파일}

![IES Profile](./images/1617944-20210527125954790-2014059921.jpg)
*IES Light Profile*

### 개념

IES (Illuminating Engineering Society) 프로파일은 실제 조명 기구의 배광 특성을 정의합니다.

```cpp
// IES 텍스처 에셋
class UIESLightProfile
{
    UTextureLightProfile* IESTexture;  // 1D 또는 2D 배광 텍스처
    float Multiplier;                   // 강도 배율
};
```

### 셰이더에서의 적용

```hlsl
float GetIESAttenuation(
    FDeferredLightData LightData,
    float3 L,
    Texture2D IESTexture)
{
    // 광원 로컬 좌표계로 변환
    float3 LocalL = mul(L, LightData.WorldToLight);

    // 구면 좌표 계산
    float Theta = acos(LocalL.z);                    // 수직 각도
    float Phi = atan2(LocalL.y, LocalL.x);          // 수평 각도

    // IES 텍스처 UV
    float2 IES_UV;
    IES_UV.x = Phi / (2 * PI) + 0.5;
    IES_UV.y = Theta / PI;

    // IES 값 샘플링
    float IESValue = IESTexture.SampleLevel(IESSampler, IES_UV, 0).r;

    return IESValue;
}
```

### IES 파일 구조

```
IESNA:LM-63-2002
[MANUFACTURER]
[LUMCAT]
[LUMINAIRE]
TILT=NONE
1 1000 1 37 1 1 2 -0.5 0.5 0.1
1.0 1.0 1.0
0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 ...  // 각도
0                                                            // 방위각
1.0 0.98 0.95 0.90 0.83 0.75 0.65 0.54 0.42 0.30 ...       // 강도
```

---

## 요약

```
┌─────────────────────────────────────────────────────────────────┐
│                    UE Light Types Summary                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐            │
│   │ Directional │  │    Point    │  │    Spot     │            │
│   │     |||     │  │      *      │  │      V      │            │
│   │     |||     │  │    *   *    │  │     /|\     │            │
│   │     |||     │  │  *       *  │  │    / | \    │            │
│   │     vvv     │  │*           *│  │   /  |  \   │            │
│   └─────────────┘  └─────────────┘  └─────────────┘            │
│   평행 광선         구형 감쇠        원뿔형                     │
│                                                                  │
│   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐            │
│   │    Rect     │  │    Area     │  │ Light Func  │            │
│   │   ┌─────┐   │  │   /───\     │  │   Pattern   │            │
│   │   │█████│   │  │  │     │    │  │   Texture   │            │
│   │   │█████│   │  │   \───/     │  │   Applied   │            │
│   │   └─────┘   │  │             │  │             │            │
│   └─────────────┘  └─────────────┘  └─────────────┘            │
│   사각형 영역       구체/선 광원     머티리얼 기반               │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

| 광원 타입 | 감쇠 | 그림자 | 사용 사례 |
|-----------|------|--------|-----------|
| **Directional** | 없음 | CSM | 태양, 달 |
| **Point** | 역제곱 | Cube Map | 전구, 횃불 |
| **Spot** | 역제곱 + 각도 | Single Map | 손전등, 무대조명 |
| **Rect** | 역제곱 | Soft | 창문, TV |
| **Area** | 거리 기반 | Soft | 소프트 라이팅 |

---

## 참고 자료

- 원문: https://www.cnblogs.com/timlly/p/14817455.html
- "Real-Time Area Lighting" - Karis, Epic Games
- IES Standard: IESNA LM-63
