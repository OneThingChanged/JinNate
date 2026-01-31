# Unreal Engine 렌더링 시스템 분석

![UE5 Banner](https://img2020.cnblogs.com/blog/1617944/202010/1617944-20201026110532663-1976776185.png)

---

## 소개

이 문서는 **Unreal Engine의 렌더링 시스템**을 심층 분석한 기술 문서입니다.

원문 시리즈 [剖析虚幻渲染体系](https://www.cnblogs.com/timlly/p/13512787.html)를 기반으로 핵심 내용을 정리하였습니다.

---

## 문서 구성

### 기초

| 챕터 | 주제 | 핵심 내용 |
|------|------|-----------|
| [Ch.01](UE_Rendering_01_Overview.md) | **개요 및 기초** | 엔진 역사, C++ 기능, 메모리 관리, GC |
| [Ch.02](UE_Rendering_02_MultiThreading.md) | **멀티스레드 렌더링** | 태스크 그래프, D3D12/Vulkan/Metal |

### 렌더링 파이프라인

| 챕터 | 주제 | 핵심 내용 |
|------|------|-----------|
| [Ch.03](UE_Rendering_03_RenderingMechanism.md) | **렌더링 메커니즘** | FMeshBatch, FMeshDrawCommand, 파이프라인 |
| [Ch.04](UE_Rendering_04_DeferredRendering.md) | **디퍼드 렌더링** | G-Buffer, Lighting Pass, TBDR, Clustered |
| [Ch.05](UE_Rendering_05_LightAndShadow.md) | **광원과 그림자** | CSM, PCF, PCSS, BRDF, 라이트 컬링 |

---

## 빠른 참조

### UE 렌더링 파이프라인 개요

```
┌─────────────────────────────────────────────────────────────┐
│                    UE Rendering Pipeline                     │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   Game Thread          Render Thread           GPU          │
│   ───────────          ─────────────           ───          │
│                                                             │
│   UPrimitiveComponent                                       │
│         │                                                   │
│         ▼                                                   │
│   FPrimitiveSceneProxy ──→ FMeshBatch                      │
│                                   │                         │
│                                   ▼                         │
│                            FMeshDrawCommand                 │
│                                   │                         │
│                                   ▼                         │
│                              RHI Commands ──→ GPU Execute   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 핵심 클래스

| 클래스 | 역할 |
|--------|------|
| `UPrimitiveComponent` | CPU 측 렌더링 가능 객체 |
| `FPrimitiveSceneProxy` | 렌더링 스레드 미러 |
| `FScene` | 월드의 렌더러 표현 |
| `FMeshBatch` | 메시 요소 컬렉션 |
| `FMeshDrawCommand` | 드로우 콜 상태 설명 |
| `FDeferredShadingSceneRenderer` | 디퍼드 렌더링 구현 |

---

## 기술 스택

<div class="grid cards" markdown>

-   :material-unreal:{ .lg .middle } **Unreal Engine**

    ---

    게임 및 실시간 렌더링을 위한 상용 엔진

-   :material-language-cpp:{ .lg .middle } **C++**

    ---

    Lambda, 스마트 포인터, 템플릿 활용

-   :material-gpu:{ .lg .middle } **Graphics API**

    ---

    DirectX 12, Vulkan, Metal 지원

-   :material-shader:{ .lg .middle } **HLSL/GLSL**

    ---

    셰이더 프로그래밍

</div>

---

## 참고 자료

- [원문 시리즈 (중국어)](https://www.cnblogs.com/timlly/p/13512787.html)
- [Unreal Engine 공식 문서](https://docs.unrealengine.com/)
- [Epic Games GitHub](https://github.com/EpicGames/UnrealEngine)

---

!!! tip "문서 활용"

    각 챕터는 독립적으로 읽을 수 있지만, 순서대로 읽으면 UE 렌더링 시스템을
    체계적으로 이해할 수 있습니다.
