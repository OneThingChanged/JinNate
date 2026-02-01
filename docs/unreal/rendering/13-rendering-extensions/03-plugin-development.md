# 렌더링 플러그인 개발

렌더링 기능을 담은 UE 플러그인 개발 방법을 다룹니다.

---

## 개요

렌더링 플러그인은 커스텀 셰이더, 렌더 패스, 후처리 효과를 패키지화하여 재사용 가능하게 만듭니다.

```
┌─────────────────────────────────────────────────────────────────┐
│                   렌더링 플러그인 구조                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  MyRenderingPlugin/                                             │
│  ├── MyRenderingPlugin.uplugin      ◀── 플러그인 정의          │
│  ├── Source/                                                    │
│  │   ├── MyRenderingPlugin/                                     │
│  │   │   ├── MyRenderingPlugin.Build.cs  ◀── 빌드 설정        │
│  │   │   ├── Public/                                            │
│  │   │   │   ├── MyRenderingPlugin.h                           │
│  │   │   │   ├── MyViewExtension.h                             │
│  │   │   │   └── MyShaders.h                                   │
│  │   │   └── Private/                                          │
│  │   │       ├── MyRenderingPlugin.cpp                         │
│  │   │       ├── MyViewExtension.cpp                           │
│  │   │       └── MyShaders.cpp                                 │
│  │   └── Shaders/                                              │
│  │       └── Private/                    ◀── USF 셰이더        │
│  │           ├── MyComputeShader.usf                           │
│  │           └── MyPixelShader.usf                             │
│  ├── Content/                            ◀── 에셋 (선택)       │
│  │   └── Materials/                                            │
│  └── Resources/                          ◀── 리소스 (선택)     │
│      └── Icon128.png                                           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 프로젝트 설정

### uplugin 파일

```json
// MyRenderingPlugin.uplugin
{
    "FileVersion": 3,
    "Version": 1,
    "VersionName": "1.0",
    "FriendlyName": "My Rendering Plugin",
    "Description": "Custom rendering features for UE5",
    "Category": "Rendering",
    "CreatedBy": "Your Name",
    "CreatedByURL": "",
    "DocsURL": "",
    "MarketplaceURL": "",
    "SupportURL": "",
    "CanContainContent": true,
    "IsBetaVersion": false,
    "IsExperimentalVersion": false,
    "Installed": false,
    "Modules": [
        {
            "Name": "MyRenderingPlugin",
            "Type": "Runtime",
            "LoadingPhase": "PostConfigInit"
        }
    ]
}
```

### Build.cs 파일

```csharp
// MyRenderingPlugin.Build.cs
using UnrealBuildTool;

public class MyRenderingPlugin : ModuleRules
{
    public MyRenderingPlugin(ReadOnlyTargetRules Target) : base(Target)
    {
        PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;

        PublicDependencyModuleNames.AddRange(new string[]
        {
            "Core",
            "CoreUObject",
            "Engine",
        });

        PrivateDependencyModuleNames.AddRange(new string[]
        {
            "RenderCore",
            "Renderer",
            "RHI",
            "Projects"
        });

        // 셰이더 디렉토리 등록
        // Plugin/Source/Shaders 경로 사용
        PublicIncludePaths.Add(ModuleDirectory);
    }
}
```

---

## 모듈 구현

### 모듈 헤더

```cpp
// MyRenderingPlugin.h
#pragma once

#include "Modules/ModuleManager.h"

class FMyRenderingPluginModule : public IModuleInterface
{
public:
    virtual void StartupModule() override;
    virtual void ShutdownModule() override;

private:
    TSharedPtr<class FMyViewExtension, ESPMode::ThreadSafe> ViewExtension;
    FDelegateHandle OnPostEngineInitHandle;
};
```

### 모듈 구현

```cpp
// MyRenderingPlugin.cpp
#include "MyRenderingPlugin.h"
#include "MyViewExtension.h"
#include "Interfaces/IPluginManager.h"
#include "ShaderCore.h"

#define LOCTEXT_NAMESPACE "FMyRenderingPluginModule"

void FMyRenderingPluginModule::StartupModule()
{
    // 셰이더 디렉토리 등록
    FString PluginShaderDir = FPaths::Combine(
        IPluginManager::Get().FindPlugin(TEXT("MyRenderingPlugin"))->GetBaseDir(),
        TEXT("Source/Shaders")
    );
    AddShaderSourceDirectoryMapping(
        TEXT("/Plugin/MyRenderingPlugin"),
        PluginShaderDir
    );

    // 엔진 초기화 후 ViewExtension 등록
    OnPostEngineInitHandle = FCoreDelegates::OnPostEngineInit.AddLambda([this]()
    {
        ViewExtension = FSceneViewExtensions::NewExtension<FMyViewExtension>();
    });
}

