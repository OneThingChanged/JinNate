# 언리얼 렌더링 시스템 분석

> 원문 시리즈: [剖析虚幻渲染体系](https://www.cnblogs.com/timlly/p/13512787.html)

Unreal Engine의 렌더링 아키텍처를 심층 분석하는 시리즈입니다.

---

## 목차

| 챕터 | 주제 | 설명 |
|------|------|------|
| [Ch.01](01-overview.md) | 개요 및 기초 | 엔진 역사, C++ 기초, 메모리 관리 |
| [Ch.02](02-multithreading.md) | 멀티스레드 렌더링 | Game/Render/RHI 스레드, Task Graph |
| [Ch.03](03-rendering-mechanism.md) | 렌더링 메커니즘 | FMeshBatch, FMeshDrawCommand, Mesh Pass |
| [Ch.04](04-deferred-rendering.md) | 디퍼드 렌더링 | G-Buffer, Lighting Pass, TBDR |
| [Ch.05](05-light-and-shadow.md) | 광원과 그림자 | Light Types, Shadow Mapping, BRDF |

---

## 참고 자료

- [원문 시리즈 (중국어)](https://www.cnblogs.com/timlly/p/13512787.html)
- [Unreal Engine 공식 문서](https://docs.unrealengine.com/)
