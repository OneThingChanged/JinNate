# UE Platform 모듈

UE의 플랫폼 추상화 레이어를 설명합니다.

---

## Platform 추상화 구조

```
┌─────────────────────────────────────────────────────────────────┐
│                    UE Platform 모듈                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Engine Code (플랫폼 독립)                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                         │   │
│  │  FPlatformProcess::CreateProc()                        │   │
│  │  FPlatformMemory::Malloc()                             │   │
│  │  FPlatformMisc::GetCPUInfo()                           │   │
│  │                                                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                             │                                   │
│                typedef      │                                   │
│                             ▼                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  FGenericPlatformXXX (Default Implementation)          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                             │                                   │
│              ┌──────────────┼──────────────┐                   │
│              ▼              ▼              ▼                   │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐        │
│  │FWindowsPlatform│  │FLinuxPlatform│  │FMacPlatform │        │
│  │    XXX       │  │    XXX       │  │    XXX       │        │
│  └──────────────┘  └──────────────┘  └──────────────┘        │
│                                                                 │
│  컴파일 시점에 플랫폼별 구현 선택                              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## FPlatformProcess

```cpp
// 프로세스/스레드 관리
class FPlatformProcess
{
public:
    // 프로세스 생성
    static FProcHandle CreateProc(
        const TCHAR* URL,
        const TCHAR* Params,
        bool bLaunchDetached,
        bool bLaunchHidden,
        bool bLaunchReallyHidden,
        uint32* OutProcessID,
        int32 PriorityModifier,
        const TCHAR* OptionalWorkingDirectory,
        void* PipeWriteChild,
        void* PipeReadChild
    );

    // 현재 프로세스 ID
    static uint32 GetCurrentProcessId();

    // Sleep
    static void Sleep(float Seconds);
    static void SleepNoStats(float Seconds);
    static void SleepInfinite();

    // 스레드
    static void SetThreadAffinityMask(uint64 AffinityMask);
    static void SetThreadPriority(EThreadPriority Priority);

    // 공유 라이브러리
    static void* GetDllHandle(const TCHAR* Filename);
    static void FreeDllHandle(void* DllHandle);
    static void* GetDllExport(void* DllHandle, const TCHAR* ProcName);
};
```

---

## FPlatformMemory

```
┌─────────────────────────────────────────────────────────────────┐
│                    FPlatformMemory                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  메모리 정보 조회:                                             │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ FPlatformMemoryStats Stats;                             │   │
│  │ FPlatformMemory::GetStats(Stats);                       │   │
│  │                                                         │   │
│  │ Stats.TotalPhysical      // 전체 물리 메모리           │   │
│  │ Stats.TotalVirtual       // 전체 가상 메모리           │   │
│  │ Stats.AvailablePhysical  // 사용 가능 물리             │   │
│  │ Stats.AvailableVirtual   // 사용 가능 가상             │   │
│  │ Stats.UsedPhysical       // 사용 중 물리               │   │
│  │ Stats.UsedVirtual        // 사용 중 가상               │   │
│  │ Stats.PeakUsedPhysical   // 피크 사용량                │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  메모리 할당:                                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ // 기본 할당                                            │   │
│  │ void* Ptr = FPlatformMemory::Malloc(Size, Alignment);  │   │
│  │ FPlatformMemory::Free(Ptr);                            │   │
│  │                                                         │   │
│  │ // 재할당                                               │   │
│  │ Ptr = FPlatformMemory::Realloc(Ptr, NewSize, Align);   │   │
│  │                                                         │   │
│  │ // 대용량 페이지                                        │   │
│  │ void* Large = FPlatformMemory::BinnedAllocFromOS(Size);│   │
│  │ FPlatformMemory::BinnedFreeToOS(Large, Size);          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### UE 메모리 할당자

```
┌─────────────────────────────────────────────────────────────────┐
│                    UE Memory Allocator                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  FMalloc (Interface)                                           │
│       │                                                         │
│       ├── FMallocBinned      (기본, 작은 할당 최적화)          │
│       ├── FMallocBinned2     (UE4.26+, 더 나은 스레드 성능)    │
│       ├── FMallocBinned3     (UE5, 최신)                       │
│       ├── FMallocTBB         (Intel TBB 사용)                  │
│       ├── FMallocMimalloc    (mimalloc 사용)                   │
│       ├── FMallocAnsi        (기본 CRT malloc)                 │
│       └── FMallocStomp       (디버깅용, 접근 오류 감지)        │
│                                                                 │
│  Binned Allocator 구조:                                        │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Size Class:  16B │ 32B │ 48B │ ... │ 32KB │ Large      │   │
│  │              └───┴─────┴─────┴─────┴──────┴─────┘      │   │
│  │                          │                              │   │
│  │              각 Size Class별 Pool 관리                  │   │
│  │              → 단편화 최소화, 빠른 할당                 │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## FPlatformMisc

```cpp
// 시스템 정보 및 유틸리티
class FPlatformMisc
{
public:
    // CPU 정보
    static int32 NumberOfCores();
    static int32 NumberOfCoresIncludingHyperthreads();
    static const TCHAR* GetCPUVendor();
    static const TCHAR* GetCPUBrand();

