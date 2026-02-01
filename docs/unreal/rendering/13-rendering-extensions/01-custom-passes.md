# 커스텀 렌더 패스

SceneViewExtension과 커스텀 렌더 패스를 구현하는 방법을 다룹니다.

---

## 개요

UE는 렌더링 파이프라인의 다양한 지점에 커스텀 코드를 삽입할 수 있는 확장 포인트를 제공합니다.

```
┌─────────────────────────────────────────────────────────────────┐
│                   렌더링 패스 삽입 포인트                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                    Frame Begin                          │    │
│  └────────────────────────┬────────────────────────────────┘    │
│                           │                                     │
│                           ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  PreRenderView_RenderThread ◀── 커스텀 패스 삽입       │    │
│  └────────────────────────┬────────────────────────────────┘    │
│                           ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                    PrePass (Depth)                      │    │
│  └────────────────────────┬────────────────────────────────┘    │
│                           ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  PostRenderBasePass_RenderThread ◀── 커스텀 패스 삽입  │    │
│  └────────────────────────┬────────────────────────────────┘    │
│                           ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                    BasePass (G-Buffer)                  │    │
│  └────────────────────────┬────────────────────────────────┘    │
│                           ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                    Lighting Pass                        │    │
│  └────────────────────────┬────────────────────────────────┘    │
│                           ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  PrePostProcessPass_RenderThread ◀── 커스텀 패스 삽입  │    │
│  └────────────────────────┬────────────────────────────────┘    │
│                           ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                    PostProcess                          │    │
│  └────────────────────────┬────────────────────────────────┘    │
│                           ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                    Frame End                            │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## SceneViewExtension

### 기본 구현

```cpp
// MyViewExtension.h
#pragma once

#include "SceneViewExtension.h"

class FMyViewExtension : public FSceneViewExtensionBase
{
public:
    FMyViewExtension(const FAutoRegister& AutoRegister);

    //~ Begin FSceneViewExtensionBase Interface
    virtual void SetupViewFamily(FSceneViewFamily& InViewFamily) override {}
    virtual void SetupView(FSceneViewFamily& InViewFamily, FSceneView& InView) override {}
    virtual void BeginRenderViewFamily(FSceneViewFamily& InViewFamily) override {}

    virtual void PreRenderViewFamily_RenderThread(
        FRDGBuilder& GraphBuilder,
        FSceneViewFamily& InViewFamily) override;

    virtual void PreRenderView_RenderThread(
        FRDGBuilder& GraphBuilder,
        FSceneView& InView) override;

    virtual void PostRenderBasePassDeferred_RenderThread(
        FRDGBuilder& GraphBuilder,
        FSceneView& InView,
        const FRenderTargetBindingSlots& RenderTargets,
        TRDGUniformBufferRef<FSceneTextureUniformParameters> SceneTextures) override;

    virtual void PrePostProcessPass_RenderThread(
        FRDGBuilder& GraphBuilder,
        const FSceneView& View,
        const FPostProcessingInputs& Inputs) override;
    //~ End FSceneViewExtensionBase Interface

    virtual bool IsActiveThisFrame_Internal(
        const FSceneViewExtensionContext& Context) const override
    {
        return true;  // 항상 활성화
    }
};
```

### 구현 예제

```cpp
// MyViewExtension.cpp
#include "MyViewExtension.h"
#include "PostProcess/PostProcessing.h"
#include "ScenePrivate.h"

FMyViewExtension::FMyViewExtension(const FAutoRegister& AutoRegister)
    : FSceneViewExtensionBase(AutoRegister)
{
}

void FMyViewExtension::PreRenderViewFamily_RenderThread(
    FRDGBuilder& GraphBuilder,
    FSceneViewFamily& InViewFamily)
{
    // 뷰 패밀리 렌더링 전 초기화
}

void FMyViewExtension::PreRenderView_RenderThread(
    FRDGBuilder& GraphBuilder,
    FSceneView& InView)
{
    // 각 뷰 렌더링 전 처리
    // 예: 커스텀 데이터 준비
}

void FMyViewExtension::PostRenderBasePassDeferred_RenderThread(
    FRDGBuilder& GraphBuilder,
    FSceneView& InView,
    const FRenderTargetBindingSlots& RenderTargets,
    TRDGUniformBufferRef<FSceneTextureUniformParameters> SceneTextures)
{
    // BasePass 후 G-Buffer 데이터 활용 가능
    // 예: 커스텀 디퍼드 데칼, 추가 G-Buffer 처리
}

void FMyViewExtension::PrePostProcessPass_RenderThread(
    FRDGBuilder& GraphBuilder,
    const FSceneView& View,
    const FPostProcessingInputs& Inputs)
{
    // PostProcess 전 커스텀 효과 삽입
    // SceneColor에 접근 가능
}
```

### 등록 및 해제

```cpp
// 플러그인 또는 게임 모듈에서
class FMyModule : public IModuleInterface
{
public:
    virtual void StartupModule() override
    {
        // ViewExtension 등록
        ViewExtension = FSceneViewExtensions::NewExtension<FMyViewExtension>();
    }

