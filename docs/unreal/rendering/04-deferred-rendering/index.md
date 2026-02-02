# Chapter 04: 디퍼드 렌더링 파이프라인

> 원문: https://www.cnblogs.com/timlly/p/14732412.html
> 시리즈: 剖析虚幻渲染体系 (Unreal 렌더링 시스템 분석)

UE의 디퍼드 셰이딩 아키텍처와 G-Buffer 시스템을 분석합니다.

---

## 문서 구성

| 문서 | 주제 | 핵심 내용 |
|------|------|----------|
| [01. 디퍼드 렌더링 개요](01-deferred-overview.md) | 기본 개념 | 2-패스 구조, Forward vs Deferred |
| [02. G-Buffer 구조](02-gbuffer.md) | 데이터 저장 | MRT 레이아웃, 데이터 패킹 |
| [03. 렌더링 파이프라인](03-pipeline-stages.md) | 단계별 분석 | PrePass → BasePass → Lighting |
| [04. 디퍼드 변형](04-deferred-variants.md) | 고급 기법 | TBDR, Clustered, Visibility Buffer |
| [05. 프레임 분석](05-frame-analysis.md) | 실제 분석 | RenderDoc, GPU Visualizer |

---

## 핵심 개념 미리보기

### 디퍼드 렌더링 2-패스 구조

```
┌────────────────────────────────────────────────────────────────────┐
│                 UE Deferred Rendering Pipeline                      │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│  1. Base Pass (Geometry Pass)                                      │
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
│  2. Lighting Pass                                                  │
│     └─→ G-Buffer 샘플링 + 라이트별 계산                             │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

### Forward vs Deferred 비교

| 측면 | Deferred | Forward |
|------|----------|---------|
| **복잡도** | O(NumLights × PixelCount) | O(NumObjects × NumLights) |
| **라이트 지원** | 100+ | <10 실용적 |
| **MSAA** | TAA 대안 | 네이티브 HW |
| **반투명** | 미지원 (포워드 패스 필요) | 지원 |
| **메모리** | 높음 (G-Buffer) | 낮음 |

---

## 다음 챕터

이 챕터를 완료하면 [Ch.05 광원과 그림자](../05-light-and-shadow/index.md)로 진행하세요.

---

## 참고 자료

- [원문 시리즈 (중국어)](https://www.cnblogs.com/timlly/p/14732412.html)
- [NVIDIA GPU Gems - Deferred Rendering](https://developer.nvidia.com/gpugems/)
- [AMD GPUOpen](https://gpuopen.com/)
---

<div style="display: flex; justify-content: space-between; align-items: center; padding: 16px 0;">
  <a href="../03-rendering-mechanism/05-draw-commands-optimization/" style="text-decoration: none;">← 이전: Ch.03 05. 렌더링 메커니즘</a>
  <a href="01-deferred-overview/" style="text-decoration: none;">다음: 01. 디퍼드 렌더링 개요 →</a>
</div>
