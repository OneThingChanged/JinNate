# 02. G-Buffer 구조

> G-Buffer 레이아웃과 데이터 패킹

---

## 목차

1. [G-Buffer 개요](#1-g-buffer-개요)
2. [UE G-Buffer 레이아웃](#2-ue-g-buffer-레이아웃)
3. [데이터 패킹 기법](#3-데이터-패킹-기법)
4. [셰이딩 모델 ID](#4-셰이딩-모델-id)

---

## 1. G-Buffer 개요 {#1-g-buffer-개요}

### 1.1 시각화

![G-Buffer 내용](../images/ch04/1617944-20210505184337183-1419009066.png)
*G-Buffer 구성: 좌상-위치, 우상-노말, 좌하-베이스 컬러, 우하-스페큘러*

### 1.2 저장 데이터

| 데이터 | 용도 |
|--------|------|
| **Position/Depth** | 월드 위치 재구성 |
| **Normal** | 라이팅 계산 |
| **Base Color** | 디퓨즈/알베도 |
| **Metallic/Specular** | 머티리얼 속성 |
| **Roughness** | 스페큘러 분산 |
| **AO** | 앰비언트 오클루전 |
| **Shading Model ID** | 16가지 셰이딩 모델 구분 |

---

## 2. UE G-Buffer 레이아웃 {#2-ue-g-buffer-레이아웃}

### 2.1 MRT 구성

```cpp
// UE G-Buffer 레이아웃
GBufferA: RGBA8
  - RGB: World Normal (팔면체 인코딩)
  - A: Per-Object Data

GBufferB: RGBA8
  - R: Metallic
  - G: Specular
  - B: Roughness
  - A: Shading Model ID (4비트) + Selective Output Mask (4비트)

GBufferC: RGBA8
  - RGB: Base Color
  - A: AO (또는 머티리얼별 데이터)

GBufferD: (선택적) RGBA8
  - 커스텀 데이터 (서브서피스 등)

SceneDepth: D24S8 또는 D32F
  - 뎁스 값
```

### 2.2 메모리 예산

| 해상도 | G-Buffer 크기 (3 MRT) |
|--------|----------------------|
| 1080p | ~24 MB |
| 1440p | ~43 MB |
| 4K | ~95 MB |

---

## 3. 데이터 패킹 기법 {#3-데이터-패킹-기법}

### 3.1 노말 인코딩

```hlsl
// 팔면체 인코딩 (3D → 2D)
float2 EncodeNormal(float3 N)
{
    N.xy /= dot(1, abs(N));
    if (N.z <= 0)
        N.xy = (1 - abs(N.yx)) * sign(N.xy);
    return N.xy * 0.5 + 0.5;
}

float3 DecodeNormal(float2 Encoded)
{
    float2 N = Encoded * 2 - 1;
    float3 Normal = float3(N, 1 - dot(1, abs(N)));
    if (Normal.z < 0)
        Normal.xy = (1 - abs(Normal.yx)) * sign(Normal.xy);
    return normalize(Normal);
}
```

### 3.2 Metallic/Roughness 패킹

```hlsl
// 8비트에 저장
uint PackMaterialParams(float Metallic, float Roughness)
{
    return uint(Metallic * 255) | (uint(Roughness * 255) << 8);
}

void UnpackMaterialParams(uint Packed, out float Metallic, out float Roughness)
{
    Metallic = (Packed & 0xFF) / 255.0;
    Roughness = ((Packed >> 8) & 0xFF) / 255.0;
}
```

---

## 4. 셰이딩 모델 ID {#4-셰이딩-모델-id}

### 4.1 지원 셰이딩 모델

| ID | 셰이딩 모델 | 용도 |
|----|-------------|------|
| 0 | Unlit | 라이팅 없음 |
| 1 | Default Lit | 기본 PBR |
| 2 | Subsurface | 피부, 왁스 |
| 3 | Preintegrated Skin | 최적화된 피부 |
| 4 | Clear Coat | 자동차 페인트 |
| 5 | Subsurface Profile | 고급 SSS |
| 6 | Two Sided Foliage | 나뭇잎 |
| 7 | Hair | 머리카락 |
| 8 | Cloth | 천 |
| 9 | Eye | 눈 |

```cpp
// 4비트 = 최대 16개 셰이딩 모델
enum class EMaterialShadingModel : uint8
{
    MSM_Unlit = 0,
    MSM_DefaultLit = 1,
    MSM_Subsurface = 2,
    // ...
    MSM_NUM = 16
};
```

---

## 다음 문서

[03. 렌더링 파이프라인](03-pipeline-stages.md)에서 단계별 렌더링 과정을 살펴봅니다.
