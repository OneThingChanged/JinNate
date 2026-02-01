# UI 머티리얼과 이펙트

UI에서 사용되는 머티리얼, 포스트 프로세스 효과, 커스텀 셰이더를 분석합니다.

---

## UI 머티리얼 개요

```
┌─────────────────────────────────────────────────────────────────┐
│                   UI Material Overview                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  UI 머티리얼 = User Interface 도메인 머티리얼                    │
│                                                                 │
│  특징:                                                          │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • Material Domain: User Interface                       │   │
│  │ • Blend Mode: Translucent, Masked, Opaque              │   │
│  │ • 라이팅 없음 (Unlit)                                   │   │
│  │ • 2D 렌더링 최적화                                      │   │
│  │ • 동적 파라미터 지원                                    │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  사용 사례:                                                     │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         │
│  │ Progress Bar │  │ Radar/Minimap│  │ Blur Effect  │         │
│  │ Animation    │  │ Overlay      │  │ Distortion   │         │
│  └──────────────┘  └──────────────┘  └──────────────┘         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Material Domain 설정

```
┌─────────────────────────────────────────────────────────────────┐
│               User Interface Material Domain                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Material Properties:                                           │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  Material Domain    ──►  User Interface                  │   │
│  │                                                          │   │
│  │  Blend Mode         ──►  Translucent                     │   │
│  │                          (또는 Masked, Opaque)           │   │
│  │                                                          │   │
│  │  Two Sided          ──►  Disabled (일반적)               │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  출력 핀 (User Interface Domain):                               │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  Final Color  ─► 최종 RGB 출력                           │   │
│  │  Opacity      ─► 알파 값                                 │   │
│  │  Opacity Mask ─► 마스크 값 (Masked 모드)                 │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 기본 UI 머티리얼

```cpp
// C++에서 UI 머티리얼 생성
UMaterial* CreateUIMaterial()
{
    UMaterial* Material = NewObject<UMaterial>();

    // UI 도메인 설정
    Material->MaterialDomain = EMaterialDomain::MD_UI;
    Material->BlendMode = EBlendMode::BLEND_Translucent;

    // 텍스처 파라미터
    UMaterialExpressionTextureSampleParameter2D* TextureParam =
        NewObject<UMaterialExpressionTextureSampleParameter2D>(Material);
    TextureParam->ParameterName = TEXT("UITexture");
    Material->Expressions.Add(TextureParam);

    // 색상 파라미터
    UMaterialExpressionVectorParameter* ColorParam =
        NewObject<UMaterialExpressionVectorParameter>(Material);
    ColorParam->ParameterName = TEXT("TintColor");
    ColorParam->DefaultValue = FLinearColor::White;
    Material->Expressions.Add(ColorParam);

    // Multiply 노드
    UMaterialExpressionMultiply* Multiply =
        NewObject<UMaterialExpressionMultiply>(Material);
    Multiply->A.Connect(0, TextureParam);
    Multiply->B.Connect(0, ColorParam);
    Material->Expressions.Add(Multiply);

    // 출력 연결
    Material->EmissiveColor.Connect(0, Multiply);
    Material->Opacity.Connect(4, TextureParam); // Alpha

    return Material;
}
```

---

## 동적 머티리얼 인스턴스

```
┌─────────────────────────────────────────────────────────────────┐
│              Dynamic Material Instance for UI                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  동적 파라미터 변경:                                            │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  Widget                                                  │   │
│  │     │                                                    │   │
│  │     ▼                                                    │   │
│  │  UImage                                                  │   │
│  │     │                                                    │   │
│  │     ▼                                                    │   │
│  │  Set Brush From Material()                               │   │
│  │     │                                                    │   │
│  │     ▼                                                    │   │
│  │  UMaterialInstanceDynamic                                │   │
│  │     │                                                    │   │
│  │     └─► SetScalarParameter("Progress", 0.75)            │   │
│  │     └─► SetVectorParameter("Color", Red)                │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 동적 머티리얼 사용

```cpp
// 프로그레스 바 위젯
UCLASS()
class UProgressBarWidget : public UUserWidget
{
    GENERATED_BODY()

public:
    void SetProgress(float Value)
    {
        Progress = FMath::Clamp(Value, 0.0f, 1.0f);

        if (MaterialInstance)
        {
            MaterialInstance->SetScalarParameterValue(
                TEXT("Progress"), Progress
            );
        }
    }

