# 톤 매핑과 컬러

HDR에서 LDR로의 변환과 컬러 그레이딩 시스템을 분석합니다.

---

## 톤 매핑 개요

### HDR과 LDR

```
┌─────────────────────────────────────────────────────────────────┐
│                    HDR → LDR 변환                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  HDR (High Dynamic Range)                                       │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                         │   │
│  │  휘도 범위: 0.0 ~ 수만 (태양: ~100,000 nits)             │   │
│  │  포맷: FP16, FP32                                       │   │
│  │                                                         │   │
│  │  ■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■     │   │
│  │  0.001        1.0        100       10000      100000    │   │
│  │  ↑            ↑          ↑         ↑          ↑         │   │
│  │  어둠         피부      백지      전구        태양      │   │
│  │                                                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                           │                                     │
│                   톤 매핑 (압축)                                 │
│                           │                                     │
│                           ▼                                     │
│  LDR (Low Dynamic Range)                                        │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                         │   │
│  │  휘도 범위: 0.0 ~ 1.0 (8-bit: 0~255)                     │   │
│  │  포맷: RGBA8, sRGB                                      │   │
│  │                                                         │   │
│  │  ■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■     │   │
│  │  0.0                    0.5                        1.0  │   │
│  │                                                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 자동 노출 (Auto Exposure)

### 노출 계산

```cpp
// 자동 노출 시스템
class FAutoExposure
{
public:
    // 노출 계산 방법
    enum class EMethod
    {
        Histogram,      // 히스토그램 기반
        Basic,          // 평균 휘도 기반
        Manual          // 수동 설정
    };

    // 히스토그램 기반 노출 계산
    float ComputeExposureHistogram(
        const FRDGTexture* SceneColor,
        const FViewInfo& View)
    {
        // 1. 휘도 히스토그램 생성
        FRDGTexture* Histogram = BuildLuminanceHistogram(SceneColor);

        // 2. 히스토그램 분석
        float AverageLuminance = AnalyzeHistogram(
            Histogram,
            View.FinalPostProcessSettings.AutoExposureLowPercent,
            View.FinalPostProcessSettings.AutoExposureHighPercent);

        // 3. 노출 값 계산
        float TargetExposure = 0.18f / AverageLuminance;  // 18% 그레이 기준

        // 4. 범위 클램핑
        TargetExposure = FMath::Clamp(
            TargetExposure,
            View.FinalPostProcessSettings.AutoExposureMinBrightness,
            View.FinalPostProcessSettings.AutoExposureMaxBrightness);

        // 5. 시간에 따른 적응
        float AdaptedExposure = AdaptExposure(
            PreviousExposure,
            TargetExposure,
            View.FinalPostProcessSettings.AutoExposureSpeedUp,
            View.FinalPostProcessSettings.AutoExposureSpeedDown,
            DeltaTime);

        return AdaptedExposure;
    }
};
```

### 히스토그램 셰이더

```hlsl
// 휘도 히스토그램 생성
[numthreads(8, 8, 1)]
void BuildHistogramCS(uint3 DispatchThreadId : SV_DispatchThreadID)
{
    float2 UV = (DispatchThreadId.xy + 0.5) / InputSize;
    float3 Color = SceneColorTexture.SampleLevel(UV, 0).rgb;

    // 휘도 계산 (Rec. 709)
    float Luminance = dot(Color, float3(0.2126, 0.7152, 0.0722));

    // 로그 휘도로 변환 (더 나은 분포)
    float LogLuminance = log2(max(Luminance, 0.0001));

    // 히스토그램 범위 [-8, 8] EV 매핑
    float NormalizedLog = (LogLuminance + 8.0) / 16.0;
    NormalizedLog = saturate(NormalizedLog);

    // 버킷 인덱스 결정
    uint BucketIndex = uint(NormalizedLog * (HISTOGRAM_SIZE - 1));

    // 아토믹 카운트 증가
    InterlockedAdd(HistogramBuffer[BucketIndex], 1);
}

