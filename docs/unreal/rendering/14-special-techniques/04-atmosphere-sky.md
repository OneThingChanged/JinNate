# 대기와 하늘

Sky Atmosphere, Volumetric Cloud, 안개 시스템의 구현과 설정을 다룹니다.

---

## 개요

UE5의 대기 시스템은 물리 기반 산란 모델을 사용하여 사실적인 하늘과 대기 효과를 렌더링합니다.

```
┌─────────────────────────────────────────────────────────────────┐
│                    대기 렌더링 시스템                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│                    ┌─────────────────┐                          │
│                    │  Directional    │                          │
│                    │    Light (Sun)  │                          │
│                    └────────┬────────┘                          │
│                             │                                   │
│                             ▼                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                 Sky Atmosphere                           │   │
│  │  ┌───────────────┐  ┌───────────────┐                   │   │
│  │  │Rayleigh Scatter│ │ Mie Scatter   │                   │   │
│  │  │  (하늘 파랑)   │  │ (태양 주변)   │                   │   │
│  │  └───────────────┘  └───────────────┘                   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                             │                                   │
│                             ▼                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │               Volumetric Cloud                           │   │
│  │         (3D 노이즈 기반 구름 렌더링)                      │   │
│  └─────────────────────────────────────────────────────────┘   │
│                             │                                   │
│                             ▼                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              Exponential Height Fog                      │   │
│  │          (지면 근처 안개, 볼류메트릭 포그)                │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Sky Atmosphere

### 물리적 원리

```
┌─────────────────────────────────────────────────────────────────┐
│                    대기 산란 원리                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Rayleigh Scattering (레일리 산란):                            │
│  - 파장보다 작은 입자에 의한 산란                              │
│  - 짧은 파장(파랑)이 더 많이 산란                              │
│  - 하늘이 파란 이유                                            │
│                                                                 │
│       ☀ ────▶ 대기 ────▶ 파랑 산란 ↗↙↖↘                       │
│                          빨강 직진 ─────▶                       │
│                                                                 │
│  Mie Scattering (미 산란):                                     │
│  - 파장과 비슷한 크기의 입자에 의한 산란                       │
│  - 모든 파장이 비슷하게 산란 (흰색)                            │
│  - 태양 주변의 밝은 후광                                       │
│                                                                 │
│  해질녘/새벽:                                                  │
│  - 빛이 더 긴 경로를 통과                                      │
│  - 파란빛은 모두 산란되고 빨간빛만 남음                        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 컴포넌트 설정

```cpp
// Sky Atmosphere 생성
ASkyAtmosphere* SkyAtmo = World->SpawnActor<ASkyAtmosphere>();

// 기본 파라미터
SkyAtmo->AtmosphereHeight = 60.0f;  // km (대기 두께)
SkyAtmo->GroundRadius = 6360.0f;    // km (지구 반경)

// Rayleigh 산란 (하늘 색상)
SkyAtmo->RayleighScattering = FLinearColor(0.0331f, 0.0612f, 0.1254f);
SkyAtmo->RayleighExponentialDistribution = 8.0f;  // 고도에 따른 밀도 감소

// Mie 산란 (태양 주변 후광)
SkyAtmo->MieScattering = FLinearColor(0.004f, 0.004f, 0.004f);
SkyAtmo->MieExponentialDistribution = 1.2f;
SkyAtmo->MieAnisotropy = 0.8f;  // 전방 산란 강도

// 흡수 (오존층 등)
SkyAtmo->AbsorptionScale = 1.0f;
SkyAtmo->AbsorptionTintColor = FLinearColor(0.067f, 0.115f, 0.0f);
```

### 다중 대기 광원

```cpp
// 두 번째 광원 (달)
DirectionalLight->bAtmosphereSunLightEnabled = true;
DirectionalLight->AtmosphereSunLightIndex = 1;  // 0=태양, 1=달

// 달의 약한 빛
MoonLight->Intensity = 0.1f;
MoonLight->LightSourceAngle = 0.5f;  // 작은 광원
```

---

## Volumetric Cloud

### 구름 레이어 설정

```cpp
// Volumetric Cloud 생성
AVolumetricCloud* VCloud = World->SpawnActor<AVolumetricCloud>();

// 레이어 설정
VCloud->LayerBottomAltitude = 5.0f;   // km (구름 바닥)
VCloud->LayerHeight = 10.0f;          // km (구름 두께)

// 추적 설정
VCloud->TracingStartMaxDistance = 350.0f;  // km (최대 거리)
VCloud->TracingMaxDistance = 50.0f;
VCloud->ShadowTracingDistance = 15.0f;

// 품질 설정
VCloud->ViewSampleCountScale = 1.0f;
VCloud->ReflectionSampleCountScale = 0.25f;  // 반사는 낮은 품질
VCloud->ShadowViewSampleCountScale = 1.0f;
```

