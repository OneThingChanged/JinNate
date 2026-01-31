# Chapter 04: 디퍼드 렌더링 파이프라인

> 원문: https://www.cnblogs.com/timlly/p/14732412.html
> 시리즈: 剖析虚幻渲染体系 (Unreal 렌더링 시스템 분석)

---

## 목차

1. [디퍼드 렌더링 개요](#1-디퍼드-렌더링-개요)
2. [G-Buffer 구조](#2-g-buffer-구조)
3. [렌더링 파이프라인 순서](#3-렌더링-파이프라인-순서)
4. [Forward vs Deferred 비교](#4-forward-vs-deferred-비교)
5. [디퍼드 렌더링 변형](#5-디퍼드-렌더링-변형)
6. [UE 핵심 클래스](#6-ue-핵심-클래스)
7. [스크린 스페이스 기법](#7-스크린-스페이스-기법)
8. [UE 프레임 분석](#8-ue-프레임-분석)

---

## 1. 디퍼드 렌더링 개요 {#1-디퍼드-렌더링-개요}

### 핵심 개념

![디퍼드 렌더링 개요](./images/ch04/1617944-20210505184316256-1193511203.png)
*디퍼드 렌더링의 두 패스: 1) Geometry Pass - 씬 오브젝트를 GBuffer에 래스터화, 2) Lighting Pass - GBuffer의 기하 정보로 픽셀별 라이팅 계산*

디퍼드 렌더링은 두 개의 주요 패스로 구성됩니다:

| 패스 | 역할 |
|------|------|
| **Geometry Pass (Base Pass)** | 씬 오브젝트 정보를 GBuffer에 기록 |
| **Lighting Pass** | GBuffer 데이터로 라이팅 계산 |

### G-Buffer 시각화

![G-Buffer 내용](./images/ch04/1617944-20210505184337183-1419009066.png)
*G-Buffer 구성: 좌상-위치, 우상-노말, 좌하-베이스 컬러, 우하-스페큘러*

---

## 2. G-Buffer 구조 {#2-g-buffer-구조}

### 2.1 저장 데이터

G-Buffer는 Base Pass에서 기록되는 기하학적 데이터를 저장합니다:

| 채널 | 내용 | 설명 |
|------|------|------|
| **Position/Depth** | 스크린 스페이스 뎁스 | 월드 위치 재구성용 |
| **Normal** | 표면 노말 벡터 | 라이팅 계산용 |
| **Base Color** | 디퓨즈/알베도 | 기본 색상 |
| **Material Params** | AO, Roughness, Metallic | 머티리얼 속성 |
| **Shading Model ID** | 4비트 식별자 | 최대 16개 셰이딩 모델 지원 |
| **Per-Object Data** | 커스텀 속성 | 머티리얼별 데이터 |

> "UE는 Shading Model ID를 저장하기 위해 4비트를 사용하여, 최대 16개의 다른 셰이딩 타입을 지원합니다."

### 2.2 라이트 버퍼

![라이트 버퍼](./images/ch04/1617944-20210505185610583-375513794.jpg)
*광원 버퍼에 저장되는 라이트 데이터와 레이아웃*

---

## 3. 렌더링 파이프라인 순서 {#3-렌더링-파이프라인-순서}

### 3.1 UpdateAllPrimitiveSceneInfos

CPU와 GPU 프리미티브 데이터 업데이트. GPU Scene의 경우 scatter-upload 버퍼를 통해 Texture2D 또는 StructuredBuffer로 전송.

**프리미티브당 데이터 (~576 bytes):**
- Transform 행렬
- Bounds
- Lighting 채널
- Custom 데이터

### 3.2 InitViews

| 작업 | 설명 |
|------|------|
| 가시성 계산 | 오클루전 컬링 |
| 뷰 프러스텀 설정 | 카메라 프러스텀 |
| TAA 지터 적용 | Temporal AA |
| 포워드 라이팅 리소스 | 초기화 |
| 볼류메트릭 포그 | 설정 |

### 3.3 PrePass (Depth-Only)

컬러 출력 없이 불투명 오브젝트의 뎁스만 렌더링.

**모드:**
- `Disabled` - 비활성화
- `Occlusion-only` - 오클루전만
- `Complete` - 전체 뎁스 (Hierarchical-Z 구축, Early-Z 최적화)

### 3.4 Base Pass

> "Geometry Pass는 라이팅 계산 없이 씬 오브젝트 정보를 GBuffer에 기록하여, 가려진 표면에 대한 중복 계산을 피합니다."

```cpp
for each opaque/masked object:
    SetUnlitMaterial()
    DrawToGBuffer()
```

**저장 데이터:**
1. Position (depth + screen UV로 재구성 가능)
2. Normals
3. Material parameters (diffuse, emissive, specular, AO)

### 3.5 Lighting Pass

핵심 디퍼드 셰이딩 계산. 스크린 스페이스 픽셀을 순회하며 GBuffer 샘플링:

```cpp
for each pixel in RenderTarget:
    pixelData = sample GBuffer at UV
    color = 0
    for each light:
        color += CalculateLighting(light, pixelData)
    WriteSceneColor(color)
```

**복잡도:** O(NumLights × ScreenWidth × ScreenHeight) - 지오메트리 수와 분리됨

### 3.6 Translucency

반투명 오브젝트는 별도의 포워드 패스로 렌더링. 디퍼드 렌더링은 머티리얼 블렌딩 요구사항으로 인해 반투명을 효율적으로 처리할 수 없음.

### 3.7 Post-Processing

- 스크린 스페이스 효과 (SSAO, SSR, SSGI)
- 톤 매핑, 블룸, 컬러 그레이딩
- TAA temporal resolve

---

## 4. Forward vs Deferred 비교 {#4-forward-vs-deferred-비교}

| 측면 | Deferred | Forward |
|------|----------|---------|
| **복잡도** | O(NumLights × PixelCount) | O(NumObjects × NumLights) |
| **라이트 지원** | 우수 (100+) | 제한적 (<10 실용적) |
| **MSAA** | 어려움; TAA 대안 | 네이티브 HW 지원 |
| **머티리얼 타입** | GBuffer 슬롯으로 제약 | 무제한 |
| **반투명** | 미지원 (포워드 패스 필요) | 네이티브 지원 |
| **메모리/대역폭** | 매우 높음 | 낮음 |
| **오버드로우 영향** | 최소 | 심각 |

---

## 5. 디퍼드 렌더링 변형 {#5-디퍼드-렌더링-변형}

### 5.1 Tiled Deferred Rendering (TBDR)

![TBDR 뎁스](./images/ch04/1617944-20210505184450431-1525923419.jpg)
*TBDR의 각 타일 내 뎁스 범위에 따른 다양한 Bounding Box*

![PowerVR TBDR](./images/ch04/1617944-20210505184505127-1940715490.jpg)
*PowerVR TBDR 아키텍처 - 클리핑 후 래스터화 전에 Tiling 단계 추가, On-Chip Depth/Color Buffer로 빠른 접근*

스크린을 타일로 분할하고, AABB 교차를 사용하여 타일별로 라이트를 컬링하여 픽셀당 라이트 반복을 줄임.

### 5.2 Clustered Deferred Rendering

![Clustered 개념](./images/ch04/1617944-20210505184543959-1768447878.jpg)
*Clustered Deferred의 핵심: 뎁스를 여러 조각으로 세분화하여 각 클러스터의 바운딩 박스를 더 정확히 계산*

![Explicit 분할](./images/ch04/1617944-20210505184554417-1311070443.jpg)
*Explicit 뎁스 분할로 더 정확한 바운딩 박스 위치 결정*

![비교](./images/ch04/1617944-20210505184605861-1136735194.jpg)
*빨간색: Tiled 분할, 녹색: Implicit 클러스터링, 파란색: Explicit 클러스터링 - Explicit이 가장 정밀한 바운딩 박스*

TBDR을 뎁스 슬라이싱으로 확장하여 3D 클러스터 생성.

> "타일 방식보다 더 정밀한 라이트 컬링으로, 뎁스 범위가 희소할 때의 비효율성을 방지합니다."

### 5.3 Visibility Buffer

![Visibility Buffer](./images/ch04/1617944-20210505184726143-882156015.jpg)
*GBuffer vs Visibility Buffer 렌더링 파이프라인 비교 - 후자는 삼각형+인스턴스 ID만 4bytes에 저장하여 VRAM 점유 대폭 감소*

GBuffer를 삼각형 ID + 인스턴스 ID (4 bytes)로 대체하고, 속성 보간을 셰이딩 패스로 지연.

**특징:**
- 대역폭 감소
- Bindless 텍스처 필요
- 픽셀당 머티리얼 페치 필요

### 5.4 Decoupled Deferred Shading

![Decoupled Shading](./images/ch04/1617944-20210505184643677-1430840819.jpg)
*좌: 시간에 따른 표면 점의 스크린 투영 변화, 우: memoization cache로 이전 셰이딩 결과 재사용*

![Decoupled 효과](./images/ch04/1617944-20210505184710085-994097301.jpg)
*위: 4x 슈퍼샘플링 DOF, 중: 픽셀당 셰이딩률(SSPP), 아래: 카메라 캡처 씬*

스토캐스틱 샘플 간 셰이딩 결과 재사용을 위한 메모이제이션 캐시 추가로 MSAA 지원 향상.

### 5.5 Fine Pruned Tiled Light Lists

![Light Pruning](./images/ch04/1617944-20210505184743826-1788055643.jpg)
*위: 대략적 컬링 결과, 아래: 정밀 컬링 결과 - 정밀 컬링으로 불필요한 라이트 대폭 제거*

### 5.6 Deferred Coarse Pixel Shading

![Coarse Shading](./images/ch04/1617944-20210505184818850-1769555354.jpg)
*Compute Shader 기반 렌더링 - ddx/ddy로 변화가 적은 픽셀을 찾아 셰이딩 주파수 감소*

![Coarse 결과](./images/ch04/1617944-20210505184847205-1236677959.jpg)
*Power Plant(좌)와 Sponza(우) 씬 렌더링*

![Coarse 성능](./images/ch04/1617944-20210505184859313-1717036908.jpg)
*Power Plant: 50-60% 절약, Sponza: 25-37% 절약*

### 5.7 Deferred Adaptive Compute Shading (DACS)

![DACS 레벨](./images/ch04/1617944-20210505184928373-1999627280.jpg)
*DACS의 5개 레벨과 보간 - 각 레벨의 새 픽셀(노란색)에 대해 local variance 추정으로 보간/직접 셰이딩 결정*

![DACS 품질](./images/ch04/1617944-20210505184946758-975511783.jpg)
*UE4 씬에서 DACS의 다양한 셰이딩률에서의 이미지 렌더링 지표*

![DACS 비교](./images/ch04/1617944-20210505185000426-491469970.jpg)
*Checkerboard 대비 DACS: 동일 시간에 RMSE 21.5%, 동일 품질에서 4.22배 빠름*

### 5.8 Deferred MSAA

![Deferred MSAA](./images/ch04/1617944-20210505185120010-1494148795.jpg)
*Geometry Pass에서 표준 GBuffer + 멀티샘플 픽셀용 확장 데이터 저장으로 MSAA 지원하면서 GBuffer 점유 감소*

---

## 6. UE 핵심 클래스 {#6-ue-핵심-클래스}

### 6.1 FSceneRenderer

렌더링 상태, 뷰, 하이레벨 파이프라인 조정을 관리하는 추상 부모 클래스.

### 6.2 FDeferredShadingSceneRenderer

PC/콘솔용 디퍼드 파이프라인을 처리하는 구체적 구현:

```cpp
class FDeferredShadingSceneRenderer : public FSceneRenderer
{
    void RenderPrePass();
    void RenderBasePass();
    void RenderLight();
    void RenderTiledDeferredLighting();
    void RenderTranslucency();
};
```

### 6.3 FGPUScene

scatter-upload 패턴으로 GPU 측 프리미티브 데이터 관리, 텍스처와 구조화 버퍼 저장 모두 지원.

### 6.4 FViewInfo

뷰별 데이터:
- 프러스텀
- 행렬
- 가시 프리미티브 리스트
- 스크린 퍼센티지

---

## 7. 스크린 스페이스 기법 {#7-스크린-스페이스-기법}

GBuffer 데이터를 필요로 하는 포스트 프로세스 효과:

| 기법 | 설명 |
|------|------|
| **SSAO** | 뎁스/노말을 사용한 로컬 섀도잉 |
| **SSR** | 뎁스 버퍼를 트레이싱하여 반사 |
| **SSGI** | 간접 라이팅 근사 |

이들은 디퍼드의 GBuffer가 있어야만 실용적이며, 포워드 렌더링에서는 사용 불가.

---

## 8. UE 프레임 분석 {#8-ue-프레임-분석}

### 8.1 GPU Visualizer

![GPU Visualizer](./images/ch04/1617944-20210505185140547-1216273573.jpg)
*콘솔 명령 `profilegpu` 실행 후 GPU Visualizer 창 - 매 프레임 렌더링 단계와 소요 시간 확인*

### 8.2 RenderDoc 캡처

![RenderDoc](./images/ch04/1617944-20210505185153758-185516829.jpg)
*RenderDoc으로 캡처한 UE의 한 프레임*

### 8.3 프레임 렌더링 단계

![프레임 단계 1](./images/ch04/1617944-20210505185242764-1968557601.jpg)

![프레임 단계 2](./images/ch04/1617944-20210505185315935-1204060267.jpg)

![프레임 단계 3](./images/ch04/1617944-20210505185326242-1305974724.jpg)

![프레임 단계 4](./images/ch04/1617944-20210505185343871-1695859747.jpg)

---

## 요약 다이어그램

```
┌────────────────────────────────────────────────────────────────────┐
│                 UE Deferred Rendering Pipeline                      │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│  1. UpdateAllPrimitiveSceneInfos                                   │
│     └─→ CPU/GPU 프리미티브 데이터 업데이트                          │
│                     │                                              │
│                     ▼                                              │
│  2. InitViews                                                      │
│     └─→ 가시성, 오클루전, 프러스텀 설정                             │
│                     │                                              │
│                     ▼                                              │
│  3. PrePass (Z-PrePass)                                            │
│     └─→ 뎁스만 렌더링, Early-Z 최적화                               │
│                     │                                              │
│                     ▼                                              │
│  4. Base Pass (Geometry Pass)                                      │
│     └─→ G-Buffer 생성 (Position, Normal, Color, Material)          │
│                     │                                              │
│  ┌──────────────────┼──────────────────┐                           │
│  │     G-Buffer     │                  │                           │
│  │  ┌─────┬─────┐   │                  │                           │
│  │  │ Pos │ Nor │   │                  │                           │
│  │  ├─────┼─────┤   │                  │                           │
│  │  │Color│Metal│   │                  │                           │
│  │  └─────┴─────┘   │                  │                           │
│  └──────────────────┼──────────────────┘                           │
│                     ▼                                              │
│  5. Lighting Pass                                                  │
│     └─→ G-Buffer 샘플링 + 라이트별 계산                             │
│                     │                                              │
│                     ▼                                              │
│  6. Translucency (Forward)                                         │
│     └─→ 반투명 오브젝트 별도 렌더링                                 │
│                     │                                              │
│                     ▼                                              │
│  7. Post-Processing                                                │
│     └─→ SSAO, SSR, Bloom, TAA, Tone Mapping                        │
│                     │                                              │
│                     ▼                                              │
│                Final Frame                                         │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

---

## 참고 자료

- 원문: https://www.cnblogs.com/timlly/p/14732412.html
- "Deferred Rendering" - NVIDIA GPU Gems
- "Tiled and Clustered Forward Shading" - AMD GPUOpen
- UE4 Source: Engine/Source/Runtime/Renderer/Private/DeferredShadingRenderer.cpp
