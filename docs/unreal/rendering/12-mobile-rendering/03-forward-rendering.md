# Mobile Forward 렌더링

모바일 Forward 렌더링 파이프라인의 구조와 동작을 설명합니다.

---

## Forward 렌더링 개요

Forward 렌더링은 모바일의 기본 렌더링 경로로, 지오메트리와 라이팅을 한 번에 처리합니다.

```
┌─────────────────────────────────────────────────────────────────┐
│                    Forward 렌더링 흐름                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    FMobileSceneRenderer                  │   │
│  └───────────────────────┬─────────────────────────────────┘   │
│                          │                                      │
│                          ▼                                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  InitViews()                                             │   │
│  │  • Visibility Culling                                   │   │
│  │  • Primitive 수집                                       │   │
│  └───────────────────────┬─────────────────────────────────┘   │
│                          │                                      │
│                          ▼                                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  RenderForward()                                         │   │
│  │  ├── PrePass (선택적)                                   │   │
│  │  ├── BasePass + Lighting                                │   │
│  │  ├── Translucency                                       │   │
│  │  └── Post Process                                       │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## FMobileSceneRenderer 구조

### 주요 멤버

```cpp
class FMobileSceneRenderer : public FSceneRenderer
{
    // Forward 렌더링
    void RenderForward(FRHICommandListImmediate& RHICmdList);

    // Deferred 렌더링 (UE 4.26+)
    void RenderDeferred(FRHICommandListImmediate& RHICmdList);

    // 공통 기능
    void InitViews(...);
    void RenderShadowDepthMaps(FRHICommandListImmediate& RHICmdList);
    void RenderTranslucency(FRHICommandListImmediate& RHICmdList);
};
```

### 렌더링 메인 루프

```cpp
void FMobileSceneRenderer::Render(FRHICommandListImmediate& RHICmdList)
{
    // 1. 뷰 초기화
    InitViews(RHICmdList);

    // 2. 그림자 맵 렌더링
    RenderShadowDepthMaps(RHICmdList);

    // 3. 경로 선택
    if (bUseDeferredShading)
    {
        RenderDeferred(RHICmdList);
    }
    else
    {
        RenderForward(RHICmdList);
    }

    // 4. Post Process
    RenderPostProcess(RHICmdList);
}
```

---

## Forward Pass 상세

### Base Pass

Forward에서 Base Pass는 지오메트리와 라이팅을 함께 처리합니다.

```
┌─────────────────────────────────────────────────────────────────┐
│                    Forward Base Pass                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  각 오브젝트에 대해:                                            │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Vertex Shader                                          │   │
│  │  ├── World Position 계산                                │   │
│  │  ├── Normal/Tangent 변환                                │   │
│  │  └── UV 전달                                            │   │
│  └───────────────────────┬─────────────────────────────────┘   │
│                          │                                      │
│                          ▼                                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Pixel Shader                                           │   │
│  │  ├── Material 속성 계산                                 │   │
│  │  │   • BaseColor                                        │   │
│  │  │   • Normal                                           │   │
│  │  │   • Roughness, Metallic                              │   │
│  │  │                                                      │   │
│  │  ├── Lighting 계산 (한 번에)                            │   │
│  │  │   • Directional Light                                │   │
│  │  │   • Point/Spot Lights (최대 4+4)                     │   │
│  │  │   • Shadow 샘플링                                    │   │
│  │  │   • IBL (Image-Based Lighting)                       │   │
│  │  │                                                      │   │
│  │  └── Final Color 출력                                   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Forward 셰이더 구조

```hlsl
// MobileBasePassPixelShader.usf 간략화
void Main(
    FVertexFactoryInterpolantsVSToPS Interpolants,
    FMobileBasePassInterpolantsVSToPS BasePassInterpolants,
    out half4 OutColor : SV_Target0)
{
    // 1. Material 계산
    FMaterialPixelParameters MaterialParameters = GetMaterialPixelParameters(...);
    FPixelMaterialInputs PixelMaterialInputs = GetPixelMaterialInputs(MaterialParameters);

    // 2. GBuffer 데이터 구성 (Deferred 호환 구조)
    FGBufferData GBuffer;
    GBuffer.BaseColor = GetMaterialBaseColor(PixelMaterialInputs);
    GBuffer.Metallic = GetMaterialMetallic(PixelMaterialInputs);
    GBuffer.Roughness = GetMaterialRoughness(PixelMaterialInputs);
    GBuffer.WorldNormal = GetMaterialNormal(MaterialParameters);

    // 3. Lighting 계산
    half3 Color = 0;

    // Directional Light
    Color += GetDirectionalLighting(GBuffer, ShadowFactor);

    // Local Lights (Point + Spot)
    LOOP for (uint i = 0; i < NumLocalLights; i++)
    {
        Color += GetLocalLighting(GBuffer, LocalLights[i]);
    }

    // IBL
    Color += GetImageBasedReflectionLighting(GBuffer);

    // 4. 출력
    OutColor = half4(Color, 1.0);
}
```

