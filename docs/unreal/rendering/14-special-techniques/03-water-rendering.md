# 물 렌더링

UE5 Water System, 파동 시뮬레이션, 반사/굴절 렌더링을 다룹니다.

---

## 개요

사실적인 물 렌더링은 파동 시뮬레이션, 표면 셰이딩, 반사/굴절, 수중 효과 등 여러 기술의 조합입니다.

```
┌─────────────────────────────────────────────────────────────────┐
│                    물 렌더링 구성 요소                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                   파동 시뮬레이션                        │    │
│  │  ┌───────────┐  ┌───────────┐  ┌───────────┐          │    │
│  │  │ Gerstner  │  │   FFT     │  │Interactive│          │    │
│  │  │   Wave    │  │  Ocean    │  │  Ripple   │          │    │
│  │  └───────────┘  └───────────┘  └───────────┘          │    │
│  └───────────────────────────────┬─────────────────────────┘    │
│                                  │                              │
│                                  ▼                              │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                    표면 셰이딩                           │    │
│  │  Normal Mapping + Fresnel + Specular + Subsurface       │    │
│  └───────────────────────────────┬─────────────────────────┘    │
│                                  │                              │
│                    ┌─────────────┼─────────────┐                │
│                    ▼             ▼             ▼                │
│             ┌───────────┐ ┌───────────┐ ┌───────────┐          │
│             │  반사     │ │  굴절     │ │  Caustics │          │
│             │Reflection │ │Refraction │ │           │          │
│             └───────────┘ └───────────┘ └───────────┘          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## UE5 Water System

### Water Body 타입

```cpp
// 사용 가능한 Water Body 타입
AWaterBodyOcean      // 바다
AWaterBodyLake       // 호수
AWaterBodyRiver      // 강
AWaterBodyCustom     // 커스텀 형태
```

### 기본 설정

```cpp
// Water Body 생성 및 설정
AWaterBodyLake* Lake = World->SpawnActor<AWaterBodyLake>();

// 파동 설정
Lake->WaterWaves->SetWavesParameters(
    WaveAmplitude,   // 파도 높이
    WaveLength,      // 파장
    Steepness        // 가파름
);

// 외관 설정
Lake->WaterMaterial;  // 물 머티리얼
Lake->UnderwaterPostProcessMaterial;  // 수중 포스트 프로세스
```

### Single Layer Water

```cpp
// 프로젝트 설정에서 활성화
r.Water.SingleLayerWater = 1

// Single Layer Water 특징:
// - 단일 패스 렌더링 (효율적)
// - 굴절 근사치 사용
// - 대부분의 경우 충분한 품질
```

```
┌─────────────────────────────────────────────────────────────────┐
│              Single Layer Water vs Multi-Pass                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Single Layer Water:                                            │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  BasePass ──▶ 물 표면 (1 Pass) ──▶ Composite           │    │
│  │              Reflection: SSR + Probe                     │    │
│  │              Refraction: Screen UV Offset               │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                 │
│  Multi-Pass (Traditional):                                      │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  Scene ──▶ Reflection Capture ──▶ Refraction Capture   │    │
│  │        ──▶ Water Surface ──▶ Composite                  │    │
│  │  비용: 훨씬 높음                                        │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 파동 시뮬레이션

### Gerstner Wave

수학적으로 정의된 파동으로, 실시간 계산에 적합합니다.

```hlsl
// Gerstner Wave 공식
float3 GerstnerWave(float2 Position, float Time, float Amplitude, float Wavelength, float Steepness, float2 Direction)
{
    float k = 2.0 * PI / Wavelength;
    float c = sqrt(9.8 / k);  // 파동 속도
    float2 d = normalize(Direction);
    float f = k * (dot(d, Position) - c * Time);

    float3 Offset;
    Offset.x = Steepness * Amplitude * d.x * cos(f);
    Offset.y = Steepness * Amplitude * d.y * cos(f);
    Offset.z = Amplitude * sin(f);

    return Offset;
}

// 여러 파동 합성
float3 TotalOffset = 0;
TotalOffset += GerstnerWave(Pos, Time, Amp1, WaveLen1, Steep1, Dir1);
TotalOffset += GerstnerWave(Pos, Time, Amp2, WaveLen2, Steep2, Dir2);
TotalOffset += GerstnerWave(Pos, Time, Amp3, WaveLen3, Steep3, Dir3);
```

### FFT Ocean

Fourier 변환을 사용한 스펙트럼 기반 해양 시뮬레이션입니다.

