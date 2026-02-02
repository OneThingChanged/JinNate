# 블룸과 광원 효과

Bloom, Lens Flare, Light Shafts 등 광원 기반 포스트 이펙트를 분석합니다.

---

## 광원 복잡도와 블룸

![광원 복잡도 시각화](../images/ch07/1617944-20210505184743826-1788055643.jpg)

*타일별 광원 수 시각화 - 블룸은 이러한 밝은 광원 영역에서 글로우 효과를 생성 (색상이 따뜻할수록 더 많은 광원)*

---

## 블룸 (Bloom)

### 블룸 개념

블룸은 밝은 영역이 주변으로 번지는 효과로, 실제 카메라와 인간의 눈에서 발생하는 현상을 모방합니다.

```
┌─────────────────────────────────────────────────────────────────┐
│                    블룸 효과                                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  원본 이미지           블룸 적용 후                               │
│  ┌─────────────┐      ┌─────────────┐                           │
│  │             │      │    ░░░░     │                           │
│  │      ●      │  →   │  ░░████░░   │   밝은 영역이             │
│  │             │      │    ░░░░     │   주변으로 번짐            │
│  └─────────────┘      └─────────────┘                           │
│                                                                 │
│  물리적 원인:                                                    │
│  - 렌즈 내부 산란 (Lens Scattering)                              │
│  - 회절 (Diffraction)                                           │
│  - 눈의 유리체 산란                                              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 가우시안 블룸 파이프라인

```
┌─────────────────────────────────────────────────────────────────┐
│                    가우시안 블룸 파이프라인                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Scene Color (Full Res)                                         │
│       │                                                         │
│       ▼                                                         │
│  ┌─────────────┐                                                │
│  │ Threshold   │ ← 밝은 픽셀만 추출 (임계값 이상)                │
│  └─────┬───────┘                                                │
│        │                                                        │
│        ▼                                                        │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌──────────┐  │
│  │ Downsample  │→│ Downsample  │→│ Downsample  │→│   ...    │  │
│  │   1/2       │ │    1/4      │ │    1/8      │ │  1/64    │  │
│  └─────┬───────┘ └─────┬───────┘ └─────┬───────┘ └────┬─────┘  │
│        │               │               │              │         │
│        ▼               ▼               ▼              ▼         │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌──────────┐  │
│  │ Blur H + V  │ │ Blur H + V  │ │ Blur H + V  │ │Blur H + V│  │
│  └─────┬───────┘ └─────┬───────┘ └─────┬───────┘ └────┬─────┘  │
│        │               │               │              │         │
│        └───────────────┴───────────────┴──────────────┘         │
│                           │                                     │
│                           ▼                                     │
│                    ┌─────────────┐                              │
│                    │  Upsample   │ ← 모든 레벨 합산             │
│                    │  + Combine  │                              │
│                    └─────┬───────┘                              │
│                          │                                      │
│                          ▼                                      │
│                    ┌─────────────┐                              │
│                    │ Add to      │                              │
│                    │ Scene Color │                              │
│                    └─────────────┘                              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 블룸 셰이더

