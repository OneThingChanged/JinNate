# 06. 메모리 관리 시스템

> UE의 메모리 할당자, 가비지 컬렉션, 메모리 배리어

---

## 목차

1. [할당자 계층 구조](#1-할당자-계층-구조)
2. [FMallocBinned 상세](#2-fmallocbinned-상세)
3. [플랫폼별 할당자](#3-플랫폼별-할당자)
4. [가비지 컬렉션](#4-가비지-컬렉션)
5. [메모리 배리어](#5-메모리-배리어)
6. [메모리 프로파일링](#6-메모리-프로파일링)

---

## 1. 할당자 계층 구조 {#1-할당자-계층-구조}

### 1.1 FMalloc 계층

```
FMalloc (추상 기본 클래스)
│
├─ FMallocAnsi        ─── stdlib malloc/free 래퍼
│
├─ FMallocBinned      ─── UE 기본값, 42개 블록 크기 풀
│
├─ FMallocBinned2     ─── 단순화된 비닝, 더 적은 풀
│
├─ FMallocBinned3     ─── 64비트 전용, 스레드 로컬 캐시
│
├─ FMallocTBB         ─── Intel Threading Building Blocks
│
├─ FMallocJemalloc    ─── jemalloc 기반 (일부 플랫폼)
│
├─ FMallocMimalloc    ─── mimalloc 기반 (실험적)
│
└─ FMallocStomp       ─── 디버그용 가드 페이지
```

### 1.2 FMalloc 인터페이스

```cpp
class FMalloc
{
public:
    // 기본 할당/해제
    virtual void* Malloc(SIZE_T Size, uint32 Alignment) = 0;
    virtual void* Realloc(void* Ptr, SIZE_T NewSize, uint32 Alignment) = 0;
    virtual void Free(void* Ptr) = 0;

    // 크기 질의
    virtual bool GetAllocationSize(void* Ptr, SIZE_T& OutSize);

    // 트리밍 (시스템에 메모리 반환)
    virtual bool Trim(bool bTrimThreadCaches);

    // 통계
    virtual void GetAllocatorStats(FGenericMemoryStats& OutStats);

    // 디버그
    virtual void DumpAllocatorStats(class FOutputDevice& Ar);
    virtual bool ValidateHeap();
};

// 전역 할당자 접근
FMalloc* GMalloc = FPlatformMemory::BaseAllocator();
```

### 1.3 메모리 할당 API

```cpp
// 기본 할당
void* Ptr = FMemory::Malloc(Size);
void* AlignedPtr = FMemory::Malloc(Size, 16);  // 16바이트 정렬

// 재할당
Ptr = FMemory::Realloc(Ptr, NewSize);

// 해제
FMemory::Free(Ptr);

// 제로 초기화 할당
void* ZeroedPtr = FMemory::MallocZeroed(Size);

// 메모리 복사/설정
FMemory::Memcpy(Dest, Src, Size);
FMemory::Memset(Dest, Value, Size);
FMemory::Memzero(Dest, Size);

// 비교
int32 Result = FMemory::Memcmp(Ptr1, Ptr2, Size);
```

---

## 2. FMallocBinned 상세 {#2-fmallocbinned-상세}

### 2.1 비닝 전략

FMallocBinned는 할당 요청을 크기별 풀(Bin)로 라우팅합니다:

| 크기 범위 | 전략 | 상세 |
|-----------|------|------|
| **0 ~ 32KB** | Small 블록 | `PoolTable[42]` 사용 |
| **32 ~ 96KB** | Medium 블록 | `PagePoolTable[2]` 사용 |
| **> 96KB** | 직접 OS 할당 | 해시 버킷으로 추적 |

### 2.2 Small 블록 풀 크기

```cpp
// 42개의 풀 크기 (바이트)
static constexpr uint32 SmallPoolSizes[] = {
    16,    32,    48,    64,    80,    96,    112,   128,
    160,   192,   224,   256,   288,   320,   384,   448,
    512,   576,   640,   704,   768,   896,   1024,  1168,
    1360,  1632,  2048,  2336,  2720,  3264,  4096,  4672,
    5456,  6544,  8192,  9360,  10912, 13104, 16384, 21840,
    32768
};

// 크기 → 풀 인덱스 매핑
int32 GetPoolIndex(SIZE_T Size)
{
    // 이진 탐색 또는 테이블 룩업
    for (int32 i = 0; i < ARRAY_COUNT(SmallPoolSizes); ++i)
    {
        if (Size <= SmallPoolSizes[i])
        {
            return i;
        }
    }
    return INDEX_NONE;  // Large 할당
}
```

### 2.3 풀 구조

```cpp
// 각 풀은 동일 크기의 블록들로 구성
struct FPoolTable
{
    // Free 리스트 헤드
    FFreeMem* FirstPool;

    // 풀 통계
    uint32 NumAllocated;
    uint32 NumFree;

    // 블록 크기
    uint32 BlockSize;
};

// Free 메모리 블록 (침투적 리스트)
struct FFreeMem
{
    FFreeMem* Next;
    // ... 실제 데이터 공간
};
```

### 2.4 할당 흐름

```
┌─────────────────────────────────────────────────────────────────┐
│                    FMallocBinned 할당 흐름                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Malloc(Size) 호출                                              │
│       │                                                         │
│       ▼                                                         │
│  ┌─────────────────┐                                            │
│  │ Size <= 32KB?   │──── Yes ──→ Small 블록 경로               │
│  └────────┬────────┘                  │                         │
│           │                           ▼                         │
│           │ No                  ┌───────────────┐               │
│           │                     │ Pool Index    │               │
│           │                     │ 계산          │               │
│           │                     └───────┬───────┘               │
│           │                             │                       │
│           │                             ▼                       │
│           │                     ┌───────────────┐               │
│           │                     │ Free 블록     │               │
│           │                     │ 있음?         │               │
│           │                     └───────┬───────┘               │
│           │                        Yes  │  No                   │
│           │                             │   │                   │
│           │                     ┌───────┘   └───────┐           │
│           │                     ▼                   ▼           │
│           │              반환 블록            새 페이지 할당     │
│           │                                                     │
│           ▼                                                     │
│  ┌─────────────────┐                                            │
│  │ Size <= 96KB?   │──── Yes ──→ Medium 블록 경로              │
│  └────────┬────────┘                                            │
│           │                                                     │
│           │ No                                                  │
│           ▼                                                     │
│  ┌─────────────────┐                                            │
│  │ Large 할당      │                                            │
│  │ (직접 OS 호출)  │                                            │
│  └─────────────────┘                                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. 플랫폼별 할당자 {#3-플랫폼별-할당자}

### 3.1 기본 할당자 선택

| 플랫폼 | 기본 할당자 | 에디터 할당자 |
|--------|-------------|---------------|
| **Windows 32-bit** | Binned | TBB |
| **Windows 64-bit** | Binned3 | TBB |
| **Linux** | Binned | Binned |
| **macOS** | Binned | Binned |
| **iOS** | Binned | — |
| **Android** | Binned | — |
| **콘솔** | 플랫폼 전용 | — |

### 3.2 런타임 할당자 변경

```cpp
// 명령줄 인수로 할당자 선택
// -ansimalloc    : FMallocAnsi
// -binnedmalloc  : FMallocBinned
// -binnedmalloc2 : FMallocBinned2
// -binnedmalloc3 : FMallocBinned3
// -tbbmalloc     : FMallocTBB
// -stompmalloc   : FMallocStomp (디버그)

// 코드에서 할당자 선택
FMalloc* CreateMalloc()
{
    if (FParse::Param(FCommandLine::Get(), TEXT("ansimalloc")))
    {
        return new FMallocAnsi();
    }
    else if (FParse::Param(FCommandLine::Get(), TEXT("stompmalloc")))
    {
        return new FMallocStomp();
    }
    // ... 기타 할당자

    return new FMallocBinned3();  // 기본값
}
```

### 3.3 FMallocStomp (디버그)

메모리 오류 감지를 위한 디버그 할당자:

```cpp
class FMallocStomp : public FMalloc
{
    virtual void* Malloc(SIZE_T Size, uint32 Alignment) override
    {
        // 가드 페이지를 할당 앞뒤에 배치
        // 오버플로우/언더플로우 시 즉시 크래시

        SIZE_T TotalSize = Size + PageSize * 2;  // 가드 페이지
        void* Ptr = VirtualAlloc(...);

        // 앞쪽 가드 페이지: NO_ACCESS
        VirtualProtect(Ptr, PageSize, PAGE_NOACCESS);

        // 뒤쪽 가드 페이지: NO_ACCESS
        VirtualProtect((char*)Ptr + PageSize + Size, PageSize, PAGE_NOACCESS);

        return (char*)Ptr + PageSize;
    }

    virtual void Free(void* Ptr) override
    {
        // 해제 후에도 가드 페이지 유지
        // Use-after-free 감지
        VirtualProtect(Ptr, Size, PAGE_NOACCESS);
    }
};
```

---

## 4. 가비지 컬렉션 {#4-가비지-컬렉션}

### 4.1 Mark-Sweep 알고리즘

UE의 GC는 3단계로 동작합니다:

| 단계 | 영문명 | 설명 |
|------|--------|------|
| **1단계** | Reachability Analysis | 루트부터 순회, 도달 가능 객체 마킹 |
| **2단계** | Unreachable Collection | 마킹 안 된 객체 수집 |
| **3단계** | Incremental Purge | 수집된 객체 점진적 파괴 |

```cpp
void CollectGarbageInternal(EObjectFlags KeepFlags, bool bPerformFullPurge)
{
    // 1단계: 도달성 분석
    FRealtimeGC TagUsedRealtimeGC;
    TagUsedRealtimeGC.PerformReachabilityAnalysis(
        KeepFlags,
        bForceSingleThreaded,
        bWithClusters);

    // 2단계: 도달 불가 객체 수집
    GatherUnreachableObjects(bForceSingleThreaded);

    // 3단계: 점진적 퍼지
    IncrementalPurgeGarbage(false);

    // 메모리 트림
    FMemory::Trim();
}
```

### 4.2 GC 루트

GC 루트는 항상 도달 가능한 것으로 간주되는 객체입니다:

```cpp
// 루트 유형
// 1. 전역 UObject 배열의 객체들
// 2. UPROPERTY로 참조된 객체들
// 3. AddToRoot()로 명시적 등록된 객체들
// 4. 스택의 UObject 포인터들 (일부 상황)

// 명시적 루트 등록
MyObject->AddToRoot();      // GC 보호
MyObject->RemoveFromRoot(); // GC 보호 해제

// GC 주의사항
void SomeFunction()
{
    // 위험: Raw 포인터는 GC가 추적하지 않음
    UMyObject* Obj = NewObject<UMyObject>();

    // GC 발생 시 Obj가 수집될 수 있음!
    DoSomethingThatMayTriggerGC();

    Obj->Use();  // 위험!
}

// 안전: UPROPERTY 사용
UCLASS()
class UMyClass : public UObject
{
    UPROPERTY()
    UMyObject* SafeObj;  // GC가 추적함
};
```

### 4.3 클러스터링

관련 객체들을 클러스터로 묶어 GC 효율 향상:

```cpp
// 클러스터 예시: 액터와 그 컴포넌트들
// Actor
//   └─ Cluster Root
//       ├─ StaticMeshComponent
//       ├─ CollisionComponent
//       └─ ...

// 클러스터 전체가 한 번에 마킹/수집됨
// 개별 객체 순회 대비 오버헤드 감소
```

### 4.4 GC 트리거 조건

```cpp
// 자동 GC 트리거 조건
// 1. 일정 시간 간격 (GCInterval)
// 2. 할당량 임계치 초과
// 3. 메모리 압박 상황

// 수동 GC 트리거
GEngine->ForceGarbageCollection(true);  // 전체 GC
CollectGarbage(GARBAGE_COLLECTION_KEEPFLAGS);

// GC 일시 중지/재개
FGCScopeGuard GCScopeGuard;  // 스코프 내 GC 금지

// 또는
GEngine->DelayGarbageCollection();
```

---

## 5. 메모리 배리어 {#5-메모리-배리어}

### 5.1 컴파일러 배리어

컴파일러의 명령어 재배열을 방지:

```cpp
// 플랫폼별 컴파일러 배리어
#if defined(_MSC_VER)
    #define COMPILER_BARRIER() _ReadWriteBarrier()
#elif defined(__GNUC__)
    #define COMPILER_BARRIER() __asm__ __volatile__("" ::: "memory")
#elif defined(__clang__)
    #define COMPILER_BARRIER() __asm__ __volatile__("" ::: "memory")
#endif

// C++11 표준
std::atomic_signal_fence(std::memory_order_acq_rel);
```

### 5.2 하드웨어 메모리 배리어

CPU의 메모리 연산 재배열을 방지:

| 배리어 타입 | 방지하는 재배열 | 용도 |
|-------------|-----------------|------|
| **LoadLoad** | 읽기 후 읽기 | 읽기 순서 보장 |
| **StoreStore** | 쓰기 후 쓰기 | 쓰기 순서 보장 |
| **LoadStore** | 읽기 후 쓰기 | 읽기-쓰기 순서 |
| **StoreLoad** | 쓰기 후 읽기 | 완전 배리어 (가장 비쌈) |

```cpp
// UE 메모리 배리어 함수
FPlatformMisc::MemoryBarrier();  // 완전 배리어

// x86/x64
// _mm_mfence()  // 완전 배리어
// _mm_lfence()  // Load 배리어
// _mm_sfence()  // Store 배리어

// ARM
// __dmb()       // Data Memory Barrier
// __dsb()       // Data Synchronization Barrier
// __isb()       // Instruction Synchronization Barrier
```

### 5.3 Acquire-Release 의미론

```cpp
// Producer-Consumer 패턴
class FLockFreeQueue
{
    std::atomic<FNode*> Head;
    std::atomic<FNode*> Tail;

public:
    void Enqueue(FNode* Node)
    {
        FNode* OldTail = Tail.load(std::memory_order_relaxed);

        while (!Tail.compare_exchange_weak(
            OldTail,
            Node,
            std::memory_order_release,  // 이전 쓰기가 모두 보이도록
            std::memory_order_relaxed))
        {
        }
    }

    FNode* Dequeue()
    {
        FNode* OldHead = Head.load(std::memory_order_acquire);  // 이후 읽기 전에 동기화

        if (OldHead == nullptr)
        {
            return nullptr;
        }

        // ...
    }
};
```

---

## 6. 메모리 프로파일링 {#6-메모리-프로파일링}

### 6.1 콘솔 명령

```cpp
// 메모리 통계 출력
stat memory           // 기본 메모리 통계
stat memoryplatform   // 플랫폼별 메모리
stat memorystatic     // 정적 메모리
stat MemoryAllocator  // 할당자 통계

// GC 통계
stat gc               // GC 통계

// 메모리 리포트
memreport -full       // 전체 메모리 리포트
obj list class=UTexture2D  // 특정 클래스 객체 목록
```

### 6.2 LLM (Low-Level Memory Tracker)

```cpp
// LLM 태그 정의
LLM_DECLARE_TAG(MyCustomTag);
LLM_DEFINE_TAG(MyCustomTag, "My/Custom/Tag");

// 메모리 추적
{
    LLM_SCOPE(MyCustomTag);
    void* Ptr = FMemory::Malloc(1024);
    // 이 할당은 MyCustomTag로 추적됨
}

// 또는 함수 전체
LLM_SCOPE_BYNAME(TEXT("MySystem/Initialize"));
void MySystem::Initialize()
{
    // 모든 할당이 추적됨
}
```

### 6.3 메모리 최적화 팁

```cpp
// 1. 적절한 컨테이너 Reserve
TArray<int32> Array;
Array.Reserve(ExpectedSize);  // 재할당 방지

// 2. TInlineAllocator 사용
TArray<int32, TInlineAllocator<16>> SmallArray;  // 16개까지 스택

// 3. Shrink 호출
Array.Shrink();  // 여유 공간 해제

// 4. Reset vs Empty
Array.Empty();  // 메모리 해제
Array.Reset();  // 메모리 유지, 재사용

// 5. Move 의미론 활용
void ProcessArray(TArray<FData>&& Data)
{
    LocalArray = MoveTemp(Data);  // 복사 대신 이동
}
```

---

## 요약

| 주제 | 핵심 내용 |
|------|----------|
| **할당자** | FMallocBinned (기본), 크기별 풀링 |
| **비닝** | Small(~32KB): 42개 풀, Medium(~96KB): 2개 풀 |
| **GC** | Mark-Sweep 3단계, 클러스터링 최적화 |
| **메모리 배리어** | 컴파일러/하드웨어 재배열 방지 |
| **프로파일링** | LLM, stat memory, memreport |

---

## 다음 문서

[07. 엔진 오브젝트 및 시작 파이프라인](07-object-hierarchy.md)에서 UObject 계층과 엔진 시작 과정을 살펴봅니다.
