# Chapter 02: 멀티스레드 렌더링

> 원문: https://www.cnblogs.com/timlly/p/14327537.html
> 시리즈: 剖析虚幻渲染体系 (Unreal 렌더링 시스템 분석)

---

## 목차

1. [멀티스레딩 개요](#1-멀티스레딩-개요)
2. [병렬 처리 기초](#2-병렬-처리-기초)
3. [스레딩 인프라](#3-스레딩-인프라)
4. [태스크 그래프 시스템](#4-태스크-그래프-시스템)
5. [현대 그래픽 API 멀티스레딩](#5-현대-그래픽-api-멀티스레딩)
6. [UE 렌더링 스레드 아키텍처](#6-ue-렌더링-스레드-아키텍처)
7. [다른 엔진들의 패턴](#7-다른-엔진들의-패턴)
8. [동기화 프리미티브](#8-동기화-프리미티브)

---

## 1. 멀티스레딩 개요

### 멀티코어 시대

![Ryzen 3990X](./images/ch02/1617944-20210125205726496-824035894.png)
*AMD Ryzen 3990X 홍보 포스터 - 64코어 128스레드*

### 암달의 법칙 (Amdahl's Law)

![암달의 법칙](./images/ch02/1617944-20210125205854934-1159288776.png)
*암달의 법칙 - 병렬화 비율과 가속비 관계*

> 병렬화 가능한 작업 비율이 낮을수록 가속비 효과가 떨어집니다:
> - 병렬화 50%: 16코어에서 천장 도달
> - 병렬화 95%: 2048코어에서 천장 도달

---

## 2. 병렬 처리 기초

### 2.1 SMP (대칭적 다중 처리)

![SMP Windows](./images/ch02/1617944-20210125205921059-1248630297.png)
*Windows SMP에서 멀티코어 CPU 스레드 배치*

![스레드 생성](./images/ch02/1617944-20210125205931746-536130067.png)
*Windows 스레드 생성 및 초기화 과정*

### 2.2 동시성 vs 병렬성

![동시성과 병렬성](./images/ch02/1617944-20210125205945659-2118423516.png)
*위: 듀얼 코어의 동시 실행 (병렬) / 아래: 단일 코어의 멀티태스킹 (동시성)*

### 2.3 원자적 연산의 필요성

![Compiler Explorer](./images/ch02/1617944-20210125210006316-152371240.png)
*Compiler Explorer - C++ 코드가 여러 어셈블리 명령어로 컴파일됨 → atomic 연산 필요*

### 2.4 데이터 분할 전략

#### 선형 분할

![선형 분할](./images/ch02/1617944-20210125210040229-1901094181.png)
*연속 데이터를 균등 분할하여 여러 스레드에 분배*

#### 재귀적 분할

![재귀적 분할](./images/ch02/1617944-20210125210046729-1151631426.png)
*재귀적 데이터 분할 방식*

#### 태스크 분할

![태스크 분할](./images/ch02/1617944-20210125210053113-1285961954.png)
*태스크 기반 분할 방식*

### 2.5 Fork-Join 모델

![Fork-Join](./images/ch02/1617944-20210125210106602-484285706.png)
*위: 직렬 실행 모델 / 아래: Fork-Join 병렬 실행 모델*

---

## 3. 스레딩 인프라

### 3.1 TAtomic

C++ std::atomic을 대체하는 커스텀 원자적 연산 래퍼.

**지원 메모리 오더링 모드:**
- `Relaxed` - 최소 동기화
- `SequentiallyConsistent` - 완전 순차적 일관성

### 3.2 TFuture / TPromise

```cpp
TFuture<T> future;
future.Wait();           // 블로킹 대기
future.WaitFor(duration); // 타임아웃 대기
T result = future.Get(); // 결과 획득
```

### 3.3 FRunnable & FRunnableThread

```cpp
class FRunnable
{
    virtual bool Init();  // 초기화
    virtual uint32 Run(); // 실행 (메인 로직)
    virtual void Stop();  // 정지 요청
    virtual void Exit();  // 종료 처리
};
```

| 클래스 | 플랫폼 | 사용 API |
|--------|--------|----------|
| **FRunnableThreadWin** | Windows | CreateThread |
| **FRunnableThreadPThread** | Linux, macOS, iOS | POSIX pthread |
| **FFakeThread** | 단일스레드 | 폴백 |

### 3.4 스레드 풀: FQueuedThreadPool

```
FQueuedThreadPoolBase
├─ QueuedWork[]     (대기 태스크 큐)
├─ QueuedThreads[]  (사용 가능한 워커)
├─ AllThreads[]     (모든 풀 스레드)
└─ FCriticalSection (동기화)
```

---

## 4. 태스크 그래프 시스템

### 4.1 계층 아키텍처

```
FBaseGraphTask (추상 기본 클래스)
    │
    ├─ NumberOfPrerequistitesOutstanding (원자적 카운터)
    │
    └─ TGraphTask<TTask> (템플릿 래퍼)
           ├─ TaskStorage
           ├─ 선행 조건 추적
           └─ 후속 태스크 의존성
```

### 4.2 Named vs Unnamed 스레드

**전용 Named 스레드:**

| 스레드 | 역할 |
|--------|------|
| **GameThread** | 게임 로직, 틱 |
| **RHIThread** | RHI 명령 처리 |
| **AudioThread** | 오디오 처리 |
| **RenderingThread** | 렌더링 명령 처리 |

**Unnamed 워커 스레드 우선순위:**

| 우선순위 | 용도 |
|----------|------|
| **High** | 즉시 처리 필요 |
| **Normal** | 일반 태스크 |
| **Background** | 저우선순위 작업 |

---

## 5. 현대 그래픽 API 멀티스레딩

### 5.1 전통 그래픽 API의 한계

![전통 API](./images/ch02/1617944-20210125210143940-1531101013.png)
*전통 그래픽 API의 선형 드로우 명령 실행*

![CPU-GPU 블로킹](./images/ch02/1617944-20210125210152724-219846672.jpg)
*전통 API - 단일 스레드/Context에서 블로킹 드로우 콜, CPU와 GPU 병렬 불가*

### 5.2 DirectX 11 멀티스레딩

![DX11 아키텍처](./images/ch02/1617944-20210125210204887-1574578553.png)
*"Practical Parallel Rendering with DirectX 9 and 10"의 소프트웨어 레벨 멀티스레드 렌더링 아키텍처*

![DX11 모델](./images/ch02/1617944-20210125210224685-921400643.png)
*DirectX 11 멀티스레드 모델*

![DX11 상세](./images/ch02/1617944-20210125210250981-472165669.png)
*DirectX 11 멀티스레드 아키텍처 상세*

### 5.3 DirectX 12 멀티스레딩

![DX12 모델](./images/ch02/1617944-20210125210312585-1398642718.png)
*DirectX 12 멀티스레드 모델*

![DX12 메커니즘](./images/ch02/1617944-20210125210324897-639832403.png)
*DX12: CPU 스레드 → 명령 리스트 → 명령 큐 → GPU 엔진 실행 메커니즘*

#### 세 가지 큐 타입 → GPU 엔진 매핑

```
┌─────────────────┐     ┌─────────────────┐
│   Copy Queue    │ ──→ │   Copy Engine   │
└─────────────────┘     └─────────────────┘

┌─────────────────┐     ┌─────────────────┐
│  Compute Queue  │ ──→ │ Compute + Copy  │
└─────────────────┘     └─────────────────┘

┌─────────────────┐     ┌─────────────────┐
│    3D Queue     │ ──→ │   All Engines   │
└─────────────────┘     └─────────────────┘
```

### 5.4 Vulkan 멀티스레딩

![Vulkan 병렬](./images/ch02/1617944-20210125210348224-1598024134.jpg)
*Vulkan 그래픽 API 병렬 처리*

![Vulkan CommandPool](./images/ch02/1617944-20210125210402618-829810560.jpg)
*Vulkan CommandPool의 프레임 간 병렬 처리*

![Vulkan 동기화](./images/ch02/1617944-20210125210419647-168271108.jpg)
*Vulkan 동기화: Semaphore(큐 동기화), Fence(GPU-CPU), Event/Barrier(Command Buffer)*

### 5.5 Metal 멀티스레딩

![API 마이그레이션](./images/ch02/1617944-20210125210433701-1895270677.png)
*OpenGL에서 신세대 API 마이그레이션 비용 vs 성능 이점*

![Metal 개념](./images/ch02/1617944-20210125210454310-1431175121.png)
*Metal 기본 개념: CommandEncoder (Render/Compute/Blit) → CommandBuffer → CommandQueue*

![Metal 멀티스레드](./images/ch02/1617944-20210125210507226-1441423249.png)
*Metal 멀티스레드 모델 - 3개 CPU 스레드가 다른 타입의 Encoder 동시 녹화*

---

## 6. UE 렌더링 스레드 아키텍처

### 6.1 게임 스레드 vs 렌더 스레드 분리

> "렌더링 스레드는 GPU 실행을 게임 로직으로부터 분리하여, 물리/애니메이션/로직이 GPU가 이전 프레임의 명령을 소비하는 동안 진행할 수 있게 합니다."

### 6.2 프레임 파이프라이닝 (Triple Buffering)

```
시간 ─────────────────────────────────────────→

Game Thread:   [Frame N+2] [Frame N+3] [Frame N+4]
                   │
Render Thread:     │    [Frame N+1] [Frame N+2] [Frame N+3]
                   │        │
GPU:               │        │    [Frame N] [Frame N+1] [Frame N+2]
```

| 컴포넌트 | 처리 중인 프레임 |
|----------|------------------|
| **Game Thread** | Frame N |
| **Render Thread** | Frame N-1 |
| **GPU** | Frame N-2 |

### 6.3 명령 큐잉

```cpp
ENQUEUE_RENDER_COMMAND(CommandName)(
    [](FRHICommandListImmediate& RHICmdList)
    {
        // 렌더 스레드에서 실행될 코드
    });
```

---

## 7. 다른 엔진들의 패턴

### 7.1 Frostbite FrameGraph

![Frostbite FrameGraph](./images/ch02/1617944-20210125210618582-154442848.png)
*Frostbite 엔진의 Frame Graph 방식 디퍼드 렌더링 순서 및 의존성 그래프*

### 7.2 Naughty Dog Fiber 시스템

| 특징 | 설명 |
|------|------|
| 경량 컨텍스트 스위칭 | 최소 레지스터 오버헤드 |
| Fiber별 TLS | 데이터 격리 |

### 7.3 Destiny Engine Job System

| 기능 | 설명 |
|------|------|
| **Priority FIFO** | 우선순위 기반 선입선출 |
| **Frame-ahead Buffering** | 프레임 선행 버퍼링 |
| **Dynamic Load-balancing** | 동적 부하 분산 |

---

## 8. 동기화 프리미티브

### 8.1 이벤트 (FEvent)

| 플랫폼 | 구현 |
|--------|------|
| Windows | `CreateEvent` |
| POSIX | 조건 변수 |

### 8.2 크리티컬 섹션 (FCriticalSection)

```cpp
FCriticalSection CriticalSection;
{
    FScopeLock Lock(&CriticalSection);
    // 보호된 코드
}
```

### 8.3 원자적 연산

| 연산 | 용도 |
|------|------|
| **Increment** | 참조 카운트 증가 |
| **Exchange** | 값 교환 |
| **Compare-and-Swap** | 조건부 교환 |

---

## 핵심 설계 원칙

| 원칙 | 설명 |
|------|------|
| **관심사 분리** | 에셋 로딩, 물리, 애니메이션, 렌더링이 독립 스레드 |
| **최소 동기화** | 프레임 선행 버퍼링으로 스레드 간 대기 감소 |
| **하드웨어 지역성** | 스레드 친화도 마스크로 CPU 코어에 고정 |
| **확장성** | 동적 워커 수가 하드웨어 동시성에 적응 |

---

## 요약 다이어그램

```
┌─────────────────────────────────────────────────────────────────┐
│                    UE 멀티스레드 렌더링 아키텍처                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐      │
│  │ Game Thread  │───→│Render Thread │───→│  RHI Thread  │      │
│  │  (Frame N)   │    │ (Frame N-1)  │    │ (Frame N-2)  │      │
│  └──────────────┘    └──────────────┘    └──────────────┘      │
│         │                   │                   │               │
│         ▼                   ▼                   ▼               │
│  ┌──────────────────────────────────────────────────────┐      │
│  │              Task Graph System                        │      │
│  └──────────────────────────────────────────────────────┘      │
│         │                                                       │
│         ▼                                                       │
│  ┌──────────────────────────────────────────────────────┐      │
│  │         Graphics API (D3D12 / Vulkan / Metal)         │      │
│  └──────────────────────────────────────────────────────┘      │
│         │                                                       │
│         ▼                                                       │
│  ┌──────────────────────────────────────────────────────┐      │
│  │              GPU (Copy / Compute / 3D)                │      │
│  └──────────────────────────────────────────────────────┘      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 참고 자료

- 원문: https://www.cnblogs.com/timlly/p/14327537.html
- DirectX 12 Programming Guide
- Vulkan Specification
- Apple Metal Documentation