```hlsl
// 블룸 임계값 추출
float4 BloomThresholdPS(float2 UV : TEXCOORD0) : SV_Target
{
    float3 Color = SceneColorTexture.Sample(LinearSampler, UV).rgb;

    // 휘도 계산
    float Luminance = dot(Color, float3(0.2126, 0.7152, 0.0722));

    // 임계값 적용 (부드러운 전환)
    float BloomLuminance = Luminance - BloomThreshold;
    float BloomAmount = saturate(BloomLuminance / (BloomLuminance + 1.0));

    // 색상 유지하면서 밝기만 조절
    return float4(Color * BloomAmount * BloomIntensity, 1);
}

// 가우시안 블러 (분리 가능한 필터)
// 수평 패스
float4 GaussianBlurHorizontalPS(float2 UV : TEXCOORD0) : SV_Target
{
    float3 Color = float3(0, 0, 0);
    float TotalWeight = 0;

    // 5-tap 가우시안
    float Weights[5] = { 0.0545, 0.2442, 0.4026, 0.2442, 0.0545 };
    float Offsets[5] = { -2, -1, 0, 1, 2 };

    for (int i = 0; i < 5; i++)
    {
        float2 SampleUV = UV + float2(Offsets[i] * TexelSize.x, 0);
        Color += InputTexture.Sample(LinearSampler, SampleUV).rgb * Weights[i];
        TotalWeight += Weights[i];
    }

    return float4(Color / TotalWeight, 1);
}

// 수직 패스 (동일 패턴)
float4 GaussianBlurVerticalPS(float2 UV : TEXCOORD0) : SV_Target
{
    // ... 수평과 동일하지만 Y축 오프셋 사용
}

// 업샘플 및 합성
float4 BloomUpsamplePS(float2 UV : TEXCOORD0) : SV_Target
{
    // 현재 레벨
    float3 Current = CurrentLevelTexture.Sample(LinearSampler, UV).rgb;

    // 이전 레벨 (더 낮은 해상도)
    float3 Previous = PreviousLevelTexture.Sample(LinearSampler, UV).rgb;

    // 가중 합산
    return float4(Current + Previous * BloomLevelWeight, 1);
}
```

### UE 블룸 설정

```cpp
// 블룸 파라미터
UPROPERTY(EditAnywhere, Category="Bloom")
float BloomIntensity = 0.675f;  // 전체 강도

UPROPERTY(EditAnywhere, Category="Bloom")
float BloomThreshold = -1.0f;   // 임계값 (-1 = 자동)

// 개별 레벨 강도
UPROPERTY(EditAnywhere, Category="Bloom")
float Bloom1Size = 0.3f;        // 가장 작은 블룸

UPROPERTY(EditAnywhere, Category="Bloom")
float Bloom2Size = 1.0f;

UPROPERTY(EditAnywhere, Category="Bloom")
float Bloom3Size = 2.0f;

UPROPERTY(EditAnywhere, Category="Bloom")
float Bloom4Size = 10.0f;

UPROPERTY(EditAnywhere, Category="Bloom")
float Bloom5Size = 30.0f;

UPROPERTY(EditAnywhere, Category="Bloom")
float Bloom6Size = 64.0f;       // 가장 큰 블룸

// 개별 틴트
UPROPERTY(EditAnywhere, Category="Bloom")
FLinearColor Bloom1Tint = FLinearColor::White;
// ... Bloom2Tint ~ Bloom6Tint
```

---

## 컨볼루션 블룸

### 커스텀 커널

```cpp
// 컨볼루션 블룸 - 커스텀 블룸 형태
UPROPERTY(EditAnywhere, Category="Bloom|Convolution")
UTexture2D* BloomConvolutionTexture;  // 블룸 커널 텍스처

UPROPERTY(EditAnywhere, Category="Bloom|Convolution")
float BloomConvolutionSize = 1.0f;    // 커널 크기

UPROPERTY(EditAnywhere, Category="Bloom|Convolution")
float BloomConvolutionCenterUV;       // 커널 중심
```

### FFT 컨볼루션

```hlsl
// FFT 기반 컨볼루션 블룸
// 주파수 영역에서 곱셈 = 공간 영역에서 컨볼루션

// 1. 씬 컬러와 커널을 FFT 변환
ComplexTexture SceneFFT = FFT2D(ThresholdedSceneColor);
ComplexTexture KernelFFT = FFT2D(BloomKernel);

// 2. 주파수 영역에서 곱셈
ComplexTexture ResultFFT = ComplexMultiply(SceneFFT, KernelFFT);

// 3. 역 FFT로 공간 영역 복원
Texture2D BloomResult = InverseFFT2D(ResultFFT);
```

---

## 렌즈 플레어 (Lens Flare)

### 개념