// 히스토그램 분석
[numthreads(1, 1, 1)]
void AnalyzeHistogramCS()
{
    uint TotalPixels = InputWidth * InputHeight;
    uint LowCount = uint(TotalPixels * LowPercent);
    uint HighCount = uint(TotalPixels * HighPercent);

    // 하위/상위 백분위 제외한 평균 계산
    uint AccumulatedCount = 0;
    float WeightedSum = 0;
    uint ValidCount = 0;

    for (uint i = 0; i < HISTOGRAM_SIZE; i++)
    {
        uint BucketCount = HistogramBuffer[i];
        uint PrevAccumulated = AccumulatedCount;
        AccumulatedCount += BucketCount;

        // 범위 내 픽셀만 계산
        if (AccumulatedCount > LowCount && PrevAccumulated < (TotalPixels - HighCount))
        {
            float LogLuminance = (float(i) / (HISTOGRAM_SIZE - 1)) * 16.0 - 8.0;
            float Luminance = exp2(LogLuminance);

            WeightedSum += Luminance * BucketCount;
            ValidCount += BucketCount;
        }
    }

    float AverageLuminance = WeightedSum / max(ValidCount, 1);
    OutputAverageLuminance[0] = AverageLuminance;
}
```

### 적응 속도

```cpp
// 시간에 따른 노출 적응
float AdaptExposure(
    float CurrentExposure,
    float TargetExposure,
    float SpeedUp,
    float SpeedDown,
    float DeltaTime)
{
    float Speed = (TargetExposure > CurrentExposure) ? SpeedUp : SpeedDown;

    // 지수 적응
    float Alpha = 1.0f - FMath::Exp(-DeltaTime * Speed);

    return FMath::Lerp(CurrentExposure, TargetExposure, Alpha);
}
```

---

## 톤 매핑 연산자

### ACES 톤 매핑

```hlsl
// ACES (Academy Color Encoding System) 톤 매핑
// UE의 기본 톤 매퍼

float3 ACESFilm(float3 x)
{
    // ACES 근사 (Stephen Hill 버전)
    float a = 2.51f;
    float b = 0.03f;
    float c = 2.43f;
    float d = 0.59f;
    float e = 0.14f;

    return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}

// ACES 전체 파이프라인
float3 ACESToneMapping(float3 LinearColor)
{
    // 1. 노출 적용
    float3 ExposedColor = LinearColor * Exposure;

    // 2. RRT (Reference Rendering Transform)
    //    - 색공간 변환: sRGB → AP1
    //    - 글로우 매핑
    //    - 레드 수정
    float3 RRTColor = RRT(ExposedColor);

    // 3. ODT (Output Device Transform)
    //    - sRGB 디스플레이용 변환
    float3 ODTColor = ODT_sRGB(RRTColor);

    return ODTColor;
}
```

### Filmic 톤 매핑

```hlsl
// Uncharted 2 Filmic 톤 매핑 (John Hable)
float3 Uncharted2Tonemap(float3 x)
{
    float A = 0.15f;  // Shoulder Strength
    float B = 0.50f;  // Linear Strength
    float C = 0.10f;  // Linear Angle
    float D = 0.20f;  // Toe Strength
    float E = 0.02f;  // Toe Numerator
    float F = 0.30f;  // Toe Denominator

    return ((x * (A * x + C * B) + D * E) / (x * (A * x + B) + D * F)) - E / F;
}

float3 FilmicToneMapping(float3 Color)
{
    float ExposureBias = 2.0f;
    float3 Curr = Uncharted2Tonemap(ExposureBias * Color);

    float3 W = float3(11.2f, 11.2f, 11.2f);  // Linear White Point
    float3 WhiteScale = 1.0f / Uncharted2Tonemap(W);

    return Curr * WhiteScale;
}
```

### Reinhard 톤 매핑

```hlsl
// 간단한 Reinhard 톤 매핑
float3 ReinhardTonemap(float3 Color)
{
    return Color / (1.0f + Color);
}

// 확장 Reinhard (화이트 포인트 지정)
float3 ReinhardExtended(float3 Color, float WhitePoint)
{
    float3 Numerator = Color * (1.0f + (Color / (WhitePoint * WhitePoint)));
    return Numerator / (1.0f + Color);
}