void FMyRenderingPluginModule::ShutdownModule()
{
    FCoreDelegates::OnPostEngineInit.Remove(OnPostEngineInitHandle);

    if (ViewExtension.IsValid())
    {
        ViewExtension.Reset();
    }
}

#undef LOCTEXT_NAMESPACE

IMPLEMENT_MODULE(FMyRenderingPluginModule, MyRenderingPlugin)
```

---

## 셰이더 통합

### 셰이더 디렉토리 구조

```
Source/
├── Shaders/
│   └── Private/
│       ├── Common.ush           ◀── 공통 함수
│       ├── MyComputeShader.usf  ◀── 컴퓨트 셰이더
│       └── MyPixelShader.usf    ◀── 픽셀 셰이더
```

### Global Shader 정의

```cpp
// MyShaders.h
#pragma once

#include "GlobalShader.h"
#include "ShaderParameterStruct.h"

// 컴퓨트 셰이더
class FMyComputeShader : public FGlobalShader
{
public:
    DECLARE_GLOBAL_SHADER(FMyComputeShader);
    SHADER_USE_PARAMETER_STRUCT(FMyComputeShader, FGlobalShader);

    BEGIN_SHADER_PARAMETER_STRUCT(FParameters, )
        SHADER_PARAMETER_RDG_TEXTURE_SRV(Texture2D, InputTexture)
        SHADER_PARAMETER_RDG_TEXTURE_UAV(RWTexture2D<float4>, OutputTexture)
        SHADER_PARAMETER_SAMPLER(SamplerState, InputSampler)
        SHADER_PARAMETER(FVector4f, Params)
        SHADER_PARAMETER(FIntPoint, TextureSize)
    END_SHADER_PARAMETER_STRUCT()

    static bool ShouldCompilePermutation(const FGlobalShaderPermutationParameters& Parameters)
    {
        return IsFeatureLevelSupported(Parameters.Platform, ERHIFeatureLevel::SM5);
    }

    static void ModifyCompilationEnvironment(
        const FGlobalShaderPermutationParameters& Parameters,
        FShaderCompilerEnvironment& OutEnvironment)
    {
        FGlobalShader::ModifyCompilationEnvironment(Parameters, OutEnvironment);
        OutEnvironment.SetDefine(TEXT("THREADGROUP_SIZE"), 8);
    }
};

// 픽셀 셰이더
class FMyPixelShader : public FGlobalShader
{
public:
    DECLARE_GLOBAL_SHADER(FMyPixelShader);
    SHADER_USE_PARAMETER_STRUCT(FMyPixelShader, FGlobalShader);

    BEGIN_SHADER_PARAMETER_STRUCT(FParameters, )
        SHADER_PARAMETER_RDG_TEXTURE_SRV(Texture2D, SceneColorTexture)
        SHADER_PARAMETER_SAMPLER(SamplerState, SceneSampler)
        SHADER_PARAMETER(float, EffectIntensity)
        RENDER_TARGET_BINDING_SLOTS()
    END_SHADER_PARAMETER_STRUCT()

    static bool ShouldCompilePermutation(const FGlobalShaderPermutationParameters& Parameters)
    {
        return IsFeatureLevelSupported(Parameters.Platform, ERHIFeatureLevel::SM5);
    }
};
```

### 셰이더 구현 등록

```cpp
// MyShaders.cpp
#include "MyShaders.h"

// 셰이더 구현 등록
IMPLEMENT_GLOBAL_SHADER(FMyComputeShader,
    "/Plugin/MyRenderingPlugin/Private/MyComputeShader.usf",
    "MainCS",
    SF_Compute);

IMPLEMENT_GLOBAL_SHADER(FMyPixelShader,
    "/Plugin/MyRenderingPlugin/Private/MyPixelShader.usf",
    "MainPS",
    SF_Pixel);
```

### USF 셰이더 파일

```hlsl
// MyComputeShader.usf
#include "/Engine/Private/Common.ush"

Texture2D InputTexture;
SamplerState InputSampler;
RWTexture2D<float4> OutputTexture;
float4 Params;
int2 TextureSize;

