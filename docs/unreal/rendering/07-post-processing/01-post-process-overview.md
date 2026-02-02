# 포스트 프로세스 개요

UE의 포스트 프로세싱 시스템 아키텍처와 파이프라인을 분석합니다.

---

## 포스트 프로세싱이란?

포스트 프로세싱은 3D 씬 렌더링이 완료된 후 2D 이미지에 적용되는 효과들입니다. 화면 전체에 적용되는 풀스크린 패스로 구현됩니다.

![G-Buffer 렌더링 파이프라인](../images/ch07/1617944-20210505184316256-1193511203.png)

*디퍼드 렌더링에서 G-Buffer가 생성되고 라이팅이 합성되는 과정 - 이 결과물이 포스트 프로세싱의 입력이 됨*

```
┌─────────────────────────────────────────────────────────────────┐
│                    렌더링 파이프라인에서의 위치                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  3D 렌더링 단계                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Geometry → Shading → Lighting → G-Buffer → Compose    │   │
│  └────────────────────────┬────────────────────────────────┘   │
│                           │                                     │
│                           ▼                                     │
│                    Scene Color (HDR)                            │
│                           │                                     │
│                           ▼                                     │
│  포스트 프로세싱 단계                                             │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                         │   │
│  │  Input: Scene Color, Depth, Velocity, G-Buffer          │   │
│  │                    │                                    │   │
│  │                    ▼                                    │   │
│  │  ┌──────────────────────────────────────────────────┐  │   │
│  │  │  Pass 1: SSAO                                     │  │   │
│  │  │  Pass 2: SSR                                      │  │   │
│  │  │  Pass 3: DOF                                      │  │   │
│  │  │  Pass 4: Motion Blur                              │  │   │
│  │  │  Pass 5: TAA/TSR                                  │  │   │
│  │  │  Pass 6: Bloom                                    │  │   │
│  │  │  Pass 7: Exposure                                 │  │   │
│  │  │  Pass 8: Tone Mapping                             │  │   │
│  │  │  Pass 9: Color Grading                            │  │   │
│  │  │  Pass 10: Film Effects                            │  │   │
│  │  └──────────────────────────────────────────────────┘  │   │
│  │                    │                                    │   │
│  │                    ▼                                    │   │
│  │  Output: Final Image (LDR, sRGB)                        │   │
│  │                                                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 시스템 아키텍처

### 핵심 클래스

```cpp
// 포스트 프로세스 렌더링 시스템
class FPostProcessing
{
public:
    // 메인 렌더링 함수
    static void Process(
        FRDGBuilder& GraphBuilder,
        const FViewInfo& View,
        const FSceneViewFamily& ViewFamily,
        TRDGUniformBufferRef<FSceneTextureUniformParameters> SceneTextures,
        FRDGTextureRef SceneColor,
        FRDGTextureRef SceneDepth,
        FRDGTextureRef SceneVelocity);

private:
    // 개별 패스들
    static void AddSSAOPass(FRDGBuilder& GraphBuilder, ...);
    static void AddSSRPass(FRDGBuilder& GraphBuilder, ...);
    static void AddBloomPass(FRDGBuilder& GraphBuilder, ...);
    static void AddTonemapPass(FRDGBuilder& GraphBuilder, ...);
    // ... 추가 패스들
};