```
┌─────────────────────────────────────────────────────────────────┐
│                    렌즈 플레어 요소                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│                     광원                                        │
│                       ●                                         │
│                       │                                         │
│       ┌───────────────┼───────────────┐                        │
│       │               │               │                         │
│       ▼               ▼               ▼                         │
│                                                                 │
│  ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐     │
│  │  Ghost  │    │  Halo   │    │ Starburst│    │  Streak │     │
│  │         │    │         │    │          │    │         │     │
│  │    ○    │    │   ◐     │    │    ✦     │    │   ━━━   │     │
│  │         │    │         │    │          │    │         │     │
│  └─────────┘    └─────────┘    └─────────┘    └─────────┘     │
│                                                                 │
│  Ghost: 광원 반대편에 나타나는 반사 이미지                       │
│  Halo: 광원 주변의 원형 글로우                                   │
│  Starburst: 조리개 회절에 의한 별 모양                           │
│  Streak: 아나모픽 렌즈의 수평 줄무늬                             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 렌즈 플레어 구현

```hlsl
// 이미지 기반 렌즈 플레어
float4 LensFlarePS(float2 UV : TEXCOORD0) : SV_Target
{
    float3 Result = float3(0, 0, 0);

    // 밝은 픽셀 추출
    float3 Threshold = ExtractBrightPixels(UV);

    // Ghost 효과 (여러 개의 반전된 이미지)
    for (int i = 0; i < NUM_GHOSTS; i++)
    {
        float2 GhostUV = float2(1, 1) - UV;  // 중심 기준 반전
        GhostUV = lerp(float2(0.5, 0.5), GhostUV, GhostScales[i]);

        float3 Ghost = ThresholdTexture.Sample(LinearSampler, GhostUV).rgb;
        Ghost *= GhostColors[i] * GhostIntensities[i];

        // 비네트 (가장자리 페이드)
        float Vignette = 1.0 - length(GhostUV - 0.5) * 2.0;
        Ghost *= saturate(Vignette);

        Result += Ghost;
    }

    // Halo 효과
    float2 HaloUV = float2(1, 1) - UV;
    float2 HaloVec = HaloUV - float2(0.5, 0.5);
    float HaloRadius = length(HaloVec);

    if (HaloRadius < HaloSize)
    {
        float HaloFalloff = 1.0 - (HaloRadius / HaloSize);
        float3 HaloColor = ThresholdTexture.Sample(LinearSampler, HaloUV).rgb;
        Result += HaloColor * HaloIntensity * pow(HaloFalloff, HaloFalloffPower);
    }

    return float4(Result, 1);
}

// 아나모픽 스트릭
float4 AnamorphicStreakPS(float2 UV : TEXCOORD0) : SV_Target
{
    float3 Result = float3(0, 0, 0);
    float TotalWeight = 0;

    // 수평 방향으로 긴 블러
    for (int i = -STREAK_SAMPLES; i <= STREAK_SAMPLES; i++)
    {
        float2 SampleUV = UV + float2(i * StreakSpread, 0);
        float Weight = exp(-abs(i) * StreakFalloff);

        float3 Sample = ThresholdTexture.Sample(LinearSampler, SampleUV).rgb;
        Result += Sample * Weight;
        TotalWeight += Weight;
    }

    return float4(Result / TotalWeight * StreakIntensity, 1);
}
```

### UE 렌즈 플레어 설정

```cpp
// 렌즈 플레어 파라미터
UPROPERTY(EditAnywhere, Category="Lens|Lens Flares")
float LensFlareIntensity = 1.0f;

UPROPERTY(EditAnywhere, Category="Lens|Lens Flares")
FLinearColor LensFlareTint = FLinearColor::White;

UPROPERTY(EditAnywhere, Category="Lens|Lens Flares")
float LensFlareThreshold = 8.0f;

// 보케 렌즈 플레어 (이미지 기반)
UPROPERTY(EditAnywhere, Category="Lens|Lens Flares")
UTexture* LensFlareBokehShape;