// 휘도 기반 Reinhard
float3 ReinhardLuminance(float3 Color)
{
    float Luminance = dot(Color, float3(0.2126, 0.7152, 0.0722));
    float MappedLuminance = Luminance / (1.0f + Luminance);
    return Color * (MappedLuminance / Luminance);
}
```

### UE 톤 매퍼 설정

```cpp
// 톤 매퍼 선택
UENUM()
enum class ETonemapperType : uint8
{
    // ACES (기본)
    ACES,

    // 필름 슬로프/토/숄더/블랙클립/화이트클립 조절 가능
    FilmSlope,

    // 커스텀
    Custom,
};

// 포스트 프로세스 설정
UPROPERTY()
float FilmSlope = 0.88f;

UPROPERTY()
float FilmToe = 0.55f;

UPROPERTY()
float FilmShoulder = 0.26f;

UPROPERTY()
float FilmBlackClip = 0.0f;

UPROPERTY()
float FilmWhiteClip = 0.04f;
```

---

## 컬러 그레이딩

### 컬러 보정 파라미터

```cpp
// 글로벌 컬러 보정
struct FColorGradingSettings
{
    // 휘도 영역별 조절
    struct FColorAdjustment
    {
        FVector4 Saturation;    // 채도
        FVector4 Contrast;      // 대비
        FVector4 Gamma;         // 감마
        FVector4 Gain;          // 게인
        FVector4 Offset;        // 오프셋
    };

    FColorAdjustment Global;     // 전체
    FColorAdjustment Shadows;    // 어두운 영역
    FColorAdjustment Midtones;   // 중간 영역
    FColorAdjustment Highlights; // 밝은 영역
};
```

### 컬러 그레이딩 셰이더

```hlsl
// 컬러 그레이딩 적용
float3 ApplyColorGrading(float3 Color, FColorGradingParams Params)
{
    // 휘도 계산
    float Luminance = dot(Color, float3(0.2126, 0.7152, 0.0722));

    // 영역 가중치 계산
    float ShadowWeight = 1.0 - smoothstep(0.0, 0.33, Luminance);
    float HighlightWeight = smoothstep(0.55, 1.0, Luminance);
    float MidtoneWeight = 1.0 - ShadowWeight - HighlightWeight;

    // 글로벌 조절
    Color = ApplyColorAdjustment(Color, Params.Global);

    // 영역별 조절
    float3 ShadowColor = ApplyColorAdjustment(Color, Params.Shadows);
    float3 MidtoneColor = ApplyColorAdjustment(Color, Params.Midtones);
    float3 HighlightColor = ApplyColorAdjustment(Color, Params.Highlights);

    // 블렌딩
    Color = ShadowColor * ShadowWeight
          + MidtoneColor * MidtoneWeight
          + HighlightColor * HighlightWeight;

    return Color;
}

// 개별 조절 적용
float3 ApplyColorAdjustment(float3 Color, FColorAdjustment Adj)
{
    float Luminance = dot(Color, float3(0.2126, 0.7152, 0.0722));

    // 채도
    Color = lerp(Luminance.xxx, Color, Adj.Saturation.rgb * Adj.Saturation.a);

    // 대비
    Color = (Color - 0.5) * (Adj.Contrast.rgb * Adj.Contrast.a) + 0.5;

    // 감마
    Color = pow(max(Color, 0), 1.0 / (Adj.Gamma.rgb * Adj.Gamma.a));

    // 게인
    Color *= Adj.Gain.rgb * Adj.Gain.a;

    // 오프셋
    Color += Adj.Offset.rgb * Adj.Offset.a;

    return Color;
}
```

---

## LUT (Look-Up Table)

### LUT 개념

```
┌─────────────────────────────────────────────────────────────────┐
│                    Color LUT                                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  3D LUT (32x32x32)                                              │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                         │   │
│  │    입력 색상 (R, G, B) → LUT 인덱스 → 출력 색상          │   │
│  │                                                         │   │
│  │    ┌────────────────────────────────────────────────┐   │   │
│  │    │  R ───→ X축                                    │   │   │
│  │    │  G ───→ Y축                                    │   │   │
│  │    │  B ───→ Z축                                    │   │   │
│  │    │                                                │   │   │
│  │    │  각 셀에 변환된 RGB 값 저장                     │   │   │
│  │    └────────────────────────────────────────────────┘   │   │
│  │                                                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  2D Atlas 형태 (UE에서 사용)                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                         │   │
│  │  256x16 텍스처 (16x16 그리드 × 16 슬라이스)              │   │
│  │                                                         │   │
│  │  ┌──┬──┬──┬──┬──┬──┬──┬──┬──┬──┬──┬──┬──┬──┬──┬──┐   │   │
│  │  │0 │1 │2 │3 │4 │5 │6 │7 │8 │9 │10│11│12│13│14│15│   │   │
│  │  │  │  │  │  │  │  │  │  │  │  │  │  │  │  │  │  │   │   │
│  │  │B=│B=│B=│B=│B=│B=│B=│B=│B=│B=│B=│B=│B=│B=│B=│B=│   │   │
│  │  │0 │1 │2 │3 │4 │5 │6 │7 │8 │9 │10│11│12│13│14│15│   │   │
│  │  └──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┘   │   │
│  │    │    │                                              │   │
│  │    R    G                                              │   │
│  │                                                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### LUT 샘플링