// 포스트 프로세스 입력
struct FPostProcessInputs
{
    FRDGTextureRef SceneColor;
    FRDGTextureRef SceneDepth;
    FRDGTextureRef SceneVelocity;
    FRDGTextureRef GBufferA;
    FRDGTextureRef GBufferB;
    FRDGTextureRef GBufferC;
    FRDGTextureRef CustomDepth;
    FRDGTextureRef CustomStencil;
};
```

### 패스 구조

```cpp
// RDG 기반 포스트 프로세스 패스
void AddBloomPass(
    FRDGBuilder& GraphBuilder,
    const FViewInfo& View,
    FRDGTextureRef SceneColor,
    FRDGTextureRef& OutBloom)
{
    // 셰이더 파라미터 설정
    FBloomPassParameters* Parameters = GraphBuilder.AllocParameters<FBloomPassParameters>();
    Parameters->SceneColor = SceneColor;
    Parameters->BloomThreshold = View.FinalPostProcessSettings.BloomThreshold;
    Parameters->BloomIntensity = View.FinalPostProcessSettings.BloomIntensity;

    // 패스 추가
    GraphBuilder.AddPass(
        RDG_EVENT_NAME("Bloom"),
        Parameters,
        ERDGPassFlags::Compute,
        [Parameters, &View](FRHIComputeCommandList& RHICmdList)
        {
            // 셰이더 실행
            FBloomCS::FParameters ShaderParams;
            ShaderParams.SceneColorTexture = Parameters->SceneColor;
            ShaderParams.BloomThreshold = Parameters->BloomThreshold;

            TShaderMapRef<FBloomCS> ComputeShader(View.ShaderMap);
            FComputeShaderUtils::Dispatch(RHICmdList, ComputeShader, ShaderParams,
                FIntVector(View.ViewRect.Width(), View.ViewRect.Height(), 1));
        });
}
```

---

## 포스트 프로세스 볼륨

### 볼륨 시스템

```cpp
// 포스트 프로세스 볼륨 액터
UCLASS()
class APostProcessVolume : public AVolume
{
    GENERATED_BODY()

public:
    // 포스트 프로세스 설정
    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="PostProcess")
    FPostProcessSettings Settings;

    // 볼륨 속성
    UPROPERTY(EditAnywhere, Category="PostProcess")
    float BlendRadius = 100.0f;

    UPROPERTY(EditAnywhere, Category="PostProcess")
    float BlendWeight = 1.0f;

    UPROPERTY(EditAnywhere, Category="PostProcess")
    bool bEnabled = true;

    UPROPERTY(EditAnywhere, Category="PostProcess")
    bool bUnbound = false;  // true면 전체 월드에 적용

    UPROPERTY(EditAnywhere, Category="PostProcess")
    int32 Priority = 0;
};
```

### 설정 구조체

```cpp
// 포스트 프로세스 설정 (일부)
USTRUCT(BlueprintType)
struct FPostProcessSettings
{
    GENERATED_BODY()

    // ========== Bloom ==========
    UPROPERTY(EditAnywhere, Category="Bloom", meta=(ClampMin="0.0", ClampMax="8.0"))
    float BloomIntensity = 0.675f;

    UPROPERTY(EditAnywhere, Category="Bloom", meta=(ClampMin="-1.0", ClampMax="8.0"))
    float BloomThreshold = -1.0f;

    UPROPERTY(EditAnywhere, Category="Bloom")
    float BloomSizeScale = 4.0f;

    // Convolution Bloom
    UPROPERTY(EditAnywhere, Category="Bloom")
    UTexture2D* BloomConvolutionTexture;

    // ========== Exposure ==========
    UPROPERTY(EditAnywhere, Category="Exposure")
    TEnumAsByte<EAutoExposureMethod> AutoExposureMethod;

    UPROPERTY(EditAnywhere, Category="Exposure")
    float AutoExposureBias = 0.0f;

    UPROPERTY(EditAnywhere, Category="Exposure")
    float AutoExposureMinBrightness = 0.03f;

    UPROPERTY(EditAnywhere, Category="Exposure")
    float AutoExposureMaxBrightness = 2.0f;

    UPROPERTY(EditAnywhere, Category="Exposure")
    float AutoExposureSpeedUp = 3.0f;

    UPROPERTY(EditAnywhere, Category="Exposure")
    float AutoExposureSpeedDown = 1.0f;

    // ========== Color Grading ==========
    UPROPERTY(EditAnywhere, Category="Color Grading|Global")
    FVector4 ColorSaturation = FVector4(1.0f, 1.0f, 1.0f, 1.0f);

