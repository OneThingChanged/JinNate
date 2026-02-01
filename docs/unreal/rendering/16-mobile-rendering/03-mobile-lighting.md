# 모바일 라이팅

모바일 플랫폼에서의 라이팅 시스템과 그림자 구현을 분석합니다.

---

## Forward 라이팅

### 라이트 처리 방식

```
┌─────────────────────────────────────────────────────────────────┐
│                  Mobile Forward Lighting                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Deferred (Desktop)                 Forward (Mobile)            │
│  ┌─────────────────────┐           ┌─────────────────────┐     │
│  │                     │           │                     │     │
│  │ Pass 1: G-Buffer    │           │ Single Pass:        │     │
│  │ Pass 2: Lighting    │           │  • Geometry         │     │
│  │ Pass 3: ...         │           │  • All Lights       │     │
│  │                     │           │  • Shadows          │     │
│  │ 무제한 라이트       │           │  • Output           │     │
│  └─────────────────────┘           └─────────────────────┘     │
│                                                                 │
│  Forward 라이트 제한:                                            │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  ┌────────────────────────────────────────────────────┐ │   │
│  │  │ Directional Light: 1개 (CSM 그림자)               │ │   │
│  │  │ Point/Spot Lights: 최대 4개 (동적)                 │ │   │
│  │  │ Sky Light: 1개 (환경광)                            │ │   │
│  │  └────────────────────────────────────────────────────┘ │   │
│  │                                                          │   │
│  │  라이트 선택 기준:                                       │   │
│  │  • 밝기 (Intensity)                                     │   │
│  │  • 거리 (Distance to Object)                           │   │
│  │  • 그림자 캐스팅 여부                                    │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 라이트 패킹

```cpp
// 모바일 라이트 유니폼 버퍼
struct FMobileDirectionalLightData
{
    FVector4 DirectionalLightDirection;
    FVector4 DirectionalLightColor;
    FVector4 DirectionalLightShadowTransition;
};

struct FMobilePointLightData
{
    // 최대 4개 라이트 패킹
    FVector4 LightPositionAndInvRadius[MAX_MOBILE_POINT_LIGHTS];
    FVector4 LightColorAndFalloff[MAX_MOBILE_POINT_LIGHTS];
    FVector4 SpotLightAngles[MAX_MOBILE_POINT_LIGHTS];
};

// 셰이더에서 라이트 루프
half3 MobilePointLightLoop(
    half3 WorldPos,
    half3 N,
    half3 V,
    half3 DiffuseColor,
    half Roughness)
{
    half3 TotalLight = 0;

    UNROLL
    for (int i = 0; i < NUM_MOBILE_POINT_LIGHTS; i++)
    {
        float3 LightPos = PointLights[i].Position;
        float InvRadius = PointLights[i].InvRadius;
        half3 LightColor = PointLights[i].Color;

        float3 L = LightPos - WorldPos;
        float DistSq = dot(L, L);
        L = normalize(L);

        // 감쇠 계산
        float Attenuation = Square(saturate(1 - Square(DistSq * InvRadius * InvRadius)));

        // 라이팅
        half NoL = saturate(dot(N, L));
        TotalLight += DiffuseColor * LightColor * NoL * Attenuation;
    }

    return TotalLight;
}
```

---

## 모바일 그림자

### Cascaded Shadow Maps

```
┌─────────────────────────────────────────────────────────────────┐
│                  Mobile CSM 구조                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Desktop CSM             Mobile CSM (최적화)                    │
│  ┌─────────────────┐    ┌─────────────────┐                    │
│  │ 4 캐스케이드    │    │ 2 캐스케이드    │                    │
│  │ ┌─┬─┬─┬─┐       │    │ ┌───┬───┐       │                    │
│  │ │0│1│2│3│       │    │ │ 0 │ 1 │       │                    │
│  │ └─┴─┴─┴─┘       │    │ └───┴───┘       │                    │
│  │ 2K × 4 = 8K    │    │ 1K × 2 = 2K     │                    │
│  └─────────────────┘    └─────────────────┘                    │
│                                                                 │
│  설정:                                                          │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ r.Mobile.Shadow.MaxCSMResolution=1024                   │   │
│  │ r.Mobile.Shadow.CSMCacheEnabled=1                       │   │
│  │ r.Shadow.MaxCSMCascades=2                               │   │
│  │ r.Shadow.DistanceScale=0.5  (거리 축소)                 │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  캐스케이드 분할:                                                │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  Camera ────●────────────────────────────────────────▶  │   │
│  │         │◀── Cascade 0 ──▶│◀────── Cascade 1 ──────▶│   │   │
│  │         0m               15m                     50m    │   │
│  │                                                          │   │
│  │  • 가까운 영역: 높은 해상도                              │   │
│  │  • 먼 영역: 낮은 해상도                                  │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 그림자 샘플링

