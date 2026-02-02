# Ch.07 포스트 프로세싱

UE의 포스트 프로세싱 파이프라인과 다양한 효과들을 분석합니다.

---

## 개요

포스트 프로세싱은 씬 렌더링 후 최종 이미지에 적용되는 효과들입니다. 톤 매핑, 블룸, 모션 블러 등 영화적 품질을 위한 핵심 기술입니다.

![디퍼드 렌더링에서 포스트 프로세싱](../images/ch07/1617944-20210505184316256-1193511203.png)

*G-Buffer 기반 디퍼드 렌더링 파이프라인 - 포스트 프로세싱의 입력이 되는 씬 컬러가 생성되는 과정*

```
┌─────────────────────────────────────────────────────────────────┐
│                    포스트 프로세싱 파이프라인                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Scene Color (HDR)                                              │
│       │                                                         │
│       ▼                                                         │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    Screen Space Effects                  │   │
│  │  ┌───────────┐  ┌───────────┐  ┌───────────┐            │   │
│  │  │   SSAO    │  │    SSR    │  │    SSS    │            │   │
│  │  │ (앰비언트 │  │  (반사)   │  │(서브서피스)│            │   │
│  │  │  오클루전)│  │           │  │           │            │   │
│  │  └───────────┘  └───────────┘  └───────────┘            │   │
│  └────────────────────────┬────────────────────────────────┘   │
│                           │                                     │
│                           ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    Temporal Effects                      │   │
│  │  ┌───────────┐  ┌───────────┐  ┌───────────┐            │   │
│  │  │   TAA     │  │  Motion   │  │   DOF     │            │   │
│  │  │           │  │   Blur    │  │ (피사계   │            │   │
│  │  │           │  │           │  │  심도)    │            │   │
│  │  └───────────┘  └───────────┘  └───────────┘            │   │
│  └────────────────────────┬────────────────────────────────┘   │
│                           │                                     │
│                           ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    Light Effects                         │   │
│  │  ┌───────────┐  ┌───────────┐  ┌───────────┐            │   │
│  │  │   Bloom   │  │   Lens    │  │   Light   │            │   │
│  │  │           │  │   Flare   │  │   Shafts  │            │   │
│  │  └───────────┘  └───────────┘  └───────────┘            │   │
│  └────────────────────────┬────────────────────────────────┘   │
│                           │                                     │
│                           ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    Color Processing                      │   │
│  │  ┌───────────┐  ┌───────────┐  ┌───────────┐            │   │
│  │  │  Auto     │  │   Tone    │  │   Color   │            │   │
│  │  │ Exposure  │  │  Mapping  │  │  Grading  │            │   │
│  │  └───────────┘  └───────────┘  └───────────┘            │   │
│  └────────────────────────┬────────────────────────────────┘   │
│                           │                                     │
│                           ▼                                     │
│                    Final Image (LDR)                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 목차

| 문서 | 주제 | 핵심 내용 |
|------|------|----------|
| [01](01-post-process-overview.md) | 포스트 프로세스 개요 | 파이프라인, 볼륨, 머티리얼 |
| [02](02-tone-mapping-color.md) | 톤 매핑과 컬러 | 노출, 톤 매핑, 컬러 그레이딩 |
| [03](03-bloom-effects.md) | 블룸과 광원 효과 | Bloom, Lens Flare, Light Shafts |
| [04](04-temporal-effects.md) | 템포럴 효과 | Motion Blur, DOF, TAA |
| [05](05-screen-space-effects.md) | 스크린 스페이스 효과 | SSAO, SSR, SSS |

---

## 포스트 프로세스 볼륨

### 기본 구조

```cpp
// 포스트 프로세스 볼륨
UCLASS()
class APostProcessVolume : public AVolume
{
    UPROPERTY()
    FPostProcessSettings Settings;

    // 볼륨 설정
    UPROPERTY()
    float BlendRadius;      // 블렌드 거리

    UPROPERTY()
    float BlendWeight;      // 블렌드 가중치

    UPROPERTY()
    bool bUnbound;          // 무한 영역 적용

    UPROPERTY()
    int32 Priority;         // 우선순위
};

// 포스트 프로세스 설정 구조체
USTRUCT()
struct FPostProcessSettings
{
    // 블룸
    UPROPERTY()
    float BloomIntensity;

    UPROPERTY()
    float BloomThreshold;

    // 노출
    UPROPERTY()
    float AutoExposureBias;

    UPROPERTY()
    float AutoExposureMinBrightness;

    UPROPERTY()
    float AutoExposureMaxBrightness;

