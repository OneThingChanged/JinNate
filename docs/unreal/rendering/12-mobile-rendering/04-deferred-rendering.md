# Mobile Deferred 렌더링

UE 4.26+에서 도입된 모바일 Deferred Shading 구현을 설명합니다.

---

## Deferred Shading 개요

모바일 Deferred는 TBDR 아키텍처를 활용하여 G-Buffer를 타일 메모리 내에서 처리합니다.

```
┌─────────────────────────────────────────────────────────────────┐
│                    Mobile Deferred 파이프라인                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Geometry Pass (GBuffer 생성)                            │   │
│  │  • BaseColor + Metallic → RT0                           │   │
│  │  • WorldNormal + Specular → RT1                         │   │
│  │  • Depth → Depth Buffer                                 │   │
│  └───────────────────────┬─────────────────────────────────┘   │
│                          │                                      │
│                          │  Subpass (타일 메모리 유지)          │
│                          ▼                                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Lighting Pass                                           │   │
│  │  • G-Buffer 읽기 (타일 메모리에서)                      │   │
│  │  • Directional Light                                    │   │
│  │  • Local Lights (Tiled)                                 │   │
│  │  • IBL                                                  │   │
│  └───────────────────────┬─────────────────────────────────┘   │
│                          │                                      │
│                          ▼                                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Final Output (Resolve to System Memory)                 │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## G-Buffer 구조

### 모바일 최적화 G-Buffer

데스크톱 대비 축소된 G-Buffer를 사용하여 대역폭을 절약합니다.

```
┌─────────────────────────────────────────────────────────────────┐
│                    Mobile G-Buffer Layout                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  RT0 (RGBA8 또는 RGB10A2):                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  R: BaseColor.r                                         │   │
│  │  G: BaseColor.g                                         │   │
│  │  B: BaseColor.b                                         │   │
│  │  A: Metallic                                            │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  RT1 (RGBA8 또는 RGB10A2):                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  R: WorldNormal.x (encoded)                             │   │
│  │  G: WorldNormal.y (encoded)                             │   │
│  │  B: Roughness                                           │   │
│  │  A: ShadingModelID / Specular                           │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Depth (D24S8 또는 D32F):                                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  24-bit Depth + 8-bit Stencil                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  총 대역폭: 64~80 bits per pixel (타일 내)                     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Normal 인코딩

```hlsl
// Octahedron Normal Encoding (2채널로 3D Normal 저장)
float2 EncodeNormal(float3 N)
{
    N /= (abs(N.x) + abs(N.y) + abs(N.z));
    if (N.z < 0)
    {
        N.xy = (1 - abs(N.yx)) * sign(N.xy);
    }
    return N.xy * 0.5 + 0.5;
}

float3 DecodeNormal(float2 Encoded)
{
    float2 N = Encoded * 2 - 1;
    float3 Normal = float3(N.xy, 1 - abs(N.x) - abs(N.y));
    if (Normal.z < 0)
    {
        Normal.xy = (1 - abs(Normal.yx)) * sign(Normal.xy);
    }
    return normalize(Normal);
}
```

---

## Subpass 활용

### Vulkan/Metal Subpass

TBDR GPU에서 G-Buffer를 시스템 메모리에 쓰지 않고 타일 메모리 내에서 직접 사용합니다.

```
┌─────────────────────────────────────────────────────────────────┐
│                    Subpass 동작 방식                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Without Subpass (비효율적):                                    │
│  ┌────────────────────────────────────────────────────────┐    │
│  │  Geometry Pass                                          │    │
│  │       │                                                 │    │
│  │       ▼                                                 │    │
│  │  [G-Buffer → System Memory]  ← 대역폭 사용             │    │
│  │       │                                                 │    │
│  │       ▼                                                 │    │
│  │  [System Memory → G-Buffer]  ← 대역폭 사용             │    │
│  │       │                                                 │    │
│  │       ▼                                                 │    │
│  │  Lighting Pass                                          │    │
│  └────────────────────────────────────────────────────────┘    │
│                                                                 │
│  With Subpass (효율적):                                         │
│  ┌────────────────────────────────────────────────────────┐    │
│  │  Geometry Pass                                          │    │
│  │       │                                                 │    │
│  │       │  ┌─────────────────────┐                        │    │
│  │       └─▶│   Tile Memory      │  ← 타일 내 유지        │    │
│  │          │   (G-Buffer)       │                        │    │
│  │       ┌──│                    │                        │    │
│  │       │  └─────────────────────┘                        │    │
│  │       ▼                                                 │    │
│  │  Lighting Pass                                          │    │
│  │       │                                                 │    │
│  │       ▼                                                 │    │
│  │  [Final Color → System Memory]  ← 최종 출력만 기록     │    │
│  └────────────────────────────────────────────────────────┘    │
│                                                                 │
│  대역폭 절감: 36~62%                                           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Vulkan Subpass 코드

```cpp
// Render Pass 생성 시 Subpass 정의
VkSubpassDescription subpasses[2];

// Subpass 0: Geometry Pass
subpasses[0].pColorAttachments = gbufferAttachments;  // RT0, RT1
subpasses[0].pDepthStencilAttachment = &depthAttachment;

// Subpass 1: Lighting Pass
subpasses[1].pInputAttachments = gbufferInputs;  // Subpass 0 출력을 입력으로
subpasses[1].pColorAttachments = &finalColorAttachment;