[numthreads(THREADGROUP_SIZE, THREADGROUP_SIZE, 1)]
void MainCS(uint3 DispatchThreadId : SV_DispatchThreadID)
{
    if (any(DispatchThreadId.xy >= TextureSize))
        return;

    float2 UV = (DispatchThreadId.xy + 0.5f) / float2(TextureSize);

    float4 Color = InputTexture.SampleLevel(InputSampler, UV, 0);

    // 커스텀 처리
    Color.rgb = lerp(Color.rgb, Color.rgb * Params.rgb, Params.a);

    OutputTexture[DispatchThreadId.xy] = Color;
}
```

```hlsl
// MyPixelShader.usf
#include "/Engine/Private/Common.ush"

Texture2D SceneColorTexture;
SamplerState SceneSampler;
float EffectIntensity;

void MainPS(
    float4 SvPosition : SV_POSITION,
    float2 UV : TEXCOORD0,
    out float4 OutColor : SV_Target0)
{
    float4 SceneColor = SceneColorTexture.Sample(SceneSampler, UV);

    // 간단한 비네트 효과 예시
    float2 VignetteCenter = UV - 0.5f;
    float VignetteFactor = 1.0f - dot(VignetteCenter, VignetteCenter);
    VignetteFactor = saturate(VignetteFactor * 2.0f);

    OutColor.rgb = lerp(SceneColor.rgb, SceneColor.rgb * VignetteFactor, EffectIntensity);
    OutColor.a = SceneColor.a;
}
```

---

## ViewExtension 구현

### 완전한 예제

```cpp
// MyViewExtension.h
#pragma once

#include "SceneViewExtension.h"

class FMyViewExtension : public FSceneViewExtensionBase
{
public:
    FMyViewExtension(const FAutoRegister& AutoRegister);

    virtual void SetupViewFamily(FSceneViewFamily& InViewFamily) override;
    virtual void SetupView(FSceneViewFamily& InViewFamily, FSceneView& InView) override;

    virtual void PrePostProcessPass_RenderThread(
        FRDGBuilder& GraphBuilder,
        const FSceneView& View,
        const FPostProcessingInputs& Inputs) override;

    virtual bool IsActiveThisFrame_Internal(
        const FSceneViewExtensionContext& Context) const override;

    // 설정
    float EffectIntensity = 1.0f;
    bool bEnabled = true;
};
```

```cpp
// MyViewExtension.cpp
#include "MyViewExtension.h"
#include "MyShaders.h"
#include "PostProcess/PostProcessing.h"
#include "PixelShaderUtils.h"

FMyViewExtension::FMyViewExtension(const FAutoRegister& AutoRegister)
    : FSceneViewExtensionBase(AutoRegister)
{
}

void FMyViewExtension::SetupViewFamily(FSceneViewFamily& InViewFamily)
{
    // 뷰 패밀리 설정
}

void FMyViewExtension::SetupView(FSceneViewFamily& InViewFamily, FSceneView& InView)
{
    // 개별 뷰 설정
}

bool FMyViewExtension::IsActiveThisFrame_Internal(
    const FSceneViewExtensionContext& Context) const
{
    return bEnabled;
}

void FMyViewExtension::PrePostProcessPass_RenderThread(
    FRDGBuilder& GraphBuilder,
    const FSceneView& View,
    const FPostProcessingInputs& Inputs)
{
    if (!bEnabled || EffectIntensity <= 0.0f)
        return;

    // SceneColor 가져오기
    FRDGTextureRef SceneColor = (*Inputs.SceneTextures)->SceneColorTexture;
    FRDGTextureRef OutputTexture = GraphBuilder.CreateTexture(
        SceneColor->Desc,
        TEXT("MyEffectOutput")
    );

    // 파라미터 설정
    FMyPixelShader::FParameters* Parameters =
        GraphBuilder.AllocParameters<FMyPixelShader::FParameters>();

    Parameters->SceneColorTexture = GraphBuilder.CreateSRV(
        FRDGTextureSRVDesc::Create(SceneColor));
    Parameters->SceneSampler = TStaticSamplerState<SF_Bilinear>::GetRHI();
    Parameters->EffectIntensity = EffectIntensity;
    Parameters->RenderTargets[0] = FRenderTargetBinding(
        OutputTexture, ERenderTargetLoadAction::ENoAction);

    TShaderMapRef<FMyPixelShader> PixelShader(View.ShaderMap);

    FPixelShaderUtils::AddFullscreenPass(
        GraphBuilder,
        View.ShaderMap,
        RDG_EVENT_NAME("MyCustomEffect"),
        PixelShader,
        Parameters,
        View.ViewRect
    );

    // 결과를 SceneColor로 복사
    AddCopyTexturePass(GraphBuilder, OutputTexture, SceneColor);
}
```

---

## 블루프린트 노출

### 설정 컴포넌트

```cpp
// MyEffectComponent.h
UCLASS(ClassGroup=(Rendering), meta=(BlueprintSpawnableComponent))
class MYRENDERINGPLUGIN_API UMyEffectComponent : public UActorComponent
{
    GENERATED_BODY()

public:
    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Effect")
    bool bEnabled = true;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Effect",
              meta = (ClampMin = "0.0", ClampMax = "1.0"))
    float EffectIntensity = 1.0f;

    UFUNCTION(BlueprintCallable, Category = "Effect")
    void SetEffectEnabled(bool bNewEnabled);

    UFUNCTION(BlueprintCallable, Category = "Effect")
    void SetEffectIntensity(float NewIntensity);