    UPROPERTY(EditAnywhere, Category="Color Grading|Global")
    FVector4 ColorContrast = FVector4(1.0f, 1.0f, 1.0f, 1.0f);

    UPROPERTY(EditAnywhere, Category="Color Grading|Global")
    FVector4 ColorGamma = FVector4(1.0f, 1.0f, 1.0f, 1.0f);

    UPROPERTY(EditAnywhere, Category="Color Grading|Global")
    FVector4 ColorGain = FVector4(1.0f, 1.0f, 1.0f, 1.0f);

    UPROPERTY(EditAnywhere, Category="Color Grading|Global")
    FVector4 ColorOffset = FVector4(0.0f, 0.0f, 0.0f, 0.0f);

    // LUT
    UPROPERTY(EditAnywhere, Category="Color Grading|Misc")
    UTexture* ColorGradingLUT;

    // ========== Depth of Field ==========
    UPROPERTY(EditAnywhere, Category="Lens|Depth of Field")
    float DepthOfFieldFocalDistance = 0.0f;

    UPROPERTY(EditAnywhere, Category="Lens|Depth of Field")
    float DepthOfFieldFstop = 4.0f;

    UPROPERTY(EditAnywhere, Category="Lens|Depth of Field")
    float DepthOfFieldSensorWidth = 24.576f;

    // ========== Motion Blur ==========
    UPROPERTY(EditAnywhere, Category="Lens|Motion Blur")
    float MotionBlurAmount = 0.5f;

    UPROPERTY(EditAnywhere, Category="Lens|Motion Blur")
    float MotionBlurMax = 5.0f;

    UPROPERTY(EditAnywhere, Category="Lens|Motion Blur")
    float MotionBlurTargetFPS = 30.0f;

    // ========== Ambient Occlusion ==========
    UPROPERTY(EditAnywhere, Category="Rendering Features|Ambient Occlusion")
    float AmbientOcclusionIntensity = 0.5f;

    UPROPERTY(EditAnywhere, Category="Rendering Features|Ambient Occlusion")
    float AmbientOcclusionRadius = 200.0f;

    // ... 수백 개의 추가 파라미터
};
```

---

## 볼륨 블렌딩

### 블렌딩 시스템

```cpp
// 씬에서 볼륨 수집 및 블렌딩
class FPostProcessVolumeBlending
{
public:
    static void BlendVolumes(
        const FVector& ViewLocation,
        const TArray<APostProcessVolume*>& Volumes,
        FPostProcessSettings& OutSettings)
    {
        // 기본 설정으로 시작
        OutSettings = FPostProcessSettings();
        float TotalWeight = 0.0f;

        // 우선순위로 정렬
        TArray<APostProcessVolume*> SortedVolumes = Volumes;
        SortedVolumes.Sort([](const APostProcessVolume& A, const APostProcessVolume& B)
        {
            return A.Priority < B.Priority;
        });

        // 각 볼륨 블렌딩
        for (APostProcessVolume* Volume : SortedVolumes)
        {
            if (!Volume->bEnabled)
                continue;

            float Weight = ComputeVolumeWeight(Volume, ViewLocation);

            if (Weight > 0.0f)
            {
                BlendSettings(OutSettings, Volume->Settings, Weight);
                TotalWeight += Weight;
            }
        }

        // 정규화 (필요한 경우)
        if (TotalWeight > 1.0f)
        {
            NormalizeSettings(OutSettings, TotalWeight);
        }
    }

private:
    static float ComputeVolumeWeight(APostProcessVolume* Volume, const FVector& Location)
    {
        if (Volume->bUnbound)
        {
            return Volume->BlendWeight;
        }

        // 볼륨 바운드 체크
        FBoxSphereBounds Bounds = Volume->GetBounds();
        float Distance = FMath::Max(0.0f, Bounds.ComputeSquaredDistanceFromBoxToPoint(Location));
        Distance = FMath::Sqrt(Distance);

        if (Distance <= 0.0f)
        {
            // 볼륨 내부
            return Volume->BlendWeight;
        }
        else if (Distance < Volume->BlendRadius)
        {
            // 블렌드 영역 - 부드러운 전환
            float Alpha = 1.0f - (Distance / Volume->BlendRadius);
            Alpha = FMath::SmoothStep(0.0f, 1.0f, Alpha);
            return Volume->BlendWeight * Alpha;
        }

        return 0.0f;
    }