```hlsl
// 모바일 그림자 샘플링 (최적화)
half MobileShadow(float3 WorldPos, float2 ScreenUV)
{
    // 캐스케이드 선택
    int CascadeIndex = SelectCascade(WorldPos);

    // 그림자 좌표 계산
    float4 ShadowCoord = mul(float4(WorldPos, 1), ShadowMatrix[CascadeIndex]);
    ShadowCoord.xyz /= ShadowCoord.w;

    // 간단한 PCF (2x2)
    half Shadow = 0;
    float2 ShadowTexelSize = 1.0 / ShadowMapSize;

    UNROLL
    for (int y = -1; y <= 1; y += 2)
    {
        UNROLL
        for (int x = -1; x <= 1; x += 2)
        {
            float2 Offset = float2(x, y) * ShadowTexelSize * 0.5;
            float Depth = ShadowMap.Sample(ShadowSampler, ShadowCoord.xy + Offset).r;
            Shadow += (ShadowCoord.z <= Depth) ? 1.0 : 0.0;
        }
    }

    return Shadow * 0.25;
}

// 더 간단한 버전 (하드 그림자)
half MobileHardShadow(float4 ShadowCoord)
{
    float Depth = ShadowMap.Sample(ShadowSampler, ShadowCoord.xy).r;
    return (ShadowCoord.z <= Depth) ? 1.0 : 0.0;
}
```

### Modulated Shadows

```
┌─────────────────────────────────────────────────────────────────┐
│                  Modulated Shadows                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  일반 그림자:                                                    │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  Light Color × Shadow → Final Color                     │   │
│  │  (1.0, 1.0, 0.8) × 0.3 = (0.3, 0.3, 0.24)              │   │
│  │                                                          │   │
│  │  특징: 자체 그림자 지원, 정확한 라이팅                   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Modulated Shadow (저비용):                                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  Final = BaseColor × ShadowColor                        │   │
│  │  Final = (1.0, 0.8, 0.6) × (0.5, 0.5, 0.6)             │   │
│  │        = (0.5, 0.4, 0.36)                               │   │
│  │                                                          │   │
│  │  특징:                                                   │   │
│  │  • 자체 그림자 없음                                      │   │
│  │  • 별도 그림자 패스 없음                                 │   │
│  │  • 그림자 색상 커스터마이즈 가능                         │   │
│  │  • 반투명 그림자 가능                                    │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  설정:                                                          │
│  Light → Mobility → Stationary                                 │
│  Light → Cast Modulated Shadows = True                         │
│  Light → Modulated Shadow Color = (0.5, 0.5, 0.6)              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 간접광 (GI)

### 모바일 GI 옵션

```
┌─────────────────────────────────────────────────────────────────┐
│                  Mobile GI 옵션                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Lightmaps (정적)                                            │
│     ┌─────────────────────────────────────────────────────┐    │
│     │ • 사전 베이크된 조명                                  │    │
│     │ • 최고 품질                                           │    │
│     │ • 메모리 사용                                         │    │
│     │ • 동적 오브젝트에 미적용                              │    │
│     └─────────────────────────────────────────────────────┘    │
│                                                                 │
│  2. Indirect Lighting Cache (ILC)                               │
│     ┌─────────────────────────────────────────────────────┐    │
│     │ • 동적 오브젝트용 간접광                              │    │
│     │ • 볼륨 기반 샘플링                                    │    │
│     │ • SH 라이팅                                           │    │
│     └─────────────────────────────────────────────────────┘    │
│                                                                 │
│  3. Sky Light                                                   │
│     ┌─────────────────────────────────────────────────────┐    │
│     │ • 환경 큐브맵 기반                                    │    │
│     │ • 단순 앰비언트                                       │    │
│     │ • 저비용                                              │    │
│     └─────────────────────────────────────────────────────┘    │
│                                                                 │
│  4. 없음 (Fully Dynamic)                                        │
│     ┌─────────────────────────────────────────────────────┐    │
│     │ • 직접광만                                            │    │
│     │ • 최저 비용                                           │    │
│     │ • 어두운 그림자 영역                                  │    │
│     └─────────────────────────────────────────────────────┘    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Lightmap 최적화

```cpp
// 라이트맵 설정
// World Settings → Lightmass

// 모바일 권장 설정
Lightmap Resolution = 32-64       // 낮은 해상도
Indirect Lighting Quality = 0.5   // 빠른 베이킹
Indirect Lighting Smoothness = 0.8

// 라이트맵 UV 압축
// Static Mesh Editor → LOD Settings
Min Lightmap Resolution = 32
Lightmap Coordinate Index = 1

// 모바일 라이트맵 샘플링
half3 SampleLightmap(float2 LightmapUV)
{
    // 라이트맵 텍스처 (RGBM 인코딩)
    half4 Encoded = LightmapTexture.Sample(LightmapSampler, LightmapUV);

    // RGBM 디코딩
    half3 Lightmap = Encoded.rgb * Encoded.a * 16.0;

    return Lightmap;
}
```

---

## 반사

### 모바일 반사 옵션