```cpp
// FFT Ocean 시스템 (Niagara 또는 Compute Shader)
// Phillips 스펙트럼 사용

// 스펙트럼 생성
float PhillipsSpectrum(float2 K, float2 WindDir, float WindSpeed)
{
    float L = WindSpeed * WindSpeed / 9.8f;
    float k = length(K);
    float kL = k * L;

    float Phillips = A * exp(-1.0f / (kL * kL)) / (k * k * k * k);
    Phillips *= pow(dot(normalize(K), normalize(WindDir)), 2);

    return Phillips;
}

// IFFT로 하이트맵 생성
// Compute Shader에서 병렬 처리
```

### Interactive Ripple

플레이어나 오브젝트와 상호작용하는 잔물결입니다.

```cpp
// 잔물결 시뮬레이션 (Render Target 기반)
UTextureRenderTarget2D* RippleRT;

// 상호작용 지점 추가
void AddRipple(FVector WorldLocation, float Radius, float Strength)
{
    FVector2D UV = WorldToRippleUV(WorldLocation);

    // 머티리얼 파라미터로 전달
    RippleMID->SetVectorParameterValue(
        TEXT("RippleCenter"),
        FLinearColor(UV.X, UV.Y, Radius, Strength)
    );
}

// 시뮬레이션 업데이트 (매 프레임)
void UpdateRippleSimulation()
{
    // 파동 방정식 풀이
    // Height += (Left + Right + Top + Bottom - 4*Center) * DampingFactor
    // GPU에서 Compute Shader로 처리
}
```

---

## 표면 셰이딩

### Fresnel 효과

```hlsl
// 프레넬 계산 (수면 반사)
float FresnelFactor(float3 ViewDir, float3 Normal, float F0)
{
    float NdotV = saturate(dot(Normal, ViewDir));
    // Schlick 근사
    return F0 + (1.0 - F0) * pow(1.0 - NdotV, 5.0);
}

// 물의 IOR(굴절률) = 1.33
// F0 = ((1.33 - 1) / (1.33 + 1))^2 ≈ 0.02
float Fresnel = FresnelFactor(ViewDir, WaterNormal, 0.02);

// 결과: 직각으로 보면 투명, 낮은 각도로 보면 반사
```

### 노멀 맵 디테일

```hlsl
// 여러 스케일의 노멀 맵 합성
float3 Normal1 = SampleNormal(UV * Scale1 + Time * Flow1);
float3 Normal2 = SampleNormal(UV * Scale2 + Time * Flow2);
float3 Normal3 = SampleNormal(UV * Scale3 + Time * Flow3);

// 블렌딩
float3 FinalNormal = normalize(
    Normal1 * Weight1 +
    Normal2 * Weight2 +
    Normal3 * Weight3
);

// 거리에 따른 디테일 페이드
float Distance = length(CameraPos - WorldPos);
float DetailFade = saturate(1.0 - Distance / MaxDistance);
FinalNormal = lerp(float3(0,0,1), FinalNormal, DetailFade);
```

### 서브서피스 산란

```hlsl
// 물의 서브서피스 색상
float3 SubsurfaceColor = float3(0.0, 0.2, 0.3);  // 청록색

// 깊이 기반 서브서피스
float WaterDepth = GetWaterDepth(WorldPos);
float SubsurfaceFactor = saturate(WaterDepth / MaxSubsurfaceDepth);

// 조명 방향으로의 투과
float3 LightThrough = SubsurfaceColor * SubsurfaceFactor * LightColor;
```

---

## 반사와 굴절

### 반사 (Reflection)

```cpp
// 반사 설정 옵션
// 1. Screen Space Reflection (SSR)
r.SSR.Quality = 3;  // SSR 품질

// 2. Planar Reflection (정확하지만 비용 높음)
APlanarReflection* PlanarRefl;
PlanarRefl->ScreenPercentage = 50;  // 해상도 조절
PlanarRefl->NormalDistortionStrength = 500;

// 3. Reflection Capture (정적)
// Scene에 Sphere/Box Reflection Capture 배치
```

```
┌─────────────────────────────────────────────────────────────────┐
│                   반사 방법 비교                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  방법              품질     동적   비용    용도                 │
│  ────────────────  ─────   ────  ──────  ─────────────────────  │
│  SSR              높음     O      중간    일반적인 사용          │
│  Planar           최고     O      높음    작은 평면 (웅덩이)     │
│  Reflection Probe 낮음     X      낮음    정적 환경              │
│  Lumen Reflection 높음     O      높음    UE5 GI 환경           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 굴절 (Refraction)

```hlsl
// Screen UV 오프셋 방식 (Single Layer Water)
float2 RefractionOffset = WaterNormal.xy * RefractionStrength;
float2 RefractedUV = ScreenUV + RefractionOffset;

// 깊이 기반 오프셋 조절
float SceneDepth = SampleSceneDepth(RefractedUV);
float WaterSurfaceDepth = GetWaterSurfaceDepth();
float DepthDifference = SceneDepth - WaterSurfaceDepth;

