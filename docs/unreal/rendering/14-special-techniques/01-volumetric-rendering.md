# 볼류메트릭 렌더링

볼류메트릭 포그, God Ray, 라이트 샤프트 등 볼류메트릭 효과의 구현 원리를 다룹니다.

---

## 개요

볼류메트릭 렌더링은 공기 중의 입자에 의한 빛의 산란을 시뮬레이션하여 깊이감과 분위기를 만들어냅니다.

```
┌─────────────────────────────────────────────────────────────────┐
│                   볼류메트릭 렌더링 원리                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  빛의 경로:                                                     │
│                                                                 │
│     광원 ─────────▶ 매질 (안개/먼지) ─────────▶ 카메라         │
│                          │                                      │
│                          │ 산란                                 │
│                          ▼                                      │
│                    ┌───────────┐                               │
│                    │ In-Scatter│ ◀── 매질로 들어오는 빛        │
│                    │ Out-Scatter│ ◀── 매질에서 빠져나가는 빛   │
│                    │ Absorption│ ◀── 흡수되는 빛               │
│                    └───────────┘                               │
│                                                                 │
│  Beer-Lambert 법칙:                                             │
│  Transmittance = exp(-σ × distance)                            │
│  σ = 소멸 계수 (extinction coefficient)                        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Volumetric Fog

### 아키텍처

```
┌─────────────────────────────────────────────────────────────────┐
│                Volumetric Fog 파이프라인                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Froxel (Frustum + Voxel) 볼륨 생성                         │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │         Near ◀────────────────────────────▶ Far          │  │
│  │  ┌────┬────┬────┬────┬────┬────┬────┬────┐              │  │
│  │  │    │    │    │    │    │    │    │    │ ◀─ Z Slice   │  │
│  │  ├────┼────┼────┼────┼────┼────┼────┼────┤              │  │
│  │  │    │    │    │    │    │    │    │    │              │  │
│  │  └────┴────┴────┴────┴────┴────┴────┴────┘              │  │
│  │         (지수적 깊이 분포)                                 │  │
│  └───────────────────────────────────────────────────────────┘  │
│                              │                                  │
│                              ▼                                  │
│  2. 밀도/산란 계산                                              │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  각 Froxel에서:                                           │  │
│  │  - 높이 기반 밀도                                         │  │
│  │  - 노이즈 밀도                                            │  │
│  │  - 광원 기여도 (섀도우 맵 샘플링)                         │  │
│  └───────────────────────────────────────────────────────────┘  │
│                              │                                  │
│                              ▼                                  │
│  3. Ray Marching 적분                                          │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  시선을 따라 전면→후면 누적                                │  │
│  │  In-Scattering + Transmittance                            │  │
│  └───────────────────────────────────────────────────────────┘  │
│                              │                                  │
│                              ▼                                  │
│  4. 씬 컬러와 합성                                              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 활성화 및 설정

```cpp
// Exponential Height Fog 컴포넌트에서 활성화
ExponentialHeightFog->bEnableVolumetricFog = true;

// 전역 설정
r.VolumetricFog = 1
r.VolumetricFog.GridPixelSize = 8      // XY 해상도 (낮을수록 선명)
r.VolumetricFog.GridSizeZ = 64         // Z 슬라이스 수
r.VolumetricFog.HistoryWeight = 0.9    // 템포럴 안정화

// 거리 설정
ExponentialHeightFog->VolumetricFogDistance = 6000.0f;
ExponentialHeightFog->VolumetricFogStartDistance = 0.0f;
```

### 밀도 함수

```cpp
// 높이 기반 밀도
FogDensity = FogDensity * exp(-FogHeightFalloff * (Z - FogHeight))

// 구형 볼륨 (Local Volumetric Fog)
LocalVolumetricFog->Extent = FVector(500, 500, 500);
LocalVolumetricFog->FogDensity = 1.0f;
LocalVolumetricFog->HeightFogOffset = 0.0f;
```

---

## 라이트 산란

### 광원별 기여

