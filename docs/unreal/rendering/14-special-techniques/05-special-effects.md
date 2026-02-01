# 기타 특수 효과

서브서피스 스캐터링, 머리카락, 눈/얼음, 홀로그램 등 다양한 특수 렌더링 기법을 다룹니다.

---

## 개요

고급 시각 효과는 특수한 셰이딩 모델과 렌더링 기법을 통해 구현됩니다.

```
┌─────────────────────────────────────────────────────────────────┐
│                    특수 효과 분류                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                 서피스 셰이딩 모델                         │  │
│  │  ┌───────────┐  ┌───────────┐  ┌───────────┐            │  │
│  │  │ Subsurface│  │   Hair    │  │   Eye     │            │  │
│  │  │ Scattering│  │           │  │           │            │  │
│  │  └───────────┘  └───────────┘  └───────────┘            │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                   재질 표현                               │  │
│  │  ┌───────────┐  ┌───────────┐  ┌───────────┐            │  │
│  │  │   눈/얼음 │  │   천/직물 │  │ 보석/유리 │            │  │
│  │  └───────────┘  └───────────┘  └───────────┘            │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                 스타일라이즈 효과                          │  │
│  │  ┌───────────┐  ┌───────────┐  ┌───────────┐            │  │
│  │  │ 홀로그램  │  │  글리치   │  │  툰 셰이딩│            │  │
│  │  └───────────┘  └───────────┘  └───────────┘            │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Subsurface Scattering (SSS)

피부, 왁스, 대리석 등 빛이 표면 아래로 들어가 산란되는 재질을 표현합니다.

### Subsurface Profile

```cpp
// Subsurface Profile 에셋 생성
USubsurfaceProfile* SkinProfile = NewObject<USubsurfaceProfile>();

// 산란 색상 (빛이 재질 내부에서 어떤 색으로 산란되는지)
SkinProfile->SubsurfaceColor = FLinearColor(0.48f, 0.23f, 0.1f);  // 피부

// 산란 반경 (얼마나 멀리 퍼지는지)
SkinProfile->ScatterRadius = 1.2f;

// 버프 설정
SkinProfile->FalloffColor = FLinearColor(1.0f, 0.37f, 0.3f);
SkinProfile->BoundaryColorBleed = FLinearColor(0.85f, 0.35f, 0.25f);
```

### 머티리얼 설정

```cpp
// 머티리얼에서 SSS 셰이딩 모델 사용
Material->ShadingModel = MSM_SubsurfaceProfile;
Material->SubsurfaceProfile = SkinProfile;

// 머티리얼 노드:
// - Base Color: 표면 색상
// - Opacity: SSS 강도 (0=SSS 없음, 1=완전 SSS)
// - Subsurface Color: 프로파일 오버라이드 (선택)
```

```
┌─────────────────────────────────────────────────────────────────┐
│                    SSS 렌더링 원리                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│        빛 입사                                                  │
│           ↓                                                     │
│  ═════════════════════════════  표면                           │
│           ↓      ↙↘↓↙↘                                         │
│     ┌─────────────────────┐                                    │
│     │    산란 영역        │  ← 빛이 내부에서 산란               │
│     │   ↙↘↓↙↘↓↙↘        │                                    │
│     └─────────────────────┘                                    │
│           ↓↙↘                                                   │
│  ═════════════════════════════  표면                           │
│           ↓                                                     │
│        빛 출사 (부드러운 확산)                                  │
│                                                                 │
│  효과:                                                          │
│  - 두꺼운 부분: 어둡게                                         │
│  - 얇은 부분 (귀 등): 빛 투과 (붉은색)                         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 머리카락 렌더링

### Hair Shading Model

```cpp
// 머리카락 셰이딩 모델
Material->ShadingModel = MSM_Hair;

// 머티리얼 입력:
// - Base Color: 머리카락 색상 (멜라닌 기반)
// - Scatter: 산란 색상
// - Specular: 스페큘러 강도
// - Roughness: 거칠기 (스트랜드 방향)
// - Backlit: 역광 투과
```

### Kajiya-Kay 모델

```hlsl
// 머리카락 스페큘러 (Kajiya-Kay)
float3 HairSpecular(float3 T, float3 V, float3 L, float Roughness)
{
    // T = 머리카락 접선 방향
    float3 H = normalize(V + L);

    float TdotH = dot(T, H);
    float sinTH = sqrt(1.0 - TdotH * TdotH);

    // 이방성 스페큘러
    float Specular = pow(sinTH, 1.0 / Roughness);

    return Specular;
}
```

### Groom/Strand 렌더링