    static void BlendSettings(FPostProcessSettings& Dest, const FPostProcessSettings& Src, float Weight)
    {
        // 각 파라미터별 블렌딩 (오버라이드 체크 포함)
        if (Src.bOverride_BloomIntensity)
        {
            Dest.BloomIntensity = FMath::Lerp(Dest.BloomIntensity, Src.BloomIntensity, Weight);
        }

        if (Src.bOverride_AutoExposureBias)
        {
            Dest.AutoExposureBias = FMath::Lerp(Dest.AutoExposureBias, Src.AutoExposureBias, Weight);
        }

        // ... 모든 파라미터에 대해 반복
    }
};
```

### 오버라이드 시스템

```cpp
// 파라미터별 오버라이드 플래그
USTRUCT()
struct FPostProcessSettings
{
    // Bloom 오버라이드
    UPROPERTY()
    uint8 bOverride_BloomIntensity : 1;

    UPROPERTY()
    uint8 bOverride_BloomThreshold : 1;

    // 실제 값
    UPROPERTY()
    float BloomIntensity;

    UPROPERTY()
    float BloomThreshold;

    // ... 각 파라미터마다 오버라이드 플래그 존재
};

// 블루프린트에서 동적 수정
void AMyActor::ModifyPostProcess()
{
    APostProcessVolume* Volume = GetPostProcessVolume();

    // 오버라이드 활성화 후 값 설정
    Volume->Settings.bOverride_BloomIntensity = true;
    Volume->Settings.BloomIntensity = 2.0f;

    Volume->Settings.bOverride_ColorSaturation = true;
    Volume->Settings.ColorSaturation = FVector4(0.0f, 0.0f, 0.0f, 1.0f);  // 흑백
}
```

---

## 카메라 포스트 프로세스

### 카메라 컴포넌트 설정

```cpp
// 카메라에 직접 적용
UCLASS()
class UCameraComponent : public USceneComponent
{
    // 카메라 포스트 프로세스 설정
    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="PostProcess")
    FPostProcessSettings PostProcessSettings;

    // 블렌드 가중치
    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="PostProcess")
    float PostProcessBlendWeight = 1.0f;
};

// 사용 예
void AMyPlayerCamera::BeginPlay()
{
    Super::BeginPlay();

    // 카메라에 직접 포스트 프로세스 적용
    CameraComponent->PostProcessSettings.bOverride_DepthOfFieldFstop = true;
    CameraComponent->PostProcessSettings.DepthOfFieldFstop = 1.4f;

    CameraComponent->PostProcessSettings.bOverride_DepthOfFieldFocalDistance = true;
    CameraComponent->PostProcessSettings.DepthOfFieldFocalDistance = 500.0f;
}
```

---

## 커스텀 포스트 프로세스 머티리얼

### 블렌더블 시스템

```cpp
// 블렌더블 인터페이스
class IBlendableInterface
{
public:
    virtual void OverrideBlendableSettings(
        FSceneView& View,
        float Weight) const = 0;
};

// 포스트 프로세스 머티리얼
UCLASS()
class UMaterialInterface : public UObject, public IBlendableInterface
{
    // 블렌더블 위치
    UPROPERTY()
    EBlendableLocation BlendableLocation;
};

// 블렌더블 위치 옵션
UENUM()
enum class EBlendableLocation : uint8
{
    // 톤 매핑 전 (HDR)
    BL_BeforeTonemapping,