// 얕은 물에서 굴절 줄이기
RefractionOffset *= saturate(DepthDifference / RefractDistance);
float3 RefractedColor = SampleSceneColor(ScreenUV + RefractionOffset);
```

### 깊이 기반 효과

```hlsl
// 깊이에 따른 색상 변화
float WaterDepth = GetWaterDepth(WorldPos);

// 감쇠 색상 (깊을수록 어두워짐)
float3 AbsorptionColor = float3(0.2, 0.4, 0.5);
float3 Absorption = exp(-AbsorptionColor * WaterDepth);

// 수중 색상과 블렌딩
float3 DeepWaterColor = float3(0.0, 0.05, 0.1);
float3 WaterColor = lerp(DeepWaterColor, RefractedColor, Absorption);
```

---

## 수중 효과

### Underwater Post Process

```cpp
// 수중 포스트 프로세스 설정
UnderwaterPostProcess->Settings.bOverride_ColorGamma = true;
UnderwaterPostProcess->Settings.ColorGamma = FVector4(0.8, 0.9, 1.0, 1.0);

UnderwaterPostProcess->Settings.bOverride_DepthOfFieldFocalDistance = true;
UnderwaterPostProcess->Settings.DepthOfFieldFocalDistance = 100.0f;

// 수중 안개
UnderwaterPostProcess->Settings.bOverride_AmbientOcclusionIntensity = true;
UnderwaterPostProcess->Settings.AmbientOcclusionIntensity = 0.0f;
```

### 수면 교차 처리

```cpp
// 카메라 수중 여부 판단
bool IsUnderwater = CameraLocation.Z < WaterSurfaceHeight;

if (IsUnderwater)
{
    // 수중 포스트 프로세스 활성화
    UnderwaterPP->bEnabled = true;

    // 수면 아래에서 위를 볼 때 전반사 효과
    // Total Internal Reflection
}
else
{
    UnderwaterPP->bEnabled = false;
}
```

---

## Caustics

물을 통과한 빛이 바닥에 만드는 패턴입니다.

```hlsl
// Caustics 패턴 생성
float3 CausticsTexture = Texture2DSample(CausticsMap,
    WorldPos.xy * CausticsScale + Time * CausticsFlow).rgb;

// 두 레이어 블렌딩 (더 자연스러운 효과)
float3 Caustics1 = Texture2DSample(CausticsMap,
    WorldPos.xy * Scale1 + Time * Speed1).rgb;
float3 Caustics2 = Texture2DSample(CausticsMap,
    WorldPos.xy * Scale2 + Time * Speed2).rgb;

float3 Caustics = min(Caustics1, Caustics2);  // 어두운 부분 강조

// 깊이에 따른 감쇠
float CausticsIntensity = saturate(1.0 - WaterDepth / MaxCausticsDepth);
Caustics *= CausticsIntensity * SunIntensity;

// 바닥 라이팅에 추가
BottomColor += Caustics;
```

---

## 최적화

### LOD 설정

```cpp
// 거리 기반 테셀레이션
WaterMesh->bUseDynamicTessellation = true;
WaterMesh->TessellationMaxLevel = 8;
WaterMesh->TessellationFalloff = 1000.0f;  // 거리에 따른 감소

// 파동 LOD
r.Water.WaveSimulationGridSize = 256  // 해상도
r.Water.MaxWaveHeight = 300           // 최대 파고
```

### 반사 최적화

```cpp
// SSR 품질 조절
r.SSR.Quality = 2           // 중간 품질
r.SSR.HalfResSceneColor = 1 // 절반 해상도

// Planar Reflection 제한
PlanarReflection->ScreenPercentage = 25;  // 25% 해상도
PlanarReflection->MaxReflectionActors = 10;  // 반사 액터 수 제한
```

---

## 콘솔 명령

```cpp
// Water System
r.Water.SingleLayerWater 1
r.Water.WaveSimulation 1

// 반사
r.SSR.Quality 3
r.ReflectionCapture.MaxDiameter 1000

// 디버그
r.Water.DebugShowWaterInfo 1
ShowFlag.VisualizeWater 1
```

---

## 요약

| 기능 | 기술 | 비용 |
|------|------|------|
| 파동 | Gerstner/FFT | 낮음-중간 |
| 표면 | Normal + Fresnel | 낮음 |
| 반사 | SSR/Planar | 중간-높음 |
| 굴절 | UV Offset | 낮음 |
| Caustics | 텍스처 투영 | 낮음 |

---

## 참고 자료

- [Water System](https://docs.unrealengine.com/water-system/)
- [Ocean Simulation](https://docs.unrealengine.com/ocean-system/)
- [Tessendorf Waves](http://graphics.ucsd.edu/courses/rendering/2005/jdewall/tessendorf.pdf)
