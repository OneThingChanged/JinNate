# BasePass

> Chapter 05-2: G-Buffer 생성과 머티리얼 렌더링

---

## 목차

1. [BasePass 개요](#1-basepass-개요)
2. [렌더링 파이프라인 위치](#2-렌더링-파이프라인-위치)
3. [렌더 상태 설정](#3-렌더-상태-설정)
4. [버텍스 셰이더](#4-버텍스-셰이더)
5. [픽셀 셰이더](#5-픽셀-셰이더)
6. [G-Buffer 레이아웃](#6-g-buffer-레이아웃)
7. [머티리얼 처리](#7-머티리얼-처리)

---

## 1. BasePass 개요 {#1-basepass-개요}

![BasePass 개요](../images/ch05/1617944-20210527125905484-986749331.jpg)
*BasePass 렌더링 단계*

BasePass는 디퍼드 렌더링 파이프라인에서 **G-Buffer를 생성**하는 핵심 단계입니다. 모든 불투명 오브젝트의 머티리얼 속성(BaseColor, Normal, Roughness, Metallic 등)을 Multiple Render Targets(MRT)에 기록합니다.

### 주요 역할

```
┌─────────────────────────────────────────────────────────────────┐
│                      BasePass 역할                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   1. 머티리얼 평가 (Material Evaluation)                         │
│      - BaseColor, Normal, Roughness, Metallic                   │
│      - 셰이딩 모델 ID                                            │
│                                                                  │
│   2. G-Buffer 기록 (MRT Output)                                 │
│      - GBufferA: Normal + ShadingModelID                        │
│      - GBufferB: BaseColor + Metallic                           │
│      - GBufferC: Specular + Roughness                           │
│      - GBufferD: Custom Data                                    │
│                                                                  │
│   3. 뎁스 버퍼 기록                                              │
│      - 라이팅 패스용 뎁스 정보                                    │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. 렌더링 파이프라인 위치 {#2-렌더링-파이프라인-위치}

![파이프라인 위치](../images/ch05/1617944-20210527125917125-541399809.jpg)
*디퍼드 렌더링 파이프라인에서 BasePass의 위치*

BasePass는 `FDeferredShadingSceneRenderer::Render`에서 PrePass 이후, LightingPass 이전에 실행됩니다.

```
FDeferredShadingSceneRenderer::Render()
│
├─→ PrePass (Early Z / Depth Only)
│   └─ Depth Buffer 생성
│
├─→ ★ BasePass ★
│   ├─ 모든 View 순회
│   ├─ 각 View에서 BasePass 렌더링
│   └─ G-Buffer 생성
│
├─→ Shadow Depth Pass
│   └─ Shadow Maps 생성
│
└─→ LightingPass
    └─ G-Buffer 읽기 + 라이팅 계산
```

### 코드 흐름

```cpp
void FDeferredShadingSceneRenderer::Render(FRHICommandListImmediate& RHICmdList)
{
    // PrePass
    RenderPrePass(RHICmdList);

    // BasePass
    RenderBasePass(RHICmdList);  // ← 여기

    // Shadow
    RenderShadowDepthMaps(RHICmdList);

    // Lighting
    RenderLights(RHICmdList);
}

void FDeferredShadingSceneRenderer::RenderBasePass(FRHICommandListImmediate& RHICmdList)
{
    // 모든 View 순회
    for (int32 ViewIndex = 0; ViewIndex < Views.Num(); ViewIndex++)
    {
        FViewInfo& View = Views[ViewIndex];

        // 병렬 렌더링 활성화 시
        if (GRHICommandList.UseParallelExecute())
        {
            // 병렬 커맨드 리스트 생성
            FScopedCommandListWaitForTasks Flusher(RHICmdList, View);

            // BasePass 렌더링
            RenderBasePassView(RHICmdList, View);
        }
        else
        {
            RenderBasePassView(RHICmdList, View);
        }
    }
}
```

---

## 3. 렌더 상태 설정 {#3-렌더-상태-설정}

![렌더 상태](../images/ch05/1617944-20210527130006177-768044047.jpg)
*BasePass의 렌더 상태 설정*

### Blend State

G-Buffer에 RGBA 채널을 모두 기록합니다.

```cpp
// BasePass Blend State
FBlendStateInitializerRHI BlendState;

// 각 Render Target에 대해
for (uint32 i = 0; i < MaxSimultaneousRenderTargets; i++)
{
    BlendState.RenderTargets[i].ColorBlendOp = BO_Add;
    BlendState.RenderTargets[i].ColorSrcBlend = BF_One;
    BlendState.RenderTargets[i].ColorDestBlend = BF_Zero;
    BlendState.RenderTargets[i].ColorWriteMask = CW_RGBA;  // RGBA 모두 기록
}
```

### Depth-Stencil State

뎁스 쓰기와 테스트가 활성화됩니다.

```cpp
// BasePass Depth-Stencil State
FDepthStencilStateInitializerRHI DepthState;

DepthState.bEnableDepthWrite = true;        // 뎁스 쓰기 활성화
DepthState.DepthTest = CF_DepthNearOrEqual; // 비교 함수: NearOrEqual
DepthState.bEnableFrontFaceStencil = false;
DepthState.bEnableBackFaceStencil = false;
```

> **NearOrEqual 비교**: PrePass에서 이미 뎁스를 기록했으므로, 동일한 뎁스 값을 통과시킵니다.

### Render Targets 바인딩

![MRT 바인딩](../images/ch05/1617944-20210527130020649-841720934.png)
*Multiple Render Targets 바인딩 구조*

```cpp
FRHIRenderPassInfo RPInfo;

// G-Buffer 바인딩
RPInfo.ColorRenderTargets[0] = FRHIRenderPassInfo::ColorEntry(GBufferA, ERenderTargetActions::Clear_Store);
RPInfo.ColorRenderTargets[1] = FRHIRenderPassInfo::ColorEntry(GBufferB, ERenderTargetActions::Clear_Store);
RPInfo.ColorRenderTargets[2] = FRHIRenderPassInfo::ColorEntry(GBufferC, ERenderTargetActions::Clear_Store);
RPInfo.ColorRenderTargets[3] = FRHIRenderPassInfo::ColorEntry(GBufferD, ERenderTargetActions::Clear_Store);

// Depth Buffer
RPInfo.DepthStencilRenderTarget.DepthStencilTarget = SceneDepthZ;
RPInfo.DepthStencilRenderTarget.Action = EDepthStencilTargetActions::LoadDepthStencil_StoreDepthStencil;

RHICmdList.BeginRenderPass(RPInfo, TEXT("BasePass"));
```

---

## 4. 버텍스 셰이더 {#4-버텍스-셰이더}

![버텍스 셰이더](../images/ch05/1617944-20210527130038520-1705617727.jpg)
*버텍스 셰이더 처리 흐름*

### TBasePassVS 템플릿 클래스

```cpp
// C++ 측 셰이더 클래스
template<typename LightMapPolicyType>
class TBasePassVS : public FMeshMaterialShader
{
    DECLARE_SHADER_TYPE(TBasePassVS, MeshMaterial);

public:
    static bool ShouldCompilePermutation(...)
    {
        return IsFeatureLevelSupported(Platform, ERHIFeatureLevel::SM5);
    }

    static void ModifyCompilationEnvironment(...)
    {
        // 컴파일 환경 설정
        FMeshMaterialShader::ModifyCompilationEnvironment(Parameters, OutEnvironment);
        LightMapPolicyType::ModifyCompilationEnvironment(Parameters, OutEnvironment);
    }
};
```

### 버텍스 셰이더 처리 과정

```hlsl
// BasePassVertexShader.usf

struct FBasePassVSOutput
{
    FVertexFactoryInterpolantsVSToPS FactoryInterpolants;
    FBasePassInterpolantsVSToPS BasePassInterpolants;
    float4 Position : SV_POSITION;
};

FBasePassVSOutput Main(FVertexFactoryInput Input)
{
    FBasePassVSOutput Output;

    // 1. 로컬 → 월드 변환
    FVertexFactoryIntermediates VFIntermediates = GetVertexFactoryIntermediates(Input);
    float4 WorldPosition = VertexFactoryGetWorldPosition(Input, VFIntermediates);

    // 2. 머티리얼 월드 위치 오프셋 적용
    float3 WorldPositionOffset = GetMaterialWorldPositionOffset(Input);
    WorldPosition.xyz += WorldPositionOffset;

    // 3. 탄젠트 공간 계산
    float3x3 TangentToLocal = VertexFactoryGetTangentToLocal(Input, VFIntermediates);
    float3x3 TangentToWorld = CalcTangentToWorld(TangentToLocal, WorldPosition);

    Output.BasePassInterpolants.TangentToWorld0 = TangentToWorld[0];
    Output.BasePassInterpolants.TangentToWorld2 = TangentToWorld[2];

    // 4. 클립 공간 변환
    Output.Position = mul(WorldPosition, View.WorldToClip);

    // 5. 보간 데이터 준비
    Output.FactoryInterpolants = VertexFactoryGetInterpolantsVSToPS(Input, VFIntermediates);

    // 6. 추가 데이터 (Fog, Velocity 등)
    #if NEEDS_BASEPASS_VERTEX_FOGGING
        Output.BasePassInterpolants.VertexFog = ComputeVolumeFog(WorldPosition);
    #endif

    #if WRITES_VELOCITY_TO_GBUFFER
        Output.BasePassInterpolants.VelocityPrevPosition = mul(PrevWorldPosition, View.PrevWorldToClip);
    #endif

    return Output;
}
```

### 버텍스 셰이더 주요 기능

| 기능 | 설명 |
|------|------|
| **Position Transform** | Local → World → Clip 변환 |
| **WPO (World Position Offset)** | 머티리얼 기반 위치 오프셋 |
| **Tangent Space** | TBN 매트릭스 계산 |
| **Interpolants** | 픽셀 셰이더용 데이터 준비 |
| **Volumetric Fog** | 볼류메트릭 포그 데이터 |
| **Velocity** | 모션 블러용 이전 프레임 위치 |

---

## 5. 픽셀 셰이더 {#5-픽셀-셰이더}

![픽셀 셰이더](../images/ch05/1617944-20210527130049178-1390887379.jpg)
*픽셀 셰이더 G-Buffer 출력 과정*

### 픽셀 셰이더 처리 과정

```hlsl
// BasePassPixelShader.usf

void Main(
    FVertexFactoryInterpolantsVSToPS Interpolants,
    FBasePassInterpolantsVSToPS BasePassInterpolants,
    in float4 SvPosition : SV_Position,
    out float4 OutGBufferA : SV_Target0,
    out float4 OutGBufferB : SV_Target1,
    out float4 OutGBufferC : SV_Target2,
    out float4 OutGBufferD : SV_Target3,
    out float4 OutGBufferE : SV_Target4,
    out float4 OutGBufferVelocity : SV_Target5)
{
    // 1. 머티리얼 파라미터 획득
    FMaterialPixelParameters MaterialParameters = GetMaterialPixelParameters(
        Interpolants,
        SvPosition);

    // 2. 픽셀 머티리얼 입력 계산
    FPixelMaterialInputs PixelMaterialInputs;
    CalcMaterialParameters(MaterialParameters, PixelMaterialInputs, SvPosition);

    // 3. 월드 노멀 계산
    float3 WorldNormal = MaterialParameters.WorldNormal;

    #if MATERIAL_TANGENT_SPACE_NORMAL
        // 탄젠트 공간 노멀 맵 적용
        float3 TangentNormal = GetMaterialNormal(PixelMaterialInputs);
        WorldNormal = TransformTangentVectorToWorld(
            BasePassInterpolants.TangentToWorld0,
            BasePassInterpolants.TangentToWorld2,
            TangentNormal);
    #endif

    // 4. G-Buffer 데이터 구성
    FGBufferData GBuffer = (FGBufferData)0;

    GBuffer.WorldNormal = normalize(WorldNormal);
    GBuffer.BaseColor = GetMaterialBaseColor(PixelMaterialInputs);
    GBuffer.Metallic = GetMaterialMetallic(PixelMaterialInputs);
    GBuffer.Specular = GetMaterialSpecular(PixelMaterialInputs);
    GBuffer.Roughness = GetMaterialRoughness(PixelMaterialInputs);
    GBuffer.ShadingModelID = GetMaterialShadingModel(PixelMaterialInputs);
    GBuffer.CustomData = GetMaterialCustomData0(PixelMaterialInputs);

    // 5. 파생 값 계산
    GBuffer.DiffuseColor = GBuffer.BaseColor * (1 - GBuffer.Metallic);
    GBuffer.SpecularColor = ComputeF0(GBuffer.Specular, GBuffer.BaseColor, GBuffer.Metallic);

    // 6. G-Buffer 인코딩 및 출력
    EncodeGBuffer(GBuffer,
        OutGBufferA,
        OutGBufferB,
        OutGBufferC,
        OutGBufferD,
        OutGBufferE);

    // 7. Velocity 출력 (모션 블러용)
    #if WRITES_VELOCITY_TO_GBUFFER
        float4 ScreenPos = SvPositionToScreenPosition(SvPosition);
        float4 PrevScreenPos = BasePassInterpolants.VelocityPrevPosition;
        OutGBufferVelocity = EncodeVelocity(ScreenPos, PrevScreenPos);
    #endif
}
```

### 픽셀 셰이더 주요 기능

| 단계 | 함수 | 출력 |
|------|------|------|
| **머티리얼 평가** | `GetMaterial*()` | BaseColor, Roughness, etc. |
| **노멀 변환** | `TransformTangentVectorToWorld` | World Normal |
| **G-Buffer 구성** | `FGBufferData` | 구조체 채우기 |
| **인코딩** | `EncodeGBuffer` | MRT 출력 |
| **Velocity** | `EncodeVelocity` | 모션 벡터 |

---

## 6. G-Buffer 레이아웃 {#6-g-buffer-레이아웃}

![G-Buffer 레이아웃](../images/ch05/1617944-20210527130104721-1388293420.jpg)
*G-Buffer MRT 레이아웃 구조*

### UE4/5 기본 G-Buffer 레이아웃

```
┌─────────────────────────────────────────────────────────────────┐
│                    G-Buffer Layout (MRT)                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   GBufferA (RGBA8)                                              │
│   ┌────────┬────────┬────────┬────────┐                         │
│   │ Normal │ Normal │PerObj  │Shading │                         │
│   │  .xy   │  (Oct) │ Data   │ModelID │                         │
│   └────────┴────────┴────────┴────────┘                         │
│                                                                  │
│   GBufferB (RGBA8)                                              │
│   ┌────────┬────────┬────────┬────────┐                         │
│   │ Base   │ Base   │ Base   │Metallic│                         │
│   │Color.r │Color.g │Color.b │        │                         │
│   └────────┴────────┴────────┴────────┘                         │
│                                                                  │
│   GBufferC (RGBA8)                                              │
│   ┌────────┬────────┬────────┬────────┐                         │
│   │Specular│Roughness│Reserved│Selective│                       │
│   │        │        │        │OutputMask│                       │
│   └────────┴────────┴────────┴────────┘                         │
│                                                                  │
│   GBufferD (RGBA8) - Custom Data                                │
│   ┌────────┬────────┬────────┬────────┐                         │
│   │Custom0 │Custom1 │Custom2 │Custom3 │                         │
│   │(SSS/CC)│        │        │        │                         │
│   └────────┴────────┴────────┴────────┘                         │
│                                                                  │
│   GBufferE (RGBA8) - Precomputed Shadow                         │
│   ┌────────┬────────┬────────┬────────┐                         │
│   │Shadow  │Shadow  │Shadow  │Shadow  │                         │
│   │Factor0 │Factor1 │Factor2 │Factor3 │                         │
│   └────────┴────────┴────────┴────────┘                         │
│                                                                  │
│   Velocity (RG16F)                                              │
│   ┌────────────────┬────────────────┐                           │
│   │   Velocity.x   │   Velocity.y   │                           │
│   └────────────────┴────────────────┘                           │
│                                                                  │
│   Depth (D24S8 or D32F)                                         │
│   ┌─────────────────────────────────┐                           │
│   │          Scene Depth            │                           │
│   └─────────────────────────────────┘                           │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 각 버퍼 상세

![G-Buffer 상세](../images/ch05/1617944-20210527130206062-1209308195.jpg)
*G-Buffer 채널별 상세 정보*

| Buffer | Format | 내용 |
|--------|--------|------|
| **GBufferA** | RGBA8 | Normal(Oct), PerObjectData, ShadingModelID |
| **GBufferB** | RGBA8 | BaseColor(RGB), Metallic(A) |
| **GBufferC** | RGBA8 | Specular(R), Roughness(G), SelectiveOutputMask(A) |
| **GBufferD** | RGBA8 | Custom Data (Subsurface, ClearCoat 등) |
| **GBufferE** | RGBA8 | Precomputed Shadow Factors |
| **Velocity** | RG16F | Motion Vector |
| **Depth** | D24S8/D32F | Scene Depth |

### Shading Model별 Custom Data 사용

![Custom Data 사용](../images/ch05/1617944-20210527130217837-1881273996.jpg)
*셰이딩 모델별 Custom Data 활용*

| Shading Model | CustomData0 | CustomData1 |
|---------------|-------------|-------------|
| **Subsurface** | Opacity | Subsurface Color |
| **Clear Coat** | Clear Coat | Clear Coat Roughness |
| **Cloth** | Fuzz Color | Cloth |
| **Eye** | Iris Mask | Iris Distance |
| **Hair** | Backlit | Scatter |

---

## 7. 머티리얼 처리 {#7-머티리얼-처리}

![머티리얼 처리](../images/ch05/1617944-20210527130233682-592550534.jpg)
*머티리얼 평가 및 G-Buffer 기록 과정*

### 머티리얼 프록시 선택

```cpp
// FMeshBatch에서 머티리얼 가져오기
const FMaterial* Material = MeshBatch.MaterialRenderProxy->GetMaterialWithFallback(
    FeatureLevel,
    MaterialRenderProxy);
```

### Uniform Buffer 바인딩

![Uniform Buffer](../images/ch05/1617944-20210527130252040-1869057576.png)
*Uniform Buffer 구조 및 바인딩*

```cpp
// BasePass Uniform Parameters
BEGIN_GLOBAL_SHADER_PARAMETER_STRUCT(FOpaqueBasePassUniformParameters, )
    SHADER_PARAMETER_STRUCT(FSceneTextureUniformParameters, SceneTextures)
    SHADER_PARAMETER_STRUCT(FViewUniformShaderParameters, View)
    SHADER_PARAMETER_STRUCT(FForwardLightData, ForwardLightData)
    SHADER_PARAMETER_STRUCT(FReflectionCaptureShaderData, ReflectionCapture)
    SHADER_PARAMETER(float, IndirectLightingColorScale)
    SHADER_PARAMETER(float, DitheredLODTransitionValue)
END_GLOBAL_SHADER_PARAMETER_STRUCT()

// 바인딩
TUniformBufferRef<FOpaqueBasePassUniformParameters> BasePassUniformBuffer =
    TUniformBufferRef<FOpaqueBasePassUniformParameters>::CreateUniformBufferImmediate(
        BasePassParameters, UniformBuffer_SingleFrame);

RHICmdList.SetShaderUniformBuffer(VertexShader, BasePassUniformBuffer);
RHICmdList.SetShaderUniformBuffer(PixelShader, BasePassUniformBuffer);
```

### 머티리얼 표현식 평가

![머티리얼 그래프](../images/ch05/1617944-20210527130306160-322807720.jpg)
*머티리얼 그래프에서 셰이더 코드로 변환*

```hlsl
// 머티리얼 노드 그래프가 컴파일된 코드
float3 GetMaterialBaseColor(FPixelMaterialInputs PixelMaterialInputs)
{
    // 머티리얼 에디터에서 연결된 노드 그래프가
    // 이 함수의 본문으로 컴파일됨

    // 예: TextureSample → Multiply → Output
    float4 TexSample = Texture2DSample(Material.Texture0, Material.Sampler0, PixelMaterialInputs.TexCoords[0]);
    float3 TintColor = Material.VectorExpressions[0].rgb;
    return TexSample.rgb * TintColor;
}

float GetMaterialRoughness(FPixelMaterialInputs PixelMaterialInputs)
{
    // Roughness 입력에 연결된 노드 그래프
    return lerp(Material.ScalarExpressions[0], Material.ScalarExpressions[1],
                Texture2DSample(Material.Texture1, Material.Sampler0, PixelMaterialInputs.TexCoords[0]).r);
}
```

### 머티리얼 컴파일 파이프라인

![컴파일 파이프라인](../images/ch05/1617944-20210527130345916-1848201300.png)
*머티리얼 노드에서 HLSL 코드 생성 과정*

```
┌─────────────────────────────────────────────────────────────────┐
│                Material Compilation Pipeline                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   ┌───────────────┐                                             │
│   │ Material Graph│  ─── UMaterial (에디터에서 생성)             │
│   └───────┬───────┘                                             │
│           │                                                      │
│           ▼                                                      │
│   ┌───────────────┐                                             │
│   │ Expression   │  ─── FMaterialCompiler가 노드 순회            │
│   │ Compilation   │                                             │
│   └───────┬───────┘                                             │
│           │                                                      │
│           ▼                                                      │
│   ┌───────────────┐                                             │
│   │ HLSL Code    │  ─── GetMaterial*() 함수 본문 생성           │
│   │ Generation    │                                             │
│   └───────┬───────┘                                             │
│           │                                                      │
│           ▼                                                      │
│   ┌───────────────┐                                             │
│   │ Shader       │  ─── DXC/FXC로 바이트코드 컴파일              │
│   │ Compilation   │                                             │
│   └───────┬───────┘                                             │
│           │                                                      │
│           ▼                                                      │
│   ┌───────────────┐                                             │
│   │ PSO Creation │  ─── Pipeline State Object 생성             │
│   └───────────────┘                                             │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 요약

![BasePass 요약](../images/ch05/1617944-20210527130425016-374852199.png)
*BasePass 전체 프로세스 요약*

```
┌─────────────────────────────────────────────────────────────────┐
│                    BasePass Summary                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   Input                        Output                           │
│   ─────                        ──────                           │
│   • Mesh Geometry              • GBufferA (Normal, ShadingModel)│
│   • Material Properties        • GBufferB (BaseColor, Metallic) │
│   • Transform Matrices         • GBufferC (Specular, Roughness) │
│   • Textures                   • GBufferD (Custom Data)         │
│                                • GBufferE (Shadow Factors)      │
│                                • Velocity                       │
│                                • Depth                          │
│                                                                  │
│   Pipeline Position: PrePass → ★BasePass★ → Shadows → Lighting │
│                                                                  │
│   Key Features:                                                  │
│   • MRT (Multiple Render Targets)                               │
│   • Parallel Command Lists                                       │
│   • Material Graph Evaluation                                    │
│   • Tangent Space Normal Mapping                                 │
│   • Motion Vector Generation                                     │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 참고 자료

- 원문: https://www.cnblogs.com/timlly/p/14817455.html
- UE Source: `Engine/Source/Runtime/Renderer/Private/BasePassRendering.cpp`
- UE Shader: `Engine/Shaders/Private/BasePassPixelShader.usf`
---

<div style="display: flex; justify-content: space-between; align-items: center; padding: 16px 0;">
  <a href="../01-shader-system/" style="text-decoration: none;">← 이전: 01. 셰이더 시스템 아키텍처</a>
  <a href="../03-light-sources/" style="text-decoration: none;">다음: 03. 광원 (Light Sources) →</a>
</div>