    // 톤 매핑 후 (LDR)
    BL_AfterTonemapping,

    // 반투명 전
    BL_BeforeTranslucency,

    // 톤 매퍼 대체
    BL_ReplacingTonemapper,

    // SSR 입력
    BL_SSRInput,
};
```

### 머티리얼 셋업

```cpp
// 포스트 프로세스 머티리얼 생성
void SetupPostProcessMaterial()
{
    // 1. 머티리얼 생성 (에디터에서)
    // Material Domain: Post Process
    // Blendable Location: After Tonemapping

    // 2. 포스트 프로세스 볼륨에 추가
    APostProcessVolume* Volume = ...;

    // 웨이티드 블렌더블 추가
    FWeightedBlendable Blendable;
    Blendable.Object = MyPostProcessMaterial;
    Blendable.Weight = 1.0f;

    Volume->Settings.WeightedBlendables.Array.Add(Blendable);
}
```

### 셰이더 노드 예제

```hlsl
// 커스텀 포스트 프로세스 HLSL

// 입력 텍스처
Texture2D SceneColorTexture;
Texture2D SceneDepthTexture;
SamplerState SceneColorSampler;

// 유틸리티 함수
float3 GetSceneColor(float2 UV)
{
    return SceneColorTexture.Sample(SceneColorSampler, UV).rgb;
}

float GetSceneDepth(float2 UV)
{
    return SceneDepthTexture.Sample(SceneColorSampler, UV).r;
}

// 아웃라인 효과 예제
float4 OutlineEffect(float2 UV)
{
    float Depth = GetSceneDepth(UV);
    float3 Color = GetSceneColor(UV);

    // 주변 깊이 샘플링
    float2 PixelSize = 1.0 / ViewportSize;

    float DepthN = GetSceneDepth(UV + float2(0, -1) * PixelSize);
    float DepthS = GetSceneDepth(UV + float2(0, 1) * PixelSize);
    float DepthE = GetSceneDepth(UV + float2(1, 0) * PixelSize);
    float DepthW = GetSceneDepth(UV + float2(-1, 0) * PixelSize);

    // 엣지 검출
    float Edge = abs(DepthN - DepthS) + abs(DepthE - DepthW);
    Edge = saturate(Edge * EdgeStrength);

    // 아웃라인 적용
    float3 OutlineColor = float3(0, 0, 0);
    Color = lerp(Color, OutlineColor, Edge);

    return float4(Color, 1);
}
```

---

## Scene Textures

### 접근 가능한 텍스처

포스트 프로세싱에서 사용되는 G-Buffer 텍스처들입니다.

![G-Buffer 구성 요소](../images/ch07/1617944-20210505184337183-1419009066.png)

*G-Buffer의 주요 구성 요소: Position, Normals, Albedo, Specular - 이 데이터들이 포스트 프로세싱 효과의 입력으로 사용됨*

```cpp
// 포스트 프로세스에서 사용 가능한 씬 텍스처
struct FSceneTextures
{
    // 컬러 버퍼
    FRDGTextureRef SceneColor;           // HDR 씬 컬러
    FRDGTextureRef SceneColorCopy;       // 씬 컬러 복사본

    // 깊이 버퍼
    FRDGTextureRef SceneDepth;           // 씬 깊이
    FRDGTextureRef CustomDepth;          // 커스텀 깊이

    // G-Buffer
    FRDGTextureRef GBufferA;             // WorldNormal
    FRDGTextureRef GBufferB;             // Metallic, Specular, Roughness
    FRDGTextureRef GBufferC;             // BaseColor
    FRDGTextureRef GBufferD;             // Custom Data
    FRDGTextureRef GBufferE;             // Pre-computed shadow
    FRDGTextureRef GBufferF;             // Tangent