### 구름 머티리얼

```cpp
// 볼류메트릭 구름 머티리얼 구조
// - 밀도 함수
// - 라이팅
// - 색상

// 노이즈 기반 밀도
float CloudDensity(float3 WorldPos)
{
    float BaseNoise = Texture3DSample(CloudNoiseTexture, WorldPos * NoiseScale);
    float DetailNoise = Texture3DSample(DetailNoiseTexture, WorldPos * DetailScale);

    // 높이 기반 마스크
    float HeightFraction = (WorldPos.z - CloudBottom) / CloudHeight;
    float HeightMask = HeightGradient(HeightFraction);

    // 커버리지
    float Coverage = CloudCoverageTexture.Sample(WorldPos.xy * CoverageScale);

    return saturate(BaseNoise * DetailNoise * HeightMask - (1 - Coverage));
}
```

### 구름 타입

```
┌─────────────────────────────────────────────────────────────────┐
│                     구름 타입과 고도                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  고도 (km)                                                      │
│     │                                                           │
│  12 ┤  ═══════════════════════════  권운 (Cirrus)              │
│     │          얇고 섬유질                                      │
│   8 ┤  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓  고적운 (Altocumulus)       │
│     │          중간 높이의 뭉게구름                             │
│   4 ┤  ████████████████████████████  적운 (Cumulus)            │
│     │          낮은 뭉게구름                                    │
│   2 ┤  ░░░░░░░░░░░░░░░░░░░░░░░░░░░  층운 (Stratus)             │
│     │          낮은 안개 같은 구름                              │
│   0 ┴────────────────────────────────────────────               │
│                                                                 │
│  UE에서: 여러 레이어로 다양한 구름 타입 표현 가능              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Exponential Height Fog

### 기본 설정

```cpp
// Height Fog 생성
AExponentialHeightFog* Fog = World->SpawnActor<AExponentialHeightFog>();

// 기본 파라미터
Fog->FogDensity = 0.02f;           // 밀도
Fog->FogHeightFalloff = 0.2f;      // 높이에 따른 감소율
Fog->FogMaxOpacity = 1.0f;         // 최대 불투명도

// 색상 설정
Fog->FogInscatteringColor = FLinearColor(0.5f, 0.6f, 0.7f);  // 안개 색상
Fog->DirectionalInscatteringColor = FLinearColor(1.0f, 0.9f, 0.7f);  // 태양 방향 색상

// 거리 설정
Fog->FogStartDistance = 0.0f;      // 시작 거리
Fog->FogCutoffDistance = 0.0f;     // 컷오프 (0 = 무한)
```

### 두 번째 안개 레이어

```cpp
// 이중 레이어 안개 (예: 지면 안개 + 대기 안개)
Fog->SecondFogData.FogDensity = 0.1f;
Fog->SecondFogData.FogHeightFalloff = 2.0f;  // 빠른 감소 (지면 근처만)
Fog->SecondFogData.FogHeightOffset = -500.0f;
```

### 볼류메트릭 포그 연동

```cpp
// 볼류메트릭 포그 활성화
Fog->bEnableVolumetricFog = true;

// 볼류메트릭 설정
Fog->VolumetricFogScatteringDistribution = 0.2f;  // 위상 함수 (g)
Fog->VolumetricFogAlbedo = FLinearColor(1.0f, 1.0f, 1.0f);
Fog->VolumetricFogEmissive = FLinearColor(0.0f, 0.0f, 0.0f);
Fog->VolumetricFogExtinctionScale = 1.0f;
Fog->VolumetricFogDistance = 6000.0f;
```

---

## Sky Light

### 환경 조명

```cpp
// Sky Light 설정
ASkyLight* SkyLight = World->SpawnActor<ASkyLight>();

// 캡처 방식
SkyLight->SourceType = SLS_CapturedScene;  // 또는 SLS_SpecifiedCubemap

// 품질 설정
SkyLight->Intensity = 1.0f;
SkyLight->bLowerHemisphereIsBlack = false;
SkyLight->LowerHemisphereColor = FLinearColor(0.1f, 0.1f, 0.12f);

// 실시간 캡처
SkyLight->bRealTimeCapture = true;  // 동적 환경에서 필요
```

### 큐브맵 캡처

```cpp
// 씬 캡처로 Sky Light 업데이트
SkyLight->RecaptureScene();