```cpp
// Directional Light
DirectionalLight->bUseAtmosphericFog = true;
DirectionalLight->VolumetricScatteringIntensity = 1.0f;

// Point/Spot Light
PointLight->VolumetricScatteringIntensity = 1.0f;
// 자동으로 Volumetric Fog에 기여

// 그림자 영향
r.VolumetricFog.HistoryMissSupersampleCount = 4  // 품질
```

### 위상 함수 (Phase Function)

```
┌─────────────────────────────────────────────────────────────────┐
│                     산란 위상 함수                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Henyey-Greenstein Phase Function:                             │
│                                                                 │
│         1 - g²                                                  │
│  p(θ) = ─────────────────────────                              │
│         4π(1 + g² - 2g·cos(θ))^(3/2)                           │
│                                                                 │
│  g = 비대칭 파라미터 (-1 ~ 1)                                   │
│  - g > 0: 전방 산란 (Forward Scatter)                          │
│  - g < 0: 후방 산란 (Back Scatter)                             │
│  - g = 0: 등방성 (Isotropic)                                    │
│                                                                 │
│       g = -0.5        g = 0          g = 0.5                   │
│          ◀              ●              ▶                       │
│       후방 산란       등방성         전방 산란                  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

```cpp
// UE에서 설정
ExponentialHeightFog->VolumetricFogScatteringDistribution = 0.2f;  // g 값
// 양수 = 전방 산란 (태양 주변 밝음)
```

---

## God Ray (Light Shaft)

### 스크린 스페이스 방식

```cpp
// Light Shaft (스크린 스페이스)
DirectionalLight->bEnableLightShaftOcclusion = true;
DirectionalLight->bEnableLightShaftBloom = true;
DirectionalLight->OcclusionMaskDarkness = 0.3f;
DirectionalLight->OcclusionDepthRange = 10000.0f;
DirectionalLight->BloomScale = 1.0f;
DirectionalLight->BloomThreshold = 0.1f;
```

```
┌─────────────────────────────────────────────────────────────────┐
│                 Light Shaft 알고리즘                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. 오클루전 마스크 생성                                        │
│     - 광원 위치에서 깊이 비교                                   │
│     - 가려진 픽셀 = 어둡게                                      │
│                                                                 │
│  2. 방사형 블러 (Radial Blur)                                  │
│     ┌───────────────────────────────────────────┐               │
│     │              ☀ (광원 위치)                │               │
│     │            ↗ ↑ ↖                         │               │
│     │          ↗   │   ↖                       │               │
│     │        ↗     │     ↖                     │               │
│     │      각 픽셀에서 광원 방향으로 샘플링      │               │
│     └───────────────────────────────────────────┘               │
│                                                                 │
│  3. 씬과 합성 (Additive Blend)                                 │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 볼류메트릭 방식 vs 스크린 스페이스

| 방식 | 장점 | 단점 |
|------|------|------|
| Volumetric Fog | 3D 정확성, 물리 기반 | 비용 높음 |
| Screen Space | 빠름, 저비용 | 근사치, 아티팩트 |

---

## 로컬 볼류메트릭 포그

### 볼륨 액터

```cpp
// Local Volumetric Fog Volume
// 특정 영역에만 안개 적용

UPROPERTY()
ULocalVolumetricFogVolume* FogVolume;

FogVolume->Extent = FVector(1000, 1000, 500);
FogVolume->FogDensity = 5.0f;
FogVolume->FogAlbedo = FLinearColor(0.9f, 0.9f, 1.0f);
FogVolume->FogEmissive = FLinearColor::Black;
```

### 노이즈 기반 변형

```cpp
// 노이즈로 밀도 변형 (움직이는 안개)
FogVolume->bOverrideGlobalFogDensity = true;
FogVolume->MaterialInstance;  // 노이즈 머티리얼 사용
```

```hlsl
// 볼류메트릭 머티리얼 셰이더
float Density = FogDensity;

// 3D 노이즈로 변형
float3 NoiseUV = WorldPosition * NoiseScale + Time * WindDirection;
float NoiseValue = TextureSample(NoiseTexture, NoiseUV).r;
Density *= NoiseValue;

return Density;
```

