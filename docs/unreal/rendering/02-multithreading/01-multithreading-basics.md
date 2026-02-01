# 01. 멀티스레딩 기초

> 병렬 처리의 필요성과 기본 개념

---

## 목차

1. [멀티코어 시대](#1-멀티코어-시대)
2. [암달의 법칙](#2-암달의-법칙)
3. [동시성 vs 병렬성](#3-동시성-vs-병렬성)
4. [SMP 아키텍처](#4-smp-아키텍처)
5. [데이터 분할 전략](#5-데이터-분할-전략)
6. [Fork-Join 모델](#6-fork-join-모델)

---

## 1. 멀티코어 시대 {#1-멀티코어-시대}

### 1.1 CPU 발전 역사

2006년경부터 단일 코어 클럭 속도 향상이 한계에 도달했습니다:

- **전력 장벽**: 높은 클럭 = 높은 발열 = 높은 전력 소모
- **메모리 장벽**: CPU 속도 >> 메모리 속도
- **ILP 한계**: 명령어 수준 병렬성의 물리적 한계

![Ryzen 3990X](../images/ch02/1617944-20210125205726496-824035894.png)
*AMD Ryzen 3990X - 64코어 128스레드의 현대 CPU*

### 1.2 해결책: 멀티코어

| 시기 | 접근 방식 | 특징 |
|------|----------|------|
| ~2006 | 클럭 속도 증가 | 단일 스레드 성능 향상 |
| 2006~ | 코어 수 증가 | 병렬 처리 능력 향상 |
| 현재 | 이종 컴퓨팅 | CPU + GPU + NPU |

### 1.3 게임 엔진에서의 영향

```
싱글 스레드 게임 엔진 (과거)
┌────────────────────────────────────────────┐
│ Input → Logic → Physics → Render → Output │
└────────────────────────────────────────────┘
      CPU 0        CPU 1~N: 유휴 상태

멀티스레드 게임 엔진 (현재)
┌─────────┬─────────┬─────────┬─────────┐
│  Input  │  Logic  │ Physics │ Render  │
│  (CPU0) │  (CPU1) │  (CPU2) │ (CPU3)  │
└─────────┴─────────┴─────────┴─────────┘
      모든 코어 활용
```

---

## 2. 암달의 법칙 {#2-암달의-법칙}

### 2.1 공식

암달의 법칙은 병렬화의 이론적 한계를 설명합니다:

$$
Speedup = \frac{1}{(1-P) + \frac{P}{N}}
$$

- **P**: 병렬화 가능한 비율 (0~1)
- **N**: 프로세서 수
- **1-P**: 순차 실행 필수 비율

![암달의 법칙](../images/ch02/1617944-20210125205854934-1159288776.png)
*암달의 법칙 - 병렬화 비율과 가속비 관계*

### 2.2 실제 의미

| 병렬화 비율 | 무한 코어 시 최대 가속 | 실용적 한계 |
|------------|----------------------|-------------|
| 50% | 2x | ~16 코어에서 포화 |
| 75% | 4x | ~64 코어에서 포화 |
| 90% | 10x | ~256 코어에서 포화 |
| 95% | 20x | ~2048 코어에서 포화 |
| 99% | 100x | ~8192 코어에서 포화 |

```cpp
// 암달의 법칙 계산
float CalculateSpeedup(float ParallelFraction, int32 NumProcessors)
{
    float SequentialFraction = 1.0f - ParallelFraction;
    return 1.0f / (SequentialFraction + ParallelFraction / NumProcessors);
}

// 예시
float Speedup = CalculateSpeedup(0.95f, 16);  // 약 9.14x
```

### 2.3 게임에서의 적용

```cpp
// 게임 프레임의 구성 요소 (예시)
struct FFrameWork
{
    // 순차 실행 필수 (약 10%)
    void MainThreadOnly()
    {
        ProcessInput();          // 입력은 순차적
        UpdateGameState();       // 게임 상태 업데이트
        SyncRenderThread();      // 스레드 동기화
    }

    // 병렬화 가능 (약 90%)
    void Parallelizable()
    {
        ParallelFor(Actors, UpdateActor);       // 액터 업데이트
        ParallelFor(Components, UpdateComp);    // 컴포넌트 업데이트
        PhysicsSimulation();                     // 물리 (내부 병렬화)
        AnimationUpdate();                       // 애니메이션 (내부 병렬화)
        RenderScene();                           // 렌더링 (별도 스레드)
    }
};
```

---

## 3. 동시성 vs 병렬성 {#3-동시성-vs-병렬성}

### 3.1 정의

| 개념 | 정의 | 요구 사항 |
|------|------|----------|
| **동시성 (Concurrency)** | 여러 작업이 진행 중 | 최소 1 코어 |
| **병렬성 (Parallelism)** | 여러 작업이 동시 실행 | 여러 코어 필요 |

![동시성과 병렬성](../images/ch02/1617944-20210125205945659-2118423516.png)
*위: 듀얼 코어의 병렬 실행 / 아래: 단일 코어의 동시성 (시분할)*

### 3.2 코드 예시

```cpp
// 동시성 - 단일 코어에서도 가능
void ConcurrentExample()
{
    // Task A와 B가 번갈아 실행 (시분할)
    std::thread ThreadA([]{ DoWorkA(); });
    std::thread ThreadB([]{ DoWorkB(); });

    ThreadA.join();
    ThreadB.join();
}

// 병렬성 - 여러 코어 필요
void ParallelExample()
{
    // Task A와 B가 진짜 동시에 실행
    #pragma omp parallel sections
    {
        #pragma omp section
        { DoWorkA(); }  // Core 0

        #pragma omp section
        { DoWorkB(); }  // Core 1
    }
}
```

### 3.3 UE에서의 동시성/병렬성

```cpp
// 동시성: 비동기 태스크 (완료 시점 미정)
TFuture<FResult> Future = Async(EAsyncExecution::ThreadPool,
    []() { return ComputeResult(); });

// 병렬성: ParallelFor (즉시 병렬 실행)
ParallelFor(Items.Num(), [&Items](int32 Index)
{
    ProcessItem(Items[Index]);
});
```

---

## 4. SMP 아키텍처 {#4-smp-아키텍처}

### 4.1 대칭적 다중 처리 (SMP)

모든 CPU가 동등하게 메모리에 접근:

![SMP Windows](../images/ch02/1617944-20210125205921059-1248630297.png)
*Windows SMP에서 멀티코어 CPU 스레드 배치*

```
┌─────────────────────────────────────────┐
│              공유 메모리                 │
└─────────┬───────────┬───────────┬───────┘
          │           │           │
     ┌────┴────┐ ┌────┴────┐ ┌────┴────┐
     │  CPU 0  │ │  CPU 1  │ │  CPU 2  │
     │  Cache  │ │  Cache  │ │  Cache  │
     └─────────┘ └─────────┘ └─────────┘
```

### 4.2 캐시 일관성 문제

```cpp
// 문제: 두 CPU가 같은 변수 접근
int SharedValue = 0;

// CPU 0
void ThreadA()
{
    SharedValue = 1;  // CPU 0 캐시에 기록
    // CPU 1은 아직 이전 값을 볼 수 있음!
}

// CPU 1
void ThreadB()
{
    int Local = SharedValue;  // 0 또는 1?
}

// 해결: 원자적 연산 또는 메모리 배리어
std::atomic<int> AtomicValue{0};

void ThreadA_Fixed()
{
    AtomicValue.store(1, std::memory_order_release);
}

void ThreadB_Fixed()
{
    int Local = AtomicValue.load(std::memory_order_acquire);
}
```

### 4.3 스레드 생성

![스레드 생성](../images/ch02/1617944-20210125205931746-536130067.png)
*Windows 스레드 생성 및 초기화 과정*

```cpp
// UE 스레드 생성
FRunnableThread* Thread = FRunnableThread::Create(
    MyRunnable,           // FRunnable 인스턴스
    TEXT("MyThread"),     // 스레드 이름
    0,                    // 스택 크기 (0 = 기본값)
    TPri_Normal,          // 우선순위
    FPlatformAffinity::GetNoAffinityMask()  // CPU 친화도
);
```

---

## 5. 데이터 분할 전략 {#5-데이터-분할-전략}

### 5.1 선형 분할

연속 데이터를 균등하게 나눔:

![선형 분할](../images/ch02/1617944-20210125210040229-1901094181.png)
*연속 데이터를 균등 분할하여 여러 스레드에 분배*

```cpp
// UE ParallelFor - 선형 분할
void ProcessActors(const TArray<AActor*>& Actors)
{
    ParallelFor(Actors.Num(), [&Actors](int32 Index)
    {
        // 각 인덱스가 다른 워커에 분배됨
        Actors[Index]->UpdateTransform();
    });
}

// 수동 분할
void ManualPartition(TArray<int32>& Data, int32 NumThreads)
{
    int32 ChunkSize = Data.Num() / NumThreads;

    TArray<TFuture<void>> Futures;
    for (int32 i = 0; i < NumThreads; ++i)
    {
        int32 Start = i * ChunkSize;
        int32 End = (i == NumThreads - 1) ? Data.Num() : Start + ChunkSize;

        Futures.Add(Async(EAsyncExecution::ThreadPool, [&Data, Start, End]()
        {
            for (int32 j = Start; j < End; ++j)
            {
                ProcessElement(Data[j]);
            }
        }));
    }

    // 완료 대기
    for (auto& Future : Futures)
    {
        Future.Wait();
    }
}
```

### 5.2 재귀적 분할

분할 정복 알고리즘에 적합:

![재귀적 분할](../images/ch02/1617944-20210125210046729-1151631426.png)
*재귀적 데이터 분할 방식*

```cpp
// 재귀적 병렬 정렬 (의사 코드)
template<typename T>
void ParallelSort(T* Data, int32 Count, int32 MinParallelSize = 1024)
{
    if (Count < MinParallelSize)
    {
        // 직렬 정렬
        std::sort(Data, Data + Count);
        return;
    }

    int32 Mid = Count / 2;

    // 두 반쪽을 병렬로 정렬
    TGraphTask<FSortTask>::CreateTask()
        .ConstructAndDispatchWhenReady(Data, Mid);
    TGraphTask<FSortTask>::CreateTask()
        .ConstructAndDispatchWhenReady(Data + Mid, Count - Mid);

    // 병합 (순차적)
    std::inplace_merge(Data, Data + Mid, Data + Count);
}
```

### 5.3 태스크 분할

![태스크 분할](../images/ch02/1617944-20210125210053113-1285961954.png)
*태스크 기반 분할 방식*

```cpp
// 태스크 기반 분할 - 이종 작업
void TaskBasedPartition()
{
    // 다양한 크기/종류의 태스크
    TGraphTask<FPhysicsTask>::CreateTask().ConstructAndDispatchWhenReady();
    TGraphTask<FAnimationTask>::CreateTask().ConstructAndDispatchWhenReady();
    TGraphTask<FAudioTask>::CreateTask().ConstructAndDispatchWhenReady();
    TGraphTask<FNavigationTask>::CreateTask().ConstructAndDispatchWhenReady();

    // 워크 스틸링으로 자동 부하 분산
}
```

---

## 6. Fork-Join 모델 {#6-fork-join-모델}

### 6.1 개념

Fork-Join은 병렬 프로그래밍의 기본 패턴입니다:

![Fork-Join](../images/ch02/1617944-20210125210106602-484285706.png)
*위: 직렬 실행 / 아래: Fork-Join 병렬 실행*

```
┌─────────────────────────────────────────────────────────────────┐
│                        Fork-Join 패턴                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  메인 스레드: ═══════╦═══════════════════════════╦═════════════  │
│                    Fork                        Join              │
│                     │                           │                │
│  워커 1:            └─── Task A ────────────────┤                │
│  워커 2:            └─── Task B ────────────────┤                │
│  워커 3:            └─── Task C ────────────────┘                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 6.2 UE 구현

```cpp
// UE의 Fork-Join: ParallelFor
void ForkJoinExample(TArray<FData>& DataArray)
{
    // Fork: 여러 워커에 작업 분배
    ParallelFor(DataArray.Num(), [&DataArray](int32 Index)
    {
        ProcessData(DataArray[Index]);
    });
    // Join: ParallelFor 반환 시 모든 작업 완료 보장

    // 결과 사용 가능
    UseResults(DataArray);
}

// Task Graph를 통한 Fork-Join
void TaskGraphForkJoin()
{
    // 완료 이벤트
    FGraphEventRef CompletionEvent = FGraphEvent::CreateGraphEvent();

    // Fork: 여러 태스크 생성
    FGraphEventArray Prerequisites;
    for (int32 i = 0; i < NumTasks; ++i)
    {
        FGraphEventRef TaskEvent = TGraphTask<FMyTask>::CreateTask()
            .ConstructAndDispatchWhenReady(i);
        Prerequisites.Add(TaskEvent);
    }

    // Join: 모든 태스크 완료 대기
    FTaskGraphInterface::Get().WaitUntilTasksComplete(Prerequisites);

    // 또는 후속 태스크 설정
    TGraphTask<FContinuationTask>::CreateTask(&Prerequisites)
        .ConstructAndDispatchWhenReady();
}
```

### 6.3 중첩 Fork-Join

```cpp
// 중첩 병렬 처리
void NestedForkJoin(TArray<TArray<FData>>& NestedData)
{
    // 외부 Fork
    ParallelFor(NestedData.Num(), [&NestedData](int32 OuterIndex)
    {
        TArray<FData>& InnerArray = NestedData[OuterIndex];

        // 내부 Fork (주의: 스레드 과다 생성 가능)
        ParallelFor(InnerArray.Num(), [&InnerArray](int32 InnerIndex)
        {
            ProcessData(InnerArray[InnerIndex]);
        });
        // 내부 Join
    });
    // 외부 Join
}

// 더 나은 방법: 평탄화
void FlattenedParallel(TArray<TArray<FData>>& NestedData)
{
    // 모든 데이터를 단일 배열로 수집
    TArray<FData*> AllData;
    for (auto& Inner : NestedData)
    {
        for (auto& Data : Inner)
        {
            AllData.Add(&Data);
        }
    }

    // 단일 ParallelFor
    ParallelFor(AllData.Num(), [&AllData](int32 Index)
    {
        ProcessData(*AllData[Index]);
    });
}
```

---

## 원자적 연산의 필요성

![Compiler Explorer](../images/ch02/1617944-20210125210006316-152371240.png)
*Compiler Explorer - C++ 코드가 여러 어셈블리 명령어로 컴파일됨*

```cpp
// 단순해 보이지만 원자적이지 않음
int Counter = 0;
Counter++;  // 실제로는 Load → Add → Store (3개 명령어)

// 두 스레드가 동시 실행 시 레이스 컨디션
// Thread A: Load 0 → Add → Store 1
// Thread B: Load 0 → Add → Store 1
// 결과: 1 (예상: 2)

// 해결: 원자적 연산
std::atomic<int> AtomicCounter{0};
AtomicCounter++;  // 원자적 증가
```

---

## 요약

| 개념 | 핵심 내용 |
|------|----------|
| **암달의 법칙** | 순차 부분이 병렬화 이득 제한 |
| **동시성 vs 병렬성** | 동시성은 논리적, 병렬성은 물리적 |
| **SMP** | 모든 CPU가 메모리 공유 |
| **데이터 분할** | 선형, 재귀적, 태스크 기반 |
| **Fork-Join** | 병렬 실행의 기본 패턴 |

---

## 다음 문서

[02. 스레딩 인프라](02-threading-infrastructure.md)에서 UE의 스레딩 빌딩 블록을 살펴봅니다.
