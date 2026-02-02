# 05. 엔진 패턴 및 동기화

> 다른 게임 엔진들의 멀티스레딩 패턴과 동기화 프리미티브

---

## 목차

1. [다른 엔진들의 패턴](#1-다른-엔진들의-패턴)
2. [Frostbite FrameGraph](#2-frostbite-framegraph)
3. [Naughty Dog Fiber 시스템](#3-naughty-dog-fiber-시스템)
4. [Destiny Job System](#4-destiny-job-system)
5. [동기화 프리미티브](#5-동기화-프리미티브)
6. [설계 원칙](#6-설계-원칙)

---

## 1. 다른 엔진들의 패턴 {#1-다른-엔진들의-패턴}

### 1.1 패턴 비교

| 엔진 | 패턴 | 특징 |
|------|------|------|
| **UE** | Named Thread + Task Graph | 고정 스레드 + 동적 태스크 |
| **Frostbite** | Frame Graph | 선언적 의존성 그래프 |
| **Naughty Dog** | Fiber System | 경량 컨텍스트 스위칭 |
| **Destiny** | Job System | 우선순위 기반 FIFO |
| **Unity** | Job System + ECS | 데이터 지향 설계 |

### 1.2 공통 목표

```
┌─────────────────────────────────────────────────────────────────┐
│                    게임 엔진 멀티스레딩 목표                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. CPU 활용 최대화                                              │
│     └─ 모든 코어가 유휴 상태 없이 작업                            │
│                                                                 │
│  2. 지연 시간 최소화                                             │
│     └─ 입력 → 화면 출력 시간 단축                                 │
│                                                                 │
│  3. 프레임 시간 안정화                                           │
│     └─ 일관된 프레임레이트 유지                                   │
│                                                                 │
│  4. 확장성                                                       │
│     └─ 2코어 ~ 64코어까지 효율적 스케일                           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. Frostbite FrameGraph {#2-frostbite-framegraph}

### 2.1 개념

Frostbite (EA DICE)의 Frame Graph는 렌더링 패스 간 의존성을 선언적으로 정의합니다:

![Frostbite FrameGraph](../images/ch02/1617944-20210125210618582-154442848.png)
*Frostbite 엔진의 Frame Graph - 디퍼드 렌더링 의존성 그래프*

### 2.2 장점

| 장점 | 설명 |
|------|------|
| **자동 리소스 관리** | 생명주기 자동 추적 |
| **메모리 앨리어싱** | 동시 사용 안 되는 리소스 메모리 공유 |
| **자동 배리어 삽입** | 의존성 기반 동기화 |
| **패스 컬링** | 미사용 패스 자동 제거 |

### 2.3 UE RDG와의 비교

```cpp
// UE의 Render Dependency Graph (Frostbite 영향)
void RenderDeferred(FRDGBuilder& GraphBuilder)
{
    // 리소스 선언
    FRDGTextureRef GBufferA = GraphBuilder.CreateTexture(
        FRDGTextureDesc::Create2D(Extent, PF_A2B10G10R10),
        TEXT("GBufferA"));

    FRDGTextureRef GBufferB = GraphBuilder.CreateTexture(
        FRDGTextureDesc::Create2D(Extent, PF_FloatRGBA),
        TEXT("GBufferB"));

    FRDGTextureRef SceneColor = GraphBuilder.CreateTexture(
        FRDGTextureDesc::Create2D(Extent, PF_FloatRGBA),
        TEXT("SceneColor"));

    // Base Pass (GBuffer 기록)
    {
        FBasePassParameters* Params = GraphBuilder.AllocParameters<FBasePassParameters>();
        Params->RenderTargets[0] = FRenderTargetBinding(GBufferA, ERenderTargetLoadAction::EClear);
        Params->RenderTargets[1] = FRenderTargetBinding(GBufferB, ERenderTargetLoadAction::EClear);

        GraphBuilder.AddPass(
            RDG_EVENT_NAME("BasePass"),
            Params,
            ERDGPassFlags::Raster,
            [](FRHICommandList& RHICmdList) { /* ... */ });
    }

    // Lighting Pass (GBuffer 읽기, SceneColor 기록)
    {
        FLightingPassParameters* Params = GraphBuilder.AllocParameters<FLightingPassParameters>();
        Params->GBufferA = GBufferA;
        Params->GBufferB = GBufferB;
        Params->RenderTargets[0] = FRenderTargetBinding(SceneColor, ERenderTargetLoadAction::EClear);

        GraphBuilder.AddPass(
            RDG_EVENT_NAME("LightingPass"),
            Params,
            ERDGPassFlags::Raster,
            [](FRHICommandList& RHICmdList) { /* ... */ });
    }

    // GraphBuilder가 의존성 분석 및 배리어 자동 삽입
}
```

---

## 3. Naughty Dog Fiber 시스템 {#3-naughty-dog-fiber-시스템}

### 3.1 Fiber란?

Fiber는 스레드보다 경량인 실행 컨텍스트입니다:

| 특성 | Thread | Fiber |
|------|--------|-------|
| **컨텍스트 스위칭** | OS 개입 (비쌈) | 사용자 공간 (저렴) |
| **스케줄링** | OS 커널 | 애플리케이션 제어 |
| **스택** | 큰 스택 (MB) | 작은 스택 (KB) |
| **생성 비용** | 높음 | 매우 낮음 |

### 3.2 Naughty Dog 구현

```cpp
// Fiber 기반 Job 시스템 (의사 코드)
class FJob
{
public:
    // Job 실행 함수
    virtual void Execute() = 0;

    // 의존성
    TArray<FJob*> Dependencies;

    // Fiber 컨텍스트
    FFiber* Fiber;
};

class FFiberScheduler
{
    TArray<FFiber*> FiberPool;
    TArray<FJob*> ReadyQueue;

    void WorkerLoop()
    {
        while (bRunning)
        {
            FJob* Job = ReadyQueue.Dequeue();

            if (Job)
            {
                // Fiber로 전환
                SwitchToFiber(Job->Fiber);
                Job->Execute();

                // 완료 후 의존성 해제
                for (FJob* Dependent : Job->Dependents)
                {
                    if (--Dependent->RemainingDeps == 0)
                    {
                        ReadyQueue.Enqueue(Dependent);
                    }
                }
            }
            else
            {
                // Job 없으면 다른 Fiber로 양보
                YieldFiber();
            }
        }
    }
};
```

### 3.3 장점

| 장점 | 설명 |
|------|------|
| **낮은 오버헤드** | 마이크로초 단위 스위칭 |
| **세밀한 제어** | 양보 시점 명시적 제어 |
| **TLS 지원** | Fiber별 Thread Local Storage |
| **대기 없는 동기화** | 블로킹 대신 양보 |

---

## 4. Destiny Job System {#4-destiny-job-system}

### 4.1 핵심 특징

Bungie의 Destiny 엔진은 다음 특징을 가집니다:

| 기능 | 설명 |
|------|------|
| **Priority FIFO** | 우선순위별 선입선출 |
| **Frame-ahead Buffering** | 프레임 선행 버퍼링 |
| **Dynamic Load-balancing** | 동적 부하 분산 |
| **Work Stealing** | 유휴 워커가 다른 큐에서 작업 훔침 |

### 4.2 우선순위 시스템

```cpp
// 우선순위 레벨
enum class EJobPriority
{
    Critical,    // 프레임 완료 필수 (렌더링)
    High,        // 중요 (물리, 애니메이션)
    Normal,      // 일반 (게임 로직)
    Low,         // 백그라운드 (스트리밍)
    Idle         // 유휴 시에만 (프리캐싱)
};

// 우선순위별 큐
class FJobSystem
{
    TQueue<FJob*> Queues[5];  // 각 우선순위별 큐

    FJob* GetNextJob()
    {
        // 높은 우선순위부터 확인
        for (int32 i = 0; i < 5; ++i)
        {
            FJob* Job;
            if (Queues[i].Dequeue(Job))
            {
                return Job;
            }
        }
        return nullptr;
    }
};
```

### 4.3 Work Stealing

```cpp
// Work Stealing 구현
class FWorkStealingScheduler
{
    // 각 워커의 로컬 큐
    TArray<TDeque<FJob*>> LocalQueues;

    void WorkerLoop(int32 WorkerIndex)
    {
        TDeque<FJob*>& MyQueue = LocalQueues[WorkerIndex];

        while (bRunning)
        {
            FJob* Job = nullptr;

            // 1. 로컬 큐에서 Pop (LIFO - 캐시 친화적)
            if (!MyQueue.IsEmpty())
            {
                Job = MyQueue.PopBack();
            }
            // 2. 다른 워커에서 Steal (FIFO)
            else
            {
                Job = TryStealFromOther(WorkerIndex);
            }

            if (Job)
            {
                Job->Execute();
            }
            else
            {
                // 모든 큐가 비어있으면 대기
                WaitForWork();
            }
        }
    }

    FJob* TryStealFromOther(int32 MyIndex)
    {
        // 랜덤 워커부터 시작하여 순회
        int32 StartIndex = FMath::Rand() % LocalQueues.Num();

        for (int32 i = 0; i < LocalQueues.Num(); ++i)
        {
            int32 VictimIndex = (StartIndex + i) % LocalQueues.Num();
            if (VictimIndex != MyIndex)
            {
                FJob* Stolen;
                if (LocalQueues[VictimIndex].TryStealFront(Stolen))
                {
                    return Stolen;
                }
            }
        }
        return nullptr;
    }
};
```

---

## 5. 동기화 프리미티브 {#5-동기화-프리미티브}

### 5.1 FEvent

OS 이벤트 객체의 래퍼:

```cpp
// FEvent 사용
FEvent* Event = FPlatformProcess::GetSynchEventFromPool();

// 워커 스레드
void WorkerThread()
{
    DoWork();
    Event->Trigger();  // 시그널
}

// 메인 스레드
void MainThread()
{
    Event->Wait();     // 대기
    // 또는 타임아웃 대기
    bool bSignaled = Event->Wait(1000);  // 1초 대기
}

// 풀에 반환
FPlatformProcess::ReturnSynchEventToPool(Event);
```

### 5.2 FCriticalSection

상호 배제 락:

```cpp
// FCriticalSection 사용
FCriticalSection CriticalSection;

void ThreadSafeFunction()
{
    // 수동 락
    CriticalSection.Lock();
    // 임계 영역
    CriticalSection.Unlock();

    // 또는 스코프 락 (권장)
    {
        FScopeLock Lock(&CriticalSection);
        // 임계 영역 - 스코프 종료 시 자동 해제
    }
}

// 조건부 락
void TryLockExample()
{
    if (CriticalSection.TryLock())
    {
        // 락 획득 성공
        DoWork();
        CriticalSection.Unlock();
    }
    else
    {
        // 락 실패 - 다른 작업 수행
    }
}
```

### 5.3 FRWLock

읽기-쓰기 락:

```cpp
FRWLock RWLock;

// 읽기 (여러 스레드 동시 가능)
void ReadData()
{
    FRWScopeLock Lock(RWLock, SLT_ReadOnly);
    // 데이터 읽기
}

// 쓰기 (단독 접근)
void WriteData()
{
    FRWScopeLock Lock(RWLock, SLT_Write);
    // 데이터 쓰기
}
```

### 5.4 FSpinLock

짧은 대기용 스핀 락:

```cpp
// FSpinLock - 짧은 임계 영역에 적합
class FSpinLock
{
    TAtomic<int32> LockState{0};

public:
    void Lock()
    {
        while (true)
        {
            int32 Expected = 0;
            if (LockState.CompareExchange(Expected, 1))
            {
                return;  // 락 획득
            }
            // 스핀 대기
            FPlatformProcess::Yield();
        }
    }

    void Unlock()
    {
        LockState.Store(0);
    }
};

// 사용 예시 - 매우 짧은 임계 영역
FSpinLock SpinLock;
void QuickUpdate()
{
    SpinLock.Lock();
    Counter++;  // 매우 빠른 작업
    SpinLock.Unlock();
}
```

### 5.5 원자적 연산

```cpp
// FPlatformAtomics를 통한 원자적 연산
int32 Value = 0;

// 원자적 증가
int32 OldValue = FPlatformAtomics::InterlockedIncrement(&Value);

// 원자적 교환
int32 OldValue = FPlatformAtomics::InterlockedExchange(&Value, 10);

// Compare-and-Swap
int32 OldValue = FPlatformAtomics::InterlockedCompareExchange(&Value, NewValue, Expected);

// 원자적 덧셈
int32 OldValue = FPlatformAtomics::InterlockedAdd(&Value, 5);
```

---

## 6. 설계 원칙 {#6-설계-원칙}

### 6.1 핵심 원칙

| 원칙 | 설명 | UE 적용 |
|------|------|---------|
| **관심사 분리** | 스레드별 명확한 역할 | Game/Render/RHI 분리 |
| **최소 동기화** | 락 사용 최소화 | Lock-free 큐, 프레임 버퍼링 |
| **데이터 지역성** | 캐시 친화적 접근 | 연속 메모리, 배치 처리 |
| **확장성** | 코어 수에 따른 스케일 | 동적 워커 수 |

### 6.2 락 피하기 전략

```cpp
// 1. 데이터 복제 (각 스레드 로컬 복사본)
void PerThreadCopy()
{
    // 각 워커가 자신만의 결과 버퍼 소유
    TArray<TArray<FResult>> PerWorkerResults;
    PerWorkerResults.SetNum(NumWorkers);

    ParallelFor(NumItems, [&](int32 Index)
    {
        int32 WorkerIndex = FTaskGraphInterface::Get().GetCurrentThreadIfKnown();
        PerWorkerResults[WorkerIndex].Add(ProcessItem(Index));
    });

    // 병합 (순차)
    for (auto& Results : PerWorkerResults)
    {
        FinalResults.Append(Results);
    }
}

// 2. Lock-free 알고리즘
TLockFreePointerListFIFO<FJob, PLATFORM_CACHE_LINE_SIZE> LockFreeQueue;

// 3. 프레임 더블/트리플 버퍼링
struct FFrameData
{
    TArray<FTransform> Transforms[3];  // 3 프레임 버퍼

    int32 WriteFrame;  // 게임 스레드 기록
    int32 ReadFrame;   // 렌더 스레드 읽기
};
```

### 6.3 성능 측정

```cpp
// 스레드 활용률 측정
DECLARE_CYCLE_STAT(TEXT("Game Thread"), STAT_GameThread, STATGROUP_Threading);
DECLARE_CYCLE_STAT(TEXT("Render Thread"), STAT_RenderThread, STATGROUP_Threading);
DECLARE_CYCLE_STAT(TEXT("Worker Thread"), STAT_WorkerThread, STATGROUP_Threading);

// 콘솔 명령
stat threading        // 스레드 통계
stat taskgraph       // Task Graph 통계
stat cpu             // CPU 사용률
```

---

## 요약

| 엔진/패턴 | 핵심 특징 | UE 적용 |
|----------|----------|---------|
| **Frostbite** | Frame Graph | RDG |
| **Naughty Dog** | Fiber | Task Graph (유사) |
| **Destiny** | Work Stealing | 워커 풀 |
| **동기화** | 최소화 | Lock-free, 버퍼링 |

---

## 다음 챕터

[Ch.03 렌더링 메커니즘](../03-rendering-mechanism/index.md)에서 FMeshBatch와 FMeshDrawCommand를 살펴봅니다.

---

## 참고 자료

- [원문 시리즈 (중국어)](https://www.cnblogs.com/timlly/p/14327537.html)
- [GDC: Parallelizing the Naughty Dog Engine Using Fibers](https://www.gdcvault.com/play/1022186/Parallelizing-the-Naughty-Dog-Engine)
- [GDC: Destiny's Multithreaded Rendering Architecture](https://www.gdcvault.com/play/1021926/Destiny-s-Multithreaded-Rendering)
- [Frostbite Frame Graph](https://www.gdcvault.com/play/1024612/FrameGraph-Extensible-Rendering-Architecture-in)
---

<div style="display: flex; justify-content: space-between; align-items: center; padding: 16px 0;">
  <a href="../04-ue-rendering-threads/" style="text-decoration: none;">← 이전: 04. UE 렌더링 스레드 아키텍처</a>
  <a href="../../03-rendering-mechanism/" style="text-decoration: none;">다음: Ch.03 렌더링 메커니즘 →</a>
</div>
