# 03. 렌더링 파이프라인 단계

> PrePass부터 Post-Processing까지

---

## 목차

1. [파이프라인 개요](#1-파이프라인-개요)
2. [PrePass (Z-PrePass)](#2-prepass-z-prepass)
3. [Base Pass](#3-base-pass)
4. [Lighting Pass](#4-lighting-pass)
5. [Translucency](#5-translucency)
6. [Post-Processing](#6-post-processing)

---

## 1. 파이프라인 개요 {#1-파이프라인-개요}

```
1. UpdateAllPrimitiveSceneInfos ─→ 프리미티브 데이터 업데이트
          │
          ▼
2. InitViews ─→ 가시성, 오클루전, 프러스텀 설정
          │
          ▼
3. PrePass ─→ 뎁스만 렌더링, Early-Z 최적화
          │
          ▼
4. Base Pass ─→ G-Buffer 생성
          │
          ▼
5. Lighting Pass ─→ G-Buffer 샘플링 + 라이팅
          │
          ▼
6. Translucency ─→ 반투명 오브젝트 (Forward)
          │
          ▼
7. Post-Processing ─→ SSAO, SSR, Bloom, TAA
```

---

## 2. PrePass (Z-PrePass) {#2-prepass-z-prepass}

### 2.1 목적

- **Early-Z 최적화**: 불필요한 픽셀 셰이딩 방지
- **HZB 생성**: Hierarchical-Z 오클루전 컬링용

### 2.2 모드

| 모드 | 설명 |
|------|------|
| **Disabled** | PrePass 비활성화 |
| **Occlusion-only** | 오클루더만 렌더링 |
| **Complete** | 모든 불투명 오브젝트 |

---

## 3. Base Pass {#3-base-pass}

### 3.1 G-Buffer 기록

```hlsl
// BasePassPixelShader.usf
void Main(
    in FBasePassInterpolants Interpolants,
    out float4 OutGBufferA : SV_Target0,
    out float4 OutGBufferB : SV_Target1,
    out float4 OutGBufferC : SV_Target2)
{
    // 머티리얼 속성 계산
    FMaterialPixelParameters MaterialParams = GetMaterialPixelParameters(...);
    FGBufferData GBuffer = (FGBufferData)0;

    // G-Buffer 채우기
    GBuffer.WorldNormal = MaterialParams.WorldNormal;
    GBuffer.BaseColor = GetMaterialBaseColor(MaterialParams);
    GBuffer.Metallic = GetMaterialMetallic(MaterialParams);
    GBuffer.Roughness = GetMaterialRoughness(MaterialParams);
    GBuffer.ShadingModelID = GetMaterialShadingModel(MaterialParams);

    // 인코딩 및 출력
    EncodeGBuffer(GBuffer, OutGBufferA, OutGBufferB, OutGBufferC);
}
```

---

## 4. Lighting Pass {#4-lighting-pass}

### 4.1 처리 흐름

```hlsl
// DeferredLightPixelShaders.usf
float4 DeferredLightPixelMain(float2 ScreenUV) : SV_Target0
{
    // G-Buffer 샘플링
    FGBufferData GBuffer = GetGBufferData(ScreenUV);

    // 월드 위치 복원
    float3 WorldPosition = ReconstructWorldPosition(ScreenUV, GBuffer.Depth);

    // 라이팅 계산
    float3 L = normalize(LightPosition - WorldPosition);
    float3 V = normalize(CameraPosition - WorldPosition);
    float3 N = GBuffer.WorldNormal;

    // BRDF
    float3 Lighting = 0;
    Lighting += CalculateDiffuse(GBuffer, L, N);
    Lighting += CalculateSpecular(GBuffer, L, V, N);

    // 감쇠
    float Attenuation = GetLightAttenuation(WorldPosition);

    return float4(Lighting * Attenuation * LightColor, 1);
}
```

---

## 5. Translucency {#5-translucency}

반투명 오브젝트는 별도의 Forward 패스로 렌더링:

- 알파 블렌딩 필요
- 정렬된 순서로 렌더링 (뒤→앞)
- G-Buffer 사용 불가

---

## 6. Post-Processing {#6-post-processing}

| 효과 | 설명 |
|------|------|
| **SSAO** | 뎁스/노말 기반 로컬 그림자 |
| **SSR** | 뎁스 버퍼 트레이싱 반사 |
| **Bloom** | 밝은 영역 글로우 |
| **TAA** | 시간적 안티앨리어싱 |
| **Tone Mapping** | HDR → LDR 변환 |

---

## 다음 문서

[04. 디퍼드 변형](04-deferred-variants.md)에서 TBDR, Clustered 등 고급 기법을 살펴봅니다.
---

<div style="display: flex; justify-content: space-between; align-items: center; padding: 16px 0;">
  <a href="../02-gbuffer/" style="text-decoration: none;">← 이전: 02. G-Buffer 구조</a>
  <a href="../04-deferred-variants/" style="text-decoration: none;">다음: 04. 디퍼드 렌더링 변형 →</a>
</div>