    virtual void ShutdownModule() override
    {
        // 자동 해제됨 (shared_ptr)
        ViewExtension.Reset();
    }

private:
    TSharedPtr<FMyViewExtension, ESPMode::ThreadSafe> ViewExtension;
};
```

---

## 커스텀 포스트 프로세스

### Blendable 인터페이스

```cpp
// UMyPostProcessComponent.h
UCLASS(BlueprintType, meta=(BlueprintSpawnableComponent))
class UMyPostProcessComponent : public UActorComponent, public IBlendableInterface
{
    GENERATED_BODY()

public:
    UPROPERTY(EditAnywhere, BlueprintReadWrite)
    float EffectIntensity = 1.0f;

    UPROPERTY(EditAnywhere, BlueprintReadWrite)
    UTexture2D* LUTTexture;

    // IBlendableInterface
    virtual void OverrideBlendableSettings(
        FSceneView& View, float Weight) const override;
};
```

### 포스트 프로세스 볼륨 연동

```cpp
void UMyPostProcessComponent::OverrideBlendableSettings(
    FSceneView& View, float Weight) const
{
    if (Weight > 0.0f)
    {
        // 커스텀 데이터를 View에 전달
        // ViewExtension에서 사용
        FFinalPostProcessSettings& Settings = View.FinalPostProcessSettings;

        // 예: 커스텀 파라미터 설정
        // Settings.MyCustomParameter = EffectIntensity * Weight;
    }
}
```

---

## 커스텀 렌더 패스 구현

### RDG 패스 추가

```cpp
// MyCustomPass.h
#pragma once

#include "RenderGraphBuilder.h"
#include "SceneRendering.h"

class FMyCustomPassRenderer
{
public:
    static void AddPass(
        FRDGBuilder& GraphBuilder,
        const FSceneView& View,
        FRDGTextureRef SceneColor,
        FRDGTextureRef SceneDepth);
};
```

```cpp
// MyCustomPass.cpp
#include "MyCustomPass.h"
#include "MyShaders.h"
#include "PixelShaderUtils.h"

BEGIN_SHADER_PARAMETER_STRUCT(FMyPassParameters, )
    SHADER_PARAMETER_RDG_TEXTURE(Texture2D, SceneColorTexture)
    SHADER_PARAMETER_RDG_TEXTURE(Texture2D, SceneDepthTexture)
    SHADER_PARAMETER_SAMPLER(SamplerState, SceneSampler)
    SHADER_PARAMETER(FVector4f, CustomParams)
    RENDER_TARGET_BINDING_SLOTS()
END_SHADER_PARAMETER_STRUCT()

void FMyCustomPassRenderer::AddPass(
    FRDGBuilder& GraphBuilder,
    const FSceneView& View,
    FRDGTextureRef SceneColor,
    FRDGTextureRef SceneDepth)
{
    // 출력 텍스처 생성
    FRDGTextureDesc OutputDesc = SceneColor->Desc;
    OutputDesc.Flags |= TexCreate_UAV;
    FRDGTextureRef OutputTexture = GraphBuilder.CreateTexture(
        OutputDesc, TEXT("MyPassOutput"));

    // 파라미터 설정
    FMyPassParameters* PassParameters = GraphBuilder.AllocParameters<FMyPassParameters>();
    PassParameters->SceneColorTexture = SceneColor;
    PassParameters->SceneDepthTexture = SceneDepth;
    PassParameters->SceneSampler = TStaticSamplerState<SF_Bilinear>::GetRHI();
    PassParameters->CustomParams = FVector4f(1.0f, 0.5f, 0.0f, 1.0f);
    PassParameters->RenderTargets[0] = FRenderTargetBinding(
        OutputTexture, ERenderTargetLoadAction::ENoAction);

    // 셰이더 가져오기
    TShaderMapRef<FMyCustomPassVS> VertexShader(View.ShaderMap);
    TShaderMapRef<FMyCustomPassPS> PixelShader(View.ShaderMap);

    // 패스 추가
    GraphBuilder.AddPass(
        RDG_EVENT_NAME("MyCustomPass"),
        PassParameters,
        ERDGPassFlags::Raster,
        [PassParameters, VertexShader, PixelShader, &View](FRHICommandList& RHICmdList)
        {
            FGraphicsPipelineStateInitializer GraphicsPSOInit;
            RHICmdList.ApplyCachedRenderTargets(GraphicsPSOInit);
            GraphicsPSOInit.BlendState = TStaticBlendState<>::GetRHI();
            GraphicsPSOInit.RasterizerState = TStaticRasterizerState<>::GetRHI();
            GraphicsPSOInit.DepthStencilState = TStaticDepthStencilState<false, CF_Always>::GetRHI();
            GraphicsPSOInit.BoundShaderState.VertexDeclarationRHI = GFilterVertexDeclaration.VertexDeclarationRHI;
            GraphicsPSOInit.BoundShaderState.VertexShaderRHI = VertexShader.GetVertexShader();
            GraphicsPSOInit.BoundShaderState.PixelShaderRHI = PixelShader.GetPixelShader();
            GraphicsPSOInit.PrimitiveType = PT_TriangleList;

            SetGraphicsPipelineState(RHICmdList, GraphicsPSOInit, 0);

            SetShaderParameters(RHICmdList, PixelShader, PixelShader.GetPixelShader(), *PassParameters);

            FPixelShaderUtils::DrawFullscreenTriangle(RHICmdList);
        });
}
```

---

## 패스 삽입 위치 선택

```
┌─────────────────────────────────────────────────────────────────┐
│                    패스 삽입 위치 가이드                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  목적                              권장 위치                    │
│  ────────────────────────────────  ────────────────────────    │
│  씬 준비 / 컬링 데이터 수집        PreRenderView               │
│  커스텀 깊이 패스                   PrePass 전후                │
│  G-Buffer 추가 쓰기                PostRenderBasePass          │
│  라이팅 데이터 활용                LightingPass 후              │
│  화면 공간 효과                    PrePostProcessPass          │
│  최종 후처리                       PostProcessPass 확장         │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ 성능 고려사항:                                          │   │
│  │ - 가능한 늦은 시점에 삽입 (불필요한 동기화 방지)        │   │
│  │ - 리소스 의존성 최소화                                  │   │
│  │ - Compute는 Async 활용 검토                             │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 씬 데이터 접근