UPROPERTY(EditAnywhere, Category="Lens|Lens Flares")
float LensFlareBokehSize = 3.0f;
```

---

## 라이트 샤프트 (Light Shafts)

### 볼류메트릭 라이트

```
┌─────────────────────────────────────────────────────────────────┐
│                    라이트 샤프트                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│         ☀ (광원)                                                │
│          │\\\                                                   │
│          │ \\\\\                                                │
│          │  \\\\\\                                              │
│          │   \\\\\\\                                            │
│       ───┼────────────   (오클루더)                             │
│          │      \\\\\\                                          │
│          │        \\\\\                                         │
│          │          \\\\                                        │
│          │            \\\   빛줄기가 오클루더                    │
│          │              \\   뒤로 뻗어나감                       │
│          ▼               \                                      │
│                                                                 │
│  원리: 방사형 블러 (Radial Blur)                                 │
│  - 광원 위치에서 방사형으로 샘플링                               │
│  - 오클루전 마스크와 결합                                        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 라이트 샤프트 셰이더

```hlsl
// 라이트 샤프트 마스크 생성
float4 LightShaftMaskPS(float2 UV : TEXCOORD0) : SV_Target
{
    // 광원 위치 (스크린 스페이스)
    float2 LightPos = WorldToScreen(LightWorldPosition);

    // 오클루전 체크 (깊이 기반)
    float SceneDepth = SceneDepthTexture.Sample(PointSampler, UV).r;
    float LightDepth = GetLightDepth(UV);

    // 오클루더가 있으면 마스크 = 0
    float Mask = (SceneDepth < LightDepth) ? 0.0 : 1.0;

    // 광원에서의 거리에 따른 페이드
    float2 ToLight = LightPos - UV;
    float Distance = length(ToLight);
    float Falloff = 1.0 - saturate(Distance / LightShaftRadius);

    return float4(Mask * Falloff, 0, 0, 1);
}

// 방사형 블러
float4 RadialBlurPS(float2 UV : TEXCOORD0) : SV_Target
{
    float2 LightPos = WorldToScreen(LightWorldPosition);
    float2 Direction = UV - LightPos;

    float3 Result = float3(0, 0, 0);
    float TotalWeight = 0;

    // 광원 방향으로 샘플링
    for (int i = 0; i < NUM_SAMPLES; i++)
    {
        float T = float(i) / float(NUM_SAMPLES);
        float2 SampleUV = UV - Direction * T * BlurLength;

        float Weight = 1.0 - T;  // 거리에 따른 감쇠
        float3 Sample = MaskTexture.Sample(LinearSampler, SampleUV).rgb;

        Result += Sample * Weight;
        TotalWeight += Weight;
    }

    return float4(Result / TotalWeight * LightShaftIntensity, 1);
}

// 씬에 합성
float4 LightShaftCompositePS(float2 UV : TEXCOORD0) : SV_Target
{
    float3 SceneColor = SceneColorTexture.Sample(LinearSampler, UV).rgb;
    float3 LightShaft = LightShaftTexture.Sample(LinearSampler, UV).rgb;

    // Additive 블렌딩
    return float4(SceneColor + LightShaft * LightColor, 1);
}
```

### UE 라이트 샤프트 설정

```cpp
// 디렉셔널 라이트의 라이트 샤프트
UPROPERTY(EditAnywhere, Category="Light Shafts")
bool bEnableLightShaftOcclusion = false;

UPROPERTY(EditAnywhere, Category="Light Shafts")
float OcclusionMaskDarkness = 0.3f;

UPROPERTY(EditAnywhere, Category="Light Shafts")
float OcclusionDepthRange = 100000.0f;

UPROPERTY(EditAnywhere, Category="Light Shafts")
bool bEnableLightShaftBloom = false;

UPROPERTY(EditAnywhere, Category="Light Shafts")
float BloomScale = 0.2f;

UPROPERTY(EditAnywhere, Category="Light Shafts")
float BloomThreshold = 0.0f;

UPROPERTY(EditAnywhere, Category="Light Shafts")
FLinearColor BloomTint = FLinearColor::White;
```

---

## 글레어 (Glare)

### 스타버스트 효과

