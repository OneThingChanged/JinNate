# Chapter 01: 개요 및 기초

> 원문: https://www.cnblogs.com/timlly/p/13877623.html
> 시리즈: 剖析虚幻渲染体系 (Unreal 렌더링 시스템 분석)

Unreal Engine의 역사부터 핵심 기초 개념까지 다루는 입문 챕터입니다.

---

## 문서 구성

이 챕터는 다음 세부 문서들로 구성됩니다:

| 문서 | 주제 | 핵심 내용 |
|------|------|----------|
| [01. 엔진 발전 역사](01-engine-history.md) | UE1~UE5 역사 | 각 버전별 기술 혁신, 주요 게임 |
| [02. 렌더링 체계 개요](02-rendering-overview.md) | 렌더링 철학 | 기술 발전, Frame Graph, 레이트레이싱 |
| [03. C++ 언어 기능](03-cpp-fundamentals.md) | UE C++ 기초 | 람다, 스마트 포인터, 델리게이트, 네이밍 |
| [04. 컨테이너 및 수학](04-containers-math.md) | 핵심 라이브러리 | TArray, TMap, 벡터/행렬, 압축 |
| [05. 좌표 공간 시스템](05-coordinate-system.md) | 8가지 좌표 공간 | Tangent→Viewport 변환 체인 |
| [06. 메모리 관리](06-memory-management.md) | 메모리 시스템 | 할당자, GC, 메모리 배리어 |
| [07. 오브젝트 및 시작](07-object-hierarchy.md) | 엔진 구조 | UObject 계층, 시작 파이프라인 |

---

## 학습 로드맵

```
┌─────────────────────────────────────────────────────────────────┐
│                    Chapter 01 학습 경로                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────┐                                               │
│  │ 01. 엔진 역사 │ ─── UE의 탄생과 발전 이해                      │
│  └──────┬───────┘                                               │
│         │                                                       │
│         ▼                                                       │
│  ┌──────────────┐                                               │
│  │ 02. 렌더링   │ ─── 렌더링 기술 발전 트렌드 파악                │
│  │    체계 개요 │                                               │
│  └──────┬───────┘                                               │
│         │                                                       │
│    ┌────┴────┐                                                  │
│    ▼         ▼                                                  │
│ ┌──────┐  ┌──────┐                                              │
│ │03.C++│  │04.수학│ ─── 코드 작성에 필요한 기초                   │
│ └──┬───┘  └──┬───┘                                              │
│    └────┬────┘                                                  │
│         ▼                                                       │
│  ┌──────────────┐                                               │
│  │ 05. 좌표계   │ ─── 3D 그래픽스 핵심 개념                       │
│  └──────┬───────┘                                               │
│         │                                                       │
│         ▼                                                       │
│  ┌──────────────┐                                               │
│  │ 06. 메모리   │ ─── 성능 최적화의 기반                          │
│  └──────┬───────┘                                               │
│         │                                                       │
│         ▼                                                       │
│  ┌──────────────┐                                               │
│  │ 07. 오브젝트 │ ─── 엔진 아키텍처 이해                          │
│  └──────────────┘                                               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 핵심 개념 미리보기

### 엔진 발전

| 버전 | 연도 | 핵심 기술 |
|------|------|----------|
| UE1 | 1995 | 소프트 렌더러, 씬 에디터 |
| UE2 | 1998 | Karma 물리, 파티클 시스템 |
| UE3 | 2004 | 프로그래머블 파이프라인, HDR |
| UE4 | 2008 | PBR, 디퍼드 렌더링, Blueprint |
| UE5 | 2021 | Nanite, Lumen |

### 핵심 좌표 공간

```
Tangent → Local → World → View → Clip → Screen → Viewport
   │         │        │       │       │        │
   └─────────┴────────┴───────┴───────┴────────┴─→ 변환 체인
```

### 메모리 할당자 계층

```
FMalloc (추상)
├─ FMallocAnsi     (stdlib)
├─ FMallocBinned   (풀 기반, 기본값)
├─ FMallocBinned2  (단순화)
├─ FMallocBinned3  (64비트 최적화)
└─ FMallocTBB      (Intel TBB)
```

---

## 다음 챕터

이 챕터를 완료하면 [Ch.02 멀티스레드 렌더링](../02-multithreading/index.md)으로 진행하세요.

---

## 참고 자료

- [원문 시리즈 (중국어)](https://www.cnblogs.com/timlly/p/13877623.html)
- [Unreal Engine 공식 문서](https://docs.unrealengine.com/)
- [Epic Games GitHub](https://github.com/EpicGames/UnrealEngine)
---

<div style="display: flex; justify-content: space-between; align-items: center; padding: 16px 0;">
  <a href="../" style="text-decoration: none;">← 이전: 렌더링 시리즈</a>
  <a href="01-engine-history/" style="text-decoration: none;">다음: 01. 엔진 발전 역사 →</a>
</div>