protected:
    virtual void BeginPlay() override;
    virtual void EndPlay(const EEndPlayReason::Type EndPlayReason) override;
};
```

### Blueprint Function Library

```cpp
// MyRenderingBlueprintLibrary.h
UCLASS()
class MYRENDERINGPLUGIN_API UMyRenderingBlueprintLibrary : public UBlueprintFunctionLibrary
{
    GENERATED_BODY()

public:
    UFUNCTION(BlueprintCallable, Category = "My Rendering")
    static void EnableCustomEffect(bool bEnable);

    UFUNCTION(BlueprintCallable, Category = "My Rendering")
    static void SetCustomEffectIntensity(float Intensity);

    UFUNCTION(BlueprintPure, Category = "My Rendering")
    static bool IsCustomEffectEnabled();
};
```

---

## 에디터 통합

### 커스텀 에디터 모듈

```cpp
// MyRenderingPluginEditor.Build.cs (별도 에디터 모듈)
PublicDependencyModuleNames.AddRange(new string[]
{
    "Core",
    "CoreUObject",
    "Engine",
    "UnrealEd",
    "MyRenderingPlugin"
});
```

### 에셋 타입 (선택)

```cpp
// 커스텀 에셋 클래스
UCLASS(BlueprintType)
class UMyEffectAsset : public UObject
{
    GENERATED_BODY()

public:
    UPROPERTY(EditAnywhere, BlueprintReadOnly)
    float DefaultIntensity = 1.0f;

    UPROPERTY(EditAnywhere, BlueprintReadOnly)
    UCurveFloat* IntensityCurve;

    UPROPERTY(EditAnywhere, BlueprintReadOnly)
    FLinearColor TintColor = FLinearColor::White;
};
```

---

## 테스트 및 디버깅

### 셰이더 핫 리로드

```cpp
// 개발 중 셰이더 리컴파일
RecompileShaders changed
RecompileShaders global
RecompileShaders material
```

### 디버그 시각화

```cpp
// 콘솔 변수로 디버그 토글
static TAutoConsoleVariable<int32> CVarMyEffectDebug(
    TEXT("r.MyEffect.Debug"),
    0,
    TEXT("Enable debug visualization for MyEffect"),
    ECVF_RenderThreadSafe
);

// 사용
if (CVarMyEffectDebug.GetValueOnRenderThread() > 0)
{
    // 디버그 출력
}
```

---

## 배포

### 플러그인 패키징

```
1. 플러그인 활성화 확인
2. 프로젝트 패키징 (Development/Shipping)
3. 필요한 플랫폼 셰이더 컴파일
4. 테스트
```

### 마켓플레이스 배포

```
- 모든 타겟 플랫폼 테스트
- 문서 작성
- 예제 프로젝트 포함
- 지원 이메일 설정
```

---

## 요약

| 단계 | 파일 | 내용 |
|------|------|------|
| 1 | .uplugin | 플러그인 메타데이터 |
| 2 | Build.cs | 모듈 의존성 |
| 3 | Module.cpp | 셰이더 등록 |
| 4 | Shaders.h/cpp | 셰이더 바인딩 |
| 5 | .usf | HLSL 셰이더 |
| 6 | ViewExtension | 패스 통합 |

---

## 참고 자료

- [Plugin Development](https://docs.unrealengine.com/plugin-development/)
- [Global Shaders](https://docs.unrealengine.com/global-shaders/)
- [Shader Plugin Examples](https://github.com/search?q=unreal+shader+plugin)