```hlsl
// 스타버스트 (조리개 회절)
float4 StarburstPS(float2 UV : TEXCOORD0) : SV_Target
{
    float3 Result = float3(0, 0, 0);

    // 블레이드 수에 따른 광선
    int NumBlades = 6;  // 조리개 블레이드 수
    float AngleStep = 3.14159 / NumBlades;

    for (int i = 0; i < NumBlades * 2; i++)
    {
        float Angle = i * AngleStep;
        float2 Dir = float2(cos(Angle), sin(Angle));

        // 해당 방향으로 블러
        float3 Streak = float3(0, 0, 0);
        for (int j = 0; j < STREAK_SAMPLES; j++)
        {
            float T = float(j) / STREAK_SAMPLES;
            float2 SampleUV = UV + Dir * T * StreakLength;

            float Weight = 1.0 - T;
            Streak += ThresholdTexture.Sample(LinearSampler, SampleUV).rgb * Weight;
        }

        Result += Streak;
    }

    return float4(Result * StarburstIntensity / (NumBlades * 2), 1);
}
```

---

## 더티 렌즈 (Dirty Lens)

### 렌즈 먼지 효과

```cpp
// 더티 렌즈 설정
UPROPERTY(EditAnywhere, Category="Lens|Dirt Mask")
UTexture* BloomDirtMask;  // 더트 마스크 텍스처

UPROPERTY(EditAnywhere, Category="Lens|Dirt Mask")
float BloomDirtMaskIntensity = 0.0f;

UPROPERTY(EditAnywhere, Category="Lens|Dirt Mask")
FLinearColor BloomDirtMaskTint = FLinearColor::White;
```

```hlsl
// 더티 렌즈 적용
float4 DirtyLensPS(float2 UV : TEXCOORD0) : SV_Target
{
    float3 Bloom = BloomTexture.Sample(LinearSampler, UV).rgb;

    // 더트 마스크 샘플링
    float3 DirtMask = DirtMaskTexture.Sample(LinearSampler, UV).rgb;

    // 블룸에 더트 마스크 곱
    float3 DirtyBloom = Bloom * DirtMask * DirtIntensity;

    // 원본 블룸과 합산
    return float4(Bloom + DirtyBloom, 1);
}
```

---

## 성능 최적화

### 해상도 스케일링

```cpp
// 블룸 품질 설정
UENUM()
enum class EBloomQuality : uint8
{
    Low,        // 3 레벨, 작은 커널
    Medium,     // 5 레벨
    High,       // 6 레벨, 큰 커널
    VeryHigh,   // 컨볼루션 블룸
};

// 품질별 설정
void GetBloomQualitySettings(EBloomQuality Quality, FBloomSettings& Out)
{
    switch (Quality)
    {
        case EBloomQuality::Low:
            Out.NumLevels = 3;
            Out.KernelSize = 3;
            Out.StartDownsample = 4;
            break;

        case EBloomQuality::Medium:
            Out.NumLevels = 5;
            Out.KernelSize = 5;
            Out.StartDownsample = 2;
            break;

        case EBloomQuality::High:
            Out.NumLevels = 6;
            Out.KernelSize = 7;
            Out.StartDownsample = 2;
            break;

        case EBloomQuality::VeryHigh:
            Out.bUseConvolution = true;
            break;
    }
}
```

---

## 요약

| 효과 | 용도 | 비용 |
|------|------|------|
| Bloom | 밝은 영역 글로우 | 낮음~중간 |
| Convolution Bloom | 커스텀 블룸 형태 | 높음 |
| Lens Flare | 렌즈 반사 효과 | 중간 |
| Light Shafts | 볼류메트릭 빛줄기 | 중간 |
| Starburst | 조리개 회절 | 중간 |
| Dirty Lens | 렌즈 오염 효과 | 낮음 |

광원 효과는 영화적 분위기를 위한 핵심 포스트 프로세스입니다.
---

<div style="display: flex; justify-content: space-between; align-items: center; padding: 16px 0;">
  <a href="../02-tone-mapping-color/" style="text-decoration: none;">← 이전: 02. 톤 매핑과 컬러</a>
  <a href="../04-temporal-effects/" style="text-decoration: none;">다음: 04. 템포럴 효과 →</a>
</div>