---

## 최적화

### 해상도 설정

```cpp
// 볼륨 해상도 조절
r.VolumetricFog.GridPixelSize = 8    // 8, 16, 32 (높을수록 저품질/빠름)
r.VolumetricFog.GridSizeZ = 64       // 32, 64, 128

// 거리 제한
ExponentialHeightFog->VolumetricFogDistance = 6000.0f;  // 최대 거리

// 템포럴 리프로젝션
r.VolumetricFog.HistoryWeight = 0.9  // 0.9 = 90% 이전 프레임 재사용
```

### 플랫폼별 설정

```cpp
// 모바일: 볼류메트릭 비활성화, 단순 포그 사용
#if PLATFORM_MOBILE
r.VolumetricFog = 0
r.Fog.MaxStartDistance = 1000
#endif

// 콘솔: 해상도 조절
#if PLATFORM_CONSOLE
r.VolumetricFog.GridPixelSize = 16
r.VolumetricFog.GridSizeZ = 32
#endif
```

### 비용 분석

```
┌─────────────────────────────────────────────────────────────────┐
│               Volumetric Fog 비용 분석 (1080p)                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  설정                          GPU 시간 (대략)                  │
│  ──────────────────────────   ───────────────────────────────  │
│  GridPixelSize=8, Z=64        ~2.0-3.0 ms                      │
│  GridPixelSize=8, Z=128       ~3.0-4.0 ms                      │
│  GridPixelSize=16, Z=64       ~1.0-1.5 ms                      │
│  GridPixelSize=16, Z=32       ~0.5-1.0 ms                      │
│                                                                 │
│  추가 비용:                                                     │
│  - 로컬 볼륨당: ~0.1-0.2 ms                                    │
│  - 동적 광원당: ~0.1-0.3 ms                                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 커스텀 구현

### 레이 마칭 셰이더

```hlsl
// 간단한 볼류메트릭 포그 레이 마칭
float4 RayMarchFog(float3 RayStart, float3 RayEnd, int Steps)
{
    float3 RayDir = RayEnd - RayStart;
    float RayLength = length(RayDir);
    RayDir /= RayLength;

    float StepSize = RayLength / Steps;
    float3 Position = RayStart;

    float Transmittance = 1.0f;
    float3 InScatter = 0;

    for (int i = 0; i < Steps; i++)
    {
        // 밀도 샘플링
        float Density = SampleFogDensity(Position);

        // 광원 기여도
        float3 LightColor = SampleLightContribution(Position);

        // 산란 누적
        float Extinction = Density * ExtinctionCoeff * StepSize;
        InScatter += LightColor * Transmittance * (1 - exp(-Extinction));
        Transmittance *= exp(-Extinction);

        Position += RayDir * StepSize;

        // 조기 종료
        if (Transmittance < 0.01f)
            break;
    }

    return float4(InScatter, Transmittance);
}
```

---

## 콘솔 명령 요약

```cpp
// 활성화
r.VolumetricFog 1

// 품질 조절
r.VolumetricFog.GridPixelSize 8
r.VolumetricFog.GridSizeZ 64
r.VolumetricFog.HistoryWeight 0.9

// 디버그
r.VolumetricFog.Visualize 1

// Light Shaft
r.LightShaftDownSampleFactor 2
r.LightShaftBlurPasses 3
```

---

## 요약

| 기법 | 용도 | 비용 |
|------|------|------|
| Volumetric Fog | 3D 안개, 광선 | 높음 |
| Light Shaft | 2D God Ray | 낮음 |
| Local Volume | 국소 안개 | 중간 |
| Height Fog | 높이 기반 안개 | 매우 낮음 |

---

## 참고 자료

- [Volumetric Fog](https://docs.unrealengine.com/volumetric-fog/)
- [Physically Based Sky](https://docs.unrealengine.com/physically-based-sky/)
- [GDC: Volumetric Rendering](https://advances.realtimerendering.com/)
