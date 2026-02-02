# Chapter 05: 광원과 그림자

> 원문: https://www.cnblogs.com/timlly/p/14817455.html
> 시리즈: 剖析虚幻渲染体系 (Unreal 렌더링 시스템 분석)

---

## 개요

이 챕터에서는 UE의 광원 시스템과 그림자 렌더링을 심층 분석합니다. 600개 이상의 셰이더 파일로 구성된 복잡한 시스템을 계층별로 살펴봅니다.

![광원 타입](../images/ch05/1617944-20210527124933083-399182186.jpg)
*UE의 다양한 광원과 그림자 효과*

---

## 문서 구성

| 문서 | 주제 | 핵심 내용 |
|------|------|-----------|
| [01. 셰이더 시스템](01-shader-system.md) | Shader Architecture | 600+ 파일, 3-Tier 구조, 14개 핵심 모듈 |
| [02. BasePass](02-basepass.md) | G-Buffer 생성 | 버텍스/픽셀 셰이더, 머티리얼 처리 |
| [03. 광원](03-light-sources.md) | Light Types | Directional, Point, Spot, Rect, Area Light |
| [04. LightingPass](04-lightingpass.md) | 디퍼드 라이팅 | 라이트 컬링, BRDF, 라이팅 계산 |
| [05. 그림자](05-shadows.md) | Shadow System | CSM, PCF, PCSS, VSM, ESM |

---

## 렌더링 파이프라인 개요

```
┌─────────────────────────────────────────────────────────────────┐
│              UE Deferred Rendering Pipeline                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐ │
│   │ PrePass  │ -> │ BasePass │ -> │ Shadow   │ -> │ Lighting │ │
│   │ (Depth)  │    │ (GBuffer)│    │ Maps     │    │ Pass     │ │
│   └──────────┘    └──────────┘    └──────────┘    └──────────┘ │
│        │               │               │               │        │
│        ▼               ▼               ▼               ▼        │
│   Depth Buffer    GBuffer RT0-4   Shadow Atlas   Final Color   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 핵심 개념 요약

### 셰이더 계층 구조

```
Tier 1 (기초)     Tier 2 (중간)         Tier 3 (구현)
─────────────────────────────────────────────────────────
Platform.ush  ->  BasePassCommon.ush  ->  BasePassVS.usf
Common.ush    ->  ShadingModels.ush   ->  BasePassPS.usf
BRDF.ush      ->  DeferredLighting    ->  DeferredLight.usf
                  Common.ush
```

### 광원 타입

| 타입 | 특징 | 사용 사례 |
|------|------|-----------|
| **Directional** | 무한 거리, 평행 광선 | 태양광 |
| **Point** | 반경 기반 감쇠 | 전구, 횃불 |
| **Spot** | 원뿔형 광원 | 손전등, 무대 조명 |
| **Rect** | 사각형 영역 | 창문, TV 화면 |
| **Area** | 구체/선 지오메트리 | 소프트 라이팅 |

### 그림자 기법

| 기법 | 특징 | 비용 |
|------|------|------|
| **Basic Shadow Map** | 하드 섀도우 | 낮음 |
| **PCF** | 소프트 섀도우 | 중간 |
| **PCSS** | 거리 기반 소프트니스 | 높음 |
| **CSM** | 거리별 해상도 분배 | 중간 |
| **VSM/ESM** | 필터링 가능 | 중간 |

---

## 다이어그램: 전체 시스템

```
┌────────────────────────────────────────────────────────────────────┐
│                 UE Light & Shadow System                           │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │                    Light Types                               │  │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐           │  │
│  │  │Direction│ │  Point  │ │  Spot   │ │  Rect   │           │  │
│  │  └─────────┘ └─────────┘ └─────────┘ └─────────┘           │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                              │                                     │
│                              ▼                                     │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │                 Light Culling                                │  │
│  │         Tiled / Clustered Light Assignment                   │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                              │                                     │
│          ┌───────────────────┼───────────────────┐                │
│          ▼                   ▼                   ▼                │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐        │
│  │ Shadow Maps  │    │    BRDF      │    │   G-Buffer   │        │
│  │  ├─ CSM      │    │  ├─ D_GGX    │    │   Sampling   │        │
│  │  ├─ PCF      │    │  ├─ F_Schlick│    │              │        │
│  │  ├─ PCSS     │    │  └─ Vis_Smith│    │              │        │
│  │  └─ VSM/ESM  │    │              │    │              │        │
│  └──────────────┘    └──────────────┘    └──────────────┘        │
│          │                   │                   │                │
│          └───────────────────┼───────────────────┘                │
│                              ▼                                     │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │                  Final Lighting                              │  │
│  │     Color = Diffuse * Shadow + Specular * Shadow            │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

---

## 참고 자료

- 원문: https://www.cnblogs.com/timlly/p/14817455.html
- "Real-Time Shadows" - Eisemann et al.
- "Physically Based Rendering" - Pharr, Jakob, Humphreys
- UE Source: `Engine/Shaders/Private/`
---

<div style="display: flex; justify-content: space-between; align-items: center; padding: 16px 0;">
  <a href="../04-deferred-rendering/05-frame-analysis/" style="text-decoration: none;">← 이전: Ch.04 05. 디퍼드 렌더링</a>
  <a href="01-shader-system/" style="text-decoration: none;">다음: 01. 셰이더 시스템 아키텍처 →</a>
</div>