    void SetColor(FLinearColor Color)
    {
        if (MaterialInstance)
        {
            MaterialInstance->SetVectorParameterValue(
                TEXT("BarColor"), Color
            );
        }
    }

protected:
    virtual void NativeConstruct() override
    {
        Super::NativeConstruct();

        // 동적 머티리얼 인스턴스 생성
        if (ProgressMaterial && ProgressImage)
        {
            MaterialInstance = UMaterialInstanceDynamic::Create(
                ProgressMaterial, this
            );

            // 이미지에 머티리얼 적용
            ProgressImage->SetBrushFromMaterial(MaterialInstance);
        }
    }

private:
    UPROPERTY(meta = (BindWidget))
    UImage* ProgressImage;

    UPROPERTY(EditDefaultsOnly)
    UMaterialInterface* ProgressMaterial;

    UPROPERTY()
    UMaterialInstanceDynamic* MaterialInstance;

    float Progress = 0.0f;
};
```

---

## UI 포스트 프로세스

```
┌─────────────────────────────────────────────────────────────────┐
│                   UI Post Process Effects                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  UI 레이어에 적용되는 포스트 프로세스:                           │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  ┌─────────────┐                                        │   │
│  │  │  3D Scene   │  ◄── 기존 렌더링                       │   │
│  │  └──────┬──────┘                                        │   │
│  │         ▼                                                │   │
│  │  ┌─────────────┐                                        │   │
│  │  │ Background  │  ◄── 배경 블러                         │   │
│  │  │ Blur        │                                        │   │
│  │  └──────┬──────┘                                        │   │
│  │         ▼                                                │   │
│  │  ┌─────────────┐                                        │   │
│  │  │  UI Layer   │  ◄── UI 위젯                           │   │
│  │  └──────┬──────┘                                        │   │
│  │         ▼                                                │   │
│  │  ┌─────────────┐                                        │   │
│  │  │ Final       │  ◄── 최종 합성                         │   │
│  │  │ Composite   │                                        │   │
│  │  └─────────────┘                                        │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 배경 블러 구현

```cpp
// BackgroundBlur 위젯 사용
UCLASS()
class UBlurMenuWidget : public UUserWidget
{
    GENERATED_BODY()

protected:
    virtual void NativeConstruct() override
    {
        Super::NativeConstruct();

        // 블러 강도 애니메이션
        if (BlurBackground)
        {
            // 초기값 설정
            BlurBackground->SetBlurStrength(0.0f);

            // 블러 인 애니메이션
            GetWorld()->GetTimerManager().SetTimer(
                BlurAnimTimer,
                [this]()
                {
                    CurrentBlur = FMath::FInterpTo(
                        CurrentBlur, TargetBlur,
                        GetWorld()->GetDeltaSeconds(), 5.0f
                    );
                    BlurBackground->SetBlurStrength(CurrentBlur);
                },
                0.016f, true
            );
        }
    }

    void SetBlurStrength(float Strength)
    {
        TargetBlur = Strength;
    }

private:
    UPROPERTY(meta = (BindWidget))
    UBackgroundBlur* BlurBackground;

    float CurrentBlur = 0.0f;
    float TargetBlur = 10.0f;
    FTimerHandle BlurAnimTimer;
};

// 또는 머티리얼 기반 블러
// Material Graph에서:
// SceneTexture (Post Process Input 0) → Gaussian Blur → Final Color
```

---

## Retainer Box 효과

