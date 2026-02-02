# Chapter 03: 렌더링 메커니즘

> 원문: https://www.cnblogs.com/timlly/p/14588598.html
> 시리즈: 剖析虚幻渲染体系 (Unreal 렌더링 시스템 분석)

UE4.22+의 메시 드로잉 파이프라인과 FMeshDrawCommand 시스템을 분석합니다.

---

## 문서 구성

| 문서 | 주제 | 핵심 내용 |
|------|------|----------|
| [01. 핵심 클래스](01-core-classes.md) | 렌더링 클래스 | UPrimitiveComponent, FSceneProxy, FScene |
| [02. 파이프라인 진화](02-pipeline-evolution.md) | 아키텍처 변화 | DrawingPolicy → FMeshDrawCommand |
| [03. 가시성과 수집](03-scene-visibility.md) | 컬링 시스템 | 프러스텀 컬링, 오클루전 컬링 |
| [04. MeshBatch와 Processor](04-mesh-batch-processor.md) | 메시 처리 | FMeshBatch, FMeshPassProcessor |
| [05. DrawCommand와 최적화](05-draw-commands-optimization.md) | 명령 생성 | FMeshDrawCommand, 캐싱, 정렬 |

---

## 학습 로드맵

```
┌─────────────────────────────────────────────────────────────────┐
│                    Chapter 03 학습 경로                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────────┐                                           │
│  │ 01. 핵심 클래스   │ ─── 렌더링 데이터 표현                     │
│  └─────────┬────────┘                                           │
│            │                                                    │
│            ▼                                                    │
│  ┌──────────────────┐                                           │
│  │ 02. 파이프라인   │ ─── 왜 FMeshDrawCommand인가?               │
│  │     진화         │                                           │
│  └─────────┬────────┘                                           │
│            │                                                    │
│            ▼                                                    │
│  ┌──────────────────┐                                           │
│  │ 03. 가시성과     │ ─── 무엇을 그릴 것인가?                    │
│  │     수집         │                                           │
│  └─────────┬────────┘                                           │
│            │                                                    │
│            ▼                                                    │
│  ┌──────────────────┐                                           │
│  │ 04. MeshBatch와  │ ─── 어떻게 처리할 것인가?                  │
│  │     Processor    │                                           │
│  └─────────┬────────┘                                           │
│            │                                                    │
│            ▼                                                    │
│  ┌──────────────────┐                                           │
│  │ 05. DrawCommand  │ ─── 최종 GPU 명령 생성                     │
│  │     와 최적화    │                                           │
│  └──────────────────┘                                           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 핵심 개념 미리보기

### 메시 드로잉 파이프라인

```
┌────────────────────────────────────────────────────────────────────┐
│                    UE4 Mesh Drawing Pipeline                        │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│  UPrimitiveComponent                                               │
│        │                                                           │
│        ▼                                                           │
│  FPrimitiveSceneProxy                                              │
│        │                                                           │
│        │ GetDynamicMeshElements()                                  │
│        ▼                                                           │
│  ┌─────────────┐                                                   │
│  │  FMeshBatch │ ← 머티리얼, 버텍스 팩토리, LOD 정보               │
│  └─────────────┘                                                   │
│        │                                                           │
│        │ FMeshPassProcessor::AddMeshBatch()                        │
│        ▼                                                           │
│  ┌──────────────────┐                                              │
│  │ FMeshDrawCommand │ ← 셰이더 바인딩, PSO, 드로우 파라미터        │
│  └──────────────────┘                                              │
│        │                                                           │
│        │ 정렬 → 병합 → 제출                                        │
│        ▼                                                           │
│  ┌──────────────────┐                                              │
│  │   RHI Commands   │ ← 최종 GPU 명령                              │
│  └──────────────────┘                                              │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

### 핵심 클래스 관계

| 클래스 | 스레드 | 역할 |
|--------|--------|------|
| **UPrimitiveComponent** | Game | 게임 오브젝트의 렌더링 가능 컴포넌트 |
| **FPrimitiveSceneProxy** | Render | 컴포넌트의 렌더링 스레드 표현 |
| **FMeshBatch** | Render | 머티리얼/버텍스 팩토리 공유 메시 배치 |
| **FMeshDrawCommand** | Render | 단일 드로우 콜의 완전한 상태 |
| **FRHICommandList** | RHI | 실제 GPU 명령 |

### UE4.22+ 개선사항

| 기능 | 이전 | 이후 (4.22+) |
|------|------|-------------|
| **명령 캐싱** | 불가 | 정적 메시 캐싱 |
| **GPU Scene** | 없음 | GPU 측 프리미티브 데이터 |
| **동적 인스턴싱** | 제한적 | 자동 병합 |
| **병렬 명령 생성** | 제한적 | 완전 병렬 |

---

## 다음 챕터

이 챕터를 완료하면 [Ch.04 디퍼드 렌더링](../04-deferred-rendering/index.md)으로 진행하세요.

---

## 참고 자료

- [원문 시리즈 (중국어)](https://www.cnblogs.com/timlly/p/14588598.html)
- [UE4 Source: Engine/Source/Runtime/Renderer/](https://github.com/EpicGames/UnrealEngine)
- [Epic Games 기술 블로그](https://www.unrealengine.com/en-US/tech-blog)
---

<div style="display: flex; justify-content: space-between; align-items: center; padding: 16px 0;">
  <a href="../02-multithreading/05-engine-patterns-sync/" style="text-decoration: none;">← 이전: Ch.02 05. 멀티스레드 렌더링</a>
  <a href="01-core-classes/" style="text-decoration: none;">다음: 01. 핵심 클래스 →</a>
</div>