```cpp
// Groom 에셋 (UE5 Hair System)
UGroomAsset* Groom;

// 설정
Groom->HairRenderingType = EHairRenderingType::Strands;  // 스트랜드 렌더링
Groom->HairInterpolationType = EHairInterpolationType::RigidTransform;

// LOD 설정
Groom->LODSettings[0].StrandWidth = 0.001f;  // 스트랜드 두께
Groom->LODSettings[0].ScreenSize = 0.5f;     // LOD 전환 크기
```

---

## 눈 렌더링

### Eye Shading Model

```cpp
// 눈 셰이딩 모델
Material->ShadingModel = MSM_Eye;

// 입력:
// - Iris Normal: 홍채 노멀 맵
// - Iris Mask: 홍채 영역 마스크
// - Iris Distance: 홍채 깊이
```

### 눈 구조

```
┌─────────────────────────────────────────────────────────────────┐
│                      눈 구조와 렌더링                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│          ┌────────────────────────┐                            │
│         /    각막 (Cornea)        \  ← 투명, 굴절              │
│        /   ┌────────────────┐     \                            │
│       │    │  동공 (Pupil)  │      │ ← 검은색                  │
│       │    │  ┌──────────┐  │      │                           │
│       │    │  │  홍채    │  │      │ ← 색상, 패턴              │
│       │    │  │ (Iris)   │  │      │                           │
│       │    │  └──────────┘  │      │                           │
│       │    └────────────────┘      │                           │
│        \    공막 (Sclera)         /  ← 흰색, SSS              │
│         \________________________/                              │
│                                                                 │
│  렌더링 요소:                                                   │
│  - 각막 굴절 (홍채가 약간 왜곡되어 보임)                       │
│  - 공막 SSS (붉은 혈관 비침)                                   │
│  - 스페큘러 하이라이트 (생기 표현)                             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 눈/얼음 재질

### 눈 (Snow) 셰이딩

```hlsl
// 눈 머티리얼
// 특징: SSS + 스파클 + 높은 러프니스

float3 SnowShading(float3 Normal, float3 ViewDir)
{
    // 기본 SSS 흰색
    float3 BaseColor = float3(0.95, 0.95, 0.98);

    // 스파클 (반짝이는 눈 결정)
    float3 SparkleNormal = SampleNoise(WorldPos * SparkleScale);
    float Sparkle = pow(saturate(dot(SparkleNormal, HalfVector)), SparklePower);
    Sparkle *= SparkleIntensity;

    // 깊이에 따른 SSS
    float SSS = SubsurfaceScattering(SunDir, Normal, ViewDir, 0.5);

    return BaseColor + Sparkle + SSS * float3(0.6, 0.7, 0.9);
}
```

### 얼음 (Ice) 셰이딩

```hlsl
// 얼음 머티리얼
// 특징: 투명 + 굴절 + 내부 균열

float3 IceShading(float3 WorldPos, float3 Normal, float3 ViewDir)
{
    // 굴절
    float3 RefractDir = refract(-ViewDir, Normal, 1.0 / 1.31);
    float3 RefractedColor = SampleSceneColor(RefractDir);

    // 프레넬
    float Fresnel = FresnelSchlick(dot(Normal, ViewDir), 0.02);

    // 내부 균열/기포 (3D 텍스처)
    float Cracks = Texture3DSample(CrackTexture, WorldPos * CrackScale).r;

    // 조합
    float3 IceColor = lerp(RefractedColor, float3(0.8, 0.9, 1.0), Fresnel);
    IceColor += Cracks * CrackColor;

    return IceColor;
}
```

---

## 천/직물 (Cloth)

### Cloth Shading Model

```cpp
// 천 셰이딩 모델
Material->ShadingModel = MSM_Cloth;

// 특징:
// - 부드러운 스페큘러
// - Fuzz (보풀) 효과
// - 이방성 반사
```

### 직물 패턴

```hlsl
// 직물 디테일
float3 ClothNormal = BlendNormals(
    MacroNormal,  // 큰 주름
    MicroNormal   // 직물 패턴
);