```
┌─────────────────────────────────────────────────────────────────┐
│                    Retainer Box Effects                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Retainer Box = 위젯을 렌더 타겟에 캐싱                          │
│                                                                 │
│  효과 머티리얼 적용 가능:                                        │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  Normal Widget:                                          │   │
│  │  ┌────────────┐                                         │   │
│  │  │  Widget A  │ ──► Direct Render                       │   │
│  │  └────────────┘                                         │   │
│  │                                                          │   │
│  │  With Retainer Box:                                      │   │
│  │  ┌────────────┐    ┌────────────┐    ┌────────────┐    │   │
│  │  │  Widget A  │ ─► │ Render     │ ─► │ Effect     │    │   │
│  │  │            │    │ Target     │    │ Material   │    │   │
│  │  └────────────┘    └────────────┘    └────────────┘    │   │
│  │                                                          │   │
│  │  가능한 효과:                                            │   │
│  │  • 블러                                                  │   │
│  │  • 그림자                                                │   │
│  │  • 글로우                                                │   │
│  │  • 디스토션                                              │   │
│  │  • 컬러 그레이딩                                         │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Retainer Box 설정

```cpp
// Retainer Box와 이펙트 머티리얼
UCLASS()
class UGlowTextWidget : public UUserWidget
{
    GENERATED_BODY()

protected:
    virtual void NativeConstruct() override
    {
        Super::NativeConstruct();

        if (GlowRetainer && GlowMaterial)
        {
            // 이펙트 머티리얼 설정
            GlowMaterialInstance = UMaterialInstanceDynamic::Create(
                GlowMaterial, this
            );
            GlowRetainer->SetEffectMaterial(GlowMaterialInstance);

            // 렌더링 페이즈 설정
            GlowRetainer->SetRenderingPhase(1, 1);
        }
    }

    void SetGlowColor(FLinearColor Color)
    {
        if (GlowMaterialInstance)
        {
            GlowMaterialInstance->SetVectorParameterValue(
                TEXT("GlowColor"), Color
            );
        }
    }

    void SetGlowIntensity(float Intensity)
    {
        if (GlowMaterialInstance)
        {
            GlowMaterialInstance->SetScalarParameterValue(
                TEXT("GlowIntensity"), Intensity
            );
        }
    }

private:
    UPROPERTY(meta = (BindWidget))
    URetainerBox* GlowRetainer;

    UPROPERTY(EditDefaultsOnly)
    UMaterialInterface* GlowMaterial;

    UPROPERTY()
    UMaterialInstanceDynamic* GlowMaterialInstance;
};
```

---

## 커스텀 UI 셰이더

```
┌─────────────────────────────────────────────────────────────────┐
│                   Custom UI Shaders                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Material Graph 예시 - 원형 프로그레스:                          │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  TexCoord ──► Remap to -1,1                              │   │
│  │      │                                                   │   │
│  │      ▼                                                   │   │
│  │  Atan2(Y, X) ──► Angle                                   │   │
│  │      │                                                   │   │
│  │      ▼                                                   │   │
│  │  Remap 0-1 ──► Compare with Progress                     │   │
│  │      │                                                   │   │
│  │      ▼                                                   │   │
│  │  Step ──► Opacity Mask                                   │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### HLSL 커스텀 노드

```hlsl
// 원형 프로그레스 바 (Custom Expression)
// Inputs: UV (Vector2), Progress (Scalar), StartAngle (Scalar)

float2 CenteredUV = UV - 0.5;
float Angle = atan2(CenteredUV.y, CenteredUV.x);

// -PI ~ PI → 0 ~ 1 변환
float NormalizedAngle = (Angle + 3.14159) / (2.0 * 3.14159);

// 시작 각도 오프셋
NormalizedAngle = frac(NormalizedAngle - StartAngle);

// 프로그레스 비교
float Mask = step(NormalizedAngle, Progress);

// 원형 마스크 (외곽 페더링)
float Dist = length(CenteredUV);
float CircleMask = smoothstep(0.5, 0.48, Dist) * smoothstep(0.3, 0.32, Dist);

return Mask * CircleMask;
```