### G-Buffer 접근

```cpp
void FMyViewExtension::PostRenderBasePassDeferred_RenderThread(
    FRDGBuilder& GraphBuilder,
    FSceneView& InView,
    const FRenderTargetBindingSlots& RenderTargets,
    TRDGUniformBufferRef<FSceneTextureUniformParameters> SceneTextures)
{
    // SceneTextures에서 G-Buffer 접근
    // SceneTextures->SceneColorTexture
    // SceneTextures->SceneDepthTexture
    // SceneTextures->GBufferATexture
    // SceneTextures->GBufferBTexture
    // SceneTextures->GBufferCTexture

    FRDGTextureRef GBufferA = SceneTextures->GetContents()->GBufferATexture;
    FRDGTextureRef Depth = SceneTextures->GetContents()->SceneDepthTexture;

    // 커스텀 패스에서 사용
}
```

### 씬 프리미티브 접근

```cpp
void ProcessScenePrimitives(const FScene* Scene, const FViewInfo& View)
{
    // 가시 프리미티브 순회
    for (int32 PrimitiveIndex : View.PrimitiveVisibilityMap)
    {
        if (View.PrimitiveVisibilityMap[PrimitiveIndex])
        {
            const FPrimitiveSceneInfo* PrimitiveInfo =
                Scene->Primitives[PrimitiveIndex];

            // 프리미티브 데이터 접근
            const FBoxSphereBounds& Bounds = PrimitiveInfo->Proxy->GetBounds();
        }
    }
}
```

---

## 디버그 드로잉

### 런타임 디버그 시각화

```cpp
void FMyViewExtension::PreRenderView_RenderThread(
    FRDGBuilder& GraphBuilder,
    FSceneView& InView)
{
    // 디버그 라인 추가
    if (InView.Family->EngineShowFlags.VisualizeBuffer)
    {
        // PDI (Primitive Draw Interface) 사용
        FPrimitiveDrawInterface* PDI = InView.GetPDI();
        if (PDI)
        {
            // 월드 공간에 박스 그리기
            DrawWireBox(PDI, FBox(FVector(-100), FVector(100)),
                FColor::Red, SDPG_World);
        }
    }
}
```

### Canvas 드로잉

```cpp
void FMyViewExtension::PostRenderView_RenderThread(
    FRDGBuilder& GraphBuilder,
    FSceneView& InView)
{
    // 2D 캔버스 드로잉
    AddPass(GraphBuilder, RDG_EVENT_NAME("DebugCanvas"),
        [&InView](FRHICommandList& RHICmdList)
        {
            FCanvas Canvas(/* ... */);
            Canvas.DrawText(FVector2D(10, 10), TEXT("Debug Text"),
                GEngine->GetSmallFont(), FLinearColor::White);
            Canvas.Flush_RenderThread(RHICmdList);
        });
}
```

---

## 요약

| 확장 방법 | 용도 | 복잡도 |
|----------|------|--------|
| SceneViewExtension | 패스 삽입 | 중간 |
| IBlendableInterface | PP 볼륨 연동 | 낮음 |
| RDG Custom Pass | 완전 커스텀 | 높음 |
| Debug Drawing | 시각화 | 낮음 |

---

## 참고 자료

- [SceneViewExtension](https://docs.unrealengine.com/scene-view-extension/)
- [RDG Programming Guide](https://docs.unrealengine.com/rdg-programming/)
- [Post Process Materials](https://docs.unrealengine.com/post-process-materials/)
