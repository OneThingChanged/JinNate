# 02. 스레딩 인프라

> UE의 스레딩 빌딩 블록과 Task Graph 시스템

---

## 목차

1. [TAtomic](#1-tatomic)
2. [TFuture와 TPromise](#2-tfuture와-tpromise)
3. [FRunnable과 FRunnableThread](#3-frunnable과-frunnablethread)
4. [스레드 풀](#4-스레드-풀)
5. [Task Graph 시스템](#5-task-graph-시스템)
6. [Named vs Unnamed 스레드](#6-named-vs-unnamed-스레드)

---

## 1. TAtomic {#1-tatomic}

### 1.1 개요

TAtomic은 C++ std::atomic의 UE 래퍼입니다:

```cpp
// 기본 사용
TAtomic<int32> Counter{0};

// 원자적 연산
Counter.Increment();           // ++
Counter.Decrement();           // --
Counter.Add(5);                // += 5
int32 Old = Counter.Exchange(10);  // 교환

// Compare-and-Swap
int32 Expected = 5;
bool Success = Counter.CompareExchange(Expected, 10);
// Counter가 5면 10으로 변경, Success = true
// Counter가 5가 아니면 Expected에 현재 값 저장, Success = false
```

### 1.2 메모리 오더링

```cpp
// 메모리 오더링 모드
enum class EMemoryOrder
{
    Relaxed,              // 최소 동기화, 최대 성능
    SequentiallyConsistent // 완전 순차적 일관성 (기본값)
};

// Relaxed - 단순 카운터에 적합
TAtomic<int32> RelaxedCounter{0};
RelaxedCounter.IncrementExchange(EMemoryOrder::Relaxed);

// SequentiallyConsistent - 동기화 필요시
TAtomic<bool> Flag{false};
Flag.Store(true);  // 기본: SequentiallyConsistent
bool Value = Flag.Load();
```

### 1.3 락 프리 데이터 구조

```cpp
// 락 프리 스택 예시
template<typename T>
class TLockFreeStack
{
    struct FNode
    {
        T Data;
        FNode* Next;
    };

    TAtomic<FNode*> Head{nullptr};

public:
    void Push(const T& Value)
    {
        FNode* NewNode = new FNode{Value, nullptr};
        FNode* OldHead = Head.Load();

        do {
            NewNode->Next = OldHead;
        } while (!Head.CompareExchange(OldHead, NewNode));
    }

    bool Pop(T& OutValue)
    {
        FNode* OldHead = Head.Load();

        while (OldHead)
        {
            if (Head.CompareExchange(OldHead, OldHead->Next))
            {
                OutValue = OldHead->Data;
                delete OldHead;
                return true;
            }
        }
        return false;
    }
};
```

---

## 2. TFuture와 TPromise {#2-tfuture와-tpromise}

### 2.1 비동기 결과 전달

```cpp
// TPromise - 결과 제공자
TPromise<FResult> Promise;

// TFuture - 결과 소비자
TFuture<FResult> Future = Promise.GetFuture();

// 워커 스레드에서
AsyncTask(EAsyncExecution::ThreadPool, [Promise = MoveTemp(Promise)]() mutable
{
    FResult Result = ComputeResult();
    Promise.SetValue(MoveTemp(Result));  // 결과 설정
});

// 메인 스레드에서
Future.Wait();           // 블로킹 대기
FResult Result = Future.Get();  // 결과 획득

// 또는 타임아웃 대기
if (Future.WaitFor(FTimespan::FromSeconds(5.0)))
{
    FResult Result = Future.Get();
}
else
{
    // 타임아웃
}
```

### 2.2 Async 함수

```cpp
// 간편한 비동기 실행
TFuture<int32> Future = Async(EAsyncExecution::ThreadPool, []()
{
    return ExpensiveComputation();
});

// 실행 옵션
enum class EAsyncExecution
{
    TaskGraph,      // Task Graph 사용 (권장)
    ThreadPool,     // 스레드 풀 사용
    Thread,         // 새 스레드 생성
    TaskGraphMainThread,  // 메인 스레드에서 태스크로
    LargeThreadPool       // 대용량 스레드 풀
};

// Then 체이닝
Async(EAsyncExecution::ThreadPool, []() { return LoadData(); })
    .Then([](TFuture<FData> DataFuture)
    {
        FData Data = DataFuture.Get();
        return ProcessData(Data);
    })
    .Then([](TFuture<FResult> ResultFuture)
    {
        FResult Result = ResultFuture.Get();
        UseResult(Result);
    });
```

### 2.3 SharedFuture

```cpp
// 여러 소비자가 동일 결과 대기
TSharedFuture<FResult> SharedFuture = Async(...).Share();

// 여러 곳에서 대기 가능
void ConsumerA() { FResult R = SharedFuture.Get(); }
void ConsumerB() { FResult R = SharedFuture.Get(); }
```

---

## 3. FRunnable과 FRunnableThread {#3-frunnable과-frunnablethread}

### 3.1 FRunnable 인터페이스

```cpp
class FRunnable
{
public:
    // 스레드 시작 전 초기화
    virtual bool Init() { return true; }

    // 메인 실행 함수
    virtual uint32 Run() = 0;

    // 정지 요청 (다른 스레드에서 호출)
    virtual void Stop() {}

    // 종료 처리 (Run 반환 후)
    virtual void Exit() {}

    // 싱글톤 허용 여부
    virtual FSingleThreadRunnable* GetSingleThreadInterface() { return nullptr; }
};
```

### 3.2 사용자 정의 스레드

```cpp
class FMyWorker : public FRunnable
{
    TAtomic<bool> bShouldStop{false};
    TQueue<FTask> TaskQueue;

public:
    virtual bool Init() override
    {
        UE_LOG(LogTemp, Log, TEXT("Worker initialized"));
        return true;
    }

    virtual uint32 Run() override
    {
        while (!bShouldStop)
        {
            FTask Task;
            if (TaskQueue.Dequeue(Task))
            {
                Task.Execute();
            }
            else
            {
                FPlatformProcess::Sleep(0.001f);  // 1ms 대기
            }
        }
        return 0;
    }

    virtual void Stop() override
    {
        bShouldStop = true;
    }

    void AddTask(FTask Task)
    {
        TaskQueue.Enqueue(MoveTemp(Task));
    }
};

// 스레드 생성 및 시작
FMyWorker* Worker = new FMyWorker();
FRunnableThread* Thread = FRunnableThread::Create(
    Worker,
    TEXT("MyWorker"),
    0,                    // 스택 크기 (0 = 기본값)
    TPri_Normal,          // 우선순위
    FPlatformAffinity::GetNoAffinityMask()
);

// 종료
Worker->Stop();
Thread->WaitForCompletion();
delete Thread;
delete Worker;
```

### 3.3 플랫폼별 구현

| 클래스 | 플랫폼 | 사용 API |
|--------|--------|----------|
| **FRunnableThreadWin** | Windows | CreateThread |
| **FRunnableThreadPThread** | Linux, macOS, iOS | POSIX pthread |
| **FFakeThread** | 단일스레드 | 폴백 |

---

## 4. 스레드 풀 {#4-스레드-풀}

### 4.1 FQueuedThreadPool

```cpp
// 전역 스레드 풀 접근
FQueuedThreadPool* GThreadPool = FQueuedThreadPoolWrapper::Get().GetThreadPool();

// 스레드 풀에 작업 추가
class FMyQueuedWork : public IQueuedWork
{
public:
    virtual void DoThreadedWork() override
    {
        // 워커 스레드에서 실행
        PerformWork();
    }

    virtual void Abandon() override
    {
        // 풀 종료 시 호출
        delete this;
    }
};

GThreadPool->AddQueuedWork(new FMyQueuedWork());
```

### 4.2 스레드 풀 구조

```cpp
class FQueuedThreadPool
{
protected:
    TArray<IQueuedWork*> QueuedWork;     // 대기 작업 큐
    TArray<FQueuedThread*> QueuedThreads; // 사용 가능한 워커
    TArray<FQueuedThread*> AllThreads;    // 모든 워커
    FCriticalSection SynchQueue;          // 동기화

public:
    // 풀 생성
    bool Create(uint32 NumThreads, uint32 StackSize, EThreadPriority Priority);

    // 작업 추가
    void AddQueuedWork(IQueuedWork* InWork);

    // 모든 작업 완료 대기
    void WaitForCompletion();

    // 풀 파괴
    void Destroy();
};
```

### 4.3 AsyncPool 사용

```cpp
// ParallelFor의 내부 구현
template<typename FunctionType>
void ParallelFor(int32 Num, FunctionType Body, bool bForceSingleThread = false)
{
    if (Num == 0 || bForceSingleThread)
    {
        for (int32 Index = 0; Index < Num; ++Index)
        {
            Body(Index);
        }
        return;
    }

    // 워커 수 결정
    int32 NumWorkers = FMath::Min(Num, FTaskGraphInterface::Get().GetNumWorkerThreads());

    // 각 워커에 작업 분배
    ParallelForImpl(Num, [&Body](int32 Index) { Body(Index); }, NumWorkers);
}

// 사용
ParallelFor(1000, [&Data](int32 Index)
{
    ProcessData(Data[Index]);
});
```

---

## 5. Task Graph 시스템 {#5-task-graph-시스템}

### 5.1 아키텍처

```
┌─────────────────────────────────────────────────────────────────┐
│                    Task Graph 아키텍처                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                 FBaseGraphTask                           │   │
│  │  - NumberOfPrerequistitesOutstanding (원자적 카운터)      │   │
│  └────────────────────────────┬────────────────────────────┘   │
│                               │                                 │
│                               ▼                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              TGraphTask<TTask>                           │   │
│  │  - TaskStorage (사용자 태스크)                           │   │
│  │  - 선행 조건 추적                                        │   │
│  │  - 후속 태스크 의존성                                     │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│          디스패치                                                │
│              │                                                  │
│              ▼                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │            FTaskGraphInterface                           │   │
│  │  - Named Thread Queues                                   │   │
│  │  - Worker Thread Pool                                    │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 5.2 태스크 정의

```cpp
// 사용자 정의 태스크
class FMyTask
{
public:
    FMyTask(int32 InData) : Data(InData) {}

    // 필수: 정적 메타데이터
    static FORCEINLINE TStatId GetStatId()
    {
        RETURN_QUICK_DECLARE_CYCLE_STAT(FMyTask, STATGROUP_TaskGraphTasks);
    }

    static FORCEINLINE ENamedThreads::Type GetDesiredThread()
    {
        return ENamedThreads::AnyThread;  // 워커 스레드
    }

    static FORCEINLINE ESubsequentsMode::Type GetSubsequentsMode()
    {
        return ESubsequentsMode::TrackSubsequents;
    }

    // 실행 함수
    void DoTask(ENamedThreads::Type CurrentThread, const FGraphEventRef& MyCompletionGraphEvent)
    {
        // 태스크 로직
        ProcessData(Data);
    }

private:
    int32 Data;
};
```

### 5.3 태스크 생성 및 디스패치

```cpp
// 단순 태스크 생성
FGraphEventRef Event = TGraphTask<FMyTask>::CreateTask()
    .ConstructAndDispatchWhenReady(42);  // 생성자 인자

// 선행 조건 지정
FGraphEventArray Prerequisites;
Prerequisites.Add(PreviousTaskEvent);

FGraphEventRef Event = TGraphTask<FMyTask>::CreateTask(&Prerequisites)
    .ConstructAndDispatchWhenReady(42);

// 완료 대기
FTaskGraphInterface::Get().WaitUntilTaskCompletes(Event);

// 또는 여러 태스크 대기
FTaskGraphInterface::Get().WaitUntilTasksComplete(Prerequisites);
```

### 5.4 의존성 그래프

```cpp
// 복잡한 의존성 예시
void BuildDependencyGraph()
{
    // Task A: 독립적
    FGraphEventRef TaskA = TGraphTask<FTaskA>::CreateTask()
        .ConstructAndDispatchWhenReady();

    // Task B: 독립적
    FGraphEventRef TaskB = TGraphTask<FTaskB>::CreateTask()
        .ConstructAndDispatchWhenReady();

    // Task C: A와 B 완료 후
    FGraphEventArray ABPrereqs = {TaskA, TaskB};
    FGraphEventRef TaskC = TGraphTask<FTaskC>::CreateTask(&ABPrereqs)
        .ConstructAndDispatchWhenReady();

    // Task D: A 완료 후
    FGraphEventArray APrereqs = {TaskA};
    FGraphEventRef TaskD = TGraphTask<FTaskD>::CreateTask(&APrereqs)
        .ConstructAndDispatchWhenReady();

    // Task E: C와 D 완료 후
    FGraphEventArray CDPrereqs = {TaskC, TaskD};
    FGraphEventRef TaskE = TGraphTask<FTaskE>::CreateTask(&CDPrereqs)
        .ConstructAndDispatchWhenReady();
}

/*
의존성 그래프:
        A ─────┬───────→ D ────┐
               │               │
               └──┐            │
                  ▼            ▼
        B ──────→ C ─────────→ E
*/
```

---

## 6. Named vs Unnamed 스레드 {#6-named-vs-unnamed-스레드}

### 6.1 Named 스레드

특정 역할을 가진 전용 스레드:

| 스레드 | 역할 | 특징 |
|--------|------|------|
| **GameThread** | 게임 로직, 틱 | 메인 스레드 |
| **RenderingThread** | 렌더링 명령 처리 | 싱글 인스턴스 |
| **RHIThread** | RHI 명령 처리 | 플랫폼별 |
| **AudioThread** | 오디오 처리 | 저지연 필요 |

```cpp
// Named 스레드로 태스크 디스패치
FGraphEventRef Event = FFunctionGraphTask::CreateAndDispatchWhenReady(
    []()
    {
        // 렌더링 스레드에서 실행
        DoRenderThreadWork();
    },
    TStatId(),
    nullptr,
    ENamedThreads::RenderThread
);

// 게임 스레드로 복귀
FFunctionGraphTask::CreateAndDispatchWhenReady(
    []()
    {
        // 게임 스레드에서 실행
        UpdateGameState();
    },
    TStatId(),
    nullptr,
    ENamedThreads::GameThread
);
```

### 6.2 Unnamed 워커 스레드

Task Graph의 범용 워커:

| 우선순위 | 용도 |
|----------|------|
| **High** | 즉시 처리 필요 (프레임 민감) |
| **Normal** | 일반 태스크 |
| **Background** | 저우선순위 (로딩, 스트리밍) |

```cpp
// 워커 스레드에서 실행
TGraphTask<FMyTask>::CreateTask()
    .ConstructAndDispatchWhenReady();  // AnyThread = 워커

// 우선순위 지정
class FHighPriorityTask
{
    static ENamedThreads::Type GetDesiredThread()
    {
        return ENamedThreads::AnyHiPriThreadNormalTask;
    }
};

class FBackgroundTask
{
    static ENamedThreads::Type GetDesiredThread()
    {
        return ENamedThreads::AnyBackgroundThreadNormalTask;
    }
};
```

### 6.3 스레드 수 결정

```cpp
// 워커 스레드 수 조회
int32 NumWorkers = FTaskGraphInterface::Get().GetNumWorkerThreads();

// 플랫폼별 기본값
// Windows/Linux: 논리 코어 수 - 2 (Game + Render용)
// 콘솔: 플랫폼 최적화된 값

// 커맨드라인 오버라이드
// -numthreads=N
```

---

## 요약

| 컴포넌트 | 용도 | 사용 시점 |
|----------|------|----------|
| **TAtomic** | 원자적 연산 | 공유 변수 접근 |
| **TFuture/TPromise** | 비동기 결과 전달 | 스레드 간 데이터 전달 |
| **FRunnable** | 커스텀 스레드 | 장기 실행 작업 |
| **FQueuedThreadPool** | 스레드 풀 | 대량 병렬 작업 |
| **Task Graph** | 의존성 관리 | 복잡한 병렬 워크플로우 |

---

## 다음 문서

[03. 그래픽 API 멀티스레딩](03-graphics-api-threading.md)에서 DX12, Vulkan, Metal의 병렬화를 살펴봅니다.
---

<div style="display: flex; justify-content: space-between; align-items: center; padding: 16px 0;">
  <a href="../01-multithreading-basics/" style="text-decoration: none;">← 이전: 01. 멀티스레딩 기초</a>
  <a href="../03-graphics-api-threading/" style="text-decoration: none;">다음: 03. 그래픽 API 멀티스레딩 →</a>
</div>