---

## Light Culling

### Per-Object Light Assignment

```
┌─────────────────────────────────────────────────────────────────┐
│                    Light Assignment 방식                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  CPU에서 각 오브젝트에 영향을 주는 광원 계산:                   │
│                                                                 │
│  오브젝트 A                                                     │
│  ┌─────────────┐      Light List: [L0, L2, L4]                 │
│  │             │                                                │
│  │     ●       │  L0: Directional                              │
│  │             │  L2: Point                                     │
│  └─────────────┘  L4: Spot                                     │
│                                                                 │
│  오브젝트 B                                                     │
│  ┌─────────────┐      Light List: [L0, L1, L3]                 │
│  │             │                                                │
│  │     ●       │  L0: Directional                              │
│  │             │  L1: Point                                     │
│  └─────────────┘  L3: Point                                    │
│                                                                 │
│  • 오브젝트당 최대 광원 수 제한 (일반적으로 4+4)               │
│  • 거리/밝기 기반 우선순위 정렬                                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Shadow 처리

### CSM (Cascaded Shadow Maps)

```
┌─────────────────────────────────────────────────────────────────┐
│                    모바일 CSM 처리                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Shadow Map 생성:                                               │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  각 Cascade에 대해:                                      │   │
│  │  • Shadow Caster 렌더링                                  │   │
│  │  • Depth만 기록                                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Forward Pass에서 샘플링:                                       │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  // Cascade 선택                                         │   │
│  │  int CascadeIndex = GetCascadeIndex(WorldPosition);      │   │
│  │                                                         │   │
│  │  // Shadow 좌표 변환                                     │   │
│  │  float4 ShadowCoord = mul(WorldPos, ShadowMatrix[Index]);│   │
│  │                                                         │   │
│  │  // PCF 샘플링                                          │   │
│  │  float Shadow = SampleShadowMapPCF(ShadowCoord);         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 모바일 Shadow 최적화

```cpp
// 권장 설정
r.Shadow.CSM.MaxCascades=2       // Cascade 수 제한
r.Shadow.MaxResolution=1024      // 해상도 제한
r.Shadow.DistanceScale=0.5       // 그림자 거리 축소
r.Shadow.FilterMethod=1          // PCF 필터링
```

---

## Translucency 처리

### Separate Translucency

```
┌─────────────────────────────────────────────────────────────────┐
│                    Translucency 렌더링                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Opaque Pass 완료 후                                         │
│                                                                 │
│  2. Translucent Objects 정렬                                    │
│     • Back-to-Front (뒤에서 앞으로)                            │
│     • Blend 모드에 따른 그룹화                                 │
│                                                                 │
│  3. 렌더링                                                      │
│     ┌───────────────────────────────────────────────────┐      │
│     │  for each TranslucentObject (sorted):             │      │
│     │      // Forward Lighting 적용                     │      │
│     │      // Alpha Blend                               │      │
│     │      DrawTranslucent(Object);                     │      │
│     └───────────────────────────────────────────────────┘      │
│                                                                 │
│  주의: 정렬 오류로 인한 아티팩트 가능                           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Forward vs Deferred 비교

```
┌─────────────────────────────────────────────────────────────────┐
│                    렌더링 경로 비교                              │
├────────────────────────────┬────────────────────────────────────┤
│         Forward            │           Deferred                 │
├────────────────────────────┼────────────────────────────────────┤
│ 적은 광원에 효율적         │ 많은 광원에 효율적                 │
│ MSAA 지원                  │ MSAA 미지원 (TAA 사용)             │
│ 대역폭 절약                │ G-Buffer 대역폭 사용               │
│ 머티리얼 복잡도 영향 있음  │ 머티리얼 복잡도 일정 비용         │
│ 기본 경로                  │ r.Mobile.ShadingPath=1            │
│ 구형 디바이스 호환         │ 신형 디바이스 권장                 │
└────────────────────────────┴────────────────────────────────────┘
```

### 선택 가이드

```
┌─────────────────────────────────────────────────────────────────┐
│                    경로 선택 기준                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Forward 권장:                                                  │
│  • 동적 광원 4개 이하                                          │
│  • MSAA 필요                                                   │
│  • 넓은 디바이스 호환성 필요                                   │
│  • 단순한 라이팅 환경                                          │
│                                                                 │
│  Deferred 권장:                                                 │
│  • 동적 광원 4개 초과                                          │
│  • 복잡한 라이팅 환경                                          │
│  • 최신 디바이스 타겟                                          │
│  • TAA 사용 가능                                               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 다음 단계

[Deferred 렌더링](04-deferred-rendering.md)에서 모바일 Deferred 구현을 알아봅니다.