    // 컬러 그레이딩
    UPROPERTY()
    FVector4 ColorSaturation;

    UPROPERTY()
    FVector4 ColorContrast;

    UPROPERTY()
    FVector4 ColorGamma;

    UPROPERTY()
    FVector4 ColorGain;

    // ... 수백 개의 추가 파라미터
};
```

### 볼륨 블렌딩

```cpp
// 뷰에서 최종 포스트 프로세스 설정 계산
void FSceneView::OverridePostProcessSettings(const FPostProcessSettings& Src, float Weight)
{
    // 가중치 기반 블렌딩
    if (Weight > 0.0f && Weight <= 1.0f)
    {
        // 각 파라미터별로 블렌딩
        FinalSettings.BloomIntensity = FMath::Lerp(
            FinalSettings.BloomIntensity,
            Src.BloomIntensity,
            Weight);

        FinalSettings.AutoExposureBias = FMath::Lerp(
            FinalSettings.AutoExposureBias,
            Src.AutoExposureBias,
            Weight);

        // ... 모든 파라미터에 대해 반복
    }
}

// 카메라 위치에 따른 볼륨 블렌딩
float ComputeVolumeWeight(APostProcessVolume* Volume, FVector CameraLocation)
{
    if (Volume->bUnbound)
    {
        return Volume->BlendWeight;
    }

    float Distance = Volume->GetDistanceToPoint(CameraLocation);

    if (Distance <= 0)
    {
        // 볼륨 내부
        return Volume->BlendWeight;
    }
    else if (Distance < Volume->BlendRadius)
    {
        // 블렌드 영역
        float Alpha = 1.0f - (Distance / Volume->BlendRadius);
        return Volume->BlendWeight * Alpha;
    }

    return 0.0f;
}
```

---

## 렌더링 순서

### 포스트 프로세스 패스

```cpp
// 포스트 프로세스 렌더링
void FDeferredShadingSceneRenderer::RenderPostProcessing()
{
    // 1. SSAO
    if (bSSAO)
    {
        RenderScreenSpaceAmbientOcclusion();
    }

    // 2. SSR
    if (bSSR)
    {
        RenderScreenSpaceReflections();
    }

    // 3. 라이팅 합성
    ComposeLighting();

    // 4. 반투명
    RenderTranslucency();

    // 5. DOF (씬 기반)
    if (bCircleDOF)
    {
        RenderCircleDOF();
    }

    // 6. 모션 블러
    if (bMotionBlur)
    {
        RenderMotionBlur();
    }

    // 7. TAA / TSR
    if (bTemporalAA)
    {
        RenderTemporalAA();
    }

    // 8. 블룸
    if (bBloom)
    {
        RenderBloom();
    }

    // 9. 톤 매핑 + 컬러 그레이딩
    RenderToneMappingAndColorGrading();

    // 10. FXAA (TAA 미사용 시)
    if (bFXAA && !bTemporalAA)
    {
        RenderFXAA();
    }

    // 11. UI 합성
    CompositeUI();
}
```

---

## 커스텀 포스트 프로세스

### 포스트 프로세스 머티리얼

```cpp
// 블렌더블 위치
UENUM()
enum EBlendableLocation
{
    BL_AfterTonemapping,           // 톤 매핑 후
    BL_BeforeTonemapping,          // 톤 매핑 전
    BL_BeforeTranslucency,         // 반투명 전
    BL_ReplacingTonemapper,        // 톤 매퍼 대체
    BL_SSRInput,                   // SSR 입력
};

// 포스트 프로세스 머티리얼 설정
UCLASS()
class UMaterialInterface
{
    // 블렌더블 위치
    UPROPERTY()
    EBlendableLocation BlendableLocation;

    // 출력 알파 사용 여부
    UPROPERTY()
    bool bOutputsAlpha;
};
```

### 커스텀 셰이더 예제

```hlsl
// 비네트 효과
float4 VignettePostProcess(float2 UV, float4 SceneColor)
{
    // 중심으로부터의 거리
    float2 Center = float2(0.5, 0.5);
    float Distance = length(UV - Center);

    // 비네트 강도 계산
    float Vignette = 1.0 - smoothstep(0.3, 0.7, Distance);

    // 적용
    return SceneColor * Vignette;
}

// 크로마틱 애버레이션
float4 ChromaticAberration(float2 UV, Texture2D SceneTexture)
{
    float2 Direction = UV - float2(0.5, 0.5);
    float Distance = length(Direction);

    float Offset = Distance * ChromaStrength;

    float R = SceneTexture.Sample(UV + Direction * Offset).r;
    float G = SceneTexture.Sample(UV).g;
    float B = SceneTexture.Sample(UV - Direction * Offset).b;

    return float4(R, G, B, 1);
}