    // 기타
    FRDGTextureRef SceneVelocity;        // 모션 벡터
    FRDGTextureRef ScreenSpaceAO;        // SSAO 결과
    FRDGTextureRef CustomStencil;        // 커스텀 스텐실
};

// 머티리얼에서 씬 텍스처 접근
// Scene Texture 노드로 접근 가능:
// - SceneColor
// - SceneDepth
// - WorldNormal
// - BaseColor
// - Metallic
// - Roughness
// - CustomDepth
// - CustomStencil
// - PostProcessInput0-6
```

---

## 성능 최적화

### 패스 결합

```cpp
// 여러 효과를 하나의 패스로 결합
class FCombinedPostProcessCS : public FGlobalShader
{
    DECLARE_GLOBAL_SHADER(FCombinedPostProcessCS);

    // 파라미터
    BEGIN_SHADER_PARAMETER_STRUCT(FParameters, )
        SHADER_PARAMETER_RDG_TEXTURE(Texture2D, SceneColor)
        SHADER_PARAMETER_RDG_TEXTURE_UAV(RWTexture2D, OutputTexture)

        // Vignette
        SHADER_PARAMETER(float, VignetteIntensity)

        // Film Grain
        SHADER_PARAMETER(float, GrainIntensity)
        SHADER_PARAMETER(float, GrainJitter)

        // Chromatic Aberration
        SHADER_PARAMETER(float, ChromaIntensity)
    END_SHADER_PARAMETER_STRUCT()
};

// 단일 패스에서 모든 효과 처리
[numthreads(8, 8, 1)]
void CombinedPostProcessCS(uint3 DispatchThreadId : SV_DispatchThreadID)
{
    float2 UV = (DispatchThreadId.xy + 0.5) / OutputSize;
    float3 Color = SceneColor.Load(DispatchThreadId.xy).rgb;

    // 비네트
    Color = ApplyVignette(Color, UV);

    // 필름 그레인
    Color = ApplyFilmGrain(Color, UV);

    // 크로마틱 애버레이션
    Color = ApplyChromaticAberration(Color, UV);

    OutputTexture[DispatchThreadId.xy] = float4(Color, 1);
}
```

### 해상도 스케일링

```cpp
// 효과별 해상도 설정
class FPostProcessDownsample
{
    // 블룸: 1/4 해상도에서 시작
    static const int BloomDownsampleFactor = 4;

    // SSAO: 1/2 해상도
    static const int SSAODownsampleFactor = 2;

    // DOF: 적응형
    static int GetDOFDownsampleFactor(int QualityLevel)
    {
        switch (QualityLevel)
        {
            case 0: return 4;  // Low
            case 1: return 2;  // Medium
            case 2: return 1;  // High
            default: return 2;
        }
    }
};
```

---

## 프로젝트 설정

UE 프로젝트 설정에서 기본 포스트 프로세싱 옵션을 구성할 수 있습니다.

![포스트 프로세싱 프로젝트 설정](../images/ch07/1617944-20210505185315935-1204060267.jpg)

*Project Settings > Rendering > Default Settings에서 Bloom, Ambient Occlusion, Auto Exposure 등의 기본값 설정*

---

## 요약

| 구성 요소 | 역할 |
|----------|------|
| PostProcessVolume | 공간 기반 설정 적용 |
| FPostProcessSettings | 모든 PP 파라미터 저장 |
| 볼륨 블렌딩 | 여러 볼륨의 부드러운 전환 |
| 블렌더블 머티리얼 | 커스텀 효과 삽입 |
| Scene Textures | PP에서 접근 가능한 버퍼들 |

포스트 프로세싱은 최종 이미지 품질을 결정하는 핵심 시스템입니다.
---

<div style="display: flex; justify-content: space-between; align-items: center; padding: 16px 0;">
  <a href="../" style="text-decoration: none;">← 이전: Ch.07 개요</a>
  <a href="../02-tone-mapping-color/" style="text-decoration: none;">다음: 02. 톤 매핑과 컬러 →</a>
</div>