```
┌─────────────────────────────────────────────────────────────────┐
│                  Mobile Reflection Options                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Reflection Captures (권장)                                   │
│     ┌─────────────────────────────────────────────────────┐    │
│     │                                                      │    │
│     │  ┌───────────────┐                                  │    │
│     │  │ Sphere/Box    │  • 사전 캡처된 큐브맵            │    │
│     │  │  Capture      │  • 저비용 샘플링                  │    │
│     │  │     ◯         │  • 정적 환경만                    │    │
│     │  └───────────────┘                                  │    │
│     │                                                      │    │
│     └─────────────────────────────────────────────────────┘    │
│                                                                 │
│  2. Screen Space Reflections (제한적)                           │
│     ┌─────────────────────────────────────────────────────┐    │
│     │ • 높은 비용                                          │    │
│     │ • 화면 밖 미반영                                     │    │
│     │ • 고사양 모바일만                                    │    │
│     │ • r.Mobile.EnableSSR=1                              │    │
│     └─────────────────────────────────────────────────────┘    │
│                                                                 │
│  3. Planar Reflections (특수 용도)                              │
│     ┌─────────────────────────────────────────────────────┐    │
│     │ • 평면 거울 효과                                     │    │
│     │ • 추가 렌더 패스                                     │    │
│     │ • 물 표면 등에 사용                                  │    │
│     │ • 매우 비쌈                                          │    │
│     └─────────────────────────────────────────────────────┘    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 반사 캡처 샘플링

```hlsl
// 모바일 반사 샘플링
half3 MobileReflection(
    half3 WorldPos,
    half3 ReflectionVector,
    half Roughness)
{
    // 가장 가까운 Reflection Capture 찾기
    // (보통 2개까지 블렌딩)

    // 러프니스를 밉 레벨로 변환
    float MipLevel = Roughness * MaxMipLevel;

    // 큐브맵 샘플링
    half4 Encoded = ReflectionCubemap.SampleLevel(
        ReflectionSampler,
        ReflectionVector,
        MipLevel);

    // RGBM 디코딩
    return Encoded.rgb * Encoded.a * 16.0;
}
```

---

## 스페셜 라이팅

### Capsule Shadows

```
┌─────────────────────────────────────────────────────────────────┐
│                  Capsule Shadows                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  기존 그림자            Capsule Shadow                          │
│  ┌─────────────┐       ┌─────────────┐                         │
│  │             │       │             │                         │
│  │  ░░░░░░░░░ │       │  ┌───────┐  │                         │
│  │  ░ Shadow ░ │       │  │Capsule│  │                         │
│  │  ░░░░░░░░░ │       │  └───────┘  │                         │
│  │             │       │      │      │                         │
│  │  Mesh-based │       │  Approx.   │                         │
│  │  고비용     │       │  저비용     │                         │
│  └─────────────┘       └─────────────┘                         │
│                                                                 │
│  설정:                                                          │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Skeletal Mesh → Details → Capsule Direct Shadow        │   │
│  │ Skeletal Mesh → Details → Capsule Indirect Shadow      │   │
│  │                                                          │   │
│  │ 장점:                                                    │   │
│  │ • 캐릭터 전용 저비용 그림자                              │   │
│  │ • 부드러운 소프트 섀도우                                 │   │
│  │ • 간접광에도 적용 가능                                   │   │
│  │                                                          │   │
│  │ 단점:                                                    │   │
│  │ • 근사값 (정확하지 않음)                                 │   │
│  │ • 캡슐 정의 필요                                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Distance Field Shadows

```cpp
// 모바일 Distance Field Shadows
// 원거리 그림자에 효과적

// 설정
r.Mobile.AllowDistanceFieldShadows=1
r.DistanceFieldAO.AOSpecularOcclusionMode=1

// 장점:
// - CSM 대체 (원거리)
// - 부드러운 소프트 섀도우
// - 대규모 오브젝트에 효과적

// 단점:
// - 메모리 사용
// - 빌드 시간
// - 작은 디테일 손실
```

---

## 성능 가이드

### 라이팅 최적화 체크리스트

```
┌─────────────────────────────────────────────────────────────────┐
│                  Mobile Lighting 최적화                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  라이트 설정                                                     │
│  □ 동적 라이트 최소화 (4개 이하)                                │
│  □ Static/Stationary 라이트 선호                                │
│  □ 그림자 캐스팅 라이트 제한                                    │
│  □ 라이트 반경 최소화                                           │
│                                                                 │
│  그림자 설정                                                     │
│  □ CSM 캐스케이드 2개 이하                                      │
│  □ 그림자 해상도 1024 이하                                      │
│  □ 그림자 거리 축소                                             │
│  □ Modulated Shadow 검토                                       │
│                                                                 │
│  GI 설정                                                        │
│  □ 라이트맵 해상도 최적화                                       │
│  □ 불필요한 ILC 비활성화                                        │
│  □ Sky Light 사용                                              │
│                                                                 │
│  반사 설정                                                       │
│  □ Reflection Capture 사용                                     │
│  □ SSR 비활성화 (저사양)                                        │
│  □ Roughness 활용 (밉맵 레벨)                                   │
│                                                                 │
│  머티리얼 설정                                                   │
│  □ Fully Rough 활용                                            │
│  □ 단순 라이팅 모델                                             │
│  □ 스페큘러 비활성화 (필요시)                                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 다음 단계

- [모바일 텍스처](04-mobile-textures.md)에서 텍스처 압축과 최적화를 학습합니다.
