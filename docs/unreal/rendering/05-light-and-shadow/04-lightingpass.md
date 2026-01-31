# LightingPass

> Chapter 05-4: 디퍼드 라이팅 계산과 BRDF

---

## 목차

1. [LightingPass 개요](#1-lightingpass-개요)
2. [라이트 컬링](#2-라이트-컬링)
3. [BRDF 계산](#3-brdf-계산)
4. [라이팅 셰이더](#4-라이팅-셰이더)
5. [다이나믹 라이팅](#5-다이나믹-라이팅)
6. [라이팅 최적화](#6-라이팅-최적화)

---

## 1. LightingPass 개요 {#1-lightingpass-개요}

LightingPass는 G-Buffer를 읽어 각 픽셀의 최종 조명을 계산합니다.

### 파이프라인 위치

```
PrePass → BasePass → Shadow Maps → ★ LightingPass ★ → Post Process
                                          │
                                          ├─ G-Buffer 읽기
                                          ├─ 라이트 컬링
                                          ├─ BRDF 계산
                                          └─ 그림자 적용
```

### 코드 흐름

```cpp
void FDeferredShadingSceneRenderer::RenderLights(FRHICommandListImmediate& RHICmdList)
{
    // 1. 라이트 수집 및 정렬
    GatherAndSortLights(Scene->Lights);

    // 2. 라이트 그리드 계산 (Clustered/Tiled)
    ComputeLightGrid(RHICmdList, Views);

    // 3. 각 라이트 타입별 렌더링
    for (const FLightSceneInfo* Light : SortedLights)
    {
        if (Light->Proxy->GetLightType() == LightType_Directional)
        {
            RenderDirectionalLight(RHICmdList, Light);
        }
        else if (Light->Proxy->GetLightType() == LightType_Point)
        {
            RenderPointLight(RHICmdList, Light);
        }
        else if (Light->Proxy->GetLightType() == LightType_Spot)
        {
            RenderSpotLight(RHICmdList, Light);
        }
        else if (Light->Proxy->GetLightType() == LightType_Rect)
        {
            RenderRectLight(RHICmdList, Light);
        }
    }
}
```

### FDirectLighting 결과 구조체

```cpp
struct FDirectLighting
{
    float3 Diffuse;        // 확산 조명
    float3 Specular;       // 정반사 조명
    float3 Transmission;   // 투과 조명 (SSS 등)
};
```

---

## 2. 라이트 컬링 {#2-라이트-컬링}

### 2.1 Tiled Light Culling

![Tiled Culling](./images/1617944-20210527125540123-1236750462.jpg)
*Tiled 기반 라이트 컬링*

스크린을 타일(예: 16x16)로 분할하여 각 타일에 영향을 미치는 라이트만 처리합니다.

```hlsl
// Tiled Light Culling Compute Shader
[numthreads(TILE_SIZE, TILE_SIZE, 1)]
void TileLightCullingCS(
    uint3 GroupId : SV_GroupID,
    uint3 GroupThreadId : SV_GroupThreadID,
    uint GroupIndex : SV_GroupIndex)
{
    // 1. 타일의 Min/Max 뎁스 계산
    float Depth = SceneDepthTexture[PixelPos].r;

    // Shared memory reduction
    GroupMemoryBarrierWithGroupSync();
    float MinDepth = WaveActiveMin(Depth);
    float MaxDepth = WaveActiveMax(Depth);

    // 2. 타일 프러스텀 계산
    Frustum TileFrustum = ComputeTileFrustum(GroupId.xy, MinDepth, MaxDepth);

    // 3. 각 라이트와 교차 테스트
    uint LightIndex = GroupIndex;
    while (LightIndex < NumLights)
    {
        FDeferredLightData Light = Lights[LightIndex];

        if (IntersectLightFrustum(Light, TileFrustum))
        {
            // 타일의 라이트 리스트에 추가
            uint Offset;
            InterlockedAdd(TileLightCount, 1, Offset);
            TileLightList[Offset] = LightIndex;
        }

        LightIndex += TILE_SIZE * TILE_SIZE;
    }
}
```

### 2.2 Clustered Light Culling

![Clustered](./images/1617944-20210527125604394-1116075554.jpg)
*Clustered 라이트 컬링*

Tiled + 뎁스 슬라이싱으로 3D 클러스터를 생성합니다.

```hlsl
// 클러스터 인덱스 계산
uint3 GetClusterIndex(float2 ScreenUV, float LinearDepth)
{
    uint2 TileXY = uint2(ScreenUV * ScreenSize / TILE_SIZE);

    // 로그 스케일 뎁스 슬라이스
    float LogDepth = log2(LinearDepth / NearPlane);
    uint SliceZ = uint(LogDepth * NumSlices / log2(FarPlane / NearPlane));

    return uint3(TileXY, SliceZ);
}

// 클러스터에서 라이트 리스트 가져오기
void GetClusterLights(uint3 ClusterIndex, out uint LightCount, out uint LightOffset)
{
    uint ClusterIdx = ClusterIndex.x +
                      ClusterIndex.y * NumTilesX +
                      ClusterIndex.z * NumTilesX * NumTilesY;

    LightCount = ClusterLightCounts[ClusterIdx];
    LightOffset = ClusterLightOffsets[ClusterIdx];
}
```

### Light Grid 시각화

```
┌─────────────────────────────────────────────────────────────────┐
│                    Clustered Light Grid                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   Screen Space (X, Y)              Depth Space (Z)              │
│   ┌───┬───┬───┬───┬───┐          ┌────────────────┐            │
│   │ 0 │ 1 │ 2 │ 3 │ 4 │          │ Near (Slice 0) │            │
│   ├───┼───┼───┼───┼───┤          ├────────────────┤            │
│   │ 5 │ 6 │ 7 │ 8 │ 9 │          │    Slice 1     │            │
│   ├───┼───┼───┼───┼───┤    ×     ├────────────────┤            │
│   │10 │11 │12 │13 │14 │          │    Slice 2     │            │
│   ├───┼───┼───┼───┼───┤          ├────────────────┤            │
│   │15 │16 │17 │18 │19 │          │ Far (Slice N)  │            │
│   └───┴───┴───┴───┴───┘          └────────────────┘            │
│                                                                  │
│   Cluster[x,y,z] = 타일에 영향을 미치는 라이트 리스트           │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. BRDF 계산 {#3-brdf-계산}

### 3.1 Cook-Torrance Specular BRDF

```hlsl
// 최종 스페큘러 BRDF
// f_r = D * G * F / (4 * NoL * NoV)
float3 SpecularBRDF(
    float Roughness,
    float3 F0,
    float NoH,
    float NoV,
    float NoL,
    float VoH)
{
    float a2 = Pow4(Roughness);  // Roughness^4

    // D: GGX Distribution
    float D = D_GGX(a2, NoH);

    // G: Smith Visibility (G / (4 * NoL * NoV))
    float Vis = Vis_SmithJointApprox(a2, NoV, NoL);

    // F: Fresnel (Schlick)
    float3 F = F_Schlick(F0, VoH);

    return D * Vis * F;
}
```

### 3.2 Diffuse BRDF

```hlsl
// Lambert Diffuse
float3 DiffuseBRDF_Lambert(float3 DiffuseColor)
{
    return DiffuseColor / PI;
}

// Disney Diffuse (Burley)
float3 DiffuseBRDF_Burley(
    float3 DiffuseColor,
    float Roughness,
    float NoV,
    float NoL,
    float VoH)
{
    float FD90 = 0.5 + 2 * VoH * VoH * Roughness;
    float FdV = 1 + (FD90 - 1) * Pow5(1 - NoV);
    float FdL = 1 + (FD90 - 1) * Pow5(1 - NoL);
    return DiffuseColor * (FdV * FdL / PI);
}
```

### 3.3 BRDF 다이어그램

![BRDF](./images/1617944-20210527125630692-2036345235.jpg)
*BRDF 컴포넌트*

```
┌─────────────────────────────────────────────────────────────────┐
│                    BRDF Components                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   Cook-Torrance Specular:    f_s = D * G * F / (4*NoL*NoV)      │
│                                                                  │
│   ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         │
│   │      D       │  │      G       │  │      F       │         │
│   │  Normal Dist │  │  Geometry    │  │   Fresnel    │         │
│   │  (GGX)       │  │  (Smith)     │  │  (Schlick)   │         │
│   └──────────────┘  └──────────────┘  └──────────────┘         │
│                                                                  │
│   Diffuse:                                                       │
│   ┌──────────────────────────────────────────┐                  │
│   │  Lambert:  f_d = c_diff / π              │                  │
│   │  Burley:   f_d = c_diff * Fd / π         │                  │
│   └──────────────────────────────────────────┘                  │
│                                                                  │
│   Final:  f = f_d * (1-F) + f_s                                 │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 4. 라이팅 셰이더 {#4-라이팅-셰이더}

### 4.1 디퍼드 라이트 픽셀 셰이더

```hlsl
// DeferredLightPixelShaders.usf

float4 DeferredLightPixelMain(
    float4 SVPos : SV_POSITION,
    float4 ScreenUV : TEXCOORD0) : SV_Target0
{
    // 1. G-Buffer 샘플링
    float2 UV = ScreenUV.xy / ScreenUV.w;
    FGBufferData GBuffer = GetGBufferData(UV);

    // 2. 월드 위치 재구성
    float SceneDepth = CalcSceneDepth(UV);
    float3 WorldPosition = ReconstructWorldPosition(UV, SceneDepth);

    // 3. 뷰 벡터 계산
    float3 V = normalize(View.WorldCameraOrigin - WorldPosition);
    float3 N = GBuffer.WorldNormal;

    // 4. 라이트 벡터 및 감쇠 계산
    float3 ToLight;
    float3 L;
    float Attenuation = GetLightAttenuation(WorldPosition, DeferredLightUniforms, ToLight, L);

    // 5. NoL 계산
    float NoL = saturate(dot(N, L));

    // 6. BRDF 계산
    BxDFContext Context;
    Init(Context, N, V, L);

    FAreaLight AreaLight;
    AreaLight.FalloffColor = DeferredLightUniforms.Color * Attenuation;

    FDirectLighting Lighting = IntegrateBxDF(
        GBuffer, N, V, L,
        Attenuation, NoL,
        AreaLight);

    // 7. 그림자 적용
    float SurfaceShadow = 1.0;
    float SubsurfaceShadow = 1.0;

    if (DeferredLightUniforms.bShadowed)
    {
        FShadowTerms ShadowTerms;
        GetShadowTerms(GBuffer, WorldPosition, DeferredLightUniforms, ShadowTerms);
        SurfaceShadow = ShadowTerms.SurfaceShadow;
        SubsurfaceShadow = ShadowTerms.TransmissionShadow;
    }

    // 8. 최종 조명 계산
    float3 FinalColor = (Lighting.Diffuse + Lighting.Specular) * SurfaceShadow
                      + Lighting.Transmission * SubsurfaceShadow;

    return float4(FinalColor, 0);
}
```

### 4.2 셰이딩 모델별 분기

```hlsl
FDirectLighting IntegrateBxDF(
    FGBufferData GBuffer,
    half3 N, half3 V, half3 L,
    float Falloff, float NoL,
    FAreaLight AreaLight)
{
    switch (GBuffer.ShadingModelID)
    {
        case SHADINGMODELID_DEFAULT_LIT:
            return DefaultLitBxDF(GBuffer, N, V, L, Falloff, NoL, AreaLight);

        case SHADINGMODELID_SUBSURFACE:
            return SubsurfaceBxDF(GBuffer, N, V, L, Falloff, NoL, AreaLight);

        case SHADINGMODELID_PREINTEGRATED_SKIN:
            return PreintegratedSkinBxDF(GBuffer, N, V, L, Falloff, NoL, AreaLight);

        case SHADINGMODELID_CLEAR_COAT:
            return ClearCoatBxDF(GBuffer, N, V, L, Falloff, NoL, AreaLight);

        case SHADINGMODELID_SUBSURFACE_PROFILE:
            return SubsurfaceProfileBxDF(GBuffer, N, V, L, Falloff, NoL, AreaLight);

        case SHADINGMODELID_TWOSIDED_FOLIAGE:
            return TwoSidedFoliageBxDF(GBuffer, N, V, L, Falloff, NoL, AreaLight);

        case SHADINGMODELID_HAIR:
            return HairBxDF(GBuffer, N, V, L, Falloff, NoL, AreaLight);

        case SHADINGMODELID_CLOTH:
            return ClothBxDF(GBuffer, N, V, L, Falloff, NoL, AreaLight);

        case SHADINGMODELID_EYE:
            return EyeBxDF(GBuffer, N, V, L, Falloff, NoL, AreaLight);

        default:
            return DefaultLitBxDF(GBuffer, N, V, L, Falloff, NoL, AreaLight);
    }
}
```

---

## 5. 다이나믹 라이팅 {#5-다이나믹-라이팅}

### 5.1 라이트별 지오메트리 렌더링

```cpp
// Point Light: 구체 지오메트리
void RenderPointLight(FRHICommandList& RHICmdList, const FLightSceneInfo* Light)
{
    // 라이트 반경에 맞는 구체 메시 렌더링
    float Radius = Light->Proxy->GetRadius();
    float3 Position = Light->Proxy->GetPosition();

    // Stencil을 사용해 라이트 볼륨 내부만 처리
    SetStencilForLightVolume(RHICmdList);

    DrawSphere(RHICmdList, Position, Radius);
}

// Spot Light: 원뿔 지오메트리
void RenderSpotLight(FRHICommandList& RHICmdList, const FLightSceneInfo* Light)
{
    float Radius = Light->Proxy->GetRadius();
    float ConeAngle = Light->Proxy->GetOuterConeAngle();

    DrawCone(RHICmdList, Position, Direction, Radius, ConeAngle);
}

// Directional Light: 풀스크린 쿼드
void RenderDirectionalLight(FRHICommandList& RHICmdList, const FLightSceneInfo* Light)
{
    DrawFullscreenQuad(RHICmdList);
}
```

### 5.2 라이트 렌더링 흐름

![Lighting Pass](./images/1617944-20210527125816032-546720973.jpg)
*UE 라이팅 패스*

```
RenderLights()
│
├─→ RenderDirectionalLight()
│   └─ 풀스크린 쿼드, CSM 그림자
│
├─→ RenderPointLight() (각 Point Light마다)
│   └─ 구체 지오메트리, 큐브맵 그림자
│
├─→ RenderSpotLight() (각 Spot Light마다)
│   └─ 원뿔 지오메트리, 2D 그림자
│
└─→ RenderRectLight() (각 Rect Light마다)
    └─ 사각형 지오메트리, 소프트 그림자
```

---

## 6. 라이팅 최적화 {#6-라이팅-최적화}

### 6.1 Early-Z와 Stencil 최적화

```cpp
// Light Volume Stencil
// 1단계: 라이트 볼륨 뒷면만 스텐실에 기록
SetDepthStencilState(DepthRead_StencilWrite_BackFace);
DrawLightVolume(BackFaces);

// 2단계: 라이트 볼륨 앞면 + 스텐실 테스트
SetDepthStencilState(DepthRead_StencilTest_FrontFace);
DrawLightVolume_WithShading(FrontFaces);  // 실제 라이팅 계산
```

### 6.2 라이트 정렬 및 배칭

```cpp
void GatherAndSortLights(TArray<FLightSceneInfo*>& Lights)
{
    // 타입별 정렬 (그림자 없는 라이트 먼저)
    Lights.Sort([](const FLightSceneInfo* A, const FLightSceneInfo* B)
    {
        // 1. 그림자 없는 라이트 우선
        if (A->bCastShadows != B->bCastShadows)
            return !A->bCastShadows;

        // 2. 같은 타입끼리
        if (A->LightType != B->LightType)
            return A->LightType < B->LightType;

        // 3. 거리순
        return A->DistanceToCamera < B->DistanceToCamera;
    });
}
```

### 6.3 라이트 컬링 통계

| 기법 | 장점 | 단점 |
|------|------|------|
| **No Culling** | 구현 간단 | O(픽셀 × 라이트) |
| **Tiled** | 2D 컬링, 빠름 | 뎁스 불연속 비효율 |
| **Clustered** | 3D 컬링, 정확 | 메모리 사용량 |
| **Forward+** | 투명 지원 | 추가 패스 필요 |

---

## 요약

```
┌─────────────────────────────────────────────────────────────────┐
│                    LightingPass Summary                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   Input                                                          │
│   ─────                                                          │
│   • G-Buffer (Normal, BaseColor, Roughness, Metallic, ...)      │
│   • Shadow Maps                                                  │
│   • Light Data (Position, Color, Radius, ...)                   │
│                                                                  │
│   Process                                                        │
│   ───────                                                        │
│   1. Light Culling (Tiled/Clustered)                            │
│   2. For each visible light:                                     │
│      - Sample G-Buffer                                           │
│      - Calculate BRDF (D * G * F)                               │
│      - Apply Shadow                                              │
│      - Accumulate Result                                         │
│                                                                  │
│   Output                                                         │
│   ──────                                                         │
│   • Final Lit Color = Σ(Diffuse + Specular) * Shadow            │
│                                                                  │
│   BRDF: f = (1-F)·Diffuse/π + D·G·F/(4·NoL·NoV)                │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 참고 자료

- 원문: https://www.cnblogs.com/timlly/p/14817455.html
- "Moving Frostbite to PBR" - Lagarde, de Rousiers
- "Real Shading in Unreal Engine 4" - Karis, Epic Games
- UE Source: `Engine/Shaders/Private/DeferredLightPixelShaders.usf`
