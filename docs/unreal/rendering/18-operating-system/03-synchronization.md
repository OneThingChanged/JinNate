# 동기화

스레드 동기화 기법과 데드락을 설명합니다.

---

## Race Condition

```
┌─────────────────────────────────────────────────────────────────┐
│                    Race Condition                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  공유 변수: int counter = 0;                                    │
│                                                                 │
│  Thread A                        Thread B                       │
│  ─────────                        ─────────                     │
│  1. Load counter (0)                                            │
│                                   2. Load counter (0)           │
│  3. Add 1 (= 1)                                                 │
│                                   4. Add 1 (= 1)                │
│  5. Store counter (1)                                           │
│                                   6. Store counter (1)          │
│                                                                 │
│  기대 결과: counter = 2                                         │
│  실제 결과: counter = 1  ← Lost Update!                        │
│                                                                 │
│  원인: 비원자적 연산 (Load → Compute → Store)                  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Critical Section

```
┌─────────────────────────────────────────────────────────────────┐
│                    Critical Section                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  임계 구역 (Critical Section):                                  │
│  공유 자원에 접근하는 코드 영역                                 │
│                                                                 │
│  Thread A                         Thread B                      │
│  ────────                         ────────                      │
│  ┌─────────────┐                                                │
│  │ Entry       │                  ← Waiting                     │
│  │ Section     │                                                │
│  └─────────────┘                                                │
│        │                                                        │
│        ▼                                                        │
│  ╔═════════════╗                                                │
│  ║  Critical   ║  ← 한 번에 하나의 스레드만                    │
│  ║  Section    ║                                                │
│  ╚═════════════╝                                                │
│        │                                                        │
│        ▼                                                        │
│  ┌─────────────┐                  ┌─────────────┐              │
│  │ Exit        │                  │ Entry       │              │
│  │ Section     │                  │ Section     │              │
│  └─────────────┘                  └─────────────┘              │
│                                         │                       │
│                                         ▼                       │
│                                   ╔═════════════╗              │
│                                   ║  Critical   ║              │
│                                   ║  Section    ║              │
│                                   ╚═════════════╝              │
│                                                                 │
│  요구사항:                                                      │
│  1. Mutual Exclusion (상호 배제)                               │
│  2. Progress (진행)                                            │
│  3. Bounded Waiting (한정 대기)                                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 동기화 프리미티브

```
┌─────────────────────────────────────────────────────────────────┐
│                    동기화 기법 비교                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Spinlock                                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ while (locked) { }  // Busy Waiting                     │   │
│  │ locked = true;                                          │   │
│  │ // Critical Section                                     │   │
│  │ locked = false;                                         │   │
│  │                                                         │   │
│  │ + 매우 빠름 (Context Switch 없음)                       │   │
│  │ - CPU 낭비 (대기 중에도 CPU 사용)                       │   │
│  │ 용도: 짧은 임계 구역, 커널 코드                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  2. Mutex                                                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ mutex.lock();      // 블록 (Sleep)                      │   │
│  │ // Critical Section                                     │   │
│  │ mutex.unlock();    // Wake up waiting threads           │   │
│  │                                                         │   │
│  │ + CPU 효율적 (대기 시 Sleep)                            │   │
│  │ - Context Switch 오버헤드                               │   │
│  │ 용도: 긴 임계 구역, 일반 코드                           │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  3. Semaphore                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ // count = N (최대 동시 접근 수)                        │   │
│  │ semaphore.wait();  // count--; if (count < 0) sleep    │   │
│  │ // Critical Section                                     │   │
│  │ semaphore.signal(); // count++; wake up one            │   │
│  │                                                         │   │
│  │ Binary Semaphore (count=1): Mutex와 유사                │   │
│  │ Counting Semaphore: 리소스 풀 관리                      │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 데드락

```
┌─────────────────────────────────────────────────────────────────┐
│                    Deadlock                                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Thread A                         Thread B                      │
│  ─────────                        ─────────                     │
│  Lock(Resource1)  ←──────────────── 대기                       │
│       │                               │                         │
│       │                         Lock(Resource2)                 │
│       │                               │                         │
│       ▼                               ▼                         │
│  Lock(Resource2)  ──── 대기 ────► Lock(Resource1)             │
│       ↑               ↓               ↑                        │
│       └───── Circular Wait ──────────┘                         │
│                                                                 │
│  데드락 4대 조건 (모두 만족 시 발생):                          │
│  1. Mutual Exclusion (상호 배제)                               │
│  2. Hold and Wait (점유 대기)                                  │
│  3. No Preemption (비선점)                                     │
│  4. Circular Wait (순환 대기)                                  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 데드락 해결

```cpp
// 해결책 1: 락 순서 고정
void ThreadA() {
    Lock(Resource1);    // 항상 1번 먼저
    Lock(Resource2);
    // ...
    Unlock(Resource2);
    Unlock(Resource1);
}

void ThreadB() {
    Lock(Resource1);    // 동일한 순서로
    Lock(Resource2);
    // ...
}

// 해결책 2: Try Lock
bool ThreadA() {
    Lock(Resource1);
    if (!TryLock(Resource2)) {
        Unlock(Resource1);
        return false;   // 재시도
    }
    // ...
}
```

---

## UE4 동기화

```cpp
// FCriticalSection (플랫폼 독립적 Mutex)
FCriticalSection Mutex;

void ThreadSafeFunction()
{
    FScopeLock ScopeLock(&Mutex);  // RAII 패턴
    // Critical Section
}   // 자동 Unlock

// FSpinLock (짧은 임계 구역용)
FSpinLock SpinLock;
SpinLock.Lock();
// 매우 짧은 작업
SpinLock.Unlock();

// FRWLock (Reader-Writer Lock)
FRWLock RWLock;
RWLock.ReadLock();      // 여러 Reader 동시 가능
// Read operation
RWLock.ReadUnlock();

RWLock.WriteLock();     // Writer는 독점
// Write operation
RWLock.WriteUnlock();
```

---

## 원자 연산

```
┌─────────────────────────────────────────────────────────────────┐
│                    Atomic Operations                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  원자 연산: 중간 상태가 존재하지 않는 연산                      │
│                                                                 │
│  // 비원자적                    // 원자적                      │
│  counter++;                     InterlockedIncrement(&counter);│
│  // Load → Add → Store         // 단일 CPU 명령어             │
│                                                                 │
│  주요 원자 연산:                                               │
│  • Atomic Load/Store                                           │
│  • Atomic Add/Sub                                              │
│  • Atomic Exchange                                             │
│  • Compare-And-Swap (CAS)                                      │
│                                                                 │
│  CAS 예시:                                                     │
│  bool CAS(int* ptr, int expected, int desired) {               │
│      if (*ptr == expected) {                                   │
│          *ptr = desired;                                       │
│          return true;                                          │
│      }                                                         │
│      return false;                                             │
│  }                                                             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### UE4 Atomic

```cpp
// FPlatformAtomics
int32 Value = 0;

// Atomic Increment
int32 NewValue = FPlatformAtomics::InterlockedIncrement(&Value);

// Compare-And-Swap
int32 Expected = 5;
int32 Desired = 10;
int32 OldValue = FPlatformAtomics::InterlockedCompareExchange(
    &Value, Desired, Expected);
// Value가 5였으면 10으로 변경, OldValue = 5 반환
// Value가 5가 아니었으면 변경 없음, 현재값 반환
```

---

## 다음 단계

[메모리 관리](04-memory-management.md)에서 가상 메모리를 알아봅니다.