// Subpass 의존성
VkSubpassDependency dependency;
dependency.srcSubpass = 0;
dependency.dstSubpass = 1;
dependency.srcStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
dependency.dstStageMask = VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT;
```

---

## Lighting Pass

### Tiled Lighting

```
┌─────────────────────────────────────────────────────────────────┐
│                    Tiled Deferred Lighting                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Light Culling (Compute Pass)                                │
│     ┌─────────────────────────────────────────────────────┐    │
│     │  화면을 타일로 분할 (예: 16x16 픽셀)                 │    │
│     │  각 타일에 영향을 주는 광원 목록 생성               │    │
│     │                                                     │    │
│     │  Tile [0,0]: Light 0, 2, 5                          │    │
│     │  Tile [0,1]: Light 0, 1, 3                          │    │
│     │  ...                                                 │    │
│     └─────────────────────────────────────────────────────┘    │
│                                                                 │
│  2. Lighting (각 타일에서)                                      │
│     ┌─────────────────────────────────────────────────────┐    │
│     │  for each pixel in tile:                            │    │
│     │      GBuffer = LoadGBuffer(pixel);                  │    │
│     │      Color = 0;                                     │    │
│     │                                                     │    │
│     │      // Directional Light (전역)                    │    │
│     │      Color += DirectionalLighting(GBuffer);         │    │
│     │                                                     │    │
│     │      // Local Lights (타일별 컬링된 목록)           │    │
│     │      for each light in TileLightList:               │    │
│     │          Color += LocalLighting(GBuffer, light);    │    │
│     │                                                     │    │
│     │      // IBL                                         │    │
│     │      Color += IBLLighting(GBuffer);                 │    │
│     │                                                     │    │
│     │      Output = Color;                                │    │
│     └─────────────────────────────────────────────────────┘    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Lighting 셰이더

```hlsl
// Mobile Deferred Lighting Shader
void MobileDeferredLightingPS(
    float4 Position : SV_Position,
    out float4 OutColor : SV_Target0)
{
    // G-Buffer 로드 (Subpass Input)
    float4 GBuffer0 = subpassLoad(GBufferRT0);
    float4 GBuffer1 = subpassLoad(GBufferRT1);
    float Depth = subpassLoad(DepthBuffer).r;

    // G-Buffer 디코딩
    float3 BaseColor = GBuffer0.rgb;
    float Metallic = GBuffer0.a;
    float3 WorldNormal = DecodeNormal(GBuffer1.rg);
    float Roughness = GBuffer1.b;

    // World Position 재구성
    float3 WorldPosition = ReconstructWorldPosition(Position.xy, Depth);

    // Lighting 계산
    float3 Color = 0;

    // Directional Light + Shadow
    Color += CalculateDirectionalLight(
        BaseColor, WorldNormal, Roughness, Metallic,
        DirectionalLightDirection, DirectionalLightColor,
        SampleCSM(WorldPosition)
    );

    // Local Lights
    uint TileIndex = GetTileIndex(Position.xy);
    uint LightCount = TileLightCounts[TileIndex];
    uint LightOffset = TileLightOffsets[TileIndex];

    for (uint i = 0; i < LightCount; i++)
    {
        uint LightIndex = TileLightIndices[LightOffset + i];
        FLocalLight Light = LocalLights[LightIndex];

        Color += CalculateLocalLight(
            BaseColor, WorldNormal, Roughness, Metallic,
            WorldPosition, Light
        );
    }

    // IBL
    Color += CalculateIBL(BaseColor, WorldNormal, Roughness, Metallic);

    OutColor = float4(Color, 1.0);
}
```

---

## 활성화 및 설정

### 콘솔 변수

```cpp
// Deferred 활성화
r.Mobile.ShadingPath=1

// 관련 설정
r.Mobile.UseHWsRGBEncoding=1    // sRGB 하드웨어 인코딩
r.Mobile.HDR32bppMode=0         // HDR 모드 (0: FP16, 1: Mosaic)
r.Mobile.DeferredShadingQuality=1  // 품질 레벨
```

### Project Settings

```
Mobile Shading Path: Mobile Deferred
Mobile HDR: Enabled
```

---

## 제한사항

```
┌─────────────────────────────────────────────────────────────────┐
│                    Mobile Deferred 제한사항                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. MSAA 미지원                                                 │
│     • TAA 사용 권장                                            │
│     • FXAA 대안 가능                                           │
│                                                                 │
│  2. 투명 오브젝트                                               │
│     • Forward Pass로 별도 처리                                 │
│     • Deferred 이점 없음                                       │
│                                                                 │
│  3. 디바이스 요구사항                                           │
│     • Vulkan 또는 Metal 지원 필요                              │
│     • Subpass 지원 필요                                        │
│     • 구형 디바이스 미지원                                     │
│                                                                 │
│  4. G-Buffer 대역폭                                             │
│     • Subpass 미지원 시 Forward보다 비효율적                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Forward vs Deferred 성능 비교

```
┌─────────────────────────────────────────────────────────────────┐
│                    성능 비교 (예시)                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  광원 수에 따른 프레임 타임 (ms):                               │
│                                                                 │
│  광원   │ Forward │ Deferred │                                 │
│  ───────┼─────────┼──────────│                                 │
│    4    │   8.0   │   9.5    │ Forward 유리                    │
│    8    │  12.0   │  10.5    │ Deferred 유리                   │
│   16    │  20.0   │  11.5    │ Deferred 크게 유리              │
│   32    │  36.0   │  13.0    │ Deferred 필수                   │
│                                                                 │
│  결론: 광원 8개 이상에서 Deferred 권장                          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 다음 단계

[모바일 최적화](05-mobile-optimization.md)에서 TBDR 최적화와 셰이더 최적화를 알아봅니다.