### 복잡한 UI 효과

```hlsl
// 홀로그램 효과
// Inputs: UV, Time, BaseColor

// 스캔라인
float ScanLine = frac(UV.y * 100.0 - Time * 2.0);
ScanLine = smoothstep(0.0, 0.1, ScanLine) * smoothstep(1.0, 0.9, ScanLine);

// 글리치
float Glitch = step(0.99, frac(sin(floor(Time * 20.0) * 12.9898) * 43758.5453));
float2 GlitchUV = UV;
GlitchUV.x += Glitch * sin(UV.y * 50.0) * 0.02;

// 색수차
float3 FinalColor;
FinalColor.r = Texture2DSample(Tex, Sampler, GlitchUV + float2(0.005, 0)).r;
FinalColor.g = Texture2DSample(Tex, Sampler, GlitchUV).g;
FinalColor.b = Texture2DSample(Tex, Sampler, GlitchUV - float2(0.005, 0)).b;

// 스캔라인 적용
FinalColor *= lerp(0.8, 1.2, ScanLine);

// 플리커
float Flicker = lerp(0.9, 1.0, frac(Time * 30.0));
FinalColor *= Flicker;

return float4(FinalColor * BaseColor.rgb, BaseColor.a);
```

---

## 마스킹 기법

```
┌─────────────────────────────────────────────────────────────────┐
│                     Masking Techniques                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. 알파 마스킹                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Texture Alpha ──► Opacity                               │   │
│  │  부드러운 엣지, 반투명 지원                              │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  2. 마스크 텍스처                                               │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Mask Texture (R채널) ──► Opacity Mask                   │   │
│  │  복잡한 형태 마스킹                                      │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  3. SDF (Signed Distance Field)                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  SDF Texture ──► Smoothstep ──► Sharp Edge               │   │
│  │  해상도 독립적 마스킹                                    │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  4. 절차적 마스킹                                               │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Math Functions ──► Procedural Shape                     │   │
│  │  원, 사각형, 다각형 등                                   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 절차적 형태 마스크

```hlsl
// 둥근 사각형 마스크
float RoundedBoxMask(float2 UV, float2 Size, float Radius)
{
    float2 CenteredUV = UV - 0.5;
    float2 HalfSize = Size * 0.5 - Radius;

    float2 d = abs(CenteredUV) - HalfSize;
    float Dist = length(max(d, 0)) + min(max(d.x, d.y), 0) - Radius;

    return 1.0 - smoothstep(0, 0.01, Dist);
}

// 육각형 마스크
float HexagonMask(float2 UV)
{
    float2 CenteredUV = UV - 0.5;
    CenteredUV = abs(CenteredUV);

    float c = dot(CenteredUV, normalize(float2(1, 1.73)));
    c = max(c, CenteredUV.x);

    return 1.0 - smoothstep(0.4, 0.41, c);
}

// 방사형 와이프 마스크 (로딩 효과)
float RadialWipeMask(float2 UV, float Progress)
{
    float2 CenteredUV = UV - 0.5;
    float Angle = atan2(CenteredUV.y, CenteredUV.x);
    float NormalizedAngle = (Angle + 3.14159) / (2.0 * 3.14159);

    return step(NormalizedAngle, Progress);
}
```

---

## 주요 클래스 요약

| 클래스 | 역할 |
|--------|------|
| `UMaterial` | 머티리얼 애셋 |
| `UMaterialInstanceDynamic` | 런타임 머티리얼 인스턴스 |
| `UImage` | 이미지 위젯 (머티리얼 지원) |
| `URetainerBox` | 렌더 타겟 캐싱 위젯 |
| `UBackgroundBlur` | 배경 블러 위젯 |
| `FSlateBrush` | 브러시 (머티리얼 참조) |

---

## 참고 자료

- [UI Materials](https://docs.unrealengine.com/ui-materials/)
- [Material Domain](https://docs.unrealengine.com/material-domain/)
- [Retainer Box](https://docs.unrealengine.com/retainer-box/)