```hlsl
// 2D LUT 텍스처에서 색상 변환
float3 ApplyLUT(float3 Color, Texture2D LUTTexture, float LUTSize)
{
    // 색상을 0-1 범위로 클램프
    Color = saturate(Color);

    // LUT 파라미터
    float SliceSize = 1.0 / LUTSize;            // 각 슬라이스 크기
    float SlicePixelSize = SliceSize / LUTSize;  // 슬라이스 내 픽셀
    float SliceInnerSize = SlicePixelSize * (LUTSize - 1.0);

    // Blue 채널로 슬라이스 선택
    float BlueSlice0 = floor(Color.b * (LUTSize - 1.0));
    float BlueSlice1 = ceil(Color.b * (LUTSize - 1.0));

    // 슬라이스 간 보간 가중치
    float BlendFactor = frac(Color.b * (LUTSize - 1.0));

    // UV 계산
    float2 UV0, UV1;
    UV0.x = BlueSlice0 * SliceSize + Color.r * SliceInnerSize + SlicePixelSize * 0.5;
    UV0.y = Color.g * SliceInnerSize + SlicePixelSize * 0.5;

    UV1.x = BlueSlice1 * SliceSize + Color.r * SliceInnerSize + SlicePixelSize * 0.5;
    UV1.y = Color.g * SliceInnerSize + SlicePixelSize * 0.5;

    // 샘플링 및 보간
    float3 Color0 = LUTTexture.SampleLevel(LinearSampler, UV0, 0).rgb;
    float3 Color1 = LUTTexture.SampleLevel(LinearSampler, UV1, 0).rgb;

    return lerp(Color0, Color1, BlendFactor);
}
```

### LUT 생성

```cpp
// 런타임 LUT 생성
UTexture2D* CreateColorLUT(const FColorGradingSettings& Settings)
{
    const int32 LUTSize = 32;
    const int32 Width = LUTSize * LUTSize;
    const int32 Height = LUTSize;

    TArray<FColor> Pixels;
    Pixels.SetNum(Width * Height);

    for (int32 B = 0; B < LUTSize; B++)
    {
        for (int32 G = 0; G < LUTSize; G++)
        {
            for (int32 R = 0; R < LUTSize; R++)
            {
                // 입력 색상
                FLinearColor InColor(
                    R / float(LUTSize - 1),
                    G / float(LUTSize - 1),
                    B / float(LUTSize - 1));

                // 컬러 그레이딩 적용
                FLinearColor OutColor = ApplyColorGrading(InColor, Settings);

                // 텍스처에 저장
                int32 X = B * LUTSize + R;
                int32 Y = G;
                Pixels[Y * Width + X] = OutColor.ToFColor(false);
            }
        }
    }

    // 텍스처 생성
    UTexture2D* LUT = UTexture2D::CreateTransient(Width, Height, PF_B8G8R8A8);
    // ... 픽셀 데이터 업로드

    return LUT;
}
```

---

## 화이트 밸런스

### 색온도 보정