// 필름 그레인
float4 FilmGrain(float2 UV, float4 SceneColor, float Time)
{
    // 노이즈 생성
    float Noise = frac(sin(dot(UV + Time, float2(12.9898, 78.233))) * 43758.5453);

    // 휘도 기반 강도
    float Luminance = dot(SceneColor.rgb, float3(0.299, 0.587, 0.114));
    float GrainStrength = lerp(0.1, 0.02, Luminance);

    // 적용
    return SceneColor + (Noise - 0.5) * GrainStrength;
}
```

---

## 성능 고려사항

### GPU 비용

```
┌────────────────────────────────────────────────────────────────┐
│                    포스트 프로세스 GPU 비용                      │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│  효과              │ 상대 비용 │ 해상도 영향                   │
│  ─────────────────┼───────────┼─────────────────────────────  │
│  Bloom            │ ●●○○○    │ 낮음 (다운샘플)               │
│  Tone Mapping     │ ●○○○○    │ 선형                         │
│  Color Grading    │ ●○○○○    │ 선형                         │
│  TAA              │ ●●○○○    │ 선형                         │
│  TSR              │ ●●●○○    │ 입력 해상도                  │
│  Motion Blur      │ ●●○○○    │ 선형                         │
│  DOF (Gaussian)   │ ●●○○○    │ 낮음 (다운샘플)               │
│  DOF (Bokeh)      │ ●●●●○    │ 높음                         │
│  SSAO             │ ●●●○○    │ 선형                         │
│  SSR              │ ●●●●○    │ 높음 (레이마칭)               │
│  FXAA             │ ●○○○○    │ 선형                         │
│                                                                │
│  ● = 상대적 비용 레벨                                          │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

### 최적화 전략

```cpp
// 해상도 스케일링
r.PostProcessing.Quality=0-4        // 품질 레벨
r.BloomQuality=0-5                  // 블룸 품질
r.MotionBlurQuality=0-4             // 모션 블러 품질
r.DepthOfFieldQuality=0-4           // DOF 품질

// 선택적 비활성화
r.DefaultFeature.Bloom=0
r.DefaultFeature.MotionBlur=0
r.DefaultFeature.AmbientOcclusion=0

// 콘솔별 설정
[XboxOne DeviceProfile]
r.PostProcessing.Quality=2
r.BloomQuality=3
```

---

## 디버깅

### 시각화 명령어

```cpp
// 버퍼 시각화
r.BufferVisualizationTarget=SceneColor
r.BufferVisualizationTarget=PostProcessInput0
r.BufferVisualizationTarget=FinalColor

// 개별 효과 토글
ShowFlag.Bloom 0
ShowFlag.MotionBlur 0
ShowFlag.DepthOfField 0
ShowFlag.Tonemapper 0

// 프로파일링
stat PostProcessing
profilegpu
```

---

## 학습 순서

1. **포스트 프로세스 개요** - 파이프라인과 볼륨 시스템
2. **톤 매핑과 컬러** - HDR→LDR 변환, 컬러 그레이딩
3. **블룸과 광원 효과** - 밝은 영역의 글로우
4. **템포럴 효과** - 시간 기반 효과들
5. **스크린 스페이스 효과** - 화면 정보 기반 효과

---

## 렌더링 품질 최적화

포스트 프로세싱에서 적응형 셰이딩을 통해 성능을 최적화할 수 있습니다.

![적응형 컴퓨트 셰이딩 비교](../images/ch07/1617944-20210505185000426-491469970.jpg)

*Deferred Adaptive Compute Shading vs Checkerboard 비교 - 동일 시간 대비 21.5% 낮은 오차, 동일 품질 대비 4.22배 빠른 성능*

---

## 참고 자료

- [UE 포스트 프로세스 공식 문서](https://docs.unrealengine.com/5.0/en-US/post-process-effects-in-unreal-engine/)
- [원문 시리즈 (중국어)](https://www.cnblogs.com/timlly/p/13512787.html)
---

<div style="display: flex; justify-content: space-between; align-items: center; padding: 16px 0;">
  <a href="../06-ue5-features/05-other-features/" style="text-decoration: none;">← 이전: Ch.06 05. UE5 신기능</a>
  <a href="01-post-process-overview/" style="text-decoration: none;">다음: 01. 포스트 프로세스 개요 →</a>
</div>
