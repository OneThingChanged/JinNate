# Ch.11 RDG (Render Dependency Graph)

UE4.22에서 도입된 렌더링 서브시스템으로, 유향 비순환 그래프(DAG) 기반의 스케줄링 시스템입니다.

---

## 개요

**RDG (Rendering Dependency Graph)**는 전체 프레임 렌더링 파이프라인의 최적화를 위한 시스템입니다. 현대 그래픽 API(DirectX 12, Vulkan, Metal 2)의 기능을 활용하여 자동 비동기 컴퓨트 스케줄링, 효율적 메모리 관리, 배리어 관리 최적화를 제공합니다.

```
┌─────────────────────────────────────────────────────────────────┐
│                    RDG 시스템 구조                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐         │
│  │  Pass 수집   │ → │  Pass 컴파일 │ → │  Pass 실행   │         │
│  │   Phase     │    │    Phase    │    │    Phase    │         │
│  └─────────────┘    └─────────────┘    └─────────────┘         │
│        │                  │                  │                  │
│        ▼                  ▼                  ▼                  │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐         │
│  │ AddPass()   │    │ 의존성 분석  │    │ Lambda 실행  │         │
│  │ 리소스 생성  │    │ 배리어 처리  │    │ 리소스 해제  │         │
│  └─────────────┘    └─────────────┘    └─────────────┘         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 핵심 장점

| 기능 | 설명 |
|------|------|
| **자동 생명주기 관리** | 리소스가 사용될 때 할당되고 참조가 없으면 해제됨 |
| **메모리 최적화** | 서브리소스 앨리어싱과 풀링 메커니즘으로 단편화 감소 |
| **배리어 최적화** | 중복 전환 자동 제거, 배치 처리 |
| **Pass 컬링** | 출력에 영향 없는 Pass 제거 |
| **Pass 병합** | Begin/EndRenderPass 호출 감소 |

---

## 주요 클래스

```
┌─────────────────────────────────────────────────────────────────┐
│                    RDG 클래스 계층 구조                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  FRDGBuilder                                                    │
│  ├── CreateTexture() / CreateBuffer()                          │
│  ├── CreateSRV() / CreateUAV()                                 │
│  ├── RegisterExternalTexture() / RegisterExternalBuffer()      │
│  ├── AddPass()                                                 │
│  ├── QueueTextureExtraction() / QueueBufferExtraction()        │
│  └── Execute()                                                 │
│                                                                 │
│  FRDGResource (Base)                                           │
│  ├── FRDGTexture                                               │
│  │   ├── FRDGTextureDesc                                       │
│  │   └── FRDGPooledTexture                                     │
│  └── FRDGBuffer                                                │
│      ├── FRDGBufferDesc                                        │
│      └── FRDGPooledBuffer                                      │
│                                                                 │
│  FRDGPass                                                      │
│  ├── TRDGLambdaPass                                            │
│  └── FRDGSentinelPass                                          │
│                                                                 │
│  FRDGAllocator                                                 │
│  └── MemStack 기반 메모리 관리                                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 문서 구성

| 문서 | 내용 |
|------|------|
| [RDG 개요](01-rdg-overview.md) | RDG 소개, 배경, 현대 그래픽 API와의 관계 |
| [RDG 기초 타입](02-rdg-fundamentals.md) | 플래그, 리소스 타입, 메모리 할당자 |
| [RDG 메커니즘](03-rdg-mechanisms.md) | 의존성 관리, 컴파일/실행 과정 |
| [RDG 개발 가이드](04-rdg-development.md) | 실제 사용법, 코드 예제 |
| [RDG 디버깅](05-rdg-debugging.md) | 디버깅 방법, 즉시 실행 모드 |

---

## 참고 자료

- [원본 문서 (timlly)](https://www.cnblogs.com/timlly/p/15217090.html)
- [UE 공식 문서 - RDG](https://docs.unrealengine.com/5.0/en-US/render-dependency-graph-in-unreal-engine/)