// 또는 지정된 큐브맵 사용
SkyLight->SourceType = SLS_SpecifiedCubemap;
SkyLight->Cubemap = MyCubemapTexture;
```

---

## 시간대 변화

### 태양 위치 시스템

```cpp
// BP_SunSky 같은 블루프린트 구현
UCLASS()
class ASunSky : public AActor
{
    UPROPERTY()
    ADirectionalLight* SunLight;

    UPROPERTY()
    ASkyAtmosphere* SkyAtmosphere;

    UPROPERTY(EditAnywhere)
    float TimeOfDay = 12.0f;  // 0-24

    void UpdateSunPosition()
    {
        // 시간을 각도로 변환
        float SunAngle = (TimeOfDay - 6.0f) / 24.0f * 360.0f;

        FRotator SunRotation;
        SunRotation.Pitch = -SunAngle;  // 태양 고도
        SunRotation.Yaw = 0.0f;         // 방위각 (계절에 따라 변경)

        SunLight->SetActorRotation(SunRotation);
    }
};
```

### 색상 변화

```cpp
// 시간대별 색상 설정
void UpdateAtmosphereColors(float TimeOfDay)
{
    // 해질녘 (황혼)
    if (TimeOfDay > 17.0f && TimeOfDay < 20.0f)
    {
        float Sunset = (TimeOfDay - 17.0f) / 3.0f;
        SunLight->SetLightColor(FLinearColor::LerpUsingHSV(
            FLinearColor(1.0f, 0.95f, 0.9f),   // 낮
            FLinearColor(1.0f, 0.4f, 0.2f),    // 해질녘
            Sunset
        ));
    }
}
```

---

## 성능 최적화

### Sky Atmosphere

```cpp
// LUT 해상도 조절
r.SkyAtmosphere.TransmittanceLUT.UseSmallFormat = 1
r.SkyAtmosphere.FastSkyLUT = 1

// 멀티 스캐터링 품질
r.SkyAtmosphere.AerialPerspectiveLUT.FastApplyOnOpaque = 1
```

### Volumetric Cloud

```cpp
// 샘플 수 조절
r.VolumetricCloud.ViewRaySampleCountScale = 0.5
r.VolumetricCloud.ReflectionRaySampleCountScale = 0.25
r.VolumetricCloud.ShadowRaySampleCountScale = 0.5

// 해상도 조절
r.VolumetricCloud.SkyAO.DownSampleLevel = 2
```

### 비용 분석

```
┌─────────────────────────────────────────────────────────────────┐
│                    대기 렌더링 비용 (1080p)                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  컴포넌트                      GPU 시간                         │
│  ────────────────────────────  ─────────────────────────────── │
│  Sky Atmosphere LUT            ~0.2-0.5 ms                      │
│  Sky Atmosphere Rendering      ~0.3-0.5 ms                      │
│  Volumetric Cloud (High)       ~2.0-4.0 ms                      │
│  Volumetric Cloud (Medium)     ~1.0-2.0 ms                      │
│  Volumetric Cloud (Low)        ~0.5-1.0 ms                      │
│  Height Fog                    ~0.1-0.2 ms                      │
│  Volumetric Fog                ~1.0-3.0 ms                      │
│                                                                 │
│  총합 (High Quality):          ~4.0-8.0 ms                     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 콘솔 명령

```cpp
// Sky Atmosphere
r.SkyAtmosphere 1
r.SkyAtmosphere.FastSkyLUT 1

// Volumetric Cloud
r.VolumetricCloud 1
r.VolumetricCloud.ViewRaySampleCountScale 1.0

// Height Fog
r.Fog 1
r.VolumetricFog 1
r.VolumetricFog.GridPixelSize 8

// 디버그
ShowFlag.Atmosphere 1
ShowFlag.Fog 1
```

---

## 요약

| 시스템 | 역할 | 비용 |
|--------|------|------|
| Sky Atmosphere | 물리 기반 하늘 | 낮음 |
| Volumetric Cloud | 3D 구름 | 높음 |
| Height Fog | 지면 안개 | 매우 낮음 |
| Volumetric Fog | 3D 안개 | 중간-높음 |
| Sky Light | 환경 조명 | 낮음 |

---

## 참고 자료

- [Sky Atmosphere](https://docs.unrealengine.com/sky-atmosphere/)
- [Volumetric Cloud](https://docs.unrealengine.com/volumetric-cloud/)
- [Atmospheric Scattering](https://seblagarde.wordpress.com/atmospheric-scattering/)