// Fuzz (보풀) - 가장자리 밝게
float Fuzz = pow(1.0 - saturate(dot(Normal, ViewDir)), FuzzPower);
float3 FuzzColor = float3(0.05, 0.05, 0.05);
```

---

## 홀로그램 효과

### 기본 홀로그램

```hlsl
// 홀로그램 머티리얼
float3 HologramEffect(float2 UV, float3 WorldPos, float3 Normal, float3 ViewDir)
{
    // 스캔라인
    float Scanline = frac(WorldPos.z * ScanlineFrequency + Time * ScanlineSpeed);
    Scanline = step(0.5, Scanline);

    // 프레넬 글로우
    float Fresnel = pow(1.0 - saturate(dot(Normal, ViewDir)), FresnelPower);

    // 색상 (청록/보라 홀로그램 느낌)
    float3 HoloColor = float3(0.0, 0.8, 1.0);
    HoloColor = lerp(HoloColor, float3(0.8, 0.2, 1.0), Fresnel);

    // 글리치/노이즈
    float Glitch = Noise(UV + Time * GlitchSpeed);
    float3 GlitchOffset = Glitch * GlitchIntensity;

    // 최종 색상
    float3 FinalColor = HoloColor * (Scanline * 0.5 + 0.5);
    FinalColor += Fresnel * HoloColor * 2.0;  // 가장자리 글로우

    return FinalColor;
}
```

### Dithered 투명도

```hlsl
// 디더 패턴 투명도 (반투명보다 효율적)
float DitherPattern = InterleavedGradientNoise(ScreenPosition);
clip(Opacity - DitherPattern);
```

---

## 글리치 효과

```hlsl
// 글리치 포스트 프로세스
float4 GlitchPostProcess(float2 UV)
{
    // 색수차 (Chromatic Aberration)
    float2 Offset = float2(GlitchAmount, 0);
    float R = SceneTexture.Sample(UV + Offset).r;
    float G = SceneTexture.Sample(UV).g;
    float B = SceneTexture.Sample(UV - Offset).b;

    // 수평 라인 오프셋
    float LineNoise = Noise(UV.y * LineFreq + Time);
    if (LineNoise > 0.95)
    {
        UV.x += sin(Time * 100) * LineOffset;
    }

    // 블록 글리치
    float2 BlockUV = floor(UV * BlockSize) / BlockSize;
    float BlockNoise = Noise(BlockUV + floor(Time * BlockSpeed));
    if (BlockNoise > 0.98)
    {
        UV.x += BlockDisplace;
    }

    return float4(R, G, B, 1.0);
}
```

---

## 투명/굴절 재질

### 유리

```hlsl
// 유리 머티리얼
float3 GlassShading(...)
{
    // 굴절
    float3 RefractDir = refract(-ViewDir, Normal, 1.0 / IOR);
    float3 RefractColor = SampleSceneColor(RefractDir);

    // 반사
    float3 ReflectDir = reflect(-ViewDir, Normal);
    float3 ReflectColor = SampleEnvironment(ReflectDir);

    // 프레넬
    float Fresnel = FresnelSchlick(NdotV, 0.04);

    // 합성
    return lerp(RefractColor, ReflectColor, Fresnel) * Tint;
}
```

### 보석

```hlsl
// 보석 (다이아몬드 등)
// 특징: 높은 IOR, 분산, 다중 반사

float3 GemShading(...)
{
    // 높은 IOR (다이아몬드 = 2.42)
    float IOR = 2.42;

    // 분산 (Dispersion) - 파장별 다른 굴절
    float3 RefractR = refract(-ViewDir, Normal, 1.0 / (IOR - Dispersion));
    float3 RefractG = refract(-ViewDir, Normal, 1.0 / IOR);
    float3 RefractB = refract(-ViewDir, Normal, 1.0 / (IOR + Dispersion));

    float R = SampleSceneColor(RefractR).r;
    float G = SampleSceneColor(RefractG).g;
    float B = SampleSceneColor(RefractB).b;

    return float3(R, G, B);
}
```

---

## 성능 고려사항

| 효과 | 비용 | 최적화 방법 |
|------|------|-------------|
| SSS Profile | 중간 | 프로파일 수 제한 |
| Hair Strands | 높음 | LOD, 카드 폴백 |
| Eye | 낮음 | - |
| Refraction | 중간 | 품질 설정 |
| Translucent | 높음 | 레이어 수 제한 |

---

## 콘솔 명령

```cpp
// SSS
r.SSS.Quality 1
r.SSS.SampleSet 2

// Hair
r.HairStrands.Enable 1
r.HairStrands.Visibility.Msaa 4

// Translucency
r.RefractionQuality 2
r.TranslucencyLightingVolumeDim 64
```

---

## 요약

| 셰이딩 모델 | 용도 | 특징 |
|------------|------|------|
| SSS Profile | 피부, 왁스 | 빛 산란 |
| Hair | 머리카락 | 이방성 스페큘러 |
| Eye | 눈 | 굴절, 홍채 깊이 |
| Cloth | 천, 직물 | 부드러운 반사 |
| Clear Coat | 자동차, 코팅 | 이중 레이어 |

---

## 참고 자료

- [Shading Models](https://docs.unrealengine.com/shading-models/)
- [Subsurface Scattering](https://docs.unrealengine.com/subsurface-scattering/)
- [Hair Rendering](https://docs.unrealengine.com/hair-rendering/)
