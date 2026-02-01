# 언리얼 렌더링 시스템 분석

> 원문 시리즈: [剖析虚幻渲染体系](https://www.cnblogs.com/timlly/p/13512787.html)

Unreal Engine의 렌더링 아키텍처를 심층 분석하는 시리즈입니다.

---

## 목차

| 챕터 | 주제 | 문서 수 | 설명 |
|------|------|--------|------|
| [Ch.01](01-overview/index.md) | 개요 및 기초 | 7개 | 엔진 역사, C++ 기초, 메모리 관리 |
| [Ch.02](02-multithreading/index.md) | 멀티스레드 렌더링 | 5개 | Game/Render/RHI 스레드, Task Graph |
| [Ch.03](03-rendering-mechanism/index.md) | 렌더링 메커니즘 | 5개 | FMeshBatch, FMeshDrawCommand |
| [Ch.04](04-deferred-rendering/index.md) | 디퍼드 렌더링 | 5개 | G-Buffer, Lighting Pass, TBDR |
| [Ch.05](05-light-and-shadow/index.md) | 광원과 그림자 | 5개 | Light Types, Shadow Mapping, BRDF |
| [Ch.06](06-ue5-features/index.md) | UE5 신기능 | 5개 | Nanite, Lumen, VSM, TSR |

---

## 시리즈 개요

```
┌─────────────────────────────────────────────────────────────────┐
│                    UE 렌더링 시스템 학습 경로                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────┐                                               │
│  │ Ch.01 개요   │ ─── 엔진 역사, C++ 기초, 메모리, 좌표계        │
│  └──────┬───────┘                                               │
│         │                                                       │
│         ▼                                                       │
│  ┌──────────────┐                                               │
│  │ Ch.02 멀티   │ ─── Task Graph, 3-스레드 모델                  │
│  │ 스레딩       │                                               │
│  └──────┬───────┘                                               │
│         │                                                       │
│         ▼                                                       │
│  ┌──────────────┐                                               │
│  │ Ch.03 렌더링 │ ─── FMeshBatch, FMeshDrawCommand               │
│  │ 메커니즘     │                                               │
│  └──────┬───────┘                                               │
│         │                                                       │
│         ▼                                                       │
│  ┌──────────────┐                                               │
│  │ Ch.04 디퍼드 │ ─── G-Buffer, Lighting Pass                   │
│  └──────┬───────┘                                               │
│         │                                                       │
│         ▼                                                       │
│  ┌──────────────┐                                               │
│  │ Ch.05 광원   │ ─── BRDF, Shadow Mapping                      │
│  │ 과 그림자    │                                               │
│  └──────┬───────┘                                               │
│         │                                                       │
│         ▼                                                       │
│  ┌──────────────┐                                               │
│  │ Ch.06 UE5   │ ─── Nanite, Lumen, VSM, TSR                   │
│  │ 신기능       │                                               │
│  └──────────────┘                                               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 전체 문서 수

- **Ch.01**: 7개 문서 (엔진 역사, 렌더링 개요, C++, 수학, 좌표계, 메모리, 오브젝트)
- **Ch.02**: 5개 문서 (멀티스레딩 기초, 인프라, API, UE 스레드, 패턴)
- **Ch.03**: 5개 문서 (핵심 클래스, 파이프라인, 가시성, MeshBatch, DrawCommand)
- **Ch.04**: 5개 문서 (개요, G-Buffer, 파이프라인, 변형, 분석)
- **Ch.05**: 5개 문서 (셰이더, BasePass, 광원, LightingPass, 그림자)
- **Ch.06**: 5개 문서 (UE5 개요, Nanite, Lumen, VSM, 기타)

**총 32개 세부 문서**

---

## 참고 자료

- [원문 시리즈 (중국어)](https://www.cnblogs.com/timlly/p/13512787.html)
- [Unreal Engine 공식 문서](https://docs.unrealengine.com/)