```hlsl
// 색온도 (Kelvin) → RGB 변환
float3 ColorTemperatureToRGB(float Temperature)
{
    // 색온도를 100으로 나눔
    float Temp = Temperature / 100.0;

    float3 Color;

    // Red
    if (Temp <= 66.0)
    {
        Color.r = 255;
    }
    else
    {
        Color.r = 329.698727446 * pow(Temp - 60.0, -0.1332047592);
    }

    // Green
    if (Temp <= 66.0)
    {
        Color.g = 99.4708025861 * log(Temp) - 161.1195681661;
    }
    else
    {
        Color.g = 288.1221695283 * pow(Temp - 60.0, -0.0755148492);
    }

    // Blue
    if (Temp >= 66.0)
    {
        Color.b = 255;
    }
    else if (Temp <= 19.0)
    {
        Color.b = 0;
    }
    else
    {
        Color.b = 138.5177312231 * log(Temp - 10.0) - 305.0447927307;
    }

    return saturate(Color / 255.0);
}

// 화이트 밸런스 적용
float3 ApplyWhiteBalance(float3 Color, float Temperature, float Tint)
{
    // 색온도 보정 색상
    float3 TempColor = ColorTemperatureToRGB(Temperature);

    // 틴트 (마젠타-그린 축)
    float3 TintColor = float3(1, 1.0 + Tint * 0.5, 1);

    // 적용 (곱셈 블렌딩)
    return Color * TempColor * TintColor;
}
```

---

## 최종 톤 매핑 패스

### 통합 셰이더

```hlsl
// 최종 톤 매핑 + 컬러 그레이딩 셰이더
float4 TonemapAndColorGradePS(float2 UV : TEXCOORD0) : SV_Target
{
    // 씬 컬러 샘플링
    float3 HDRColor = SceneColorTexture.Sample(PointSampler, UV).rgb;

    // 1. 노출 적용
    HDRColor *= Exposure;

    // 2. 화이트 밸런스
    HDRColor = ApplyWhiteBalance(HDRColor, WhiteTemperature, WhiteTint);

    // 3. 컬러 그레이딩 (HDR 상태에서)
    HDRColor = ApplyColorGrading(HDRColor, ColorGradingParams);

    // 4. 톤 매핑 (HDR → LDR)
    float3 LDRColor = ACESFilm(HDRColor);

    // 5. LUT 적용 (최종 룩)
    if (bUseLUT)
    {
        LDRColor = ApplyLUT(LDRColor, ColorGradingLUT, LUTSize);
    }

    // 6. 감마 보정 (sRGB 출력)
    float3 sRGBColor = LinearToSRGB(LDRColor);

    return float4(sRGBColor, 1);
}
```

---

## 설정 예제

### 영화적 룩

```cpp
// 영화적 룩 설정 예제
void SetupCinematicLook(FPostProcessSettings& Settings)
{
    // 톤 매핑
    Settings.bOverride_FilmSlope = true;
    Settings.FilmSlope = 0.8f;

    Settings.bOverride_FilmToe = true;
    Settings.FilmToe = 0.6f;

    Settings.bOverride_FilmShoulder = true;
    Settings.FilmShoulder = 0.2f;

    // 노출
    Settings.bOverride_AutoExposureBias = true;
    Settings.AutoExposureBias = 0.5f;

    // 컬러 그레이딩 - 약간 탈색
    Settings.bOverride_ColorSaturation = true;
    Settings.ColorSaturation = FVector4(0.9f, 0.9f, 0.9f, 1.0f);

    // 그림자에 청색 추가
    Settings.bOverride_ColorGainShadows = true;
    Settings.ColorGainShadows = FVector4(0.95f, 0.95f, 1.05f, 1.0f);

    // 하이라이트에 따뜻한 톤
    Settings.bOverride_ColorGainHighlights = true;
    Settings.ColorGainHighlights = FVector4(1.05f, 1.02f, 0.98f, 1.0f);
}
```

---

## 요약

| 구성 요소 | 역할 |
|----------|------|
| Auto Exposure | 밝기에 따른 동적 노출 조절 |
| Tone Mapping | HDR→LDR 압축 (ACES, Filmic 등) |
| Color Grading | 채도, 대비, 감마 등 색상 조절 |
| LUT | 미리 계산된 색상 변환 테이블 |
| White Balance | 색온도 및 틴트 보정 |

톤 매핑과 컬러 그레이딩은 최종 이미지의 분위기를 결정하는 핵심 요소입니다.