    // 환경
    static FString GetEnvironmentVariable(const TCHAR* Name);
    static void SetEnvironmentVar(const TCHAR* Name, const TCHAR* Value);

    // 시스템
    static void RequestExit(bool Force);
    static void ClipboardCopy(const TCHAR* Str);
    static void ClipboardPaste(FString& Result);

    // 메시지 박스
    static EAppReturnType::Type MessageBoxExt(
        EAppMsgType::Type MsgType,
        const TCHAR* Text,
        const TCHAR* Caption
    );

    // GUID
    static FGuid GetMachineId();
};
```

---

## FPlatformTime

```
┌─────────────────────────────────────────────────────────────────┐
│                    FPlatformTime                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  시간 측정:                                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ // 고정밀 타이머                                        │   │
│  │ double StartTime = FPlatformTime::Seconds();           │   │
│  │ // ... 작업 ...                                        │   │
│  │ double EndTime = FPlatformTime::Seconds();             │   │
│  │ double ElapsedMs = (EndTime - StartTime) * 1000.0;     │   │
│  │                                                         │   │
│  │ // CPU 사이클                                           │   │
│  │ uint64 StartCycles = FPlatformTime::Cycles64();        │   │
│  │ // ... 작업 ...                                        │   │
│  │ uint64 EndCycles = FPlatformTime::Cycles64();          │   │
│  │ double Seconds = FPlatformTime::ToSeconds64(           │   │
│  │     EndCycles - StartCycles);                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  날짜/시간:                                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ FDateTime Now = FDateTime::Now();          // 로컬     │   │
│  │ FDateTime UtcNow = FDateTime::UtcNow();    // UTC      │   │
│  │                                                         │   │
│  │ int32 Year = Now.GetYear();                            │   │
│  │ int32 Month = Now.GetMonth();                          │   │
│  │ int32 Day = Now.GetDay();                              │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## FPlatformAtomics

```cpp
// 원자적 연산
class FPlatformAtomics
{
public:
    // Increment/Decrement
    static int32 InterlockedIncrement(volatile int32* Value);
    static int64 InterlockedIncrement(volatile int64* Value);
    static int32 InterlockedDecrement(volatile int32* Value);

    // Add
    static int32 InterlockedAdd(volatile int32* Value, int32 Amount);
    static int64 InterlockedAdd(volatile int64* Value, int64 Amount);

    // Exchange
    static int32 InterlockedExchange(volatile int32* Value, int32 Exchange);
    static void* InterlockedExchangePtr(void** Dest, void* Exchange);

    // Compare-And-Swap
    static int32 InterlockedCompareExchange(
        volatile int32* Dest,
        int32 Exchange,
        int32 Comparand
    );
    // Dest == Comparand 이면 Dest = Exchange
    // 반환값: 이전 Dest 값

    // Memory Barrier
    static void MemoryBarrier();
};
```

---

## 플랫폼별 구현

```
┌─────────────────────────────────────────────────────────────────┐
│                    플랫폼별 파일 구조                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Engine/Source/Runtime/Core/                                   │
│  ├── Public/                                                   │
│  │   ├── GenericPlatform/                                     │
│  │   │   ├── GenericPlatformProcess.h                         │
│  │   │   ├── GenericPlatformMemory.h                          │
│  │   │   └── GenericPlatformMisc.h                            │
│  │   │                                                         │
│  │   ├── Windows/                                              │
│  │   │   ├── WindowsPlatformProcess.h                         │
│  │   │   ├── WindowsPlatformMemory.h                          │
│  │   │   └── WindowsPlatformMisc.h                            │
│  │   │                                                         │
│  │   ├── Linux/                                                │
│  │   │   └── LinuxPlatform*.h                                 │
│  │   │                                                         │
│  │   └── Mac/                                                  │
│  │       └── MacPlatform*.h                                   │
│  │                                                             │
│  └── Private/                                                  │
│      ├── Windows/                                              │
│      │   └── WindowsPlatform*.cpp                             │
│      ├── Linux/                                                │
│      └── Mac/                                                  │
│                                                                 │
│  빌드 시 TARGET_PLATFORM에 따라 적절한 구현 선택              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 참고 자료

- [UE Platform Abstraction](https://docs.unrealengine.com/5.0/en-US/API/Runtime/Core/GenericPlatform/)
- [Operating System Concepts](https://www.os-book.com/)
- [원본 문서 (timlly)](https://www.cnblogs.com/timlly/p/16844127.html)

